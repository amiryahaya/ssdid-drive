import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import LoginPage from '../LoginPage'
import { useAuthStore } from '../../stores/authStore'

vi.mock('../../stores/authStore', () => ({
  useAuthStore: vi.fn(),
}))

const mockLogin = vi.fn()

beforeEach(() => {
  vi.clearAllMocks()
  ;(useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector: (s: unknown) => unknown) =>
      selector({ login: mockLogin })
  )
  vi.stubGlobal('fetch', vi.fn())
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('LoginPage', () => {
  it('renders the login form with title', () => {
    render(<LoginPage />)
    expect(screen.getByText('SSDID Drive')).toBeInTheDocument()
    expect(screen.getByText('Admin Portal')).toBeInTheDocument()
  })

  it('shows email input and continue button', () => {
    render(<LoginPage />)
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('admin@example.com')).toBeInTheDocument()
    expect(screen.getByText('Continue')).toBeInTheDocument()
  })

  it('disables Continue when email is empty', () => {
    render(<LoginPage />)
    expect(screen.getByText('Continue')).toBeDisabled()
  })

  it('does not show OIDC or wallet options', () => {
    render(<LoginPage />)
    expect(screen.queryByText('Google')).not.toBeInTheDocument()
    expect(screen.queryByText('Microsoft')).not.toBeInTheDocument()
    expect(screen.queryByText('SSDID Wallet')).not.toBeInTheDocument()
  })

  it('shows SuperAdmin access message', () => {
    render(<LoginPage />)
    expect(screen.getByText('SuperAdmin access only. Email + TOTP required.')).toBeInTheDocument()
  })

  it('submits email and transitions to TOTP step', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    })

    render(<LoginPage />)

    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => {
      expect(screen.getByLabelText('TOTP Code')).toBeInTheDocument()
    })
  })

  it('shows error on email submission failure', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: false,
      status: 404,
      json: async () => ({ detail: 'User not found' }),
    })

    render(<LoginPage />)

    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => {
      expect(screen.getByText('User not found')).toBeInTheDocument()
    })
  })

  it('shows "Checking..." while email is being submitted', async () => {
    const user = userEvent.setup()
    let resolveResponse: (v: unknown) => void
    ;(fetch as ReturnType<typeof vi.fn>).mockImplementationOnce(
      () => new Promise((resolve) => { resolveResponse = resolve })
    )

    render(<LoginPage />)

    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    expect(screen.getByText('Checking...')).toBeInTheDocument()

    resolveResponse!({ ok: true, json: async () => ({}) })
  })

  it('shows TOTP verification form after email success', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    })

    render(<LoginPage />)

    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => {
      expect(screen.getByText('Enter the 6-digit code from your authenticator app')).toBeInTheDocument()
      expect(screen.getByLabelText('TOTP Code')).toBeInTheDocument()
      expect(screen.getByText('Verify')).toBeInTheDocument()
      expect(screen.getByText('Back')).toBeInTheDocument()
    })
  })

  it('disables Verify button until 6 digits entered', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    })

    render(<LoginPage />)

    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => {
      expect(screen.getByText('Verify')).toBeDisabled()
    })

    await user.type(screen.getByLabelText('TOTP Code'), '123456')
    expect(screen.getByText('Verify')).not.toBeDisabled()
  })

  it('calls login with session_token after successful TOTP', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce({ ok: true, json: async () => ({}) })
      .mockResolvedValueOnce({ ok: true, json: async () => ({ session_token: 'tok-123' }) })

    mockLogin.mockResolvedValue(undefined)

    render(<LoginPage />)

    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => expect(screen.getByLabelText('TOTP Code')).toBeInTheDocument())

    await user.type(screen.getByLabelText('TOTP Code'), '123456')
    await user.click(screen.getByText('Verify'))

    await waitFor(() => {
      expect(mockLogin).toHaveBeenCalledWith('tok-123')
    })
  })

  it('goes back to email step when Back is clicked', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    })

    render(<LoginPage />)

    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => expect(screen.getByText('Back')).toBeInTheDocument())

    await user.click(screen.getByText('Back'))

    expect(screen.getByLabelText('Email')).toBeInTheDocument()
  })

  it('strips non-digit characters from TOTP code input', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    })

    render(<LoginPage />)
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => expect(screen.getByLabelText('TOTP Code')).toBeInTheDocument())

    await user.type(screen.getByLabelText('TOTP Code'), '12ab34')
    expect(screen.getByLabelText('TOTP Code')).toHaveValue('1234')
  })
})
