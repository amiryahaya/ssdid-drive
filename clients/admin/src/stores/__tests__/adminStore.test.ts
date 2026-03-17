import { describe, it, expect, vi, beforeEach } from 'vitest'
import { useAdminStore } from '../adminStore'

vi.mock('../../services/api', () => ({
  api: {
    get: vi.fn(),
    post: vi.fn(),
    patch: vi.fn(),
    delete: vi.fn(),
  },
}))

import { api } from '../../services/api'

const mockApi = api as {
  get: ReturnType<typeof vi.fn>
  post: ReturnType<typeof vi.fn>
  patch: ReturnType<typeof vi.fn>
  delete: ReturnType<typeof vi.fn>
}

beforeEach(() => {
  vi.clearAllMocks()
  // Reset store state between tests
  useAdminStore.setState({
    users: [],
    usersTotal: 0,
    usersLoading: false,
    tenants: [],
    tenantsTotal: 0,
    tenantsLoading: false,
    tenantMembers: [],
    tenantMembersLoading: false,
    tenantInvitations: [],
    tenantInvitationsTotal: 0,
    tenantInvitationsLoading: false,
    auditLog: [],
    auditLogTotal: 0,
    auditLogLoading: false,
  })
})

describe('adminStore — fetchUsers', () => {
  it('fetches users and sets state', async () => {
    const items = [{ id: 'u1', did: 'did:ssdid:abc', display_name: 'Alice', email: 'alice@test.com', status: 'active', system_role: null, tenant_id: null, last_login_at: null, created_at: '2026-01-01T00:00:00Z' }]
    mockApi.get.mockResolvedValue({ items, total: 1, page: 1, page_size: 20 })

    await useAdminStore.getState().fetchUsers(1, 20)

    expect(mockApi.get).toHaveBeenCalledWith('/api/admin/users?page=1&page_size=20')
    expect(useAdminStore.getState().users).toEqual(items)
    expect(useAdminStore.getState().usersTotal).toBe(1)
    expect(useAdminStore.getState().usersLoading).toBe(false)
  })

  it('includes search parameter when provided', async () => {
    mockApi.get.mockResolvedValue({ items: [], total: 0, page: 1, page_size: 20 })

    await useAdminStore.getState().fetchUsers(1, 20, 'alice')

    expect(mockApi.get).toHaveBeenCalledWith('/api/admin/users?page=1&page_size=20&search=alice')
  })

  it('sets loading true then false', async () => {
    const states: boolean[] = []
    useAdminStore.subscribe((s) => states.push(s.usersLoading))

    mockApi.get.mockResolvedValue({ items: [], total: 0, page: 1, page_size: 20 })
    await useAdminStore.getState().fetchUsers(1, 20)

    expect(states[0]).toBe(true)
    expect(useAdminStore.getState().usersLoading).toBe(false)
  })

  it('clears users and re-throws on error', async () => {
    mockApi.get.mockRejectedValue(new Error('Network error'))

    await expect(useAdminStore.getState().fetchUsers(1, 20)).rejects.toThrow('Network error')
    expect(useAdminStore.getState().users).toEqual([])
    expect(useAdminStore.getState().usersTotal).toBe(0)
    expect(useAdminStore.getState().usersLoading).toBe(false)
  })
})

describe('adminStore — updateUser', () => {
  it('patches user and updates store list', async () => {
    const user = { id: 'u1', did: 'did:ssdid:abc', display_name: 'Alice', email: null, status: 'active', system_role: null, tenant_id: null, last_login_at: null, created_at: '2026-01-01T00:00:00Z' }
    useAdminStore.setState({ users: [user] })

    const updated = { ...user, status: 'suspended' }
    mockApi.patch.mockResolvedValue(updated)

    await useAdminStore.getState().updateUser('u1', { status: 'suspended' })

    expect(mockApi.patch).toHaveBeenCalledWith('/api/admin/users/u1', { status: 'suspended' })
    expect(useAdminStore.getState().users[0].status).toBe('suspended')
  })

  it('does not update store if user not in current list', async () => {
    useAdminStore.setState({ users: [] })
    mockApi.patch.mockResolvedValue({ id: 'u1', status: 'suspended' })

    await useAdminStore.getState().updateUser('u1', { status: 'suspended' })

    expect(useAdminStore.getState().users).toEqual([])
  })
})

