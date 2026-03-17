import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import Layout from '../Layout'
import { useAuthStore } from '../../stores/authStore'

vi.mock('../../stores/authStore', () => ({
  useAuthStore: vi.fn(),
}))

const mockLogout = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()

  // Mock window.matchMedia for responsive layout
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: query.includes('min-width: 1024px'), // pretend desktop
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  })

  ;(useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({
        user: { id: 'u1', did: 'did:ssdid:abc', display_name: 'Admin User', system_role: 'SuperAdmin' },
        logout: mockLogout,
      })
  )
})

function renderLayout(pathname = '/') {
  return render(
    <MemoryRouter initialEntries={[pathname]}>
      <Layout>
        <div data-testid="page-content">Page Content</div>
      </Layout>
    </MemoryRouter>
  )
}

describe('Layout', () => {
  it('renders children content', () => {
    renderLayout()
    expect(screen.getByTestId('page-content')).toBeInTheDocument()
  })

  it('shows page title for Dashboard on root path', () => {
    renderLayout('/')
    // Use the h1#page-title to avoid matching sidebar nav items
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Dashboard')
  })

  it('shows page title for Users', () => {
    renderLayout('/users')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Users')
  })

  it('shows page title for Tenants', () => {
    renderLayout('/tenants')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Tenants')
  })

  it('shows page title for Audit Log', () => {
    renderLayout('/audit-log')
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Audit Log')
  })

  it('shows "Tenant Details" for tenant detail paths', () => {
    renderLayout('/tenants/t1')
    expect(screen.getByText('Tenant Details')).toBeInTheDocument()
  })

  it('displays user display name', () => {
    renderLayout()
    // Name appears in both header and sidebar, verify at least one is present
    expect(screen.getAllByText('Admin User').length).toBeGreaterThanOrEqual(1)
  })

  it('calls logout when Sign Out is clicked', async () => {
    const user = userEvent.setup()
    renderLayout()

    // There may be multiple "Sign Out" buttons (header + sidebar)
    const signOutButtons = screen.getAllByText('Sign Out')
    await user.click(signOutButtons[0])
    expect(mockLogout).toHaveBeenCalled()
  })

  it('shows user DID when display_name is null', () => {
    ;(useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector: (s: unknown) => unknown) =>
        selector({
          user: { id: 'u1', did: 'did:ssdid:abc', display_name: null, system_role: 'SuperAdmin' },
          logout: mockLogout,
        })
    )
    renderLayout()
    // DID appears in both header and sidebar
    expect(screen.getAllByText('did:ssdid:abc').length).toBeGreaterThanOrEqual(1)
  })
})
