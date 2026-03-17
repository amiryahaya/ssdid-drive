import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { TenantRequestPage } from '../TenantRequestPage';
import { useAuthStore } from '../../stores/authStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

describe('TenantRequestPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    useAuthStore.setState({
      user: {
        id: 'user-1',
        email: 'test@example.com',
        name: 'Test User',
        tenantId: 'tenant-1',
      },
      isAuthenticated: true,
      isLoading: false,
      isLocked: false,
      error: null,
    });

    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_api_base_url') {
        return { api_base_url: 'http://localhost:5147' };
      }
      if (cmd === 'get_auth_token') {
        return 'mock-token';
      }
      return undefined;
    });

    // Mock fetch for form submission
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve({}),
    });
  });

  it('should render page title', () => {
    render(<TenantRequestPage />);

    expect(screen.getByText('Request Organization')).toBeInTheDocument();
  });

  it('should render page description', () => {
    render(<TenantRequestPage />);

    expect(
      screen.getByText('Request a new organization for your team')
    ).toBeInTheDocument();
  });

  it('should render organization name input', () => {
    render(<TenantRequestPage />);

    expect(screen.getByLabelText('Organization Name')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Acme Corp')).toBeInTheDocument();
  });

  it('should render reason textarea', () => {
    render(<TenantRequestPage />);

    expect(screen.getByLabelText(/Reason/)).toBeInTheDocument();
    expect(
      screen.getByPlaceholderText('Tell us about your team...')
    ).toBeInTheDocument();
  });

  it('should render submit button', () => {
    render(<TenantRequestPage />);

    expect(
      screen.getByRole('button', { name: 'Submit Request' })
    ).toBeInTheDocument();
  });

  it('should render character counter for reason', () => {
    render(<TenantRequestPage />);

    expect(screen.getByText('0/500')).toBeInTheDocument();
  });

  it('should render back to files link when authenticated', () => {
    render(<TenantRequestPage />);

    const backLink = screen.getByText('Back to Files');
    expect(backLink.closest('a')).toHaveAttribute('href', '/files');
  });

  it('should render back to login link when not authenticated', () => {
    useAuthStore.setState({ isAuthenticated: false });

    render(<TenantRequestPage />);

    const backLink = screen.getByText('Back to Login');
    expect(backLink.closest('a')).toHaveAttribute('href', '/login');
  });

  it('should render security footer', () => {
    render(<TenantRequestPage />);

    expect(
      screen.getByText('Protected with post-quantum cryptography')
    ).toBeInTheDocument();
  });

  describe('form validation', () => {
    it('should disable submit button when organization name is empty', () => {
      render(<TenantRequestPage />);

      const submitButton = screen.getByRole('button', {
        name: 'Submit Request',
      });
      expect(submitButton).toBeDisabled();
    });

    it('should enable submit button when organization name is provided', async () => {
      const { user } = render(<TenantRequestPage />);

      const input = screen.getByPlaceholderText('Acme Corp');
      await user.type(input, 'My Organization');

      const submitButton = screen.getByRole('button', {
        name: 'Submit Request',
      });
      expect(submitButton).not.toBeDisabled();
    });

    it('should show error when submitting empty name (whitespace only)', async () => {
      const { user } = render(<TenantRequestPage />);

      const input = screen.getByPlaceholderText('Acme Corp');
      await user.type(input, '   ');

      // The button should be disabled because trim() is empty
      const submitButton = screen.getByRole('button', {
        name: 'Submit Request',
      });
      expect(submitButton).toBeDisabled();
    });

    it('should show sign-in message when not authenticated', () => {
      useAuthStore.setState({ isAuthenticated: false });

      render(<TenantRequestPage />);

      expect(screen.getByText(/sign in/)).toBeInTheDocument();
    });

    it('should show error when not authenticated and trying to submit', async () => {
      useAuthStore.setState({ isAuthenticated: false });

      const { user } = render(<TenantRequestPage />);

      // Force-enable the button by typing a name
      const input = screen.getByPlaceholderText('Acme Corp');
      await user.type(input, 'Test Org');

      const submitButton = screen.getByRole('button', {
        name: 'Submit Request',
      });
      await user.click(submitButton);

      await waitFor(() => {
        expect(
          screen.getByText('Please sign in first to submit a request.')
        ).toBeInTheDocument();
      });
    });

    it('should update character counter as user types in reason', async () => {
      const { user } = render(<TenantRequestPage />);

      const textarea = screen.getByPlaceholderText(
        'Tell us about your team...'
      );
      await user.type(textarea, 'We need this for our project');

      expect(screen.getByText('28/500')).toBeInTheDocument();
    });
  });

  describe('form submission', () => {
    it('should submit the request with organization name and reason', async () => {
      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Acme Corp');

      const reasonInput = screen.getByPlaceholderText(
        'Tell us about your team...'
      );
      await user.type(reasonInput, 'We need secure file sharing');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        expect(global.fetch).toHaveBeenCalledWith(
          'http://localhost:5147/api/tenant-requests',
          expect.objectContaining({
            method: 'POST',
            body: JSON.stringify({
              organization_name: 'Acme Corp',
              reason: 'We need secure file sharing',
            }),
          })
        );
      });
    });

    it('should show success state after submission', async () => {
      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Acme Corp');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        expect(screen.getByText('Request Submitted!')).toBeInTheDocument();
        expect(
          screen.getByText(/Your request for "Acme Corp" has been submitted/)
        ).toBeInTheDocument();
      });
    });

    it('should show reviewer message after success', async () => {
      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Test Org');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        expect(
          screen.getByText(
            /An administrator will review and approve your request/
          )
        ).toBeInTheDocument();
      });
    });

    it('should show Back to Files button after success when authenticated', async () => {
      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Test Org');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        const backButton = screen.getByRole('button', {
          name: 'Back to Files',
        });
        expect(backButton.closest('a')).toHaveAttribute('href', '/files');
      });
    });

    it('should show loading state during submission', async () => {
      // Make fetch hang
      (global.fetch as ReturnType<typeof vi.fn>).mockReturnValue(
        new Promise(() => {})
      );

      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Test Org');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        expect(screen.getByText('Submitting...')).toBeInTheDocument();
      });
    });
  });

  describe('error handling', () => {
    it('should show error when submission fails', async () => {
      (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
        ok: false,
        status: 500,
      });

      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Test Org');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        expect(
          screen.getByText('Failed to submit request (500)')
        ).toBeInTheDocument();
      });
    });

    it('should show conflict error for duplicate request', async () => {
      (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
        ok: false,
        status: 409,
      });

      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Test Org');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        expect(
          screen.getByText(
            'You already have a pending organization request.'
          )
        ).toBeInTheDocument();
      });
    });

    it('should clear error when user types in name field', async () => {
      (global.fetch as ReturnType<typeof vi.fn>).mockResolvedValue({
        ok: false,
        status: 500,
      });

      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Test Org');

      await user.click(
        screen.getByRole('button', { name: 'Submit Request' })
      );

      await waitFor(() => {
        expect(
          screen.getByText('Failed to submit request (500)')
        ).toBeInTheDocument();
      });

      // Type again to clear error
      await user.type(nameInput, ' Updated');

      expect(
        screen.queryByText('Failed to submit request (500)')
      ).not.toBeInTheDocument();
    });
  });

  describe('keyboard interaction', () => {
    it('should submit on Enter key when name is filled', async () => {
      const { user } = render(<TenantRequestPage />);

      const nameInput = screen.getByPlaceholderText('Acme Corp');
      await user.type(nameInput, 'Test Org{Enter}');

      await waitFor(() => {
        expect(global.fetch).toHaveBeenCalled();
      });
    });
  });
});
