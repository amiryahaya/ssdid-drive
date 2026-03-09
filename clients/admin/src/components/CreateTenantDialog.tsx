import { useState, useEffect } from 'react'
import { useAdminStore } from '../stores/adminStore'

interface CreateTenantDialogProps {
  open: boolean
  onClose: () => void
  onCreated: () => void
}

function slugify(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
}

export default function CreateTenantDialog({
  open,
  onClose,
  onCreated,
}: CreateTenantDialogProps) {
  const createTenant = useAdminStore((s) => s.createTenant)

  const [name, setName] = useState('')
  const [slug, setSlug] = useState('')
  const [slugManual, setSlugManual] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!slugManual) {
      setSlug(slugify(name))
    }
  }, [name, slugManual])

  useEffect(() => {
    if (open) {
      setName('')
      setSlug('')
      setSlugManual(false)
      setSubmitting(false)
      setError(null)
    }
  }, [open])

  if (!open) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!name.trim() || !slug.trim()) return

    setSubmitting(true)
    setError(null)
    try {
      await createTenant(name.trim(), slug.trim())
      onCreated()
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create tenant')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-md p-6">
        <h3 className="text-lg font-semibold mb-4">Create Tenant</h3>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 mb-4 text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="tenant-name" className="block text-sm font-medium text-gray-700 mb-1">
              Name
            </label>
            <input
              id="tenant-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Acme Corporation"
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              required
              autoFocus
            />
          </div>

          <div>
            <label htmlFor="tenant-slug" className="block text-sm font-medium text-gray-700 mb-1">
              Slug
            </label>
            <input
              id="tenant-slug"
              type="text"
              value={slug}
              onChange={(e) => {
                setSlug(e.target.value)
                setSlugManual(true)
              }}
              placeholder="acme-corporation"
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              required
            />
            <p className="text-xs text-gray-400 mt-1">
              Auto-generated from name. Edit to customize.
            </p>
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
              disabled={submitting || !name.trim() || !slug.trim()}
              className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {submitting ? 'Creating...' : 'Create'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
