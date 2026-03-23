import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import NotificationsPage from '../NotificationsPage'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockFetchNotificationLogs = vi.fn().mockResolvedValue(undefined)

const sampleLogs = [
  {
    id: 'n1',
    scope: 'broadcast',
    target_id: null,
    title: 'System Maintenance',
    message: 'Scheduled maintenance window tonight from 11pm to 1am.',
    recipient_count: 42,
    sent_by_name: 'Admin',
    created_at: '2026-03-20T10:00:00Z',
  },
  {
    id: 'n2',
    scope: 'tenant',
    target_id: 't1',
    title: 'Org Update',
    message: 'Your organization settings have been updated.',
    recipient_count: 5,
    sent_by_name: 'Alice',
    created_at: '2026-03-19T08:00:00Z',
  },
  {
    id: 'n3',
    scope: 'user',
    target_id: 'u1',
    title: 'Welcome',
    message: 'Welcome to the platform!',
    recipient_count: 1,
    sent_by_name: 'Bob',
    created_at: '2026-03-18T06:00:00Z',
  },
]

function makeStore(overrides = {}) {
  return {
    notificationLogs: sampleLogs,
    notificationLogsTotal: 3,
    notificationLogsLoading: false,
    fetchNotificationLogs: mockFetchNotificationLogs,
    ...overrides,
  }
}

beforeEach(() => {
  vi.clearAllMocks()
  mockFetchNotificationLogs.mockResolvedValue(undefined)
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector?: (s: unknown) => unknown) => {
      const store = makeStore()
      return selector ? selector(store) : store
    }
  )
})

describe('NotificationsPage', () => {
  it('renders Send Notification button', () => {
    render(<NotificationsPage />)
    expect(screen.getByText('Send Notification')).toBeInTheDocument()
  })

  it('calls fetchNotificationLogs on mount', () => {
    render(<NotificationsPage />)
    expect(mockFetchNotificationLogs).toHaveBeenCalledWith(1, 20)
  })

  it('displays notification log entries in table', () => {
    render(<NotificationsPage />)
    expect(screen.getByText('System Maintenance')).toBeInTheDocument()
    expect(screen.getByText('Org Update')).toBeInTheDocument()
    expect(screen.getByText('Welcome')).toBeInTheDocument()
    expect(screen.getByText('Admin')).toBeInTheDocument()
    expect(screen.getByText('Alice')).toBeInTheDocument()
    expect(screen.getByText('Bob')).toBeInTheDocument()
  })

  it('shows broadcast scope badge with green styling', () => {
    render(<NotificationsPage />)
    const badge = screen.getByText('Broadcast')
    expect(badge.className).toContain('bg-green-100')
    expect(badge.className).toContain('text-green-800')
  })

  it('shows tenant scope badge with purple styling', () => {
    render(<NotificationsPage />)
    const badge = screen.getByText('Organization')
    expect(badge.className).toContain('bg-purple-100')
    expect(badge.className).toContain('text-purple-800')
  })

  it('shows user scope badge with blue styling', () => {
    render(<NotificationsPage />)
    const badge = screen.getByText('User')
    expect(badge.className).toContain('bg-blue-100')
    expect(badge.className).toContain('text-blue-800')
  })

  it('shows pagination info', () => {
    render(<NotificationsPage />)
    expect(screen.getByText('Page 1 of 1')).toBeInTheDocument()
  })

  it('calls fetchNotificationLogs with new page on pagination change', async () => {
    const user = userEvent.setup()
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = makeStore({ notificationLogsTotal: 25 })
        return selector ? selector(store) : store
      }
    )

    render(<NotificationsPage />)

    // Page 2 button should be rendered (total 25 / PAGE_SIZE 20 = 2 pages)
    const nextButton = screen.getByText('Next')
    await user.click(nextButton)

    await waitFor(() => {
      expect(mockFetchNotificationLogs).toHaveBeenCalledWith(2, 20)
    })
  })

  it('shows loading skeleton state', () => {
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = makeStore({ notificationLogs: [], notificationLogsTotal: 0, notificationLogsLoading: true })
        return selector ? selector(store) : store
      }
    )

    const { container } = render(<NotificationsPage />)
    const skeletons = container.querySelectorAll('.animate-pulse')
    expect(skeletons.length).toBeGreaterThan(0)
  })

  it('shows empty state when no entries', () => {
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = makeStore({ notificationLogs: [], notificationLogsTotal: 0 })
        return selector ? selector(store) : store
      }
    )

    render(<NotificationsPage />)
    expect(screen.getByText('No data found')).toBeInTheDocument()
  })

  it('shows error when fetchNotificationLogs fails', async () => {
    mockFetchNotificationLogs.mockRejectedValueOnce(new Error('Failed to fetch'))

    render(<NotificationsPage />)

    await waitFor(() => {
      expect(screen.getByText('Failed to fetch')).toBeInTheDocument()
    })
  })

  it('opens SendNotificationDialog when Send Notification button is clicked', async () => {
    const user = userEvent.setup()
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = {
          ...makeStore(),
          tenants: [],
          fetchTenants: vi.fn().mockResolvedValue(undefined),
          users: [],
          usersLoading: false,
          fetchUsers: vi.fn().mockResolvedValue(undefined),
          sendNotification: vi.fn(),
        }
        return selector ? selector(store) : store
      }
    )

    render(<NotificationsPage />)
    await user.click(screen.getByText('Send Notification'))

    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeInTheDocument()
    })
  })

  it('shows dash for null sender name', () => {
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = makeStore({
          notificationLogs: [
            {
              id: 'n4',
              scope: 'broadcast',
              target_id: null,
              title: 'Test',
              message: 'Test message',
              recipient_count: 10,
              sent_by_name: null,
              created_at: '2026-03-17T00:00:00Z',
            },
          ],
          notificationLogsTotal: 1,
        })
        return selector ? selector(store) : store
      }
    )

    render(<NotificationsPage />)
    // Null sent_by_name shows em dash
    expect(screen.getByText('\u2014')).toBeInTheDocument()
  })
})
