import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
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

  it('should render email and password inputs', () => {
    render(<LoginPage />);

    expect(screen.getByPlaceholderText('you@example.com')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Enter your password')).toBeInTheDocument();
  });

  it('should render sign in button', () => {
    render(<LoginPage />);

    expect(screen.getByRole('button', { name: 'Sign in' })).toBeInTheDocument();
  });

  it('should show/hide password on toggle', async () => {
    const { user } = render(<LoginPage />);

    const passwordInput = screen.getByPlaceholderText('Enter your password');
    expect(passwordInput).toHaveAttribute('type', 'password');

    // Find the toggle button (it contains the Eye icon)
    const toggleButton = passwordInput.parentElement?.querySelector('button');
    expect(toggleButton).toBeInTheDocument();

    await user.click(toggleButton!);
    expect(passwordInput).toHaveAttribute('type', 'text');

    await user.click(toggleButton!);
    expect(passwordInput).toHaveAttribute('type', 'password');
  });

  it('should disable submit button while loading', () => {
    useAuthStore.setState({ isLoading: true });

    render(<LoginPage />);

    const submitButton = screen.getByRole('button', { name: /signing in/i });
    expect(submitButton).toBeDisabled();
  });

  it('should show loading spinner while signing in', () => {
    useAuthStore.setState({ isLoading: true });

    render(<LoginPage />);

    expect(screen.getByText('Signing in...')).toBeInTheDocument();
    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('should show error message when login fails', () => {
    useAuthStore.setState({ error: 'Invalid credentials' });

    render(<LoginPage />);

    expect(screen.getByText('Invalid credentials')).toBeInTheDocument();
  });

  it('should clear error when dismiss is clicked', async () => {
    useAuthStore.setState({ error: 'Invalid credentials' });

    const { user } = render(<LoginPage />);

    const dismissButton = screen.getByText('Dismiss');
    await user.click(dismissButton);

    expect(useAuthStore.getState().error).toBeNull();
  });

  it('should call login with email and password on submit', async () => {
    const loginSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ login: loginSpy });

    const { user } = render(<LoginPage />);

    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.type(screen.getByPlaceholderText('Enter your password'), 'password123');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    await waitFor(() => {
      expect(loginSpy).toHaveBeenCalledWith('test@example.com', 'password123');
    });
  });

  it('should navigate to /files on successful login', async () => {
    const loginSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ login: loginSpy });

    const { user } = render(<LoginPage />);

    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.type(screen.getByPlaceholderText('Enter your password'), 'password123');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    await waitFor(() => {
      expect(mockNavigate).toHaveBeenCalledWith('/files');
    });
  });

  it('should show link to register page', () => {
    render(<LoginPage />);

    const registerLink = screen.getByRole('link', { name: 'Sign up' });
    expect(registerLink).toBeInTheDocument();
    expect(registerLink).toHaveAttribute('href', '/register');
  });

  it('should show post-quantum cryptography message', () => {
    render(<LoginPage />);

    expect(screen.getByText('Protected with post-quantum cryptography')).toBeInTheDocument();
  });
});
