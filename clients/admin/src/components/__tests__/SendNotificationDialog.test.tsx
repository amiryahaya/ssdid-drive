import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import SendNotificationDialog from '../SendNotificationDialog'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockSendNotification = vi.fn()
const mockFetchTenants = vi.fn().mockResolvedValue(undefined)
const mockFetchUsers = vi.fn().mockResolvedValue(undefined)

const sampleTenants = [
  { id: 't1', name: 'Acme Corp', slug: 'acme', disabled: false, storage_quota_bytes: null, user_count: 5, created_at: '2026-01-01T00:00:00Z' },
  { id: 't2', name: 'Beta Ltd', slug: 'beta', disabled: false, storage_quota_bytes: null, user_count: 3, created_at: '2026-02-01T00:00:00Z' },
]

const sampleUsers = [
  { id: 'u1', did: 'did:example:alice', display_name: 'Alice', email: 'alice@example.com', status: 'active', system_role: null, tenant_id: null, last_login_at: null, created_at: '2026-01-01T00:00:00Z' },
  { id: 'u2', did: 'did:example:bob', display_name: null, email: 'bob@example.com', status: 'active', system_role: null, tenant_id: null, last_login_at: null, created_at: '2026-01-01T00:00:00Z' },
]

function makeStore(overrides = {}) {
  return {
    sendNotification: mockSendNotification,
    tenants: sampleTenants,
    fetchTenants: mockFetchTenants,
    fetchUsers: mockFetchUsers,
    users: sampleUsers,
    usersLoading: false,
    ...overrides,
  }
}

beforeEach(() => {
  vi.clearAllMocks()
  mockFetchTenants.mockResolvedValue(undefined)
  mockFetchUsers.mockResolvedValue(undefined)
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector?: (s: unknown) => unknown) => {
      const store = makeStore()
      return selector ? selector(store) : store
    }
  )
})

const defaultProps = {
  open: true,
  onClose: vi.fn(),
  onSent: vi.fn(),
}

