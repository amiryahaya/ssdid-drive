import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '../../../test/utils';
import { LinkedLoginsSection } from '../LinkedLoginsSection';
import { tauriService } from '@/services/tauri';
import type { LinkedLogin } from '@/services/tauri';

vi.mock('@/services/tauri', () => ({
  tauriService: {
    listLogins: vi.fn(),
    unlinkLogin: vi.fn(),
    oidcLogin: vi.fn(),
  },
}));

const mockSuccess = vi.fn();
const mockShowError = vi.fn();
vi.mock('@/hooks/useToast', () => ({
  useToast: () => ({ success: mockSuccess, error: mockShowError }),
}));

const mockListLogins = vi.mocked(tauriService.listLogins);
const mockUnlinkLogin = vi.mocked(tauriService.unlinkLogin);
const mockOidcLogin = vi.mocked(tauriService.oidcLogin);

const twoLogins: LinkedLogin[] = [
  {
    id: 'login-1',
    provider: 'email',
    provider_subject: 'user@example.com',
    email: 'user@example.com',
    linked_at: '2025-01-15T10:00:00Z',
  },
  {
    id: 'login-2',
    provider: 'google',
    provider_subject: '1234567890',
    email: 'user@gmail.com',
    linked_at: '2025-02-01T12:00:00Z',
  },
];

const singleLogin: LinkedLogin[] = [
  {
    id: 'login-1',
    provider: 'email',
    provider_subject: 'user@example.com',
    email: 'user@example.com',
    linked_at: '2025-01-15T10:00:00Z',
  },
];

describe('LinkedLoginsSection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows loading spinner initially', () => {
    mockListLogins.mockReturnValue(new Promise(() => {})); // never resolves
    render(<LinkedLoginsSection />);
    expect(document.querySelector('.animate-spin')).toBeTruthy();
  });

  it('renders logins after load', async () => {
    mockListLogins.mockResolvedValueOnce(twoLogins);
    render(<LinkedLoginsSection />);

    await waitFor(() => {
      expect(screen.getByText('email')).toBeTruthy();
    });

    expect(screen.getByText('user@example.com')).toBeTruthy();
    expect(screen.getByText('google')).toBeTruthy();
    expect(screen.getByText('user@gmail.com')).toBeTruthy();
  });

  it('disables remove button when there is only one login', async () => {
    mockListLogins.mockResolvedValueOnce(singleLogin);
    render(<LinkedLoginsSection />);

    await waitFor(() => {
      expect(screen.getByText('email')).toBeTruthy();
    });

    const removeButton = screen.getByTitle('Cannot remove last login method');
    expect(removeButton).toBeDisabled();
  });

  it('calls unlinkLogin and reloads on remove', async () => {
    mockListLogins
      .mockResolvedValueOnce(twoLogins) // initial load
      .mockResolvedValueOnce(singleLogin); // reload after unlink
    mockUnlinkLogin.mockResolvedValueOnce(undefined as never);

    const { user } = render(<LinkedLoginsSection />);

    await waitFor(() => {
      expect(screen.getByText('google')).toBeTruthy();
    });

    const removeButtons = screen.getAllByTitle('Remove login');
    await user.click(removeButtons[0]);

    await waitFor(() => {
      expect(mockUnlinkLogin).toHaveBeenCalledWith('login-1');
    });

    expect(mockListLogins).toHaveBeenCalledTimes(2);
    expect(mockSuccess).toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Login removed' })
    );
  });

  it('shows error toast on load failure', async () => {
    mockListLogins.mockRejectedValueOnce(new Error('Network error'));
    render(<LinkedLoginsSection />);

    await waitFor(() => {
      expect(mockShowError).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Failed to load logins' })
      );
    });
  });

  it('calls oidcLogin with google when Link Google clicked', async () => {
    mockListLogins.mockResolvedValueOnce(twoLogins);
    mockOidcLogin.mockResolvedValueOnce(undefined as never);

    const { user } = render(<LinkedLoginsSection />);

    await waitFor(() => {
      expect(screen.getByText('Link Google')).toBeTruthy();
    });

    await user.click(screen.getByText('Link Google'));

    expect(mockOidcLogin).toHaveBeenCalledWith('google');
  });

  it('calls oidcLogin with microsoft when Link Microsoft clicked', async () => {
    mockListLogins.mockResolvedValueOnce(twoLogins);
    mockOidcLogin.mockResolvedValueOnce(undefined as never);

    const { user } = render(<LinkedLoginsSection />);

    await waitFor(() => {
      expect(screen.getByText('Link Microsoft')).toBeTruthy();
    });

    await user.click(screen.getByText('Link Microsoft'));

    expect(mockOidcLogin).toHaveBeenCalledWith('microsoft');
  });
});
