import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import CreateTenantDialog from '../CreateTenantDialog'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockCreateTenant = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({ createTenant: mockCreateTenant })
  )
})

describe('CreateTenantDialog', () => {
  const defaultProps = {
    open: true,
    onClose: vi.fn(),
    onCreated: vi.fn(),
  }

  it('renders name and slug fields when open', () => {
    render(<CreateTenantDialog {...defaultProps} />)
    expect(screen.getByLabelText('Name')).toBeInTheDocument()
    expect(screen.getByLabelText('Slug')).toBeInTheDocument()
    expect(screen.getByText('Create')).toBeInTheDocument()
  })

  it('does not render when closed', () => {
    render(<CreateTenantDialog {...defaultProps} open={false} />)
    expect(screen.queryByText('Create Tenant')).not.toBeInTheDocument()
  })

  it('auto-generates slug from name', async () => {
    const user = userEvent.setup()
    render(<CreateTenantDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Name'), 'Acme Corporation')

    expect(screen.getByLabelText('Slug')).toHaveValue('acme-corporation')
  })

  it('stops auto-generating slug when user manually edits it', async () => {
    const user = userEvent.setup()
    render(<CreateTenantDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Slug'), 'custom-slug')
    await user.type(screen.getByLabelText('Name'), 'Acme Corp')

    expect(screen.getByLabelText('Slug')).toHaveValue('custom-slug')
  })

  it('disables Create button when name is empty', () => {
    render(<CreateTenantDialog {...defaultProps} />)
    expect(screen.getByText('Create')).toBeDisabled()
  })

  it('calls createTenant with name and slug on submit', async () => {
    const user = userEvent.setup()
    const onCreated = vi.fn()
    const onClose = vi.fn()
    mockCreateTenant.mockResolvedValue({ id: 't1', name: 'Acme', slug: 'acme' })

    render(<CreateTenantDialog open={true} onClose={onClose} onCreated={onCreated} />)

    await user.type(screen.getByLabelText('Name'), 'Acme')
    await user.click(screen.getByText('Create'))

    await waitFor(() => {
      expect(mockCreateTenant).toHaveBeenCalledWith('Acme', 'acme')
      expect(onCreated).toHaveBeenCalled()
      expect(onClose).toHaveBeenCalled()
    })
  })

  it('shows error message on creation failure', async () => {
    const user = userEvent.setup()
    mockCreateTenant.mockRejectedValue(new Error('Slug already exists'))

    render(<CreateTenantDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Name'), 'Acme')
    await user.click(screen.getByText('Create'))

    await waitFor(() => {
      expect(screen.getByText('Slug already exists')).toBeInTheDocument()
    })
  })

  it('shows "Creating..." text while submitting', async () => {
    const user = userEvent.setup()
    let resolveCreate: (v: unknown) => void
    mockCreateTenant.mockImplementation(() => new Promise((resolve) => { resolveCreate = resolve }))

    render(<CreateTenantDialog {...defaultProps} />)

    await user.type(screen.getByLabelText('Name'), 'Acme')
    await user.click(screen.getByText('Create'))

    expect(screen.getByText('Creating...')).toBeInTheDocument()

    resolveCreate!({ id: 't1' })
  })

  it('calls onClose when Cancel is clicked', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<CreateTenantDialog open={true} onClose={onClose} onCreated={vi.fn()} />)

    await user.click(screen.getByText('Cancel'))
    expect(onClose).toHaveBeenCalled()
  })

  it('closes on Escape key', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<CreateTenantDialog open={true} onClose={onClose} onCreated={vi.fn()} />)

    await user.keyboard('{Escape}')
    expect(onClose).toHaveBeenCalled()
  })

  it('resets form fields when reopened', async () => {
    const user = userEvent.setup()
    const { rerender } = render(<CreateTenantDialog open={true} onClose={vi.fn()} onCreated={vi.fn()} />)

    await user.type(screen.getByLabelText('Name'), 'Acme')
    expect(screen.getByLabelText('Name')).toHaveValue('Acme')

    // Close and reopen
    rerender(<CreateTenantDialog open={false} onClose={vi.fn()} onCreated={vi.fn()} />)
    rerender(<CreateTenantDialog open={true} onClose={vi.fn()} onCreated={vi.fn()} />)

    expect(screen.getByLabelText('Name')).toHaveValue('')
  })
})
