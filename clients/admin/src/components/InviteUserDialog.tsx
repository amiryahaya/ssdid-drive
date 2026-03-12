import { useState, useEffect, useRef } from 'react'
import { useAdminStore } from '../stores/adminStore'
import type { AdminInvitation } from '../stores/adminStore'

interface InviteUserDialogProps {
  open: boolean
  onClose: () => void
  tenantId: string
  tenantName: string
  onInvited: () => void
}

export default function InviteUserDialog({
  open,
  onClose,
  tenantId,
  tenantName,
  onInvited,
}: InviteUserDialogProps) {
  const createAdminInvitation = useAdminStore((s) => s.createAdminInvitation)

  const [email, setEmail] = useState('')
  const [role, setRole] = useState<'owner' | 'admin'>('owner')
  const [message, setMessage] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<AdminInvitation | null>(null)
  const [copied, setCopied] = useState(false)
  const copyTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    if (open) {
      setEmail('')
      setRole('owner')
      setMessage('')
      setSubmitting(false)
      setError(null)
      setSuccess(null)
      setCopied(false)
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [open, submitting, onClose])

  useEffect(() => {
    return () => {
      if (copyTimerRef.current) clearTimeout(copyTimerRef.current)
    }
  }, [])

  if (!open) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email.trim()) return

    setSubmitting(true)
    setError(null)
    try {
      const invitation = await createAdminInvitation(
        tenantId, email.trim(), role, message.trim() || undefined)
      setSuccess(invitation)
      onInvited()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create invitation')
    } finally {
      setSubmitting(false)
    }
  }

  const handleCopy = async () => {
    if (!success) return
    try {
      await navigator.clipboard.writeText(success.short_code)
      setCopied(true)
      if (copyTimerRef.current) clearTimeout(copyTimerRef.current)
      copyTimerRef.current = setTimeout(() => setCopied(false), 2000)
    } catch {
      // clipboard API unavailable — user can manually select the code
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="invite-user-title"
      onClick={() => !submitting && onClose()}
    >
      <div
        className="bg-white rounded-xl shadow-xl w-full max-w-md p-6"
        onClick={(e) => e.stopPropagation()}
      >
        {success ? (
          <div className="text-center">
            <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
              <svg className="w-6 h-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <h3 id="invite-user-title" className="text-lg font-semibold mb-1">Invitation Sent!</h3>
            <p className="text-gray-500 text-sm mb-5">Share this code with the invited user</p>

            <div className="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-2 flex items-center justify-center gap-3">
              <span className="font-mono text-2xl font-bold tracking-wider">
                {success.short_code}
              </span>
              <button
                onClick={handleCopy}
                className="px-3 py-1 border border-gray-300 rounded-md text-xs text-gray-700 hover:bg-gray-100"
              >
                {copied ? 'Copied!' : 'Copy'}
              </button>
            </div>
            <p className="text-gray-400 text-xs mb-5">Expires in 7 days</p>

            <button
              onClick={onClose}
              className="px-6 py-2 border border-gray-300 rounded-lg text-sm text-gray-700 hover:bg-gray-50"
            >
              Close
            </button>
          </div>
        ) : (
          <>
            <h3 id="invite-user-title" className="text-lg font-semibold mb-1">
              Invite User
            </h3>
            <p className="text-gray-500 text-sm mb-5">
              Invite a user to <strong>{tenantName}</strong>
            </p>

            {error && (
              <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 mb-4 text-sm">
                {error}
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label htmlFor="invite-email" className="block text-sm font-medium text-gray-700 mb-1">
                  Email
                </label>
                <input
                  id="invite-email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="user@example.com"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  required
                  autoFocus
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Role</label>
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => setRole('owner')}
                    aria-pressed={role === 'owner'}
                    className={`flex-1 p-3 rounded-lg border-2 text-center transition-colors ${
                      role === 'owner'
                        ? 'border-blue-600 bg-blue-50'
                        : 'border-gray-200 bg-white hover:border-gray-300'
                    }`}
                  >
                    <div className={`font-semibold text-sm ${role === 'owner' ? 'text-blue-700' : 'text-gray-700'}`}>
                      Owner
                    </div>
                    <div className="text-xs text-gray-500 mt-0.5">Full tenant control</div>
                  </button>
                  <button
                    type="button"
                    onClick={() => setRole('admin')}
                    aria-pressed={role === 'admin'}
                    className={`flex-1 p-3 rounded-lg border-2 text-center transition-colors ${
                      role === 'admin'
                        ? 'border-blue-600 bg-blue-50'
                        : 'border-gray-200 bg-white hover:border-gray-300'
                    }`}
                  >
                    <div className={`font-semibold text-sm ${role === 'admin' ? 'text-blue-700' : 'text-gray-700'}`}>
                      Admin
                    </div>
                    <div className="text-xs text-gray-500 mt-0.5">Manage members</div>
                  </button>
                </div>
              </div>

              <div>
                <label htmlFor="invite-message" className="block text-sm font-medium text-gray-700 mb-1">
                  Message <span className="font-normal text-gray-400">(optional)</span>
                </label>
                <textarea
                  id="invite-message"
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  placeholder="Personal message to include with the invitation..."
                  maxLength={500}
                  rows={2}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-vertical"
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
                  disabled={submitting || !email.trim()}
                  className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {submitting ? 'Sending...' : 'Send Invitation'}
                </button>
              </div>
            </form>
          </>
        )}
      </div>
    </div>
  )
}
