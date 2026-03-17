import { create } from 'zustand'
import { api } from '../services/api'

export interface User {
  id: string
  did: string
  display_name: string | null
  email: string | null
  status: string
  system_role: string | null
  tenant_id: string | null
  last_login_at: string | null
  created_at: string
}

export interface Tenant {
  id: string
  name: string
  slug: string
  disabled: boolean
  storage_quota_bytes: number | null
  user_count: number
  created_at: string
}

export interface TenantMember {
  user_id: string
  did: string
  display_name: string | null
  email: string | null
  role: string
}

export interface AdminInvitation {
  id: string
  tenant_id: string
  invited_by_id: string
  email: string | null
  invited_user_id: string | null
  role: string
  status: string
  short_code: string
  message: string | null
  expires_at: string
  created_at: string
}

interface AdminInvitationsResponse {
  items: AdminInvitation[]
  total: number
  page: number
  page_size: number
}

interface UsersResponse {
  items: User[]
  total: number
  page: number
  page_size: number
}

interface TenantsResponse {
  items: Tenant[]
  total: number
  page: number
  page_size: number
}

interface TenantMembersResponse {
  items: TenantMember[]
}

export interface AuditLogEntry {
  id: string
  actor_id: string
  actor_name: string | null
  action: string
  target_type: string | null
  target_id: string | null
  details: string | null
  created_at: string
}

interface AuditLogResponse {
  items: AuditLogEntry[]
  total: number
  page: number
  page_size: number
}

interface AdminState {
  users: User[]
  usersTotal: number
  usersLoading: boolean
  fetchUsers: (page: number, pageSize: number, search?: string) => Promise<void>
  updateUser: (id: string, patch: Partial<Pick<User, 'status' | 'system_role'>>) => Promise<void>

  tenants: Tenant[]
  tenantsTotal: number
  tenantsLoading: boolean
  fetchTenants: (page: number, pageSize: number, search?: string) => Promise<void>
  fetchTenantById: (id: string) => Promise<Tenant>
  createTenant: (name: string, slug: string) => Promise<Tenant>
  updateTenant: (id: string, patch: Partial<Pick<Tenant, 'name' | 'disabled' | 'storage_quota_bytes'>>, clearStorageQuota?: boolean) => Promise<void>

  tenantMembers: TenantMember[]
  tenantMembersLoading: boolean
  fetchTenantMembers: (tenantId: string) => Promise<void>

  tenantInvitations: AdminInvitation[]
  tenantInvitationsTotal: number
  tenantInvitationsLoading: boolean
  fetchTenantInvitations: (tenantId: string, page?: number, pageSize?: number) => Promise<void>
  createAdminInvitation: (tenantId: string, email: string, role: string, message?: string) => Promise<AdminInvitation>
  revokeAdminInvitation: (tenantId: string, invitationId: string) => Promise<void>

  auditLog: AuditLogEntry[]
  auditLogTotal: number
  auditLogLoading: boolean
  fetchAuditLog: (page: number, pageSize: number, filters?: { actor?: string; action?: string; from?: string; to?: string }) => Promise<void>
}

