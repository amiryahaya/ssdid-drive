import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import DataTable from '../components/DataTable'
import type { Column } from '../components/DataTable'
import { useAdminStore } from '../stores/adminStore'
import type { AdminInvitation, Tenant, TenantMember } from '../stores/adminStore'
import { formatDate, formatStorageQuota, truncateDid } from '../utils/format'
import InviteUserDialog from '../components/InviteUserDialog'

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
    fetchTenantById,
    fetchTenantMembers,
    tenantInvitations,
    tenantInvitationsLoading,
    fetchTenantInvitations,
    revokeAdminInvitation,
  } = useAdminStore()

  const [error, setError] = useState<string | null>(null)
  const [directTenant, setDirectTenant] = useState<Tenant | null>(null)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [revoking, setRevoking] = useState<string | null>(null)
  const [invError, setInvError] = useState<string | null>(null)

  // Use tenant from store if available, otherwise use directly fetched one
  const tenant: Tenant | undefined = tenants.find((t) => t.id === id) ?? directTenant ?? undefined

  // Fetch tenant if not in store (e.g. direct navigation)
  useEffect(() => {
    if (!id) return
    if (!tenants.find((t) => t.id === id)) {
      fetchTenantById(id)
        .then(setDirectTenant)
        .catch(() => setError('Tenant not found'))
    }
  }, [id]) // eslint-disable-line react-hooks/exhaustive-deps

  // Fetch members
  useEffect(() => {
    if (!id) return
    setError(null)
    fetchTenantMembers(id).catch((err) =>
      setError(err instanceof Error ? err.message : 'Failed to load members'),
    )
  }, [id, fetchTenantMembers])

  // Fetch invitations
  useEffect(() => {
    if (!id) return
    fetchTenantInvitations(id).catch(() => {})
  }, [id, fetchTenantInvitations])

  const handleRevoke = async (invitationId: string) => {
    if (!id) return
    if (!confirm('Are you sure you want to revoke this invitation?')) return
    setRevoking(invitationId)
    setInvError(null)
    try {
      await revokeAdminInvitation(id, invitationId)
      await fetchTenantInvitations(id)
    } catch (err) {
      setInvError(err instanceof Error ? err.message : 'Failed to revoke invitation')
    } finally {
      setRevoking(null)
    }
  }

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
      ) : error ? (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-6">
          {error}
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

      {error && tenant && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {error}
        </div>
      )}

      <div className="flex items-center justify-between mb-3">
        <h3 className="text-lg font-semibold">Members</h3>
        <button
          onClick={() => setInviteOpen(true)}
          className="flex items-center gap-1.5 px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700"
        >
          <span className="text-base leading-none">+</span> Invite User
        </button>
      </div>
      <DataTable
        columns={memberColumns}
        data={tenantMembers}
        loading={tenantMembersLoading}
        rowKey={(m) => m.user_id}
      />

      {/* Pending Invitations */}
      <div className="mt-8">
        <h3 className="text-lg font-semibold mb-3">Pending Invitations</h3>

        {invError && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 mb-4 text-sm">
            {invError}
          </div>
        )}

        {tenantInvitationsLoading ? (
          <div className="bg-white rounded-lg shadow p-6 animate-pulse">
            <div className="h-4 bg-gray-200 rounded w-1/3 mb-4" />
            <div className="h-4 bg-gray-200 rounded w-full mb-2" />
            <div className="h-4 bg-gray-200 rounded w-2/3" />
          </div>
        ) : tenantInvitations.length === 0 ? (
          <div className="bg-white rounded-lg shadow p-6 text-center text-gray-500 text-sm">
            No invitations for this tenant.
          </div>
        ) : (
          <div className="bg-white rounded-lg shadow overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-200">
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Email</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Role</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Code</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Status</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Sent</th>
                  <th className="text-left px-4 py-3 text-gray-500 font-medium">Expires</th>
                  <th className="text-right px-4 py-3 text-gray-500 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {tenantInvitations.map((inv: AdminInvitation) => (
                  <tr key={inv.id} className="border-b border-gray-100 last:border-0">
                    <td className="px-4 py-3">{inv.email || '\u2014'}</td>
                    <td className="px-4 py-3">
                      <RoleBadge role={inv.role} />
                    </td>
                    <td className="px-4 py-3 font-mono text-xs">{inv.short_code}</td>
                    <td className="px-4 py-3">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium capitalize ${
                        inv.status === 'pending' ? 'bg-yellow-100 text-yellow-800' :
                        inv.status === 'accepted' ? 'bg-green-100 text-green-800' :
                        inv.status === 'revoked' ? 'bg-red-100 text-red-800' :
                        'bg-gray-100 text-gray-700'
                      }`}>
                        {inv.status}
                      </span>
                    </td>
                    <td className="px-4 py-3">{formatDate(inv.created_at)}</td>
                    <td className="px-4 py-3">{formatDate(inv.expires_at)}</td>
                    <td className="px-4 py-3 text-right">
                      {inv.status === 'pending' && (
                        <button
                          onClick={() => handleRevoke(inv.id)}
                          disabled={revoking === inv.id}
                          className="px-3 py-1 text-xs border border-red-300 text-red-600 rounded-md hover:bg-red-50 disabled:opacity-50"
                        >
                          {revoking === inv.id ? 'Revoking...' : 'Revoke'}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Invite Dialog */}
      {tenant && (
        <InviteUserDialog
          open={inviteOpen}
          onClose={() => setInviteOpen(false)}
          tenantId={id!}
          tenantName={tenant.name}
          onInvited={() => fetchTenantInvitations(id!)}
        />
      )}
    </div>
  )
}
