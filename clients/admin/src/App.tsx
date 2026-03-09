import { useEffect, useState } from 'react'
import { BrowserRouter, Routes, Route, Link } from 'react-router-dom'
import { useAuthStore } from './stores/authStore'
import LoginPage from './pages/LoginPage'
import DashboardPage from './pages/DashboardPage'
import UsersPage from './pages/UsersPage'
import TenantsPage from './pages/TenantsPage'
import TenantDetailPage from './pages/TenantDetailPage'
import AuditLogPage from './pages/AuditLogPage'

function AuthenticatedApp() {
  const user = useAuthStore((s) => s.user)
  const logout = useAuthStore((s) => s.logout)

  return (
    <div className="min-h-screen bg-gray-50 text-gray-900">
      <header className="bg-white border-b border-gray-200 px-6 py-4">
        <div className="flex items-center justify-between max-w-7xl mx-auto">
          <h1 className="text-xl font-bold">SSDID Drive Admin</h1>
          <div className="flex items-center gap-4">
            <nav className="flex gap-4 text-sm">
              <Link to="/" className="text-gray-600 hover:text-gray-900">
                Dashboard
              </Link>
              <Link to="/users" className="text-gray-600 hover:text-gray-900">
                Users
              </Link>
              <Link to="/tenants" className="text-gray-600 hover:text-gray-900">
                Tenants
              </Link>
              <Link to="/audit-log" className="text-gray-600 hover:text-gray-900">
                Audit Log
              </Link>
            </nav>
            <div className="flex items-center gap-3 text-sm">
              <span className="text-gray-500">
                {user?.display_name || user?.did}
              </span>
              <button
                onClick={logout}
                className="text-gray-500 hover:text-gray-900"
              >
                Sign Out
              </button>
            </div>
          </div>
        </div>
      </header>
      <main className="max-w-7xl mx-auto px-6 py-8">
        <Routes>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/users" element={<UsersPage />} />
          <Route path="/tenants" element={<TenantsPage />} />
          <Route path="/tenants/:id" element={<TenantDetailPage />} />
          <Route path="/audit-log" element={<AuditLogPage />} />
        </Routes>
      </main>
    </div>
  )
}

function App() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const initialize = useAuthStore((s) => s.initialize)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    initialize().finally(() => setReady(true))
  }, [initialize])

  if (!ready) return null

  return (
    <BrowserRouter basename="/admin">
      {isAuthenticated ? <AuthenticatedApp /> : <LoginPage />}
    </BrowserRouter>
  )
}

export default App