export const useAdminStore = create<AdminState>((set, get) => ({
  users: [],
  usersTotal: 0,
  usersLoading: false,

  fetchUsers: async (page: number, pageSize: number, search?: string) => {
    set({ usersLoading: true })
    try {
      let path = `/api/admin/users?page=${page}&page_size=${pageSize}`
      if (search) {
        path += `&search=${encodeURIComponent(search)}`
      }
      const res = await api.get<UsersResponse>(path)
      set({ users: res.items, usersTotal: res.total })
    } catch (err) {
      set({ users: [], usersTotal: 0 })
      throw err
    } finally {
      set({ usersLoading: false })
    }
  },

  updateUser: async (id: string, patch: Partial<Pick<User, 'status' | 'system_role'>>) => {
    const updated = await api.patch<User>(`/api/admin/users/${id}`, patch)
    const current = get().users
    if (current.some((u) => u.id === id)) {
      set({ users: current.map((u) => (u.id === id ? updated : u)) })
    }
  },

  tenants: [],
  tenantsTotal: 0,
  tenantsLoading: false,

  fetchTenants: async (page: number, pageSize: number, search?: string) => {
    set({ tenantsLoading: true })
    try {
      let path = `/api/admin/tenants?page=${page}&page_size=${pageSize}`
      if (search) {
        path += `&search=${encodeURIComponent(search)}`
      }
      const res = await api.get<TenantsResponse>(path)
      set({ tenants: res.items, tenantsTotal: res.total })
    } catch (err) {
      set({ tenants: [], tenantsTotal: 0 })
      throw err
    } finally {
      set({ tenantsLoading: false })
    }
  },

  fetchTenantById: async (id: string) => {
    return api.get<Tenant>(`/api/admin/tenants/${id}`)
  },

  createTenant: async (name: string, slug: string) => {
    const created = await api.post<Tenant>('/api/admin/tenants', { name, slug })
    return created
  },

  updateTenant: async (id: string, patch: Partial<Pick<Tenant, 'name' | 'disabled' | 'storage_quota_bytes'>>, clearStorageQuota?: boolean) => {
    const body: Record<string, unknown> = { ...patch }
    if (clearStorageQuota) {
      body.clear_storage_quota = true
      delete body.storage_quota_bytes
    }
    const updated = await api.patch<Tenant>(`/api/admin/tenants/${id}`, body)
    const current = get().tenants
    if (current.some((t) => t.id === id)) {
      set({ tenants: current.map((t) => (t.id === id ? updated : t)) })
    }
  },

  tenantMembers: [],
  tenantMembersLoading: false,

  fetchTenantMembers: async (tenantId: string) => {
    set({ tenantMembersLoading: true })
    try {
      const res = await api.get<TenantMembersResponse>(`/api/admin/tenants/${tenantId}/members`)
      set({ tenantMembers: res.items })
    } catch (err) {
      set({ tenantMembers: [] })
      throw err
    } finally {
      set({ tenantMembersLoading: false })
    }
  },

  tenantInvitations: [],
  tenantInvitationsTotal: 0,
  tenantInvitationsLoading: false,

  fetchTenantInvitations: async (tenantId: string, page = 1, pageSize = 20) => {
    set({ tenantInvitationsLoading: true, tenantInvitations: [], tenantInvitationsTotal: 0 })
    try {
      const res = await api.get<AdminInvitationsResponse>(
        `/api/admin/tenants/${tenantId}/invitations?page=${page}&page_size=${pageSize}`)
      set({ tenantInvitations: res.items, tenantInvitationsTotal: res.total })
    } catch (err) {
      set({ tenantInvitations: [], tenantInvitationsTotal: 0 })
      throw err
    } finally {
      set({ tenantInvitationsLoading: false })
    }
  },

  createAdminInvitation: async (tenantId: string, email: string, role: string, message?: string) => {
    const body: Record<string, string> = { email, role }
    if (message) body.message = message
    return api.post<AdminInvitation>(`/api/admin/tenants/${tenantId}/invitations`, body)
  },

  revokeAdminInvitation: async (tenantId: string, invitationId: string) => {
    await api.delete(`/api/admin/tenants/${tenantId}/invitations/${invitationId}`)
    set({
      tenantInvitations: get().tenantInvitations.map((inv) =>
        inv.id === invitationId ? { ...inv, status: 'revoked' } : inv
      ),
    })
  },

  auditLog: [],
  auditLogTotal: 0,
  auditLogLoading: false,

  fetchAuditLog: async (page: number, pageSize: number, filters?: { actor?: string; action?: string; from?: string; to?: string }) => {
    set({ auditLogLoading: true })
    try {
      const params = new URLSearchParams({ page: String(page), page_size: String(pageSize) })
      if (filters?.actor) params.set('actor', filters.actor)
      if (filters?.action) params.set('action', filters.action)
      if (filters?.from) params.set('from', filters.from)
      if (filters?.to) params.set('to', filters.to)
      const res = await api.get<AuditLogResponse>(
        `/api/admin/audit-log?${params}`,
      )
      set({ auditLog: res.items, auditLogTotal: res.total })
    } catch (err) {
      set({ auditLog: [], auditLogTotal: 0 })
      throw err
    } finally {
      set({ auditLogLoading: false })
    }
  },
}))