describe('adminStore — fetchTenants', () => {
  it('fetches tenants and sets state', async () => {
    const items = [{ id: 't1', name: 'Acme', slug: 'acme', disabled: false, storage_quota_bytes: null, user_count: 5, created_at: '2026-01-01T00:00:00Z' }]
    mockApi.get.mockResolvedValue({ items, total: 1, page: 1, page_size: 20 })

    await useAdminStore.getState().fetchTenants(1, 20)

    expect(mockApi.get).toHaveBeenCalledWith('/api/admin/tenants?page=1&page_size=20')
    expect(useAdminStore.getState().tenants).toEqual(items)
    expect(useAdminStore.getState().tenantsTotal).toBe(1)
  })

  it('includes search parameter when provided', async () => {
    mockApi.get.mockResolvedValue({ items: [], total: 0, page: 1, page_size: 20 })

    await useAdminStore.getState().fetchTenants(1, 20, 'acme')

    expect(mockApi.get).toHaveBeenCalledWith('/api/admin/tenants?page=1&page_size=20&search=acme')
  })

  it('clears tenants and re-throws on error', async () => {
    mockApi.get.mockRejectedValue(new Error('Server error'))

    await expect(useAdminStore.getState().fetchTenants(1, 20)).rejects.toThrow('Server error')
    expect(useAdminStore.getState().tenants).toEqual([])
    expect(useAdminStore.getState().tenantsLoading).toBe(false)
  })
})

describe('adminStore — fetchTenantById', () => {
  it('returns tenant from API', async () => {
    const tenant = { id: 't1', name: 'Acme', slug: 'acme', disabled: false, storage_quota_bytes: null, user_count: 5, created_at: '2026-01-01T00:00:00Z' }
    mockApi.get.mockResolvedValue(tenant)

    const result = await useAdminStore.getState().fetchTenantById('t1')

    expect(mockApi.get).toHaveBeenCalledWith('/api/admin/tenants/t1')
    expect(result).toEqual(tenant)
  })
})

describe('adminStore — createTenant', () => {
  it('posts new tenant and returns it', async () => {
    const created = { id: 't2', name: 'Beta', slug: 'beta', disabled: false, storage_quota_bytes: null, user_count: 0, created_at: '2026-01-01T00:00:00Z' }
    mockApi.post.mockResolvedValue(created)

    const result = await useAdminStore.getState().createTenant('Beta', 'beta')

    expect(mockApi.post).toHaveBeenCalledWith('/api/admin/tenants', { name: 'Beta', slug: 'beta' })
    expect(result).toEqual(created)
  })
})

describe('adminStore — updateTenant', () => {
  it('patches tenant and updates store list', async () => {
    const tenant = { id: 't1', name: 'Acme', slug: 'acme', disabled: false, storage_quota_bytes: null, user_count: 5, created_at: '2026-01-01T00:00:00Z' }
    useAdminStore.setState({ tenants: [tenant] })

    const updated = { ...tenant, name: 'Acme Corp' }
    mockApi.patch.mockResolvedValue(updated)

    await useAdminStore.getState().updateTenant('t1', { name: 'Acme Corp' })

    expect(mockApi.patch).toHaveBeenCalledWith('/api/admin/tenants/t1', { name: 'Acme Corp' })
    expect(useAdminStore.getState().tenants[0].name).toBe('Acme Corp')
  })

  it('sends clear_storage_quota flag and removes storage_quota_bytes from body', async () => {
    const tenant = { id: 't1', name: 'Acme', slug: 'acme', disabled: false, storage_quota_bytes: 1073741824, user_count: 5, created_at: '2026-01-01T00:00:00Z' }
    useAdminStore.setState({ tenants: [tenant] })
    mockApi.patch.mockResolvedValue({ ...tenant, storage_quota_bytes: null })

    await useAdminStore.getState().updateTenant('t1', {}, true)

    expect(mockApi.patch).toHaveBeenCalledWith('/api/admin/tenants/t1', { clear_storage_quota: true })
  })
})

describe('adminStore — fetchTenantMembers', () => {
  it('fetches members and sets state', async () => {
    const items = [{ user_id: 'u1', did: 'did:ssdid:abc', display_name: 'Alice', email: 'a@b.com', role: 'Owner' }]
    mockApi.get.mockResolvedValue({ items })

    await useAdminStore.getState().fetchTenantMembers('t1')

    expect(mockApi.get).toHaveBeenCalledWith('/api/admin/tenants/t1/members')
    expect(useAdminStore.getState().tenantMembers).toEqual(items)
    expect(useAdminStore.getState().tenantMembersLoading).toBe(false)
  })

  it('clears members on error', async () => {
    mockApi.get.mockRejectedValue(new Error('fail'))

    await expect(useAdminStore.getState().fetchTenantMembers('t1')).rejects.toThrow('fail')
    expect(useAdminStore.getState().tenantMembers).toEqual([])
  })
})

