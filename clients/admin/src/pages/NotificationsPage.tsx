import { useEffect, useState, useCallback } from 'react'
import DataTable from '../components/DataTable'
import type { Column } from '../components/DataTable'
import Pagination from '../components/Pagination'
import SendNotificationDialog from '../components/SendNotificationDialog'
import { useAdminStore } from '../stores/adminStore'
import type { NotificationLog } from '../stores/adminStore'
import { formatDateTime } from '../utils/format'

const PAGE_SIZE = 20

function ScopeBadge({ scope }: { scope: string }) {
  const styles: Record<string, string> = {
    user: 'bg-blue-100 text-blue-800',
    tenant: 'bg-purple-100 text-purple-800',
    broadcast: 'bg-green-100 text-green-800',
  }
  const labels: Record<string, string> = {
    user: 'User',
    tenant: 'Organization',
    broadcast: 'Broadcast',
  }
  return (
    <span
      className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
        styles[scope] ?? 'bg-gray-100 text-gray-800'
      }`}
    >
      {labels[scope] ?? scope}
    </span>
  )
}

function truncateText(text: string, maxLength = 60): string {
  if (text.length <= maxLength) return text
  return text.slice(0, maxLength - 3) + '...'
}

export default function NotificationsPage() {
  const {
    notificationLogs,
    notificationLogsTotal,
    notificationLogsLoading,
    fetchNotificationLogs,
  } = useAdminStore()

  const [page, setPage] = useState(1)
  const [error, setError] = useState<string | null>(null)
  const [showSendDialog, setShowSendDialog] = useState(false)

  const loadLogs = useCallback(
    (currentPage: number) => {
      setError(null)
      fetchNotificationLogs(currentPage, PAGE_SIZE).catch((err) =>
        setError(err instanceof Error ? err.message : 'Failed to load notifications'),
      )
    },
    [fetchNotificationLogs],
  )

  useEffect(() => {
    loadLogs(page)
  }, [page, loadLogs])

  const handleSent = () => {
    // Refresh from page 1 after sending
    setPage(1)
    loadLogs(1)
  }

  const columns: Column<NotificationLog>[] = [
    {
      key: 'created_at',
      header: 'Date',
      render: (log) => formatDateTime(log.created_at),
    },
    {
      key: 'sent_by_name',
      header: 'Sender',
      render: (log) => log.sent_by_name || '\u2014',
    },
    {
      key: 'scope',
      header: 'Scope',
      render: (log) => <ScopeBadge scope={log.scope} />,
    },
    {
      key: 'title',
      header: 'Title',
      render: (log) => (
        <span className="font-medium" title={log.title}>
          {truncateText(log.title, 40)}
        </span>
      ),
    },
    {
      key: 'message',
      header: 'Message',
      render: (log) => (
        <span className="text-gray-600" title={log.message}>
          {truncateText(log.message)}
        </span>
      ),
    },
    {
      key: 'recipient_count',
      header: 'Recipients',
      render: (log) => (
        <span className="font-medium text-gray-900">{log.recipient_count}</span>
      ),
    },
  ]

  const totalPages = Math.ceil(notificationLogsTotal / PAGE_SIZE)

  return (
    <div>
      <div className="flex items-center justify-end mb-6">
        <button
          onClick={() => setShowSendDialog(true)}
          className="px-4 py-2 text-sm text-white bg-blue-600 rounded-lg hover:bg-blue-700"
        >
          Send Notification
        </button>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {error}
        </div>
      )}

      <DataTable
        columns={columns}
        data={notificationLogs}
        loading={notificationLogsLoading}
        rowKey={(log) => log.id}
      />

      <Pagination
        page={page}
        totalPages={totalPages}
        loading={notificationLogsLoading}
        total={notificationLogsTotal}
        onChange={setPage}
      />

      <SendNotificationDialog
        open={showSendDialog}
        onClose={() => setShowSendDialog(false)}
        onSent={handleSent}
      />
    </div>
  )
}
