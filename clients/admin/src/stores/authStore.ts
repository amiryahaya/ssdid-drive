import { create } from 'zustand'
import { api, setToken, getToken, setOnUnauthorized } from '../services/api'

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

export const useAuthStore = create<AuthState>((set) => {
  const logout = () => {
    setToken(null)
    set({ token: null, user: null, isAuthenticated: false })
  }

  // Wire up API 401/403 handler to logout
  setOnUnauthorized(logout)

  return {
    token: getToken(),
    user: null,
    isAuthenticated: false,

    login: async (token: string) => {
      setToken(token)
      try {
        const user = await api.get<User>('/api/me')
        if (user.system_role !== 'SuperAdmin') {
          throw new Error('Admin access required')
        }
        set({ token, user, isAuthenticated: true })
      } catch (err) {
        setToken(null)
        throw err
      }
    },

    logout,

    initialize: async () => {
      const token = getToken()
      if (!token) return
      try {
        const user = await api.get<User>('/api/me')
        if (user.system_role !== 'SuperAdmin') {
          throw new Error('Admin access required')
        }
        set({ token, user, isAuthenticated: true })
      } catch {
        setToken(null)
        set({ token: null, user: null, isAuthenticated: false })
      }
    },
  }
})
