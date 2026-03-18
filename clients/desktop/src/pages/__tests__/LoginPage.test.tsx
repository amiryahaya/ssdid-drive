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

  it('should render Sign in with Email button', () => {
    render(<LoginPage />);

    expect(screen.getByText('Sign in with Email')).toBeInTheDocument();
  });

  it('should navigate to /login/email when email button clicked', async () => {
    const { user } = render(<LoginPage />);

    await user.click(screen.getByText('Sign in with Email'));

    expect(mockNavigate).toHaveBeenCalledWith('/login/email');
  });

  it('should render OIDC buttons (Google and Microsoft)', () => {
    render(<LoginPage />);

    expect(screen.getByText('Google')).toBeInTheDocument();
    expect(screen.getByText('Microsoft')).toBeInTheDocument();
  });

  it('should show SSDID Wallet tab', () => {
    render(<LoginPage />);

    expect(screen.getByText('SSDID Wallet')).toBeInTheDocument();
  });

  it('should show QR challenge when wallet tab is selected', async () => {
    const { user } = render(<LoginPage />);

    await user.click(screen.getByText('SSDID Wallet'));

    expect(screen.getByTestId('qr-challenge')).toBeInTheDocument();
  });

  it('should call loginWithSession when QrChallenge fires onAuthenticated', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<LoginPage />);

    // Switch to wallet tab first
    await user.click(screen.getByText('SSDID Wallet'));
    await user.click(screen.getByTestId('mock-authenticate'));

    expect(loginWithSessionSpy).toHaveBeenCalledWith('mock-session-token');
  });

  it('should navigate to /files on successful wallet authentication', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<LoginPage />);

    await user.click(screen.getByText('SSDID Wallet'));
    await user.click(screen.getByTestId('mock-authenticate'));

    expect(mockNavigate).toHaveBeenCalledWith('/files');
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

  it('should show link to register page', () => {
    render(<LoginPage />);

    const registerLink = screen.getByRole('link', { name: 'Register' });
    expect(registerLink).toBeInTheDocument();
    expect(registerLink).toHaveAttribute('href', '/register');
  });

  it('should show link to recover page', () => {
    render(<LoginPage />);

    const recoverLink = screen.getByRole('link', { name: /recover/i });
    expect(recoverLink).toBeInTheDocument();
    expect(recoverLink).toHaveAttribute('href', '/recover');
  });
});
