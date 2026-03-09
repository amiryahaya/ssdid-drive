import { useEffect, useState, useCallback, useRef } from 'react'
import { Link } from 'react-router-dom'
import DataTable from '../components/DataTable'
import type { Column } from '../components/DataTable'
import Pagination from '../components/Pagination'
import CreateTenantDialog from '../components/CreateTenantDialog'
import EditTenantDialog from '../components/EditTenantDialog'
import { useAdminStore } from '../stores/adminStore'
import type { Tenant } from '../stores/adminStore'
import { formatDate, formatStorageQuota } from '../utils/format'

const PAGE_SIZE = 20

function StatusBadge({ disabled }: { disabled: boolean }) {
  return (
    <span
      className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
        disabled
          ? 'bg-red-100 text-red-800'
          : 'bg-green-100 text-green-800'
      }`}
    >
      {disabled ? 'Disabled' : 'Enabled'}
    </span>
  )
}

export default function TenantsPage() {
  const {
    tenants,
    tenantsTotal,
    tenantsLoading,
    fetchTenants,
    updateTenant,
  } = useAdminStore()

  const [page, setPage] = useState(1)
  const [searchInput, setSearchInput] = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [updatingId, setUpdatingId] = useState<string | null>(null)
  const [showCreate, setShowCreate] = useState(false)
  const [editingTenant, setEditingTenant] = useState<Tenant | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Cleanup debounce timer on unmount
  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [])

  const loadTenants = useCallback(
    (currentPage: number, currentSearch: string) => {
      setError(null)
      fetchTenants(currentPage, PAGE_SIZE, currentSearch || undefined).catch(
        (err) =>
          setError(
            err instanceof Error ? err.message : 'Failed to load tenants',
          ),
      )
    },
    [fetchTenants],
  )

  useEffect(() => {
    loadTenants(page, debouncedSearch)
  }, [page, loadTenants, debouncedSearch])

  const handleSearchChange = (value: string) => {
    setSearchInput(value)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      setPage(1)
      setDebouncedSearch(value)
    }, 300)
  }

  const handleToggleDisabled = async (tenant: Tenant) => {
    const newDisabled = !tenant.disabled
    if (newDisabled) {
      const confirmed = window.confirm(
        `Disable tenant "${tenant.name}"? Members will lose access.`,
      )
      if (!confirmed) return
    }
    setUpdatingId(tenant.id)
    try {
      await updateTenant(tenant.id, { disabled: newDisabled })
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Failed to update tenant',
      )
    } finally {
      setUpdatingId(null)
    }
  }

  const columns: Column<Tenant>[] = [
    {
      key: 'name',
      header: 'Name',
      render: (t) => (
        <Link
          to={`/tenants/${t.id}`}
          className="text-blue-600 hover:text-blue-800 font-medium"
        >
          {t.name}
        </Link>
      ),
    },
    {
      key: 'slug',
      header: 'Slug',
      render: (t) => <span className="font-mono text-xs">{t.slug}</span>,
    },
    {
      key: 'disabled',
      header: 'Status',
      render: (t) => <StatusBadge disabled={t.disabled} />,
    },
    {
      key: 'user_count',
      header: 'Users',
    },
    {
      key: 'storage_quota_bytes',
      header: 'Storage Quota',
      render: (t) => formatStorageQuota(t.storage_quota_bytes),
    },
    {
      key: 'created_at',
      header: 'Created',
      render: (t) => formatDate(t.created_at),
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (t) => {
        const isUpdating = updatingId === t.id
        return (
          <div className="flex gap-2">
            <button
              onClick={() => setEditingTenant(t)}
              className="text-xs font-medium px-3 py-1 rounded bg-blue-50 text-blue-700 hover:bg-blue-100"
            >
              Edit
            </button>
            <button
              onClick={() => handleToggleDisabled(t)}
              disabled={isUpdating}
              className={`text-xs font-medium px-3 py-1 rounded ${
                t.disabled
                  ? 'bg-green-50 text-green-700 hover:bg-green-100'
                  : 'bg-red-50 text-red-700 hover:bg-red-100'
              } disabled:opacity-50 disabled:cursor-not-allowed`}
            >
              {isUpdating ? '...' : t.disabled ? 'Enable' : 'Disable'}
            </button>
          </div>
        )
      },
    },
  ]

  const totalPages = Math.ceil(tenantsTotal / PAGE_SIZE)

  return (
    <div>
      <div className="flex items-center justify-end mb-6">
        <div className="flex items-center gap-3">
          <input
            type="text"
            placeholder="Search tenants..."
            value={searchInput}
            onChange={(e) => handleSearchChange(e.target.value)}
            className="border border-gray-300 rounded-lg px-3 py-2 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
          <button
            onClick={() => setShowCreate(true)}
            className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700"
          >
            Create Tenant
          </button>
        </div>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {error}
        </div>
      )}

      <DataTable
        columns={columns}
        data={tenants}
        loading={tenantsLoading}
        rowKey={(t) => t.id}
      />

      <Pagination
        page={page}
        totalPages={totalPages}
        loading={tenantsLoading}
        total={tenantsTotal}
        onChange={setPage}
      />

      <CreateTenantDialog
        open={showCreate}
        onClose={() => setShowCreate(false)}
        onCreated={() => loadTenants(page, debouncedSearch)}
      />

      <EditTenantDialog
        tenant={editingTenant}
        onClose={() => setEditingTenant(null)}
        onUpdated={() => loadTenants(page, debouncedSearch)}
      />
    </div>
  )
}
