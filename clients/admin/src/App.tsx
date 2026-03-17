import { Component, useEffect, useState } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { BrowserRouter, Routes, Route, Link } from 'react-router-dom'
import { useAuthStore } from './stores/authStore'
import LoginPage from './pages/LoginPage'
import AuthCallbackPage from './pages/AuthCallbackPage'
import BootstrapPage from './pages/BootstrapPage'
import DashboardPage from './pages/DashboardPage'
import UsersPage from './pages/UsersPage'
import TenantsPage from './pages/TenantsPage'
import TenantDetailPage from './pages/TenantDetailPage'
import AuditLogPage from './pages/AuditLogPage'
import NotificationsPage from './pages/NotificationsPage'
import Layout from './components/Layout'

class ErrorBoundary extends Component<
  { children: ReactNode },
  { hasError: boolean; error: Error | null }
> {
  constructor(props: { children: ReactNode }) {
    super(props)
    this.state = { hasError: false, error: null }
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('ErrorBoundary caught:', error, info)
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-gray-50">
          <div className="bg-white rounded-lg shadow p-8 max-w-md text-center">
            <h2 className="text-xl font-semibold text-gray-900 mb-2">Something went wrong</h2>
            <p className="text-gray-600 mb-4">{this.state.error?.message}</p>
            <button
              onClick={() => window.location.reload()}
              className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700"
            >
              Reload Page
            </button>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}

function NotFoundPage() {
  return (
    <div className="text-center py-16">
      <h2 className="text-2xl font-semibold text-gray-900 mb-2">Page Not Found</h2>
      <p className="text-gray-600 mb-4">The page you are looking for does not exist.</p>
      <Link to="/" className="text-blue-600 hover:text-blue-800">
        Go to Dashboard
      </Link>
    </div>
  )
}

function AuthenticatedApp() {
  return (
    <Layout>
      <Routes>
        <Route path="/" element={<DashboardPage />} />
        <Route path="/users" element={<UsersPage />} />
        <Route path="/tenants" element={<TenantsPage />} />
        <Route path="/tenants/:id" element={<TenantDetailPage />} />
        <Route path="/audit-log" element={<AuditLogPage />} />
        <Route path="/notifications" element={<NotificationsPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </Layout>
  )
}

function App() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const initialize = useAuthStore((s) => s.initialize)
  const [ready, setReady] = useState(false)
  const [bootstrapRequired, setBootstrapRequired] = useState(false)

  useEffect(() => {
    Promise.all([
      initialize(),
      fetch('/api/admin/bootstrap/status')
        .then(r => r.json())
        .then(data => setBootstrapRequired(data.required))
        .catch(() => setBootstrapRequired(false)),
    ]).finally(() => setReady(true))
  }, [initialize])

  if (!ready) return null

  return (
    <ErrorBoundary>
      <BrowserRouter basename="/admin">
        <Routes>
          <Route path="/auth/callback" element={<AuthCallbackPage />} />
          <Route path="*" element={
            bootstrapRequired
              ? <BootstrapPage />
              : isAuthenticated
                ? <AuthenticatedApp />
                : <LoginPage />
          } />
        </Routes>
      </BrowserRouter>
    </ErrorBoundary>
  )
}

export default App
