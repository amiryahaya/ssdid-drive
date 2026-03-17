import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import AuthCallbackPage from '../AuthCallbackPage'
import { useAuthStore } from '../../stores/authStore'

vi.mock('../../stores/authStore', () => ({
  useAuthStore: vi.fn(),
}))

const mockLogin = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({ login: mockLogin, loginError: null })
  )
})

function renderWithParams(params: string) {
  return render(
    <MemoryRouter initialEntries={[`/auth/callback?${params}`]}>
      <AuthCallbackPage />
    </MemoryRouter>
  )
}

describe('AuthCallbackPage', () => {
  it('shows loading spinner when processing token', () => {
    mockLogin.mockReturnValue(new Promise(() => {})) // never resolves
    renderWithParams('token=tok-123')
    expect(screen.getByText('Signing you in...')).toBeInTheDocument()
  })

  it('calls login with token from URL params', async () => {
    mockLogin.mockResolvedValue(undefined)
    renderWithParams('token=tok-123')

    await waitFor(() => {
      expect(mockLogin).toHaveBeenCalledWith('tok-123')
    })
  })

  it('shows error when URL has error parameter', () => {
    renderWithParams('error=access_denied')
    expect(screen.getByText('Access Denied')).toBeInTheDocument()
    expect(screen.getByText('access_denied')).toBeInTheDocument()
    expect(screen.getByText('Back to Login')).toBeInTheDocument()
  })

  it('shows error when no token is present', () => {
    renderWithParams('')
    expect(screen.getByText('Access Denied')).toBeInTheDocument()
    expect(screen.getByText('No token received')).toBeInTheDocument()
  })

  it('shows error when login fails', async () => {
    mockLogin.mockRejectedValue(new Error('Not a SuperAdmin'))
    renderWithParams('token=tok-123')

    await waitFor(() => {
      expect(screen.getByText('Not a SuperAdmin')).toBeInTheDocument()
    })
  })

  it('shows loginError from store if present', () => {
    ;(useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
      (selector: (s: unknown) => unknown) =>
        selector({ login: mockLogin, loginError: 'SuperAdmin role required' })
    )
    renderWithParams('error=forbidden')

    expect(screen.getByText('forbidden')).toBeInTheDocument()
  })

  it('renders Back to Login link pointing to /admin/', () => {
    renderWithParams('error=test')
    const link = screen.getByText('Back to Login')
    expect(link.getAttribute('href')).toBe('/admin/')
  })

  it('only calls login once even on re-render', async () => {
    mockLogin.mockResolvedValue(undefined)
    const { rerender } = render(
      <MemoryRouter initialEntries={['/auth/callback?token=tok-123']}>
        <AuthCallbackPage />
      </MemoryRouter>
    )

    rerender(
      <MemoryRouter initialEntries={['/auth/callback?token=tok-123']}>
        <AuthCallbackPage />
      </MemoryRouter>
    )

    await waitFor(() => {
      expect(mockLogin).toHaveBeenCalledTimes(1)
    })
  })
})
