import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../test/utils';
import { RegisterPage } from '../RegisterPage';
import { useAuthStore } from '../../stores/authStore';

// Mock useNavigate
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// Mock QrChallenge component so tests don't depend on SSE / qrcode.react
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

  it('should render the SSDID Drive heading', () => {
    render(<RegisterPage />);

    expect(screen.getByText('SSDID Drive')).toBeInTheDocument();
  });

  it('should render the registration prompt', () => {
    render(<RegisterPage />);

    expect(screen.getByText('Scan to register with SSDID Drive')).toBeInTheDocument();
  });

  it('should render the QrChallenge component with register action', () => {
    render(<RegisterPage />);

    const qrChallenge = screen.getByTestId('qr-challenge');
    expect(qrChallenge).toBeInTheDocument();
    expect(qrChallenge).toHaveAttribute('data-action', 'register');
  });

  it('should not render old form fields', () => {
    render(<RegisterPage />);

    expect(screen.queryByPlaceholderText('John Doe')).not.toBeInTheDocument();
    expect(screen.queryByPlaceholderText('you@example.com')).not.toBeInTheDocument();
    expect(screen.queryByPlaceholderText('Minimum 8 characters')).not.toBeInTheDocument();
    expect(screen.queryByPlaceholderText('Re-enter your password')).not.toBeInTheDocument();
    expect(screen.queryByPlaceholderText('Enter your invitation token')).not.toBeInTheDocument();
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

    await user.click(screen.getByTestId('mock-authenticate'));

    expect(loginWithSessionSpy).toHaveBeenCalledWith('mock-session-token');
  });

  it('should navigate to /onboarding on successful registration', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<RegisterPage />);

    await user.click(screen.getByTestId('mock-authenticate'));

    expect(mockNavigate).toHaveBeenCalledWith('/onboarding');
  });

  it('should not navigate when loginWithSession throws', async () => {
    const loginWithSessionSpy = vi.fn().mockRejectedValue(new Error('Failed'));
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<RegisterPage />);

    await user.click(screen.getByTestId('mock-authenticate'));

    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('should show link to login page', () => {
    render(<RegisterPage />);

    const loginLink = screen.getByRole('link', { name: 'Sign in' });
    expect(loginLink).toBeInTheDocument();
    expect(loginLink).toHaveAttribute('href', '/login');
  });

  it('should show post-quantum cryptography message', () => {
    render(<RegisterPage />);

    expect(screen.getByText('Protected with post-quantum cryptography')).toBeInTheDocument();
  });
});
