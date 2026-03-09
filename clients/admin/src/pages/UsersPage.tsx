import { useEffect, useState, useCallback, useRef } from 'react'
import DataTable from '../components/DataTable'
import type { Column } from '../components/DataTable'
import { useAdminStore } from '../stores/adminStore'
import type { User } from '../stores/adminStore'

const PAGE_SIZE = 20

function truncateDid(did: string): string {
  if (did.length <= 24) return did
  return `${did.slice(0, 16)}...${did.slice(-8)}`
}

function formatDate(iso: string | null): string {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

function StatusBadge({ status }: { status: string }) {
  const isActive = status === 'active'
  return (
    <span
      className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
        isActive
          ? 'bg-green-100 text-green-800'
          : 'bg-red-100 text-red-800'
      }`}
    >
      {status}
    </span>
  )
}

export default function UsersPage() {
  const { users, usersTotal, usersLoading, fetchUsers, updateUser } =
    useAdminStore()

  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [updatingId, setUpdatingId] = useState<string | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const loadUsers = useCallback(
    (currentPage: number, currentSearch: string) => {
      setError(null)
      fetchUsers(currentPage, PAGE_SIZE, currentSearch || undefined).catch(
        (err) => setError(err instanceof Error ? err.message : 'Failed to load users'),
      )
    },
    [fetchUsers],
  )

  useEffect(() => {
    loadUsers(page, search)
  }, [page, loadUsers, search])

  const handleSearchChange = (value: string) => {
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(() => {
      setPage(1)
      setSearch(value)
    }, 300)
  }

  const handleToggleStatus = async (user: User) => {
    const newStatus = user.status === 'active' ? 'suspended' : 'active'
    if (newStatus === 'suspended') {
      const confirmed = window.confirm(
        `Suspend user ${user.display_name || user.did}? They will lose access immediately.`,
      )
      if (!confirmed) return
    }
    setUpdatingId(user.id)
    try {
      await updateUser(user.id, { status: newStatus })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update user')
    } finally {
      setUpdatingId(null)
    }
  }

  const columns: Column<User>[] = [
    {
      key: 'did',
      header: 'DID',
      render: (u) => (
        <span className="font-mono text-xs" title={u.did}>
          {truncateDid(u.did)}
        </span>
      ),
    },
    {
      key: 'display_name',
      header: 'Display Name',
      render: (u) => u.display_name || '—',
    },
    {
      key: 'email',
      header: 'Email',
      render: (u) => u.email || '—',
    },
    {
      key: 'status',
      header: 'Status',
      render: (u) => <StatusBadge status={u.status} />,
    },
    {
      key: 'system_role',
      header: 'Role',
      render: (u) => u.system_role || 'User',
    },
    {
      key: 'last_login_at',
      header: 'Last Login',
      render: (u) => formatDate(u.last_login_at),
    },
    {
      key: 'actions',
      header: 'Actions',
      render: (u) => {
        const isSuspended = u.status === 'suspended'
        const isUpdating = updatingId === u.id
        return (
          <button
            onClick={() => handleToggleStatus(u)}
            disabled={isUpdating}
            className={`text-xs font-medium px-3 py-1 rounded ${
              isSuspended
                ? 'bg-green-50 text-green-700 hover:bg-green-100'
                : 'bg-red-50 text-red-700 hover:bg-red-100'
            } disabled:opacity-50 disabled:cursor-not-allowed`}
          >
            {isUpdating ? '...' : isSuspended ? 'Activate' : 'Suspend'}
          </button>
        )
      },
    },
  ]

  const totalPages = Math.ceil(usersTotal / PAGE_SIZE)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-2xl font-semibold">Users</h2>
        <input
          type="text"
          placeholder="Search users..."
          onChange={(e) => handleSearchChange(e.target.value)}
          className="border border-gray-300 rounded-lg px-3 py-2 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
        />
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {error}
        </div>
      )}

      <DataTable columns={columns} data={users} loading={usersLoading} rowKey={(u) => u.id} />

      {!usersLoading && usersTotal > 0 && (
        <div className="flex items-center justify-between mt-4 text-sm text-gray-600">
          <span>
            Page {page} of {totalPages}
          </span>
          <div className="flex gap-2">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="px-3 py-1 border border-gray-300 rounded hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </button>
            <button
              onClick={() => setPage((p) => p + 1)}
              disabled={page >= totalPages}
              className="px-3 py-1 border border-gray-300 rounded hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
