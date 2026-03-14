import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../test/utils';
import { RegisterPage } from '../RegisterPage';
import { useAuthStore } from '../../stores/authStore';

// Mock useNavigate and useSearchParams
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
    useSearchParams: () => [new URLSearchParams(), vi.fn()],
  };
});

// Mock QrChallenge component
vi.mock('@/components/auth/QrChallenge', () => ({
  QrChallenge: ({ action, onAuthenticated }: { action: string; onAuthenticated: (token: string) => void }) => (
    <div data-testid="qr-challenge" data-action={action}>
      <button
        data-testid="mock-authenticate"
        onClick={() => onAuthenticated('mock-session-token')}
      >
        Simulate Wallet Scan
      </button>
    </div>
  ),
}));

// Mock OidcButtons
vi.mock('@/components/auth/OidcButtons', () => ({
  OidcButtons: ({ onProviderClick, disabled }: { onProviderClick: (p: string) => void; disabled: boolean }) => (
    <div data-testid="oidc-buttons">
      <button data-testid="oidc-google" onClick={() => onProviderClick('google')} disabled={disabled}>
        Google
      </button>
    </div>
  ),
}));

// Mock OtpInput
vi.mock('@/components/auth/OtpInput', () => ({
  OtpInput: ({ onComplete }: { onComplete: (code: string) => void }) => (
    <div data-testid="otp-input">
      <button data-testid="mock-otp-complete" onClick={() => onComplete('123456')}>
        Submit OTP
      </button>
    </div>
  ),
}));

describe('RegisterPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useAuthStore.setState({
      user: null,
      isAuthenticated: false,
      isLoading: false,
      isLocked: true,
      error: null,
    });
  });

  it('should render the Create Account heading', () => {
    render(<RegisterPage />);

    expect(screen.getByText('Create Account')).toBeInTheDocument();
  });

  it('should render email input', () => {
    render(<RegisterPage />);

    expect(screen.getByPlaceholderText('you@example.com')).toBeInTheDocument();
  });

  it('should render Send verification code button', () => {
    render(<RegisterPage />);

    expect(screen.getByText('Send verification code')).toBeInTheDocument();
  });

  it('should render OIDC buttons', () => {
    render(<RegisterPage />);

    expect(screen.getByTestId('oidc-buttons')).toBeInTheDocument();
  });

  it('should show collapsible SSDID Wallet section', () => {
    render(<RegisterPage />);

    expect(screen.getByText('Register with SSDID Wallet')).toBeInTheDocument();
  });

  it('should show QR challenge when wallet section is expanded', async () => {
    const { user } = render(<RegisterPage />);

    await user.click(screen.getByText('Register with SSDID Wallet'));

    expect(screen.getByTestId('qr-challenge')).toBeInTheDocument();
    expect(screen.getByTestId('qr-challenge')).toHaveAttribute('data-action', 'register');
  });

  it('should show error message when registration fails', () => {
    useAuthStore.setState({ error: 'Registration failed' });

    render(<RegisterPage />);

    expect(screen.getByText('Registration failed')).toBeInTheDocument();
  });

  it('should clear error when dismiss is clicked', async () => {
    useAuthStore.setState({ error: 'Registration failed' });

    const { user } = render(<RegisterPage />);

    const dismissButton = screen.getByText('Dismiss');
    await user.click(dismissButton);

    expect(useAuthStore.getState().error).toBeNull();
  });

  it('should call loginWithSession when QrChallenge fires onAuthenticated', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<RegisterPage />);

    await user.click(screen.getByText('Register with SSDID Wallet'));
    await user.click(screen.getByTestId('mock-authenticate'));

    expect(loginWithSessionSpy).toHaveBeenCalledWith('mock-session-token');
  });

  it('should navigate to /onboarding on successful wallet registration', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<RegisterPage />);

    await user.click(screen.getByText('Register with SSDID Wallet'));
    await user.click(screen.getByTestId('mock-authenticate'));

    expect(mockNavigate).toHaveBeenCalledWith('/onboarding');
  });

  it('should show link to login page', () => {
    render(<RegisterPage />);

    const loginLink = screen.getByRole('link', { name: 'Sign in' });
    expect(loginLink).toBeInTheDocument();
    expect(loginLink).toHaveAttribute('href', '/login');
  });
});
