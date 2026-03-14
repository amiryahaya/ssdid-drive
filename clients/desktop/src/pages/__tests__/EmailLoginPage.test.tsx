import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { EmailLoginPage } from '../EmailLoginPage';
import { useAuthStore } from '@/stores/authStore';

// Mock useNavigate
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// Mock authStore
vi.mock('@/stores/authStore', () => ({
  useAuthStore: vi.fn(),
}));

// Mock OtpInput
vi.mock('@/components/auth/OtpInput', () => ({
  OtpInput: ({ onComplete, disabled, error }: any) => (
    <div data-testid="otp-input">
      <button data-testid="complete-otp" onClick={() => onComplete('123456')} disabled={disabled}>Complete</button>
      {error && <span>{error}</span>}
    </div>
  ),
}));

describe('EmailLoginPage', () => {
  const mockEmailLogin = vi.fn();
  const mockTotpVerify = vi.fn();
  const mockClearError = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    (useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector: (s: any) => any) => {
      const state = {
        emailLogin: mockEmailLogin,
        totpVerify: mockTotpVerify,
        isLoading: false,
        error: null,
        clearError: mockClearError,
      };
      return selector(state);
    });
  });

  it('should render email input and continue button', () => {
    render(<EmailLoginPage />);

    expect(screen.getByPlaceholderText('you@example.com')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Continue' })).toBeInTheDocument();
  });

  it('should have continue button disabled when email is empty', () => {
    render(<EmailLoginPage />);

    expect(screen.getByRole('button', { name: 'Continue' })).toBeDisabled();
  });

  it('should call emailLogin on form submit with email', async () => {
    mockEmailLogin.mockResolvedValue({ requiresTotp: false });

    const { user } = render(<EmailLoginPage />);

    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.click(screen.getByRole('button', { name: 'Continue' }));

    expect(mockEmailLogin).toHaveBeenCalledWith('test@example.com');
  });

  it('should navigate to /files when requiresTotp is false', async () => {
    mockEmailLogin.mockResolvedValue({ requiresTotp: false });

    const { user } = render(<EmailLoginPage />);

    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.click(screen.getByRole('button', { name: 'Continue' }));

    await waitFor(() => {
      expect(mockNavigate).toHaveBeenCalledWith('/files');
    });
  });

  it('should show TOTP step when requiresTotp is true', async () => {
    mockEmailLogin.mockResolvedValue({ requiresTotp: true });

    const { user } = render(<EmailLoginPage />);

    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.click(screen.getByRole('button', { name: 'Continue' }));

    await waitFor(() => {
      expect(screen.getByTestId('otp-input')).toBeInTheDocument();
    });
    expect(screen.getByText('Enter Authenticator Code')).toBeInTheDocument();
  });

  it('should show error message from store', () => {
    (useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector: (s: any) => any) => {
      const state = {
        emailLogin: mockEmailLogin,
        totpVerify: mockTotpVerify,
        isLoading: false,
        error: 'Invalid credentials',
        clearError: mockClearError,
      };
      return selector(state);
    });

    render(<EmailLoginPage />);

    expect(screen.getByText('Invalid credentials')).toBeInTheDocument();
  });

  it('should have link back to /login', () => {
    render(<EmailLoginPage />);

    const link = screen.getByRole('link', { name: /back to all sign-in options/i });
    expect(link).toBeInTheDocument();
    expect(link).toHaveAttribute('href', '/login');
  });

  it('should call clearError when dismiss button is clicked', async () => {
    (useAuthStore as unknown as ReturnType<typeof vi.fn>).mockImplementation((selector: (s: any) => any) => {
      const state = {
        emailLogin: mockEmailLogin,
        totpVerify: mockTotpVerify,
        isLoading: false,
        error: 'Something went wrong',
        clearError: mockClearError,
      };
      return selector(state);
    });

    const { user } = render(<EmailLoginPage />);

    await user.click(screen.getByText('Dismiss'));

    expect(mockClearError).toHaveBeenCalled();
  });

  it('should call totpVerify and navigate to /files on TOTP complete', async () => {
    mockEmailLogin.mockResolvedValue({ requiresTotp: true });
    mockTotpVerify.mockResolvedValue(undefined);

    const { user } = render(<EmailLoginPage />);

    // Enter email and submit
    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.click(screen.getByRole('button', { name: 'Continue' }));

    // Wait for TOTP step
    await waitFor(() => {
      expect(screen.getByTestId('otp-input')).toBeInTheDocument();
    });

    // Complete OTP
    await user.click(screen.getByTestId('complete-otp'));

    await waitFor(() => {
      expect(mockTotpVerify).toHaveBeenCalledWith('test@example.com', '123456');
      expect(mockNavigate).toHaveBeenCalledWith('/files');
    });
  });
});
