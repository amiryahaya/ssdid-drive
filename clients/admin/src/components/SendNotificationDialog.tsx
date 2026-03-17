import { useState, useEffect, useRef } from 'react'
import { useAdminStore } from '../stores/adminStore'
import type { User } from '../stores/adminStore'

interface SendNotificationDialogProps {
  open: boolean
  onClose: () => void
  onSent: () => void
}

export default function SendNotificationDialog({
  open,
  onClose,
  onSent,
}: SendNotificationDialogProps) {
  const sendNotification = useAdminStore((s) => s.sendNotification)
  const tenants = useAdminStore((s) => s.tenants)
  const fetchTenants = useAdminStore((s) => s.fetchTenants)
  const fetchUsers = useAdminStore((s) => s.fetchUsers)
  const users = useAdminStore((s) => s.users)
  const usersLoading = useAdminStore((s) => s.usersLoading)

  const [scope, setScope] = useState<'user' | 'tenant' | 'broadcast'>('broadcast')
  const [targetUserId, setTargetUserId] = useState('')
  const [selectedUser, setSelectedUser] = useState<User | null>(null)
  const [userSearch, setUserSearch] = useState('')
  const [showUserDropdown, setShowUserDropdown] = useState(false)
  const [targetTenantId, setTargetTenantId] = useState('')
  const [title, setTitle] = useState('')
  const [message, setMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [recipientCount, setRecipientCount] = useState<number | null>(null)

  const searchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const userDropdownRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (open) {
      setScope('broadcast')
      setTargetUserId('')
      setSelectedUser(null)
      setUserSearch('')
      setShowUserDropdown(false)
      setTargetTenantId('')
      setTitle('')
      setMessage('')
      setSubmitting(false)
      setError(null)
      setRecipientCount(null)
      // Load tenants for the tenant selector
      fetchTenants(1, 100).catch(() => {/* ignore */})
    }
  }, [open, fetchTenants])

  useEffect(() => {
    if (!open) return
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [open, submitting, onClose])

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (userDropdownRef.current && !userDropdownRef.current.contains(e.target as Node)) {
        setShowUserDropdown(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const handleUserSearchChange = (value: string) => {
    setUserSearch(value)
    // Clear selected user if the search text changes
    if (selectedUser) {
      setSelectedUser(null)
      setTargetUserId('')
    }
    setShowUserDropdown(true)

    if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current)
    if (value.trim().length >= 1) {
      searchDebounceRef.current = setTimeout(() => {
        fetchUsers(1, 10, value.trim()).catch(() => {/* ignore */})
      }, 300)
    }
  }

  const handleSelectUser = (user: User) => {
    setSelectedUser(user)
    setTargetUserId(user.id)
    setUserSearch(user.email ?? user.display_name ?? user.did)
    setShowUserDropdown(false)
  }

  const handleClearUser = () => {
    setSelectedUser(null)
    setTargetUserId('')
    setUserSearch('')
    setShowUserDropdown(false)
  }

  if (!open) return null

  const getTargetId = () => {
    if (scope === 'user') return targetUserId || null
    if (scope === 'tenant') return targetTenantId || null
    return null
  }

  const isValid = () => {
    if (!title.trim() || !message.trim()) return false
    if (scope === 'user' && !targetUserId) return false
    if (scope === 'tenant' && !targetTenantId) return false
    return true
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!isValid()) return

    setSubmitting(true)
    setError(null)
    try {
      const result = await sendNotification(scope, getTargetId(), title.trim(), message.trim())
      setRecipientCount(result.recipients)
      onSent()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to send notification')
    } finally {
      setSubmitting(false)
    }
  }

  const getUserLabel = (user: User) => {
    const parts: string[] = []
    if (user.display_name) parts.push(user.display_name)
    if (user.email) parts.push(user.email)
    if (parts.length === 0) return user.did
    return parts.join(' — ')
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="send-notification-title"
      onClick={() => !submitting && onClose()}
    >
      <div
        className="bg-white rounded-xl shadow-xl w-full max-w-lg p-6"
        onClick={(e) => e.stopPropagation()}
      >
        {recipientCount !== null ? (
          <div className="text-center">
            <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h3 id="send-notification-title" className="text-lg font-semibold mb-1">
              Notification Sent!
            </h3>
            <p className="text-gray-500 text-sm mb-5">
              Successfully delivered to{' '}
              <span className="font-semibold text-gray-800">{recipientCount}</span>{' '}
              {recipientCount === 1 ? 'recipient' : 'recipients'}.
            </p>
            <button
              onClick={onClose}
              className="px-6 py-2 border border-gray-300 rounded-lg text-sm text-gray-700 hover:bg-gray-50"
            >
              Close
            </button>
          </div>
        ) : (
          <>
            <h3 id="send-notification-title" className="text-lg font-semibold mb-1">
              Send Notification
            </h3>
            <p className="text-gray-500 text-sm mb-5">
              Send a notification to users or organizations.
            </p>

            {error && (
              <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 mb-4 text-sm">
                {error}
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              {/* Scope selector */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Audience
                </label>
                <div className="flex gap-2">
                  {(
                    [
                      { value: 'broadcast', label: 'Broadcast to All' },
                      { value: 'tenant', label: 'Organization' },
                      { value: 'user', label: 'Specific User' },
                    ] as const
                  ).map(({ value, label }) => (
                    <button
                      key={value}
                      type="button"
                      onClick={() => setScope(value)}
                      aria-pressed={scope === value}
                      className={`flex-1 py-2 px-3 rounded-lg border-2 text-center text-xs font-medium transition-colors ${
                        scope === value
                          ? 'border-blue-600 bg-blue-50 text-blue-700'
                          : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300'
                      }`}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>

              {/* User search */}
              {scope === 'user' && (
                <div ref={userDropdownRef} className="relative">
                  <label htmlFor="notif-user-search" className="block text-sm font-medium text-gray-700 mb-1">
                    User
                  </label>
                  <div className="relative">
                    <input
                      id="notif-user-search"
                      type="text"
                      value={userSearch}
                      onChange={(e) => handleUserSearchChange(e.target.value)}
                      onFocus={() => {
                        if (userSearch.trim().length >= 1 && !selectedUser) {
                          setShowUserDropdown(true)
                        }
                      }}
                      placeholder="Search by name or email..."
                      className={`w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent pr-8 ${
                        selectedUser ? 'border-blue-400 bg-blue-50' : 'border-gray-300'
                      }`}
                      autoFocus
                      autoComplete="off"
                    />
                    {selectedUser && (
                      <button
                        type="button"
                        onClick={handleClearUser}
                        className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                        aria-label="Clear selected user"
                      >
                        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>
                    )}
                  </div>

                  {/* Dropdown results */}
                  {showUserDropdown && !selectedUser && (
                    <div className="absolute z-10 w-full mt-1 bg-white border border-gray-200 rounded-lg shadow-lg max-h-48 overflow-y-auto">
                      {usersLoading ? (
                        <div className="px-3 py-2 text-sm text-gray-500">Searching...</div>
                      ) : users.length === 0 ? (
                        <div className="px-3 py-2 text-sm text-gray-500">No users found</div>
                      ) : (
                        users.map((user) => (
                          <button
                            key={user.id}
                            type="button"
                            onClick={() => handleSelectUser(user)}
                            className="w-full text-left px-3 py-2 text-sm hover:bg-gray-50 focus:bg-gray-50 focus:outline-none border-b border-gray-100 last:border-b-0"
                          >
                            <span className="font-medium text-gray-800">
                              {user.display_name ?? user.email ?? user.did}
                            </span>
                            {user.email && user.display_name && (
                              <span className="text-gray-500 ml-2">{user.email}</span>
                            )}
                          </button>
                        ))
                      )}
                    </div>
                  )}

                  {selectedUser && (
                    <p className="mt-1 text-xs text-gray-500">
                      Selected: {getUserLabel(selectedUser)}
                    </p>
                  )}
                </div>
              )}

              {/* Tenant dropdown */}
              {scope === 'tenant' && (
                <div>
                  <label htmlFor="notif-tenant-id" className="block text-sm font-medium text-gray-700 mb-1">
                    Organization
                  </label>
                  <select
                    id="notif-tenant-id"
                    value={targetTenantId}
                    onChange={(e) => setTargetTenantId(e.target.value)}
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    required
                  >
                    <option value="">Select an organization...</option>
                    {tenants.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.name} ({t.slug})
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {/* Title */}
              <div>
                <label htmlFor="notif-title" className="block text-sm font-medium text-gray-700 mb-1">
                  Title
                </label>
                <input
                  id="notif-title"
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Notification title"
                  maxLength={200}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  required
                  autoFocus={scope === 'broadcast'}
                />
              </div>

              {/* Message */}
              <div>
                <label htmlFor="notif-message" className="block text-sm font-medium text-gray-700 mb-1">
                  Message
                </label>
                <textarea
                  id="notif-message"
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  placeholder="Notification message body..."
                  maxLength={2000}
                  rows={4}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-vertical"
                  required
                />
              </div>

              <div className="flex justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={onClose}
                  disabled={submitting}
                  className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting || !isValid()}
                  className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {submitting ? 'Sending...' : 'Send Notification'}
                </button>
              </div>
            </form>
          </>
        )}
      </div>
    </div>
  )
}
