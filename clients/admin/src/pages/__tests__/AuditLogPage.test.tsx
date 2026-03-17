import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import AuditLogPage from '../AuditLogPage'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockFetchAuditLog = vi.fn().mockResolvedValue(undefined)

const sampleEntries = [
  {
    id: 'a1',
    actor_id: 'u1',
    actor_name: 'Alice',
    action: 'auth.login',
    target_type: 'user',
    target_id: 'u1',
    details: 'Login from 192.168.1.1',
    created_at: '2026-03-15T14:30:00Z',
  },
  {
    id: 'a2',
    actor_id: 'u2',
    actor_name: null,
    action: 'tenant.created',
    target_type: null,
    target_id: null,
    details: null,
    created_at: '2026-03-14T10:00:00Z',
  },
  {
    id: 'a3',
    actor_id: 'u1',
    actor_name: 'Alice',
    action: 'file_upload',
    target_type: 'file',
    target_id: 'f1',
    details: 'A very long details string that is definitely more than sixty characters long so it should be truncated',
    created_at: '2026-03-13T08:00:00Z',
  },
]

beforeEach(() => {
  vi.clearAllMocks()
  mockFetchAuditLog.mockResolvedValue(undefined)
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector?: (s: unknown) => unknown) => {
      const store = {
        auditLog: sampleEntries,
        auditLogTotal: 3,
        auditLogLoading: false,
        fetchAuditLog: mockFetchAuditLog,
      }
      return selector ? selector(store) : store
    }
  )
})

describe('AuditLogPage', () => {
  it('calls fetchAuditLog on mount', () => {
    render(<AuditLogPage />)
    expect(mockFetchAuditLog).toHaveBeenCalled()
  })

  it('renders audit log entries', () => {
    render(<AuditLogPage />)
    // Alice appears in multiple entries (a1 and a3)
    expect(screen.getAllByText('Alice').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText('Login from 192.168.1.1')).toBeInTheDocument()
  })

  it('formats actions with title case', () => {
    render(<AuditLogPage />)
    expect(screen.getByText('Auth Login')).toBeInTheDocument()
    expect(screen.getByText('Tenant Created')).toBeInTheDocument()
    expect(screen.getByText('File Upload')).toBeInTheDocument()
  })

  it('shows actor_id when actor_name is null', () => {
    render(<AuditLogPage />)
    expect(screen.getByText('u2')).toBeInTheDocument()
  })

  it('shows target type and id', () => {
    render(<AuditLogPage />)
    expect(screen.getByText('user: u1')).toBeInTheDocument()
    expect(screen.getByText('file: f1')).toBeInTheDocument()
  })

  it('shows dash for entries with no target', () => {
    render(<AuditLogPage />)
    // The second entry has null target_type and target_id
    const dashes = screen.getAllByText('\u2014')
    expect(dashes.length).toBeGreaterThanOrEqual(1)
  })

  it('truncates long details', () => {
    render(<AuditLogPage />)
    // 57 chars + "..."
    const truncated = sampleEntries[2].details!.slice(0, 57) + '...'
    expect(screen.getByText(truncated)).toBeInTheDocument()
  })

  it('renders filter inputs', () => {
    render(<AuditLogPage />)
    expect(screen.getByLabelText('Actor')).toBeInTheDocument()
    expect(screen.getByLabelText('Action')).toBeInTheDocument()
    expect(screen.getByLabelText('From')).toBeInTheDocument()
    expect(screen.getByLabelText('To')).toBeInTheDocument()
    expect(screen.getByText('Apply')).toBeInTheDocument()
  })

  it('does not show Clear button when no filters are set', () => {
    render(<AuditLogPage />)
    expect(screen.queryByText('Clear')).not.toBeInTheDocument()
  })

  it('shows Clear button when filter input has value', async () => {
    const user = userEvent.setup()
    render(<AuditLogPage />)

    await user.type(screen.getByLabelText('Actor'), 'alice')

    expect(screen.getByText('Clear')).toBeInTheDocument()
  })

  it('applies filters when Apply is clicked', async () => {
    const user = userEvent.setup()
    render(<AuditLogPage />)

    await user.type(screen.getByLabelText('Actor'), 'alice')
    await user.type(screen.getByLabelText('Action'), 'auth.login')
    await user.click(screen.getByText('Apply'))

    await waitFor(() => {
      // Most recent call should include filters
      const lastCall = mockFetchAuditLog.mock.calls[mockFetchAuditLog.mock.calls.length - 1]
      expect(lastCall[0]).toBe(1) // page reset to 1
      expect(lastCall[2]).toEqual(
        expect.objectContaining({
          actor: 'alice',
          action: 'auth.login',
        })
      )
    })
  })

  it('clears filters when Clear is clicked', async () => {
    const user = userEvent.setup()
    render(<AuditLogPage />)

    await user.type(screen.getByLabelText('Actor'), 'alice')
    await user.click(screen.getByText('Apply'))

    await user.click(screen.getByText('Clear'))

    await waitFor(() => {
      expect(screen.getByLabelText('Actor')).toHaveValue('')
    })
  })

  it('applies filters on Enter key in filter input', async () => {
    const user = userEvent.setup()
    render(<AuditLogPage />)

    const actorInput = screen.getByLabelText('Actor')
    await user.type(actorInput, 'alice')
    await user.keyboard('{Enter}')

    await waitFor(() => {
      const lastCall = mockFetchAuditLog.mock.calls[mockFetchAuditLog.mock.calls.length - 1]
      expect(lastCall[2]).toEqual(
        expect.objectContaining({ actor: 'alice' })
      )
    })
  })

  it('shows pagination info', () => {
    render(<AuditLogPage />)
    expect(screen.getByText('Page 1 of 1')).toBeInTheDocument()
  })

  it('shows loading skeleton state', () => {
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = {
          auditLog: [],
          auditLogTotal: 0,
          auditLogLoading: true,
          fetchAuditLog: mockFetchAuditLog,
        }
        return selector ? selector(store) : store
      }
    )

    const { container } = render(<AuditLogPage />)
    const skeletons = container.querySelectorAll('.animate-pulse')
    expect(skeletons.length).toBeGreaterThan(0)
  })

  it('shows error when fetchAuditLog fails', async () => {
    mockFetchAuditLog.mockRejectedValueOnce(new Error('Forbidden'))

    render(<AuditLogPage />)

    await waitFor(() => {
      expect(screen.getByText('Forbidden')).toBeInTheDocument()
    })
  })

  it('shows empty state when no entries', () => {
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = {
          auditLog: [],
          auditLogTotal: 0,
          auditLogLoading: false,
          fetchAuditLog: mockFetchAuditLog,
        }
        return selector ? selector(store) : store
      }
    )

    render(<AuditLogPage />)
    expect(screen.getByText('No data found')).toBeInTheDocument()
  })
})
