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
  createTenant: (name: string, slug: string) => Promise<Tenant>
  updateTenant: (id: string, patch: Partial<Pick<Tenant, 'name' | 'disabled' | 'storage_quota_bytes'>>) => Promise<void>

  tenantMembers: TenantMember[]
  tenantMembersLoading: boolean
  fetchTenantMembers: (tenantId: string) => Promise<void>
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
    } finally {
      set({ usersLoading: false })
    }
  },

  updateUser: async (id: string, patch: Partial<Pick<User, 'status' | 'system_role'>>) => {
    const updated = await api.patch<User>(`/api/admin/users/${id}`, patch)
    set({
      users: get().users.map((u) => (u.id === id ? updated : u)),
    })
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
    } finally {
      set({ tenantsLoading: false })
    }
  },

  createTenant: async (name: string, slug: string) => {
    const created = await api.post<Tenant>('/api/admin/tenants', { name, slug })
    return created
  },

  updateTenant: async (id: string, patch: Partial<Pick<Tenant, 'name' | 'disabled' | 'storage_quota_bytes'>>) => {
    const updated = await api.patch<Tenant>(`/api/admin/tenants/${id}`, patch)
    set({
      tenants: get().tenants.map((t) => (t.id === id ? updated : t)),
    })
  },

  tenantMembers: [],
  tenantMembersLoading: false,

  fetchTenantMembers: async (tenantId: string) => {
    set({ tenantMembersLoading: true })
    try {
      const res = await api.get<TenantMembersResponse>(`/api/admin/tenants/${tenantId}/members`)
      set({ tenantMembers: res.items })
    } finally {
      set({ tenantMembersLoading: false })
    }
  },
}))
