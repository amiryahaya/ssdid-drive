import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import UsersPage from '../UsersPage'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockFetchUsers = vi.fn().mockResolvedValue(undefined)
const mockUpdateUser = vi.fn().mockResolvedValue(undefined)

const sampleUsers = [
  { id: 'u1', did: 'did:ssdid:abcdefghijklmnopqrstuvwxyz123456', display_name: 'Alice', email: 'alice@test.com', status: 'active', system_role: 'SuperAdmin', tenant_id: null, last_login_at: '2026-03-10T12:00:00Z', created_at: '2026-01-01T00:00:00Z' },
  { id: 'u2', did: 'did:ssdid:short', display_name: null, email: null, status: 'suspended', system_role: null, tenant_id: 't1', last_login_at: null, created_at: '2026-02-01T00:00:00Z' },
]

beforeEach(() => {
  vi.clearAllMocks()
  mockFetchUsers.mockResolvedValue(undefined)
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector?: (s: unknown) => unknown) => {
      const store = {
        users: sampleUsers,
        usersTotal: 2,
        usersLoading: false,
        fetchUsers: mockFetchUsers,
        updateUser: mockUpdateUser,
      }
      return selector ? selector(store) : store
    }
  )
})

describe('UsersPage', () => {
  it('calls fetchUsers on mount', () => {
    render(<UsersPage />)
    expect(mockFetchUsers).toHaveBeenCalledWith(1, 20, undefined)
  })

  it('renders user data in the table', () => {
    render(<UsersPage />)
    expect(screen.getByText('Alice')).toBeInTheDocument()
    expect(screen.getByText('alice@test.com')).toBeInTheDocument()
    expect(screen.getByText('SuperAdmin')).toBeInTheDocument()
  })

  it('shows dash for null display name and email', () => {
    render(<UsersPage />)
    const dashes = screen.getAllByText('\u2014')
    // DID truncation, null display_name, null email, null last_login
    expect(dashes.length).toBeGreaterThanOrEqual(2)
  })

  it('renders active status badge', () => {
    render(<UsersPage />)
    expect(screen.getByText('active')).toBeInTheDocument()
  })

  it('renders suspended status badge', () => {
    render(<UsersPage />)
    expect(screen.getByText('suspended')).toBeInTheDocument()
  })

  it('shows "User" for null system_role', () => {
    render(<UsersPage />)
    expect(screen.getByText('User')).toBeInTheDocument()
  })

  it('shows Suspend button for active users', () => {
    render(<UsersPage />)
    expect(screen.getByText('Suspend')).toBeInTheDocument()
  })

  it('shows Activate button for suspended users', () => {
    render(<UsersPage />)
    expect(screen.getByText('Activate')).toBeInTheDocument()
  })

  it('calls updateUser to suspend an active user after confirm', async () => {
    window.confirm = vi.fn().mockReturnValue(true)
    const user = userEvent.setup()

    render(<UsersPage />)
    await user.click(screen.getByText('Suspend'))

    await waitFor(() => {
      expect(window.confirm).toHaveBeenCalledWith(
        'Suspend user Alice? They will lose access immediately.'
      )
      expect(mockUpdateUser).toHaveBeenCalledWith('u1', { status: 'suspended' })
    })
  })

  it('does not call updateUser when user cancels suspend confirmation', async () => {
    window.confirm = vi.fn().mockReturnValue(false)
    const user = userEvent.setup()

    render(<UsersPage />)
    await user.click(screen.getByText('Suspend'))

    expect(mockUpdateUser).not.toHaveBeenCalled()
  })

  it('activates suspended user without confirmation', async () => {
    const user = userEvent.setup()

    render(<UsersPage />)
    await user.click(screen.getByText('Activate'))

    await waitFor(() => {
      expect(mockUpdateUser).toHaveBeenCalledWith('u2', { status: 'active' })
    })
  })

  it('shows search input', () => {
    render(<UsersPage />)
    expect(screen.getByPlaceholderText('Search users...')).toBeInTheDocument()
  })

  it('shows pagination info', () => {
    render(<UsersPage />)
    expect(screen.getByText('Page 1 of 1')).toBeInTheDocument()
  })

  it('shows loading skeleton state', () => {
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = {
          users: [],
          usersTotal: 0,
          usersLoading: true,
          fetchUsers: mockFetchUsers,
          updateUser: mockUpdateUser,
        }
        return selector ? selector(store) : store
      }
    )

    const { container } = render(<UsersPage />)
    const skeletons = container.querySelectorAll('.animate-pulse')
    expect(skeletons.length).toBeGreaterThan(0)
  })

  it('shows error when fetchUsers fails', async () => {
    mockFetchUsers.mockRejectedValueOnce(new Error('Network error'))

    render(<UsersPage />)

    await waitFor(() => {
      expect(screen.getByText('Network error')).toBeInTheDocument()
    })
  })

  it('shows error when updateUser fails', async () => {
    const user = userEvent.setup()
    mockUpdateUser.mockRejectedValue(new Error('Permission denied'))

    render(<UsersPage />)
    await user.click(screen.getByText('Activate'))

    await waitFor(() => {
      expect(screen.getByText('Permission denied')).toBeInTheDocument()
    })
  })

  it('truncates long DIDs', () => {
    render(<UsersPage />)
    // did:ssdid:abcdefghijklmnopqrstuvwxyz123456 is > 24 chars, should be truncated
    expect(screen.getByText('did:ssdid:abcdef...yz123456')).toBeInTheDocument()
  })
})
