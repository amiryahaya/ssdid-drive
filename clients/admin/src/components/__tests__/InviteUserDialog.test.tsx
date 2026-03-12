import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import InviteUserDialog from '../InviteUserDialog'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockCreateAdminInvitation = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({ createAdminInvitation: mockCreateAdminInvitation })
  )
})

describe('InviteUserDialog', () => {
  const defaultProps = {
    open: true,
    onClose: vi.fn(),
    tenantId: 'tenant-123',
    tenantName: 'Acme Corp',
    onInvited: vi.fn(),
  }

  it('renders email, role toggle, and message fields', () => {
    render(<InviteUserDialog {...defaultProps} />)
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByText('Owner')).toBeInTheDocument()
    expect(screen.getByText('Admin')).toBeInTheDocument()
    expect(screen.getByLabelText(/Message/)).toBeInTheDocument()
  })

  it('does not render when closed', () => {
    render(<InviteUserDialog {...defaultProps} open={false} />)
    expect(screen.queryByText('Invite User')).not.toBeInTheDocument()
  })

  it('defaults to Owner role', () => {
    render(<InviteUserDialog {...defaultProps} />)
    const ownerBtn = screen.getByText('Owner').closest('button')!
    expect(ownerBtn.className).toContain('border-blue-600')
  })

  it('toggles between Owner and Admin roles', async () => {
    const user = userEvent.setup()
    render(<InviteUserDialog {...defaultProps} />)

    const adminBtn = screen.getByText('Admin').closest('button')!
    await user.click(adminBtn)
    expect(adminBtn.className).toContain('border-blue-600')

    const ownerBtn = screen.getByText('Owner').closest('button')!
    expect(ownerBtn.className).not.toContain('border-blue-600')
  })

  it('calls createAdminInvitation with correct params on submit', async () => {
    const user = userEvent.setup()
    mockCreateAdminInvitation.mockResolvedValue({
      id: 'inv-1',
      short_code: 'ACME-X7K2',
      status: 'pending',
    })

    render(<InviteUserDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.click(screen.getByText('Send Invitation'))

    await waitFor(() => {
      expect(mockCreateAdminInvitation).toHaveBeenCalledWith(
        'tenant-123', 'test@example.com', 'owner', undefined
      )
    })
  })

  it('shows success state with invite code after creation', async () => {
    const user = userEvent.setup()
    mockCreateAdminInvitation.mockResolvedValue({
      id: 'inv-1',
      short_code: 'ACME-X7K2',
      status: 'pending',
    })

    render(<InviteUserDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.click(screen.getByText('Send Invitation'))

    await waitFor(() => {
      expect(screen.getByText('Invitation Sent!')).toBeInTheDocument()
      expect(screen.getByText('ACME-X7K2')).toBeInTheDocument()
      expect(screen.getByText('Copy')).toBeInTheDocument()
    })
  })

  it('shows error on failure', async () => {
    const user = userEvent.setup()
    mockCreateAdminInvitation.mockRejectedValue(new Error('Email already invited'))

    render(<InviteUserDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Email'), 'dup@example.com')
    await user.click(screen.getByText('Send Invitation'))

    await waitFor(() => {
      expect(screen.getByText('Email already invited')).toBeInTheDocument()
    })
  })

  it('calls onInvited after successful invitation creation', async () => {
    const user = userEvent.setup()
    const onInvited = vi.fn()
    mockCreateAdminInvitation.mockResolvedValue({
      id: 'inv-1', short_code: 'ACME-X7K2', status: 'pending',
    })
    render(<InviteUserDialog {...defaultProps} onInvited={onInvited} />)
    await user.type(screen.getByLabelText('Email'), 'test@example.com')
    await user.click(screen.getByText('Send Invitation'))
    await waitFor(() => expect(onInvited).toHaveBeenCalledTimes(1))
  })

  it('send button is disabled when email is empty', () => {
    render(<InviteUserDialog {...defaultProps} />)
    expect(screen.getByText('Send Invitation')).toBeDisabled()
  })

  it('closes on Escape key when not submitting', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<InviteUserDialog {...defaultProps} onClose={onClose} />)
    await user.keyboard('{Escape}')
    expect(onClose).toHaveBeenCalled()
  })
})
