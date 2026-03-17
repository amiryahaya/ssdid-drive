import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import TenantsPage from '../TenantsPage'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockFetchTenants = vi.fn().mockResolvedValue(undefined)
const mockUpdateTenant = vi.fn().mockResolvedValue(undefined)
const mockCreateTenant = vi.fn().mockResolvedValue(undefined)

const sampleTenants = [
  { id: 't1', name: 'Acme', slug: 'acme', disabled: false, storage_quota_bytes: null, user_count: 5, created_at: '2026-01-15T00:00:00Z' },
  { id: 't2', name: 'Beta Corp', slug: 'beta-corp', disabled: true, storage_quota_bytes: 5368709120, user_count: 2, created_at: '2026-02-10T00:00:00Z' },
]

beforeEach(() => {
  vi.clearAllMocks()
  mockFetchTenants.mockResolvedValue(undefined)
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector?: (s: unknown) => unknown) => {
      const store = {
        tenants: sampleTenants,
        tenantsTotal: 2,
        tenantsLoading: false,
        fetchTenants: mockFetchTenants,
        updateTenant: mockUpdateTenant,
        createTenant: mockCreateTenant,
      }
      return selector ? selector(store) : store
    }
  )
})

function renderPage() {
  return render(
    <MemoryRouter>
      <TenantsPage />
    </MemoryRouter>
  )
}

describe('TenantsPage', () => {
  it('calls fetchTenants on mount', () => {
    renderPage()
    expect(mockFetchTenants).toHaveBeenCalledWith(1, 20, undefined)
  })

  it('renders tenant data in the table', () => {
    renderPage()
    expect(screen.getByText('Acme')).toBeInTheDocument()
    expect(screen.getByText('acme')).toBeInTheDocument()
    expect(screen.getByText('Beta Corp')).toBeInTheDocument()
    expect(screen.getByText('beta-corp')).toBeInTheDocument()
  })

  it('renders Enabled badge for active tenants', () => {
    renderPage()
    expect(screen.getByText('Enabled')).toBeInTheDocument()
  })

  it('renders Disabled badge for disabled tenants', () => {
    renderPage()
    expect(screen.getByText('Disabled')).toBeInTheDocument()
  })

  it('renders tenant names as links', () => {
    renderPage()
    const link = screen.getByText('Acme').closest('a')!
    expect(link.getAttribute('href')).toBe('/tenants/t1')
  })

  it('shows storage quota or Unlimited', () => {
    renderPage()
    expect(screen.getByText('Unlimited')).toBeInTheDocument()
    expect(screen.getByText('5 GB')).toBeInTheDocument()
  })

  it('shows Create Tenant button', () => {
    renderPage()
    expect(screen.getByText('Create Tenant')).toBeInTheDocument()
  })

  it('shows search input', () => {
    renderPage()
    expect(screen.getByPlaceholderText('Search tenants...')).toBeInTheDocument()
  })

  it('shows Edit and Disable/Enable buttons for each tenant', () => {
    renderPage()
    const editButtons = screen.getAllByText('Edit')
    expect(editButtons.length).toBe(2)
    expect(screen.getByText('Disable')).toBeInTheDocument()
    expect(screen.getByText('Enable')).toBeInTheDocument()
  })

  it('calls updateTenant to disable a tenant after confirm', async () => {
    window.confirm = vi.fn().mockReturnValue(true)
    const user = userEvent.setup()

    renderPage()
    await user.click(screen.getByText('Disable'))

    await waitFor(() => {
      expect(window.confirm).toHaveBeenCalledWith(
        'Disable tenant "Acme"? Members will lose access.'
      )
      expect(mockUpdateTenant).toHaveBeenCalledWith('t1', { disabled: true })
    })
  })

  it('does not call updateTenant when user cancels disable confirmation', async () => {
    window.confirm = vi.fn().mockReturnValue(false)
    const user = userEvent.setup()

    renderPage()
    await user.click(screen.getByText('Disable'))

    expect(mockUpdateTenant).not.toHaveBeenCalled()
  })

  it('enables tenant without confirmation', async () => {
    const user = userEvent.setup()

    renderPage()
    await user.click(screen.getByText('Enable'))

    await waitFor(() => {
      expect(mockUpdateTenant).toHaveBeenCalledWith('t2', { disabled: false })
    })
  })

  it('opens create tenant dialog', async () => {
    const user = userEvent.setup()
    renderPage()

    await user.click(screen.getByText('Create Tenant'))

    await waitFor(() => {
      // Dialog should show with form fields (Name label is unique to the dialog)
      expect(screen.getByLabelText('Name')).toBeInTheDocument()
      expect(screen.getByLabelText('Slug')).toBeInTheDocument()
    })
  })

  it('opens edit dialog when Edit button is clicked', async () => {
    const user = userEvent.setup()
    renderPage()

    const editButtons = screen.getAllByText('Edit')
    await user.click(editButtons[0])

    await waitFor(() => {
      expect(screen.getByText('Edit Tenant')).toBeInTheDocument()
    })
  })

  it('shows pagination info', () => {
    renderPage()
    expect(screen.getByText('Page 1 of 1')).toBeInTheDocument()
  })

  it('shows loading skeleton state', () => {
    ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector?: (s: unknown) => unknown) => {
        const store = {
          tenants: [],
          tenantsTotal: 0,
          tenantsLoading: true,
          fetchTenants: mockFetchTenants,
          updateTenant: mockUpdateTenant,
          createTenant: mockCreateTenant,
        }
        return selector ? selector(store) : store
      }
    )

    const { container } = renderPage()
    const skeletons = container.querySelectorAll('.animate-pulse')
    expect(skeletons.length).toBeGreaterThan(0)
  })

  it('shows error when fetchTenants fails', async () => {
    mockFetchTenants.mockRejectedValueOnce(new Error('Network error'))

    renderPage()

    await waitFor(() => {
      expect(screen.getByText('Network error')).toBeInTheDocument()
    })
  })

  it('shows error when updateTenant fails', async () => {
    const user = userEvent.setup()
    mockUpdateTenant.mockRejectedValue(new Error('Update failed'))

    renderPage()
    await user.click(screen.getByText('Enable'))

    await waitFor(() => {
      expect(screen.getByText('Update failed')).toBeInTheDocument()
    })
  })
})
