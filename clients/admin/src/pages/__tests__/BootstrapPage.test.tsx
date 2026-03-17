import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import BootstrapPage from '../BootstrapPage'
import { useAuthStore } from '../../stores/authStore'

vi.mock('../../stores/authStore', () => ({
  useAuthStore: vi.fn(),
}))

vi.mock('qrcode.react', () => ({
  QRCodeSVG: ({ value }: { value: string }) => <div data-testid="qr-code">{value}</div>,
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

describe('BootstrapPage', () => {
  it('renders setup form with title', () => {
    render(<BootstrapPage />)
    expect(screen.getByText('SSDID Drive Setup')).toBeInTheDocument()
    expect(screen.getByText('Create your SuperAdmin account')).toBeInTheDocument()
    expect(screen.getByLabelText('Display Name')).toBeInTheDocument()
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
  })

  it('disables Continue when fields are empty', () => {
    render(<BootstrapPage />)
    expect(screen.getByText('Continue')).toBeDisabled()
  })

  it('enables Continue when both fields are filled', async () => {
    const user = userEvent.setup()
    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')

    expect(screen.getByText('Continue')).not.toBeDisabled()
  })

  it('submits setup form and transitions to TOTP step', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        secret: 'JBSWY3DPEHPK3PXP',
        otpauth_uri: 'otpauth://totp/SsdidDrive:admin@test.com?secret=JBSWY3DPEHPK3PXP',
        email: 'admin@test.com',
      }),
    })

    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => {
      expect(screen.getByText('Scan this QR code with your authenticator app')).toBeInTheDocument()
      expect(screen.getByTestId('qr-code')).toBeInTheDocument()
      expect(screen.getByText('JBSWY3DPEHPK3PXP')).toBeInTheDocument()
      expect(screen.getByLabelText('Enter 6-digit code')).toBeInTheDocument()
    })
  })

  it('shows error when setup request fails', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: false,
      status: 409,
      json: async () => ({ detail: 'SuperAdmin already exists' }),
    })

    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => {
      expect(screen.getByText('SuperAdmin already exists')).toBeInTheDocument()
    })
  })

  it('shows "Setting up..." while submitting', async () => {
    const user = userEvent.setup()
    let resolveResponse: (v: unknown) => void
    ;(fetch as ReturnType<typeof vi.fn>).mockImplementationOnce(
      () => new Promise((resolve) => { resolveResponse = resolve })
    )

    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    expect(screen.getByText('Setting up...')).toBeInTheDocument()

    resolveResponse!({ ok: true, json: async () => ({ secret: 'S', otpauth_uri: 'x', email: 'a@b.com' }) })
  })

  it('disables Verify & Create Account until 6 digits entered', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      ok: true,
      json: async () => ({ secret: 'S', otpauth_uri: 'otpauth://...', email: 'admin@test.com' }),
    })

    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => {
      expect(screen.getByText('Verify & Create Account')).toBeDisabled()
    })

    await user.type(screen.getByLabelText('Enter 6-digit code'), '123456')
    expect(screen.getByText('Verify & Create Account')).not.toBeDisabled()
  })

  it('confirms TOTP and shows backup codes', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ secret: 'S', otpauth_uri: 'otpauth://...', email: 'admin@test.com' }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          token: 'tok-123',
          backup_codes: ['CODE1', 'CODE2', 'CODE3'],
          account_id: 'acc-1',
          display_name: 'Admin',
          email: 'admin@test.com',
        }),
      })

    mockLogin.mockResolvedValue(undefined)

    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => expect(screen.getByLabelText('Enter 6-digit code')).toBeInTheDocument())

    await user.type(screen.getByLabelText('Enter 6-digit code'), '123456')
    await user.click(screen.getByText('Verify & Create Account'))

    await waitFor(() => {
      expect(screen.getByText('Save your backup codes')).toBeInTheDocument()
      expect(screen.getByText('CODE1')).toBeInTheDocument()
      expect(screen.getByText('CODE2')).toBeInTheDocument()
      expect(screen.getByText('CODE3')).toBeInTheDocument()
      expect(screen.getByText('Copy Codes')).toBeInTheDocument()
      expect(screen.getByText('Continue to Admin Portal')).toBeInTheDocument()
    })

    expect(mockLogin).toHaveBeenCalledWith('tok-123')
  })

  it('shows error when TOTP confirmation fails', async () => {
    const user = userEvent.setup()
    ;(fetch as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ secret: 'S', otpauth_uri: 'otpauth://...', email: 'admin@test.com' }),
      })
      .mockResolvedValueOnce({
        ok: false,
        status: 400,
        json: async () => ({ detail: 'Invalid TOTP code' }),
      })

    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => expect(screen.getByLabelText('Enter 6-digit code')).toBeInTheDocument())

    await user.type(screen.getByLabelText('Enter 6-digit code'), '000000')
    await user.click(screen.getByText('Verify & Create Account'))

    await waitFor(() => {
      expect(screen.getByText('Invalid TOTP code')).toBeInTheDocument()
    })
  })

  it('copies backup codes to clipboard', async () => {
    const user = userEvent.setup()
    const writeText = vi.fn().mockResolvedValue(undefined)
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText },
      writable: true,
      configurable: true,
    })

    ;(fetch as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({ secret: 'S', otpauth_uri: 'otpauth://...', email: 'admin@test.com' }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          token: 'tok-123',
          backup_codes: ['C1', 'C2'],
          account_id: 'acc-1',
          display_name: 'Admin',
          email: 'admin@test.com',
        }),
      })

    mockLogin.mockResolvedValue(undefined)

    render(<BootstrapPage />)

    await user.type(screen.getByLabelText('Display Name'), 'Admin')
    await user.type(screen.getByLabelText('Email'), 'admin@test.com')
    await user.click(screen.getByText('Continue'))

    await waitFor(() => expect(screen.getByLabelText('Enter 6-digit code')).toBeInTheDocument())
    await user.type(screen.getByLabelText('Enter 6-digit code'), '123456')
    await user.click(screen.getByText('Verify & Create Account'))

    await waitFor(() => expect(screen.getByText('Copy Codes')).toBeInTheDocument())
    await user.click(screen.getByText('Copy Codes'))

    expect(writeText).toHaveBeenCalledWith('C1\nC2')
  })
})