describe('adminStore — tenantInvitations', () => {
  it('fetches invitations with pagination', async () => {
    const items = [{ id: 'i1', tenant_id: 't1', invited_by_id: 'u1', email: 'new@test.com', invited_user_id: null, role: 'owner', status: 'pending', short_code: 'CODE-1', message: null, expires_at: '2026-04-01T00:00:00Z', created_at: '2026-03-01T00:00:00Z' }]
    mockApi.get.mockResolvedValue({ items, total: 1, page: 1, page_size: 20 })

    await useAdminStore.getState().fetchTenantInvitations('t1')

    expect(mockApi.get).toHaveBeenCalledWith('/api/admin/tenants/t1/invitations?page=1&page_size=20')
    expect(useAdminStore.getState().tenantInvitations).toEqual(items)
    expect(useAdminStore.getState().tenantInvitationsTotal).toBe(1)
  })

  it('creates invitation via API', async () => {
    const created = { id: 'i1', tenant_id: 't1', invited_by_id: 'u1', email: 'new@test.com', invited_user_id: null, role: 'admin', status: 'pending', short_code: 'CODE-1', message: null, expires_at: '2026-04-01T00:00:00Z', created_at: '2026-03-01T00:00:00Z' }
    mockApi.post.mockResolvedValue(created)

    const result = await useAdminStore.getState().createAdminInvitation('t1', 'new@test.com', 'admin')

    expect(mockApi.post).toHaveBeenCalledWith('/api/admin/tenants/t1/invitations', { email: 'new@test.com', role: 'admin' })
    expect(result).toEqual(created)
  })

  it('includes message in invitation body when provided', async () => {
    mockApi.post.mockResolvedValue({ id: 'i1' })

    await useAdminStore.getState().createAdminInvitation('t1', 'new@test.com', 'owner', 'Welcome!')

    expect(mockApi.post).toHaveBeenCalledWith('/api/admin/tenants/t1/invitations', { email: 'new@test.com', role: 'owner', message: 'Welcome!' })
  })

  it('revokes invitation and updates status in store', async () => {
    const inv = { id: 'i1', tenant_id: 't1', invited_by_id: 'u1', email: 'a@b.com', invited_user_id: null, role: 'owner', status: 'pending', short_code: 'CODE-1', message: null, expires_at: '2026-04-01T00:00:00Z', created_at: '2026-03-01T00:00:00Z' }
    useAdminStore.setState({ tenantInvitations: [inv] })
    mockApi.delete.mockResolvedValue(undefined)

    await useAdminStore.getState().revokeAdminInvitation('t1', 'i1')

    expect(mockApi.delete).toHaveBeenCalledWith('/api/admin/tenants/t1/invitations/i1')
    expect(useAdminStore.getState().tenantInvitations[0].status).toBe('revoked')
  })
})

describe('adminStore — fetchAuditLog', () => {
  it('fetches audit log entries', async () => {
    const items = [{ id: 'a1', actor_id: 'u1', actor_name: 'Alice', action: 'auth.login', target_type: null, target_id: null, details: null, created_at: '2026-03-01T00:00:00Z' }]
    mockApi.get.mockResolvedValue({ items, total: 1, page: 1, page_size: 20 })

    await useAdminStore.getState().fetchAuditLog(1, 20)

    expect(useAdminStore.getState().auditLog).toEqual(items)
    expect(useAdminStore.getState().auditLogTotal).toBe(1)
    expect(useAdminStore.getState().auditLogLoading).toBe(false)
  })

  it('passes filter parameters to API', async () => {
    mockApi.get.mockResolvedValue({ items: [], total: 0, page: 1, page_size: 20 })

    await useAdminStore.getState().fetchAuditLog(1, 20, {
      actor: 'alice',
      action: 'auth.login',
      from: '2026-01-01',
      to: '2026-03-01',
    })

    const calledPath = mockApi.get.mock.calls[0][0] as string
    expect(calledPath).toContain('actor=alice')
    expect(calledPath).toContain('action=auth.login')
    expect(calledPath).toContain('from=2026-01-01')
    expect(calledPath).toContain('to=2026-03-01')
  })

  it('clears audit log on error', async () => {
    mockApi.get.mockRejectedValue(new Error('fail'))

    await expect(useAdminStore.getState().fetchAuditLog(1, 20)).rejects.toThrow('fail')
    expect(useAdminStore.getState().auditLog).toEqual([])
    expect(useAdminStore.getState().auditLogTotal).toBe(0)
    expect(useAdminStore.getState().auditLogLoading).toBe(false)
  })
})
