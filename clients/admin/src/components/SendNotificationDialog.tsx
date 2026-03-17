import { useState, useEffect } from 'react'
import { useAdminStore } from '../stores/adminStore'

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

  const [scope, setScope] = useState<'user' | 'tenant' | 'broadcast'>('broadcast')
  const [targetUserId, setTargetUserId] = useState('')
  const [targetTenantId, setTargetTenantId] = useState('')
  const [title, setTitle] = useState('')
  const [message, setMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [recipientCount, setRecipientCount] = useState<number | null>(null)

  useEffect(() => {
    if (open) {
      setScope('broadcast')
      setTargetUserId('')
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

  if (!open) return null

  const getTargetId = () => {
    if (scope === 'user') return targetUserId.trim() || null
    if (scope === 'tenant') return targetTenantId || null
    return null
  }

  const isValid = () => {
    if (!title.trim() || !message.trim()) return false
    if (scope === 'user' && !targetUserId.trim()) return false
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

              {/* Conditional target input */}
              {scope === 'user' && (
                <div>
                  <label htmlFor="notif-user-id" className="block text-sm font-medium text-gray-700 mb-1">
                    User ID
                  </label>
                  <input
                    id="notif-user-id"
                    type="text"
                    value={targetUserId}
                    onChange={(e) => setTargetUserId(e.target.value)}
                    placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                    className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    required
                    autoFocus
                  />
                </div>
              )}

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
