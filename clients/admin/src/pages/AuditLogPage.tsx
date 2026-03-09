import { useEffect, useState, useCallback } from 'react'
import DataTable from '../components/DataTable'
import type { Column } from '../components/DataTable'
import { useAdminStore } from '../stores/adminStore'
import type { AuditLogEntry } from '../stores/adminStore'
import { formatDateTime } from '../utils/format'

const PAGE_SIZE = 20

function formatAction(action: string): string {
  return action
    .split('.')
    .map((part) =>
      part
        .split('_')
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' '),
    )
    .join(' ')
}

function truncateDetails(details: string | null): string {
  if (!details) return '\u2014'
  if (details.length <= 60) return details
  return details.slice(0, 57) + '...'
}

export default function AuditLogPage() {
  const { auditLog, auditLogTotal, auditLogLoading, fetchAuditLog } =
    useAdminStore()

  const [page, setPage] = useState(1)
  const [error, setError] = useState<string | null>(null)

  const loadAuditLog = useCallback(
    (currentPage: number) => {
      setError(null)
      fetchAuditLog(currentPage, PAGE_SIZE).catch((err) =>
        setError(err instanceof Error ? err.message : 'Failed to load audit log'),
      )
    },
    [fetchAuditLog],
  )

  useEffect(() => {
    loadAuditLog(page)
  }, [page, loadAuditLog])

  const columns: Column<AuditLogEntry>[] = [
    {
      key: 'actor',
      header: 'Actor',
      render: (entry) => entry.actor_name || entry.actor_id,
    },
    {
      key: 'action',
      header: 'Action',
      render: (entry) => (
        <span className="inline-block px-2 py-0.5 rounded bg-gray-100 text-xs font-medium text-gray-700">
          {formatAction(entry.action)}
        </span>
      ),
    },
    {
      key: 'target',
      header: 'Target',
      render: (entry) => {
        if (!entry.target_type && !entry.target_id) return '\u2014'
        const parts = [entry.target_type, entry.target_id].filter(Boolean)
        return (
          <span className="font-mono text-xs">{parts.join(': ')}</span>
        )
      },
    },
    {
      key: 'details',
      header: 'Details',
      render: (entry) => (
        <span title={entry.details || undefined}>
          {truncateDetails(entry.details)}
        </span>
      ),
    },
    {
      key: 'created_at',
      header: 'Timestamp',
      render: (entry) => formatDateTime(entry.created_at),
    },
  ]

  const totalPages = Math.ceil(auditLogTotal / PAGE_SIZE)

  return (
    <div>
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {error}
        </div>
      )}

      <DataTable
        columns={columns}
        data={auditLog}
        loading={auditLogLoading}
        rowKey={(entry) => entry.id}
      />

      {!auditLogLoading && auditLogTotal > 0 && (
        <div className="flex items-center justify-between mt-4 text-sm text-gray-600">
          <span>
            Page {page} of {totalPages}
          </span>
          <div className="flex gap-2">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page <= 1}
              className="px-3 py-1 border border-gray-300 rounded hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Previous
            </button>
            <button
              onClick={() => setPage((p) => p + 1)}
              disabled={page >= totalPages}
              className="px-3 py-1 border border-gray-300 rounded hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
