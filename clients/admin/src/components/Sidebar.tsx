import { Link, useLocation } from 'react-router-dom'
import { useAuthStore } from '../stores/authStore'

interface SidebarProps {
  collapsed: boolean
  onToggle: () => void
  onClose?: () => void
}

const navItems = [
  {
    path: '/',
    label: 'Dashboard',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <rect x="3" y="3" width="8" height="8" rx="1.5" />
        <rect x="13" y="3" width="8" height="8" rx="1.5" />
        <rect x="3" y="13" width="8" height="8" rx="1.5" />
        <rect x="13" y="13" width="8" height="8" rx="1.5" />
      </svg>
    ),
  },
  {
    path: '/users',
    label: 'Users',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <circle cx="9" cy="7" r="3.5" />
        <path d="M2.5 20c0-3.5 2.9-6 6.5-6s6.5 2.5 6.5 6" strokeLinecap="round" />
        <circle cx="17.5" cy="8.5" r="2.5" />
        <path d="M17.5 14c2.5 0 4.5 1.8 4.5 4.5" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    path: '/tenants',
    label: 'Tenants',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <path d="M3 21V7l9-4 9 4v14" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M9 21v-6h6v6" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M9 10h.01M15 10h.01M9 14h.01M15 14h.01" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    path: '/audit-log',
    label: 'Audit Log',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <rect x="4" y="3" width="16" height="18" rx="2" />
        <path d="M8 8h8M8 12h8M8 16h5" strokeLinecap="round" />
      </svg>
    ),
  },
]

export default function Sidebar({ collapsed, onToggle, onClose }: SidebarProps) {
  const location = useLocation()
  const user = useAuthStore((s) => s.user)
  const logout = useAuthStore((s) => s.logout)

  const isActive = (path: string) => {
    if (path === '/') return location.pathname === '/'
    return location.pathname.startsWith(path)
  }

  const handleNavClick = () => {
    onClose?.()
  }

  return (
    <aside
      className="flex flex-col h-full bg-white border-r border-gray-200 overflow-hidden transition-all duration-200 ease-in-out"
      style={{ width: collapsed ? 64 : 240 }}
    >
      {/* Logo / brand */}
      <div className="flex items-center h-14 px-4 border-b border-gray-200 shrink-0">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5} className="text-blue-600 shrink-0">
          <path d="M12 2L3 7v10l9 5 9-5V7l-9-5z" strokeLinejoin="round" />
          <path d="M12 12l9-5M12 12v10M12 12L3 7" strokeLinejoin="round" />
        </svg>
        {!collapsed && (
          <span className="ml-3 text-sm font-bold text-gray-900 whitespace-nowrap">
            SSDID Drive
          </span>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 py-2 overflow-y-auto overflow-x-hidden">
        {navItems.map((item) => {
          const active = isActive(item.path)
          return (
            <Link
              key={item.path}
              to={item.path}
              onClick={handleNavClick}
              className={`flex items-center h-10 mx-2 my-0.5 rounded-md transition-colors duration-150 ${
                active
                  ? 'border-l-3 border-blue-600 bg-blue-50 text-blue-700'
                  : 'text-gray-600 hover:bg-gray-50 border-l-3 border-transparent'
              }`}
              title={collapsed ? item.label : undefined}
            >
              <span className="shrink-0 w-10 flex items-center justify-center">
                {item.icon}
              </span>
              {!collapsed && (
                <span className="text-sm font-medium whitespace-nowrap">
                  {item.label}
                </span>
              )}
            </Link>
          )
        })}
      </nav>

      {/* User info */}
      <div className="border-t border-gray-200 p-3 shrink-0">
        {collapsed ? (
          <div className="flex flex-col items-center gap-2">
            <button
              onClick={logout}
              title="Sign Out"
              className="w-9 h-9 rounded-full bg-gray-100 flex items-center justify-center text-gray-500 hover:text-gray-700 hover:bg-gray-200 transition-colors"
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                <circle cx="12" cy="8" r="4" />
                <path d="M4 20c0-3.3 3.6-6 8-6s8 2.7 8 6" strokeLinecap="round" />
              </svg>
            </button>
          </div>
        ) : (
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center text-blue-600 shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                <circle cx="12" cy="8" r="4" />
                <path d="M4 20c0-3.3 3.6-6 8-6s8 2.7 8 6" strokeLinecap="round" />
              </svg>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 truncate">
                {user?.display_name || user?.did || 'Admin'}
              </p>
              <button
                onClick={logout}
                className="text-xs text-gray-500 hover:text-gray-700 transition-colors"
              >
                Sign Out
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Collapse toggle */}
      <button
        onClick={onToggle}
        className="flex items-center justify-center h-10 border-t border-gray-200 text-gray-400 hover:text-gray-600 hover:bg-gray-50 transition-colors shrink-0"
        title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          strokeWidth={2}
          className={`transition-transform duration-200 ${collapsed ? 'rotate-180' : ''}`}
        >
          <path d="M15 19l-7-7 7-7" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
    </aside>
  )
}
