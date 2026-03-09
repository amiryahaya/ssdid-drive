import { useState, useEffect, useCallback } from 'react'
import { useLocation } from 'react-router-dom'
import { useAuthStore } from '../stores/authStore'
import Sidebar from './Sidebar'

const STORAGE_KEY = 'ssdid_admin_sidebar'

const routeTitles: Record<string, string> = {
  '/': 'Dashboard',
  '/users': 'Users',
  '/tenants': 'Tenants',
  '/audit-log': 'Audit Log',
}

function getPageTitle(pathname: string): string {
  if (routeTitles[pathname]) return routeTitles[pathname]
  if (pathname.startsWith('/tenants/')) return 'Tenant Details'
  return 'SSDID Drive Admin'
}

export default function Layout({ children }: { children: React.ReactNode }) {
  const location = useLocation()
  const user = useAuthStore((s) => s.user)
  const logout = useAuthStore((s) => s.logout)

  const [collapsed, setCollapsed] = useState(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      return stored === 'true'
    } catch {
      return false
    }
  })
  const [mobileOpen, setMobileOpen] = useState(false)
  const [isDesktop, setIsDesktop] = useState(false)

  // Persist collapsed state
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, String(collapsed))
    } catch {
      // ignore
    }
  }, [collapsed])

  // Detect breakpoint
  useEffect(() => {
    const mql = window.matchMedia('(min-width: 1024px)')
    const handleChange = (e: MediaQueryListEvent | MediaQueryList) => {
      setIsDesktop(e.matches)
      if (!e.matches) {
        setMobileOpen(false)
      }
    }
    handleChange(mql)
    mql.addEventListener('change', handleChange)
    return () => mql.removeEventListener('change', handleChange)
  }, [])

  // Auto-collapse on tablet
  useEffect(() => {
    const tabletMql = window.matchMedia('(min-width: 768px) and (max-width: 1023px)')
    const handleTablet = (e: MediaQueryListEvent | MediaQueryList) => {
      if (e.matches) {
        setCollapsed(true)
      }
    }
    handleTablet(tabletMql)
    tabletMql.addEventListener('change', handleTablet)
    return () => tabletMql.removeEventListener('change', handleTablet)
  }, [])

  // Close mobile drawer on route change
  useEffect(() => {
    setMobileOpen(false)
  }, [location.pathname])

  const handleToggle = useCallback(() => {
    setCollapsed((prev) => !prev)
  }, [])

  const handleMobileClose = useCallback(() => {
    setMobileOpen(false)
  }, [])

  const isMobile = !isDesktop
  const showTablet = !isDesktop && window.matchMedia('(min-width: 768px)').matches

  const pageTitle = getPageTitle(location.pathname)

  return (
    <div className="flex h-screen overflow-hidden bg-gray-50">
      {/* Desktop / Tablet sidebar */}
      {isDesktop && (
        <Sidebar
          collapsed={collapsed}
          onToggle={handleToggle}
        />
      )}

      {/* Tablet: collapsed sidebar always visible */}
      {showTablet && !isDesktop && (
        <Sidebar
          collapsed={true}
          onToggle={handleToggle}
        />
      )}

      {/* Mobile overlay */}
      {isMobile && mobileOpen && (
        <>
          {/* Backdrop */}
          <div
            className="fixed inset-0 z-40 bg-black/40 backdrop-blur-sm"
            onClick={handleMobileClose}
          />
          {/* Drawer */}
          <div className="fixed inset-y-0 left-0 z-50 w-60">
            <Sidebar
              collapsed={false}
              onToggle={handleToggle}
              onClose={handleMobileClose}
            />
          </div>
        </>
      )}

      {/* Main content */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Header */}
        <header className="flex items-center h-14 px-4 bg-white border-b border-gray-200 shrink-0">
          {/* Mobile hamburger */}
          {isMobile && !showTablet && (
            <button
              onClick={() => setMobileOpen(true)}
              className="mr-3 p-1.5 -ml-1.5 text-gray-500 hover:text-gray-700 rounded-md hover:bg-gray-100 transition-colors lg:hidden"
              aria-label="Open menu"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path d="M4 6h16M4 12h16M4 18h16" strokeLinecap="round" />
              </svg>
            </button>
          )}

          <h1 className="text-lg font-semibold text-gray-900">{pageTitle}</h1>

          <div className="ml-auto flex items-center gap-3">
            {isDesktop && (
              <>
                <span className="text-sm text-gray-500 truncate max-w-48">
                  {user?.display_name || user?.did}
                </span>
                <button
                  onClick={logout}
                  className="text-sm text-gray-500 hover:text-gray-700 transition-colors"
                >
                  Sign Out
                </button>
              </>
            )}
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-7xl mx-auto">
            {children}
          </div>
        </main>
      </div>
    </div>
  )
}
