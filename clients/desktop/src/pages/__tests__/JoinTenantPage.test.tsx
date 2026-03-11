import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { JoinTenantPage } from '../JoinTenantPage';
import { useAuthStore } from '../../stores/authStore';
import { useTenantStore } from '../../stores/tenantStore';

// Mock useNavigate
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// Mock @tauri-apps/api/core
vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn().mockRejectedValue(new Error('not available')),
}));

// Mock fetch for the public API call
const mockFetch = vi.fn();
global.fetch = mockFetch;

const mockInvitationPreview = {
  id: 'inv-123',
  tenant_name: 'Acme Corp',
  role: 'member' as const,
  short_code: 'ACME-7K9X',
  expires_at: '2026-04-01T00:00:00Z',
};

describe('JoinTenantPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockFetch.mockReset();
    useAuthStore.setState({
      user: null,
      isAuthenticated: false,
      isLoading: false,
      isLocked: true,
      error: null,
    });
    useTenantStore.setState({
      availableTenants: [],
      pendingInvitations: [],
      isLoading: false,
      error: null,
    });
  });

  it('should render the page heading', () => {
    render(<JoinTenantPage />);

    expect(screen.getByText('Join a Tenant')).toBeInTheDocument();
  });

  it('should render the invite code input', () => {
    render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    expect(input).toBeInTheDocument();
  });

  it('should render the Look Up button', () => {
    render(<JoinTenantPage />);

    expect(screen.getByRole('button', { name: 'Look Up' })).toBeInTheDocument();
  });

  it('should disable Look Up button when input is empty', () => {
    render(<JoinTenantPage />);

    const button = screen.getByRole('button', { name: 'Look Up' });
    expect(button).toBeDisabled();
  });

  it('should convert input to uppercase', async () => {
    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'acme-7k9x');

    expect(input).toHaveValue('ACME-7K9X');
  });

  it('should show preview card after successful lookup', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve(mockInvitationPreview),
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'ACME-7K9X');
    await user.click(screen.getByRole('button', { name: 'Look Up' }));

    await waitFor(() => {
      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });

    expect(screen.getByText('Member')).toBeInTheDocument();
  });

  it('should show error for invalid code (404)', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'INVALID');
    await user.click(screen.getByRole('button', { name: 'Look Up' }));

    await waitFor(() => {
      expect(screen.getByText('Invalid invite code. Please check and try again.')).toBeInTheDocument();
    });
  });

  it('should show error for expired code (410)', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 410,
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'EXPIRED');
    await user.click(screen.getByRole('button', { name: 'Look Up' }));

    await waitFor(() => {
      expect(screen.getByText('This invite code has expired.')).toBeInTheDocument();
    });
  });

  it('should show Continue button and redirect to register when not authenticated', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve(mockInvitationPreview),
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'ACME-7K9X');
    await user.click(screen.getByRole('button', { name: 'Look Up' }));

    await waitFor(() => {
      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });

    const continueBtn = screen.getByRole('button', { name: 'Continue' });
    await user.click(continueBtn);

    expect(mockNavigate).toHaveBeenCalledWith('/register?invite=ACME-7K9X');
  });

  it('should show Join button when authenticated and join on click', async () => {
    useAuthStore.setState({ isAuthenticated: true, isLocked: false });

    const mockAcceptInvitation = vi.fn().mockResolvedValue({
      id: 'tenant-1',
      name: 'Acme Corp',
      slug: 'acme',
      role: 'member',
      joined_at: new Date().toISOString(),
    });
    const mockLoadTenants = vi.fn().mockResolvedValue(undefined);
    useTenantStore.setState({
      acceptInvitation: mockAcceptInvitation,
      loadTenants: mockLoadTenants,
    });

    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve(mockInvitationPreview),
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'ACME-7K9X');
    await user.click(screen.getByRole('button', { name: 'Look Up' }));

    await waitFor(() => {
      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });

    const joinBtn = screen.getByRole('button', { name: 'Join' });
    await user.click(joinBtn);

    await waitFor(() => {
      expect(mockAcceptInvitation).toHaveBeenCalledWith('inv-123');
    });

    expect(mockLoadTenants).toHaveBeenCalled();
    expect(mockNavigate).toHaveBeenCalledWith('/files');
  });

  it('should show sign in and register links when not authenticated', () => {
    render(<JoinTenantPage />);

    expect(screen.getByRole('link', { name: 'Sign in' })).toHaveAttribute('href', '/login');
    expect(screen.getByRole('link', { name: 'Register' })).toHaveAttribute('href', '/register');
  });

  it('should show back to files link when authenticated', () => {
    useAuthStore.setState({ isAuthenticated: true, isLocked: false });

    render(<JoinTenantPage />);

    expect(screen.getByText('Back to Files')).toBeInTheDocument();
  });

  it('should show post-quantum cryptography footer', () => {
    render(<JoinTenantPage />);

    expect(screen.getByText('Protected with post-quantum cryptography')).toBeInTheDocument();
  });

  it('should trigger lookup on Enter key press', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve(mockInvitationPreview),
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'ACME-7K9X');
    await user.keyboard('{Enter}');

    await waitFor(() => {
      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });
  });

  it('should strip non-alphanumeric characters except hyphens from input', async () => {
    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'acme!@#$%^&*()-7k9x');

    // Only uppercase alphanumeric and hyphens should remain
    expect(input).toHaveValue('ACME-7K9X');
  });

  it('should clear preview and code when Cancel is clicked', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve(mockInvitationPreview),
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'ACME-7K9X');
    await user.click(screen.getByRole('button', { name: 'Look Up' }));

    await waitFor(() => {
      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });

    await user.click(screen.getByRole('button', { name: 'Cancel' }));

    // Preview should be gone, input should be visible again with empty value
    expect(screen.queryByText('Acme Corp')).not.toBeInTheDocument();
    const newInput = screen.getByPlaceholderText('ACME-7K9X');
    expect(newInput).toHaveValue('');
  });

  it('should show Joining... loading state while joining', async () => {
    useAuthStore.setState({ isAuthenticated: true, isLocked: false });

    // Make acceptInvitation hang to test loading state
    const mockAcceptInvitation = vi.fn().mockImplementation(
      () => new Promise((resolve) => setTimeout(resolve, 1000))
    );
    const mockLoadTenants = vi.fn().mockResolvedValue(undefined);
    useTenantStore.setState({
      acceptInvitation: mockAcceptInvitation,
      loadTenants: mockLoadTenants,
    });

    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: () => Promise.resolve(mockInvitationPreview),
    });

    const { user } = render(<JoinTenantPage />);

    const input = screen.getByPlaceholderText('ACME-7K9X');
    await user.type(input, 'ACME-7K9X');
    await user.click(screen.getByRole('button', { name: 'Look Up' }));

    await waitFor(() => {
      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
    });

    await user.click(screen.getByRole('button', { name: 'Join' }));

    await waitFor(() => {
      expect(screen.getByText('Joining...')).toBeInTheDocument();
    });
  });
});
