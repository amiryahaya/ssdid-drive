import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import DataTable from '../components/DataTable'
import type { Column } from '../components/DataTable'
import { useAdminStore } from '../stores/adminStore'
import type { Tenant, TenantMember } from '../stores/adminStore'
import { formatDate, formatStorageQuota, truncateDid } from '../utils/format'

function RoleBadge({ role }: { role: string }) {
  const colors: Record<string, string> = {
    owner: 'bg-purple-100 text-purple-800',
    admin: 'bg-blue-100 text-blue-800',
    member: 'bg-gray-100 text-gray-700',
  }
  const cls = colors[role.toLowerCase()] ?? 'bg-gray-100 text-gray-700'
  return (
    <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium capitalize ${cls}`}>
      {role}
    </span>
  )
}

export default function TenantDetailPage() {
  const { id } = useParams<{ id: string }>()
  const {
    tenants,
    tenantMembers,
    tenantMembersLoading,
    fetchTenants,
    fetchTenantMembers,
  } = useAdminStore()

  const [error, setError] = useState<string | null>(null)

  const tenant: Tenant | undefined = tenants.find((t) => t.id === id)

  useEffect(() => {
    if (!id) return
    // Ensure tenants are loaded (in case user navigated directly)
    if (tenants.length === 0) {
      fetchTenants(1, 100).catch(() => {})
    }
    setError(null)
    fetchTenantMembers(id).catch((err) =>
      setError(err instanceof Error ? err.message : 'Failed to load members'),
    )
  }, [id, tenants.length, fetchTenants, fetchTenantMembers])

  const memberColumns: Column<TenantMember>[] = [
    {
      key: 'did',
      header: 'DID',
      render: (m) => (
        <span className="font-mono text-xs" title={m.did}>
          {truncateDid(m.did)}
        </span>
      ),
    },
    {
      key: 'display_name',
      header: 'Display Name',
      render: (m) => m.display_name || '\u2014',
    },
    {
      key: 'email',
      header: 'Email',
      render: (m) => m.email || '\u2014',
    },
    {
      key: 'role',
      header: 'Role',
      render: (m) => <RoleBadge role={m.role} />,
    },
  ]

  return (
    <div>
      <Link
        to="/tenants"
        className="text-sm text-blue-600 hover:text-blue-800 mb-4 inline-block"
      >
        &larr; Back to Tenants
      </Link>

      {tenant ? (
        <div className="bg-white rounded-lg shadow p-6 mb-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-2xl font-semibold">{tenant.name}</h2>
            <span
              className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                tenant.disabled
                  ? 'bg-red-100 text-red-800'
                  : 'bg-green-100 text-green-800'
              }`}
            >
              {tenant.disabled ? 'Disabled' : 'Enabled'}
            </span>
          </div>
          <dl className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
            <div>
              <dt className="text-gray-500">Slug</dt>
              <dd className="font-mono">{tenant.slug}</dd>
            </div>
            <div>
              <dt className="text-gray-500">Users</dt>
              <dd>{tenant.user_count}</dd>
            </div>
            <div>
              <dt className="text-gray-500">Storage Quota</dt>
              <dd>{formatStorageQuota(tenant.storage_quota_bytes)}</dd>
            </div>
            <div>
              <dt className="text-gray-500">Created</dt>
              <dd>{formatDate(tenant.created_at)}</dd>
            </div>
          </dl>
        </div>
      ) : (
        <div className="bg-white rounded-lg shadow p-6 mb-6 animate-pulse">
          <div className="h-6 bg-gray-200 rounded w-1/3 mb-4" />
          <div className="grid grid-cols-4 gap-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="h-4 bg-gray-200 rounded" />
            ))}
          </div>
        </div>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {error}
        </div>
      )}

      <h3 className="text-lg font-semibold mb-3">Members</h3>
      <DataTable
        columns={memberColumns}
        data={tenantMembers}
        loading={tenantMembersLoading}
        rowKey={(m) => m.user_id}
      />
    </div>
  )
}
