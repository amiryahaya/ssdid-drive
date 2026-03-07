import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
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

  it('should render all form fields', () => {
    render(<RegisterPage />);

    expect(screen.getByPlaceholderText('John Doe')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('you@example.com')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Minimum 8 characters')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Re-enter your password')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Enter your invitation token')).toBeInTheDocument();
  });

  it('should render create account button', () => {
    render(<RegisterPage />);

    expect(screen.getByRole('button', { name: /create account/i })).toBeInTheDocument();
  });

  it('should show error for password mismatch', async () => {
    const { user } = render(<RegisterPage />);

    await user.type(screen.getByPlaceholderText('John Doe'), 'Test User');
    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.type(screen.getByPlaceholderText('Minimum 8 characters'), 'password123');
    await user.type(screen.getByPlaceholderText('Re-enter your password'), 'different');
    await user.type(screen.getByPlaceholderText('Enter your invitation token'), 'token');

    await user.click(screen.getByRole('button', { name: /create account/i }));

    expect(screen.getByText('Passwords do not match')).toBeInTheDocument();
  });

  it('should show error for password too short', async () => {
    const { user } = render(<RegisterPage />);

    await user.type(screen.getByPlaceholderText('John Doe'), 'Test User');
    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.type(screen.getByPlaceholderText('Minimum 8 characters'), 'short');
    await user.type(screen.getByPlaceholderText('Re-enter your password'), 'short');
    await user.type(screen.getByPlaceholderText('Enter your invitation token'), 'token');

    await user.click(screen.getByRole('button', { name: /create account/i }));

    expect(screen.getByText('Password must be at least 8 characters')).toBeInTheDocument();
  });

  it('should show/hide password on toggle', async () => {
    const { user } = render(<RegisterPage />);

    const passwordInput = screen.getByPlaceholderText('Minimum 8 characters');
    expect(passwordInput).toHaveAttribute('type', 'password');

    // Find the toggle button
    const toggleButton = passwordInput.parentElement?.querySelector('button');
    expect(toggleButton).toBeInTheDocument();

    await user.click(toggleButton!);
    expect(passwordInput).toHaveAttribute('type', 'text');
  });

  it('should disable submit button while loading', () => {
    useAuthStore.setState({ isLoading: true });

    render(<RegisterPage />);

    const submitButton = screen.getByRole('button', { name: /creating account/i });
    expect(submitButton).toBeDisabled();
  });

  it('should show API error message', () => {
    useAuthStore.setState({ error: 'Invalid invitation token' });

    render(<RegisterPage />);

    expect(screen.getByText('Invalid invitation token')).toBeInTheDocument();
  });

  it('should call register with form data on submit', async () => {
    const registerSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ register: registerSpy });

    const { user } = render(<RegisterPage />);

    await user.type(screen.getByPlaceholderText('John Doe'), 'Test User');
    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.type(screen.getByPlaceholderText('Minimum 8 characters'), 'password123');
    await user.type(screen.getByPlaceholderText('Re-enter your password'), 'password123');
    await user.type(screen.getByPlaceholderText('Enter your invitation token'), 'invite-token');

    await user.click(screen.getByRole('button', { name: /create account/i }));

    await waitFor(() => {
      expect(registerSpy).toHaveBeenCalledWith(
        'test@example.com',
        'password123',
        'Test User',
        'invite-token'
      );
    });
  });

  it('should navigate to /onboarding on successful registration', async () => {
    const registerSpy = vi.fn().mockResolvedValue(undefined);
    useAuthStore.setState({ register: registerSpy });

    const { user } = render(<RegisterPage />);

    await user.type(screen.getByPlaceholderText('John Doe'), 'Test User');
    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.type(screen.getByPlaceholderText('Minimum 8 characters'), 'password123');
    await user.type(screen.getByPlaceholderText('Re-enter your password'), 'password123');
    await user.type(screen.getByPlaceholderText('Enter your invitation token'), 'invite-token');

    await user.click(screen.getByRole('button', { name: /create account/i }));

    await waitFor(() => {
      expect(mockNavigate).toHaveBeenCalledWith('/onboarding');
    });
  });

  it('should show link to login page', () => {
    render(<RegisterPage />);

    const loginLink = screen.getByRole('link', { name: 'Sign in' });
    expect(loginLink).toBeInTheDocument();
    expect(loginLink).toHaveAttribute('href', '/login');
  });

  it('should clear validation error on dismiss', async () => {
    const { user } = render(<RegisterPage />);

    // Trigger validation error
    await user.type(screen.getByPlaceholderText('John Doe'), 'Test');
    await user.type(screen.getByPlaceholderText('you@example.com'), 'test@example.com');
    await user.type(screen.getByPlaceholderText('Minimum 8 characters'), 'pass');
    await user.type(screen.getByPlaceholderText('Re-enter your password'), 'pass');
    await user.type(screen.getByPlaceholderText('Enter your invitation token'), 'token');
    await user.click(screen.getByRole('button', { name: /create account/i }));

    expect(screen.getByText('Password must be at least 8 characters')).toBeInTheDocument();

    // Dismiss error
    await user.click(screen.getByText('Dismiss'));

    expect(screen.queryByText('Password must be at least 8 characters')).not.toBeInTheDocument();
  });
});
