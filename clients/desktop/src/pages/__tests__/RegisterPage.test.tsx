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

  it('should render the Enter Invitation Code heading initially', () => {
    render(<RegisterPage />);

    expect(screen.getByText('Enter Invitation Code')).toBeInTheDocument();
  });

  it('should render invitation code input', () => {
    render(<RegisterPage />);

    expect(screen.getByPlaceholderText('Paste your invitation code')).toBeInTheDocument();
  });

  it('should render Continue button', () => {
    render(<RegisterPage />);

    expect(screen.getByText('Continue')).toBeInTheDocument();
  });

  it('should show choose step with OIDC buttons after entering invite code', async () => {
    const { user } = render(<RegisterPage />);

    // Enter an invitation code
    const input = screen.getByPlaceholderText('Paste your invitation code');
    await user.type(input, 'INVITE-CODE-123');
    await user.click(screen.getByText('Continue'));

    // Now on 'choose' step — should see Google and Microsoft OIDC buttons
    expect(screen.getByText('Create Account')).toBeInTheDocument();
    expect(screen.getByText('Google')).toBeInTheDocument();
    expect(screen.getByText('Microsoft')).toBeInTheDocument();
  });

  it('should show collapsible SSDID Wallet section on choose step', async () => {
    const { user } = render(<RegisterPage />);

    const input = screen.getByPlaceholderText('Paste your invitation code');
    await user.type(input, 'INVITE-CODE-123');
    await user.click(screen.getByText('Continue'));

    expect(screen.getByText('Register with SSDID Wallet')).toBeInTheDocument();
  });

  it('should show QR challenge when wallet section is expanded', async () => {
    const { user } = render(<RegisterPage />);

    const input = screen.getByPlaceholderText('Paste your invitation code');
    await user.type(input, 'INVITE-CODE-123');
    await user.click(screen.getByText('Continue'));

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

    // Navigate to choose step
    const input = screen.getByPlaceholderText('Paste your invitation code');
    await user.type(input, 'INVITE-CODE-123');
    await user.click(screen.getByText('Continue'));

    // Expand wallet section and authenticate
    await user.click(screen.getByText('Register with SSDID Wallet'));
    await user.click(screen.getByTestId('mock-authenticate'));

    expect(loginWithSessionSpy).toHaveBeenCalledWith('mock-session-token');
  });

  it('should navigate to /onboarding on successful wallet registration', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<RegisterPage />);

    // Navigate to choose step
    const input = screen.getByPlaceholderText('Paste your invitation code');
    await user.type(input, 'INVITE-CODE-123');
    await user.click(screen.getByText('Continue'));

    // Expand wallet section and authenticate
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
