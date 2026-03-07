import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../test/utils';
import { LoginPage } from '../LoginPage';
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

describe('LoginPage', () => {
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
    render(<LoginPage />);

    expect(screen.getByText('SSDID Drive')).toBeInTheDocument();
  });

  it('should render the wallet sign-in prompt', () => {
    render(<LoginPage />);

    expect(screen.getByText('Sign in with your SSDID Wallet')).toBeInTheDocument();
  });

  it('should render the QrChallenge component with authenticate action', () => {
    render(<LoginPage />);

    const qrChallenge = screen.getByTestId('qr-challenge');
    expect(qrChallenge).toBeInTheDocument();
    expect(qrChallenge).toHaveAttribute('data-action', 'authenticate');
  });

  it('should not render email or password inputs', () => {
    render(<LoginPage />);

    expect(screen.queryByPlaceholderText('you@example.com')).not.toBeInTheDocument();
    expect(screen.queryByPlaceholderText('Enter your password')).not.toBeInTheDocument();
  });

  it('should show error message when auth fails', () => {
    useAuthStore.setState({ error: 'Session expired' });

    render(<LoginPage />);

    expect(screen.getByText('Session expired')).toBeInTheDocument();
  });

  it('should clear error when dismiss is clicked', async () => {
    useAuthStore.setState({ error: 'Session expired' });

    const { user } = render(<LoginPage />);

    const dismissButton = screen.getByText('Dismiss');
    await user.click(dismissButton);

    expect(useAuthStore.getState().error).toBeNull();
  });

  it('should call loginWithSession when QrChallenge fires onAuthenticated', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<LoginPage />);

    await user.click(screen.getByTestId('mock-authenticate'));

    expect(loginWithSessionSpy).toHaveBeenCalledWith('mock-session-token');
  });

  it('should navigate to /files on successful authentication', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<LoginPage />);

    await user.click(screen.getByTestId('mock-authenticate'));

    expect(mockNavigate).toHaveBeenCalledWith('/files');
  });

  it('should not navigate when loginWithSession throws', async () => {
    const loginWithSessionSpy = vi.fn().mockRejectedValue(new Error('Invalid session'));
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<LoginPage />);

    await user.click(screen.getByTestId('mock-authenticate'));

    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('should show link to register page', () => {
    render(<LoginPage />);

    const registerLink = screen.getByRole('link', { name: 'Register' });
    expect(registerLink).toBeInTheDocument();
    expect(registerLink).toHaveAttribute('href', '/register');
  });

  it('should show wallet download link', () => {
    render(<LoginPage />);

    const downloadLink = screen.getByRole('link', { name: /download it/i });
    expect(downloadLink).toBeInTheDocument();
    expect(downloadLink).toHaveAttribute('href', 'https://ssdid.io/wallet');
    expect(downloadLink).toHaveAttribute('target', '_blank');
  });

  it('should show post-quantum cryptography message', () => {
    render(<LoginPage />);

    expect(screen.getByText('Protected with post-quantum cryptography')).toBeInTheDocument();
  });
});