describe('SendNotificationDialog', () => {
  it('renders when open', () => {
    render(<SendNotificationDialog {...defaultProps} />)
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Send Notification' })).toBeInTheDocument()
  })

  it('does not render when closed', () => {
    render(<SendNotificationDialog {...defaultProps} open={false} />)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('defaults to broadcast scope', () => {
    render(<SendNotificationDialog {...defaultProps} />)
    const broadcastBtn = screen.getByText('Broadcast to All').closest('button')!
    expect(broadcastBtn.className).toContain('border-blue-600')
  })

  it('switches scope to user when Specific User is clicked', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByText('Specific User'))

    const userBtn = screen.getByText('Specific User').closest('button')!
    expect(userBtn.className).toContain('border-blue-600')
  })

  it('switches scope to tenant when Organization is clicked', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByRole('button', { name: 'Organization' }))

    const tenantBtn = screen.getByRole('button', { name: 'Organization' })
    expect(tenantBtn.className).toContain('border-blue-600')
  })

  it('shows user search input when user scope is selected', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByText('Specific User'))

    expect(screen.getByPlaceholderText('Search by name or email...')).toBeInTheDocument()
  })

  it('shows tenant dropdown when tenant scope is selected', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByRole('button', { name: 'Organization' }))

    expect(screen.getByRole('combobox', { name: 'Organization' })).toBeInTheDocument()
    expect(screen.getByText('Acme Corp (acme)')).toBeInTheDocument()
    expect(screen.getByText('Beta Ltd (beta)')).toBeInTheDocument()
  })

  it('hides target field for broadcast scope', () => {
    render(<SendNotificationDialog {...defaultProps} />)

    expect(screen.queryByPlaceholderText('Search by name or email...')).not.toBeInTheDocument()
    expect(screen.queryByLabelText('Organization')).not.toBeInTheDocument()
  })

  it('send button is disabled when title and message are empty', () => {
    render(<SendNotificationDialog {...defaultProps} />)
    const sendBtn = screen.getByRole('button', { name: /Send Notification/i })
    expect(sendBtn).toBeDisabled()
  })

  it('send button is disabled when only title is filled', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Title'), 'Hello')

    expect(screen.getByRole('button', { name: /Send Notification/i })).toBeDisabled()
  })

  it('send button is disabled when only message is filled', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Message'), 'Hello world')

    expect(screen.getByRole('button', { name: /Send Notification/i })).toBeDisabled()
  })

  it('send button is disabled when user scope selected but no user chosen', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByText('Specific User'))
    await user.type(screen.getByLabelText('Title'), 'Hello')
    await user.type(screen.getByLabelText('Message'), 'World')

    expect(screen.getByRole('button', { name: /Send Notification/i })).toBeDisabled()
  })

  it('send button is disabled when tenant scope selected but no tenant chosen', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByRole('button', { name: 'Organization' }))
    await user.type(screen.getByLabelText('Title'), 'Hello')
    await user.type(screen.getByLabelText('Message'), 'World')

    expect(screen.getByRole('button', { name: /Send Notification/i })).toBeDisabled()
  })

  it('calls sendNotification with correct params for broadcast', async () => {
    const user = userEvent.setup()
    mockSendNotification.mockResolvedValue({ recipients: 10 })

    render(<SendNotificationDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Title'), 'System Alert')
    await user.type(screen.getByLabelText('Message'), 'Maintenance tonight')
    await user.click(screen.getByRole('button', { name: /Send Notification/i }))

    await waitFor(() => {
      expect(mockSendNotification).toHaveBeenCalledWith(
        'broadcast',
        null,
        'System Alert',
        'Maintenance tonight'
      )
    })
  })

  it('calls sendNotification with tenant target', async () => {
    const user = userEvent.setup()
    mockSendNotification.mockResolvedValue({ recipients: 5 })

    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByRole('button', { name: 'Organization' }))
    const select = screen.getByRole('combobox', { name: 'Organization' })
    await user.selectOptions(select, 't1')
    await user.type(screen.getByLabelText('Title'), 'Org Alert')
    await user.type(screen.getByLabelText('Message'), 'Tenant message')
    await user.click(screen.getByRole('button', { name: /Send Notification/i }))

    await waitFor(() => {
      expect(mockSendNotification).toHaveBeenCalledWith(
        'tenant',
        't1',
        'Org Alert',
        'Tenant message'
      )
    })
  })

  it('shows success state with recipient count after sending', async () => {
    const user = userEvent.setup()
    mockSendNotification.mockResolvedValue({ recipients: 42 })

    render(<SendNotificationDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Title'), 'Hello')
    await user.type(screen.getByLabelText('Message'), 'World')
    await user.click(screen.getByRole('button', { name: /Send Notification/i }))

    await waitFor(() => {
      expect(screen.getByText('Notification Sent!')).toBeInTheDocument()
      expect(screen.getByText('42')).toBeInTheDocument()
      expect(screen.getByText(/recipients/)).toBeInTheDocument()
    })
  })

  it('shows singular "recipient" when count is 1', async () => {
    const user = userEvent.setup()
    mockSendNotification.mockResolvedValue({ recipients: 1 })

    render(<SendNotificationDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Title'), 'Hello')
    await user.type(screen.getByLabelText('Message'), 'World')
    await user.click(screen.getByRole('button', { name: /Send Notification/i }))

    await waitFor(() => {
      expect(screen.getByText(/recipient\./)).toBeInTheDocument()
    })
  })

  it('calls onSent after successful send', async () => {
    const user = userEvent.setup()
    const onSent = vi.fn()
    mockSendNotification.mockResolvedValue({ recipients: 5 })

    render(<SendNotificationDialog {...defaultProps} onSent={onSent} />)

    await user.type(screen.getByLabelText('Title'), 'Hello')
    await user.type(screen.getByLabelText('Message'), 'World')
    await user.click(screen.getByRole('button', { name: /Send Notification/i }))

    await waitFor(() => {
      expect(onSent).toHaveBeenCalledTimes(1)
    })
  })

  it('shows error message on send failure', async () => {
    const user = userEvent.setup()
    mockSendNotification.mockRejectedValue(new Error('Server error'))

    render(<SendNotificationDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Title'), 'Hello')
    await user.type(screen.getByLabelText('Message'), 'World')
    await user.click(screen.getByRole('button', { name: /Send Notification/i }))

    await waitFor(() => {
      expect(screen.getByText('Server error')).toBeInTheDocument()
    })
  })

  it('resets form state when dialog is closed and reopened', async () => {
    const user = userEvent.setup()
    const { rerender } = render(<SendNotificationDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Title'), 'Old Title')
    await user.type(screen.getByLabelText('Message'), 'Old Message')

    // Close the dialog
    rerender(<SendNotificationDialog {...defaultProps} open={false} />)

    // Reopen
    rerender(<SendNotificationDialog {...defaultProps} open={true} />)

    expect(screen.getByLabelText('Title')).toHaveValue('')
    expect(screen.getByLabelText('Message')).toHaveValue('')
  })

  it('calls onClose when Cancel button is clicked', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<SendNotificationDialog {...defaultProps} onClose={onClose} />)

    await user.click(screen.getByText('Cancel'))

    expect(onClose).toHaveBeenCalled()
  })

  it('calls onClose when Escape key is pressed', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<SendNotificationDialog {...defaultProps} onClose={onClose} />)

    await user.keyboard('{Escape}')

    expect(onClose).toHaveBeenCalled()
  })

  it('searches for users when typing in user search field', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByText('Specific User'))
    await user.type(screen.getByPlaceholderText('Search by name or email...'), 'alice')

    await waitFor(() => {
      expect(mockFetchUsers).toHaveBeenCalledWith(1, 10, 'alice')
    })
  })

  it('shows user results in dropdown after searching', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByText('Specific User'))
    await user.type(screen.getByPlaceholderText('Search by name or email...'), 'al')

    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeInTheDocument()
    })
  })

  it('selects a user from dropdown results', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByText('Specific User'))
    await user.type(screen.getByPlaceholderText('Search by name or email...'), 'al')

    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeInTheDocument()
    })

    await user.click(screen.getByText('Alice'))

    expect(screen.getByDisplayValue('alice@example.com')).toBeInTheDocument()
    expect(screen.getByText(/Selected:/)).toBeInTheDocument()
  })

  it('clears selected user when X button is clicked', async () => {
    const user = userEvent.setup()
    render(<SendNotificationDialog {...defaultProps} />)

    await user.click(screen.getByText('Specific User'))
    await user.type(screen.getByPlaceholderText('Search by name or email...'), 'al')

    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeInTheDocument()
    })

    await user.click(screen.getByText('Alice'))

    // Clear the selection
    await user.click(screen.getByLabelText('Clear selected user'))

    expect(screen.queryByText(/Selected:/)).not.toBeInTheDocument()
    expect(screen.getByPlaceholderText('Search by name or email...')).toHaveValue('')
  })

  it('loads tenants on open', () => {
    render(<SendNotificationDialog {...defaultProps} />)
    expect(mockFetchTenants).toHaveBeenCalledWith(1, 100)
  })
})
