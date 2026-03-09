import { useState, useEffect } from 'react'
import { useAdminStore } from '../stores/adminStore'
import type { Tenant } from '../stores/adminStore'

interface EditTenantDialogProps {
  tenant: Tenant | null
  onClose: () => void
  onUpdated: () => void
}

export default function EditTenantDialog({
  tenant,
  onClose,
  onUpdated,
}: EditTenantDialogProps) {
  const updateTenant = useAdminStore((s) => s.updateTenant)

  const [name, setName] = useState('')
  const [storageQuotaGb, setStorageQuotaGb] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (tenant) {
      setName(tenant.name)
      if (tenant.storage_quota_bytes && tenant.storage_quota_bytes > 0) {
        setStorageQuotaGb(
          String(tenant.storage_quota_bytes / (1024 * 1024 * 1024)),
        )
      } else {
        setStorageQuotaGb('')
      }
      setSubmitting(false)
      setError(null)
    }
  }, [tenant])

  if (!tenant) return null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!name.trim()) return

    const quotaGb = storageQuotaGb.trim() ? parseFloat(storageQuotaGb) : null
    if (quotaGb !== null && (isNaN(quotaGb) || quotaGb < 0)) {
      setError('Storage quota must be a positive number or empty for unlimited')
      return
    }

    const patch: Partial<Pick<Tenant, 'name' | 'storage_quota_bytes'>> = {}

    if (name.trim() !== tenant.name) {
      patch.name = name.trim()
    }

    const newQuotaBytes = quotaGb !== null ? Math.round(quotaGb * 1024 * 1024 * 1024) : null
    if (newQuotaBytes !== tenant.storage_quota_bytes) {
      patch.storage_quota_bytes = newQuotaBytes
    }

    if (Object.keys(patch).length === 0) {
      onClose()
      return
    }

    setSubmitting(true)
    setError(null)
    try {
      await updateTenant(tenant.id, patch)
      onUpdated()
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update tenant')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div className="bg-white rounded-lg shadow-xl w-full max-w-md p-6">
        <h3 className="text-lg font-semibold mb-4">Edit Tenant</h3>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-3 mb-4 text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="edit-tenant-name" className="block text-sm font-medium text-gray-700 mb-1">
              Name
            </label>
            <input
              id="edit-tenant-name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              required
              autoFocus
            />
          </div>

          <div>
            <label htmlFor="edit-tenant-slug" className="block text-sm font-medium text-gray-700 mb-1">
              Slug
            </label>
            <input
              id="edit-tenant-slug"
              type="text"
              value={tenant.slug}
              disabled
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm font-mono bg-gray-50 text-gray-500 cursor-not-allowed"
            />
            <p className="text-xs text-gray-400 mt-1">
              Slug cannot be changed after creation.
            </p>
          </div>

          <div>
            <label htmlFor="edit-tenant-quota" className="block text-sm font-medium text-gray-700 mb-1">
              Storage Quota (GB)
            </label>
            <input
              id="edit-tenant-quota"
              type="number"
              min="0"
              step="any"
              value={storageQuotaGb}
              onChange={(e) => setStorageQuotaGb(e.target.value)}
              placeholder="Leave empty for unlimited"
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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
              disabled={submitting || !name.trim()}
              className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {submitting ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
