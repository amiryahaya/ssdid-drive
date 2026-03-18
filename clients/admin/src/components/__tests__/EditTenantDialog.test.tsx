import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import EditTenantDialog from '../EditTenantDialog'
import { useAdminStore } from '../../stores/adminStore'
import type { Tenant } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockUpdateTenant = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({ updateTenant: mockUpdateTenant })
  )
})

const baseTenant: Tenant = {
  id: 't1',
  name: 'Acme',
  slug: 'acme',
  disabled: false,
  storage_quota_bytes: null,
  user_count: 5,
  created_at: '2026-01-01T00:00:00Z',
}

describe('EditTenantDialog', () => {
  const defaultProps = {
    tenant: baseTenant,
    onClose: vi.fn(),
    onUpdated: vi.fn(),
  }

  it('renders with tenant data pre-filled', () => {
    render(<EditTenantDialog {...defaultProps} />)
    expect(screen.getByText('Edit Tenant')).toBeInTheDocument()
    expect(screen.getByLabelText('Name')).toHaveValue('Acme')
    expect(screen.getByLabelText('Slug')).toHaveValue('acme')
    expect(screen.getByLabelText('Slug')).toBeDisabled()
  })

  it('does not render when tenant is null', () => {
    render(<EditTenantDialog tenant={null} onClose={vi.fn()} onUpdated={vi.fn()} />)
    expect(screen.queryByText('Edit Tenant')).not.toBeInTheDocument()
  })

  it('pre-fills storage quota in GB when tenant has one', () => {
    const tenant = { ...baseTenant, storage_quota_bytes: 5368709120 } // 5 GB
    render(<EditTenantDialog tenant={tenant} onClose={vi.fn()} onUpdated={vi.fn()} />)
    expect(screen.getByLabelText('Storage Quota (GB)')).toHaveValue(5)
  })

  it('leaves storage quota empty when tenant has no quota', () => {
    render(<EditTenantDialog {...defaultProps} />)
    expect(screen.getByLabelText('Storage Quota (GB)')).toHaveValue(null)
  })

  it('calls updateTenant with name change on submit', async () => {
    const user = userEvent.setup()
    const onUpdated = vi.fn()
    const onClose = vi.fn()
    mockUpdateTenant.mockResolvedValue(undefined)

    render(<EditTenantDialog tenant={baseTenant} onClose={onClose} onUpdated={onUpdated} />)

    await user.clear(screen.getByLabelText('Name'))
    await user.type(screen.getByLabelText('Name'), 'Acme Corp')
    await user.click(screen.getByText('Save'))

    await waitFor(() => {
      expect(mockUpdateTenant).toHaveBeenCalledWith('t1', { name: 'Acme Corp' }, false)
      expect(onUpdated).toHaveBeenCalled()
      expect(onClose).toHaveBeenCalled()
    })
  })

  it('closes without API call when nothing changed', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()

    render(<EditTenantDialog tenant={baseTenant} onClose={onClose} onUpdated={vi.fn()} />)
    await user.click(screen.getByText('Save'))

    expect(mockUpdateTenant).not.toHaveBeenCalled()
    expect(onClose).toHaveBeenCalled()
  })

  it('shows validation error for negative storage quota', async () => {
    render(<EditTenantDialog {...defaultProps} />)

    // Set a negative value via fireEvent since type="number" min="0" may prevent
    // form submission through native validation. We bypass native validation
    // by directly changing the React state value.
    const quotaInput = screen.getByLabelText('Storage Quota (GB)')
    fireEvent.change(quotaInput, { target: { value: '-5' } })

    // Submit the form directly via fireEvent to bypass native HTML validation
    const form = quotaInput.closest('form')!
    fireEvent.submit(form)

    await waitFor(() => {
      expect(screen.getByText('Storage quota must be a positive number or empty for unlimited')).toBeInTheDocument()
    })
  })

  it('shows error on update failure', async () => {
    const user = userEvent.setup()
    mockUpdateTenant.mockRejectedValue(new Error('Name already taken'))

    render(<EditTenantDialog {...defaultProps} />)

    await user.clear(screen.getByLabelText('Name'))
    await user.type(screen.getByLabelText('Name'), 'New Name')
    await user.click(screen.getByText('Save'))

    await waitFor(() => {
      expect(screen.getByText('Name already taken')).toBeInTheDocument()
    })
  })

  it('shows "Saving..." while submitting', async () => {
    const user = userEvent.setup()
    let resolveUpdate: (value?: unknown) => void
    mockUpdateTenant.mockImplementation(() => new Promise((resolve) => { resolveUpdate = resolve }))

    render(<EditTenantDialog {...defaultProps} />)

    await user.clear(screen.getByLabelText('Name'))
    await user.type(screen.getByLabelText('Name'), 'New Name')
    await user.click(screen.getByText('Save'))

    expect(screen.getByText('Saving...')).toBeInTheDocument()

    resolveUpdate!()
  })

  it('calls onClose when Cancel is clicked', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<EditTenantDialog tenant={baseTenant} onClose={onClose} onUpdated={vi.fn()} />)

    await user.click(screen.getByText('Cancel'))
    expect(onClose).toHaveBeenCalled()
  })

  it('closes on Escape key', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<EditTenantDialog tenant={baseTenant} onClose={onClose} onUpdated={vi.fn()} />)

    await user.keyboard('{Escape}')
    expect(onClose).toHaveBeenCalled()
  })
})
