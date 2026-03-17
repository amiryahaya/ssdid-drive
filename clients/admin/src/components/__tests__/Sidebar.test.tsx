import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import Sidebar from '../Sidebar'
import { useAuthStore } from '../../stores/authStore'

vi.mock('../../stores/authStore', () => ({
  useAuthStore: vi.fn(),
}))

const mockLogout = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({
        user: { id: 'u1', did: 'did:ssdid:abc', display_name: 'Admin', system_role: 'SuperAdmin' },
        logout: mockLogout,
      })
  )
})

function renderSidebar(collapsed = false, onToggle = vi.fn(), onClose?: () => void) {
  return render(
    <MemoryRouter initialEntries={['/']}>
      <Sidebar collapsed={collapsed} onToggle={onToggle} onClose={onClose} />
    </MemoryRouter>
  )
}

describe('Sidebar', () => {
  it('renders brand name when not collapsed', () => {
    renderSidebar(false)
    expect(screen.getByText('SSDID Drive')).toBeInTheDocument()
  })

  it('hides brand name when collapsed', () => {
    renderSidebar(true)
    expect(screen.queryByText('SSDID Drive')).not.toBeInTheDocument()
  })

  it('renders all navigation links when expanded', () => {
    renderSidebar(false)
    expect(screen.getByText('Dashboard')).toBeInTheDocument()
    expect(screen.getByText('Users')).toBeInTheDocument()
    expect(screen.getByText('Tenants')).toBeInTheDocument()
    expect(screen.getByText('Audit Log')).toBeInTheDocument()
  })

  it('hides nav labels when collapsed', () => {
    renderSidebar(true)
    expect(screen.queryByText('Dashboard')).not.toBeInTheDocument()
    expect(screen.queryByText('Users')).not.toBeInTheDocument()
  })

  it('renders user display name when expanded', () => {
    renderSidebar(false)
    expect(screen.getByText('Admin')).toBeInTheDocument()
  })

  it('calls onToggle when collapse button is clicked', async () => {
    const user = userEvent.setup()
    const onToggle = vi.fn()
    renderSidebar(false, onToggle)

    const toggleBtn = screen.getByTitle('Collapse sidebar')
    await user.click(toggleBtn)
    expect(onToggle).toHaveBeenCalled()
  })

  it('shows "Expand sidebar" title when collapsed', () => {
    renderSidebar(true)
    expect(screen.getByTitle('Expand sidebar')).toBeInTheDocument()
  })

  it('calls logout when Sign Out is clicked (expanded)', async () => {
    const user = userEvent.setup()
    renderSidebar(false)

    await user.click(screen.getByText('Sign Out'))
    expect(mockLogout).toHaveBeenCalled()
  })

  it('calls logout when user icon is clicked (collapsed)', async () => {
    const user = userEvent.setup()
    renderSidebar(true)

    const signOutBtn = screen.getByTitle('Sign Out')
    await user.click(signOutBtn)
    expect(mockLogout).toHaveBeenCalled()
  })

  it('shows fallback text when user has no display_name', () => {
    ;(useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector: (s: unknown) => unknown) =>
        selector({
          user: { id: 'u1', did: 'did:ssdid:abc', display_name: null, system_role: 'SuperAdmin' },
          logout: mockLogout,
        })
    )
    renderSidebar(false)
    expect(screen.getByText('did:ssdid:abc')).toBeInTheDocument()
  })

  it('highlights the active nav item', () => {
    const { container } = render(
      <MemoryRouter initialEntries={['/users']}>
        <Sidebar collapsed={false} onToggle={vi.fn()} />
      </MemoryRouter>
    )
    // The Users link should have active styling
    const usersLink = screen.getByText('Users').closest('a')!
    expect(usersLink.className).toContain('border-blue-600')
    expect(usersLink.className).toContain('bg-blue-50')
  })
})
