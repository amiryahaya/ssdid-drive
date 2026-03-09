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

interface UsersResponse {
  items: User[]
  total: number
  offset: number
  limit: number
}

interface AdminState {
  users: User[]
  usersTotal: number
  usersLoading: boolean
  fetchUsers: (offset: number, limit: number, search?: string) => Promise<void>
  updateUser: (id: string, patch: Partial<Pick<User, 'status' | 'system_role'>>) => Promise<void>
}

export const useAdminStore = create<AdminState>((set, get) => ({
  users: [],
  usersTotal: 0,
  usersLoading: false,

  fetchUsers: async (offset: number, limit: number, search?: string) => {
    set({ usersLoading: true })
    try {
      let path = `/api/admin/users?offset=${offset}&limit=${limit}`
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
}))
