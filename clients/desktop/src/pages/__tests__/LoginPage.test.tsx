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

// Mock OidcButtons
vi.mock('@/components/auth/OidcButtons', () => ({
  OidcButtons: ({ onProviderClick, disabled }: { onProviderClick: (p: string) => void; disabled: boolean }) => (
    <div data-testid="oidc-buttons">
      <button data-testid="oidc-google" onClick={() => onProviderClick('google')} disabled={disabled}>
        Google
      </button>
      <button data-testid="oidc-microsoft" onClick={() => onProviderClick('microsoft')} disabled={disabled}>
        Microsoft
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

  it('should render OIDC buttons', () => {
    render(<LoginPage />);

    expect(screen.getByTestId('oidc-buttons')).toBeInTheDocument();
  });

  it('should show collapsible SSDID Wallet section', () => {
    render(<LoginPage />);

    expect(screen.getByText('Sign in with SSDID Wallet')).toBeInTheDocument();
  });

  it('should show QR challenge when wallet section is expanded', async () => {
    const { user } = render(<LoginPage />);

    await user.click(screen.getByText('Sign in with SSDID Wallet'));

    expect(screen.getByTestId('qr-challenge')).toBeInTheDocument();
  });

  it('should call loginWithSession when QrChallenge fires onAuthenticated', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<LoginPage />);

    // Expand wallet section first
    await user.click(screen.getByText('Sign in with SSDID Wallet'));
    await user.click(screen.getByTestId('mock-authenticate'));

    expect(loginWithSessionSpy).toHaveBeenCalledWith('mock-session-token');
  });

  it('should navigate to /files on successful wallet authentication', async () => {
    const loginWithSessionSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ loginWithSession: loginWithSessionSpy });

    const { user } = render(<LoginPage />);

    await user.click(screen.getByText('Sign in with SSDID Wallet'));
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

  it('should show invite code link', () => {
    render(<LoginPage />);

    const inviteLink = screen.getByRole('link', { name: /invite code/i });
    expect(inviteLink).toBeInTheDocument();
    expect(inviteLink).toHaveAttribute('href', '/join');
  });
});
