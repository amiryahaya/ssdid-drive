import { useEffect, useState, useCallback } from 'react'
import DataTable from '../components/DataTable'
import type { Column } from '../components/DataTable'
import Pagination from '../components/Pagination'
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

  // Filters
  const [actorFilter, setActorFilter] = useState('')
  const [actionFilter, setActionFilter] = useState('')
  const [fromDate, setFromDate] = useState('')
  const [toDate, setToDate] = useState('')
  const [appliedFilters, setAppliedFilters] = useState<{
    actor?: string; action?: string; from?: string; to?: string
  }>({})

  const loadAuditLog = useCallback(
    (currentPage: number, filters: typeof appliedFilters = appliedFilters) => {
      setError(null)
      fetchAuditLog(currentPage, PAGE_SIZE, {
        actor: filters.actor || undefined,
        action: filters.action || undefined,
        from: filters.from || undefined,
        to: filters.to ? `${filters.to}T23:59:59Z` : undefined,
      }).catch((err) =>
        setError(err instanceof Error ? err.message : 'Failed to load audit log'),
      )
    },
    [fetchAuditLog, appliedFilters],
  )

  useEffect(() => {
    loadAuditLog(page)
  }, [page, loadAuditLog])

  const handleApplyFilters = () => {
    const filters = { actor: actorFilter, action: actionFilter, from: fromDate, to: toDate }
    setAppliedFilters(filters)
    setPage(1)
    loadAuditLog(1, filters)
  }

  const handleClearFilters = () => {
    setActorFilter('')
    setActionFilter('')
    setFromDate('')
    setToDate('')
    setAppliedFilters({})
    setPage(1)
    loadAuditLog(1, {})
  }

  const hasFilters = actorFilter || actionFilter || fromDate || toDate

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
      {/* Filters */}
      <div className="bg-white border border-gray-200 rounded-lg p-4 mb-4">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <div>
            <label htmlFor="actor-filter" className="block text-xs font-medium text-gray-500 mb-1">
              Actor
            </label>
            <input
              id="actor-filter"
              type="text"
              value={actorFilter}
              onChange={(e) => setActorFilter(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleApplyFilters()}
              placeholder="Name or email"
              className="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
          <div>
            <label htmlFor="action-filter" className="block text-xs font-medium text-gray-500 mb-1">
              Action
            </label>
            <input
              id="action-filter"
              type="text"
              value={actionFilter}
              onChange={(e) => setActionFilter(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleApplyFilters()}
              placeholder="e.g. auth.login, tenant.created"
              className="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
          <div>
            <label htmlFor="from-date" className="block text-xs font-medium text-gray-500 mb-1">
              From
            </label>
            <input
              id="from-date"
              type="date"
              value={fromDate}
              onChange={(e) => setFromDate(e.target.value)}
              className="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
          <div>
            <label htmlFor="to-date" className="block text-xs font-medium text-gray-500 mb-1">
              To
            </label>
            <input
              id="to-date"
              type="date"
              value={toDate}
              onChange={(e) => setToDate(e.target.value)}
              className="w-full px-3 py-1.5 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
        </div>
        <div className="flex items-center gap-2 mt-3">
          <button
            onClick={handleApplyFilters}
            className="px-4 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 transition-colors cursor-pointer"
          >
            Apply
          </button>
          {hasFilters && (
            <button
              onClick={handleClearFilters}
              className="px-4 py-1.5 text-sm font-medium text-gray-600 bg-gray-100 rounded-md hover:bg-gray-200 transition-colors cursor-pointer"
            >
              Clear
            </button>
          )}
        </div>
      </div>

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

      <Pagination
        page={page}
        totalPages={totalPages}
        loading={auditLogLoading}
        total={auditLogTotal}
        onChange={setPage}
      />
    </div>
  )
}
