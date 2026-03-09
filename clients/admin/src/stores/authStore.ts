import { create } from 'zustand'
import { api, setToken, getToken } from '../services/api'

interface User {
  id: string
  did: string
  display_name: string | null
  system_role: string | null
}

interface AuthState {
  token: string | null
  user: User | null
  isAuthenticated: boolean
  login: (token: string) => Promise<void>
  logout: () => void
  initialize: () => Promise<void>
}

export const useAuthStore = create<AuthState>((set) => ({
  token: getToken(),
  user: null,
  isAuthenticated: false,

  login: async (token: string) => {
    setToken(token)
    const user = await api.get<User>('/api/me')
    set({ token, user, isAuthenticated: true })
  },

  logout: () => {
    setToken(null)
    set({ token: null, user: null, isAuthenticated: false })
  },

  initialize: async () => {
    const token = getToken()
    if (!token) return
    try {
      const user = await api.get<User>('/api/me')
      set({ token, user, isAuthenticated: true })
    } catch {
      setToken(null)
      set({ token: null, user: null, isAuthenticated: false })
    }
  },
}))
