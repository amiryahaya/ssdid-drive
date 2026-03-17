import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { TenantSwitcher } from '../TenantSwitcher';
import { useTenantStore, type Tenant } from '../../../stores/tenantStore';

// Mock useToast
const mockSuccess = vi.fn();
const mockShowError = vi.fn();
vi.mock('@/hooks/useToast', () => ({
  useToast: () => ({
    success: mockSuccess,
    error: mockShowError,
    info: vi.fn(),
    warning: vi.fn(),
  }),
}));

// Mock window.location.reload
const mockReload = vi.fn();
Object.defineProperty(window, 'location', {
  writable: true,
  value: { ...window.location, reload: mockReload },
});

const mockTenants: Tenant[] = [
  {
    id: 'tenant-1',
    name: 'Acme Corp',
    slug: 'acme-corp',
    role: 'owner',
    joined_at: '2024-01-01T00:00:00Z',
  },
  {
    id: 'tenant-2',
    name: 'Beta Inc',
    slug: 'beta-inc',
    role: 'admin',
    joined_at: '2024-02-01T00:00:00Z',
  },
  {
    id: 'tenant-3',
    name: 'Gamma LLC',
    slug: 'gamma-llc',
    role: 'member',
    joined_at: '2024-03-01T00:00:00Z',
  },
];

describe('TenantSwitcher', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    useTenantStore.setState({
      currentTenantId: 'tenant-1',
      currentTenant: mockTenants[0],
      availableTenants: mockTenants,
      isLoading: false,
      isSwitching: false,
      error: null,
      loadTenants: vi.fn(),
      switchTenant: vi.fn().mockResolvedValue(undefined),
    });
  });

  it('should render current tenant name in trigger button', () => {
    render(<TenantSwitcher />);

    expect(screen.getByText('Acme Corp')).toBeInTheDocument();
  });

  it('should call loadTenants on mount', () => {
    const loadTenantsSpy = vi.fn();
    useTenantStore.setState({ loadTenants: loadTenantsSpy });

    render(<TenantSwitcher />);

    expect(loadTenantsSpy).toHaveBeenCalled();
  });

  it('should not render when only one tenant and not loading', () => {
    useTenantStore.setState({
      availableTenants: [mockTenants[0]],
      isLoading: false,
    });

    const { container } = render(<TenantSwitcher />);

    expect(container.innerHTML).toBe('');
  });

  it('should not render when zero tenants and not loading', () => {
    useTenantStore.setState({
      availableTenants: [],
      currentTenant: null,
      isLoading: false,
    });

    const { container } = render(<TenantSwitcher />);

    expect(container.innerHTML).toBe('');
  });

  it('should show "Select Organization" when no current tenant', () => {
    useTenantStore.setState({
      currentTenant: null,
      availableTenants: mockTenants,
    });

    render(<TenantSwitcher />);

    expect(screen.getByText('Select Organization')).toBeInTheDocument();
  });

  it('should disable trigger button when switching', () => {
    useTenantStore.setState({ isSwitching: true });

    render(<TenantSwitcher />);

    const trigger = screen.getByRole('button');
    expect(trigger).toBeDisabled();
  });

  it('should show loading spinner when switching', () => {
    useTenantStore.setState({ isSwitching: true });

    render(<TenantSwitcher />);

    expect(document.querySelector('.animate-spin')).toBeInTheDocument();
  });

  describe('dropdown content', () => {
    it('should show all tenants when dropdown is opened', async () => {
      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Switch Organization')).toBeInTheDocument();
        // Acme Corp appears in both trigger and dropdown, so use getAllByText
        expect(screen.getAllByText('Acme Corp').length).toBeGreaterThanOrEqual(2);
        expect(screen.getByText('Beta Inc')).toBeInTheDocument();
        expect(screen.getByText('Gamma LLC')).toBeInTheDocument();
      });
    });

    it('should show role labels for each tenant', async () => {
      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Owner')).toBeInTheDocument();
        expect(screen.getByText('Admin')).toBeInTheDocument();
        expect(screen.getByText('Member')).toBeInTheDocument();
      });
    });

    it('should show check mark on current tenant', async () => {
      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        // The active tenant should have a check icon
        expect(document.querySelector('.lucide-check')).toBeInTheDocument();
      });
    });

    it('should show loading spinner in dropdown when loading', async () => {
      useTenantStore.setState({ isLoading: true });

      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(document.querySelector('.animate-spin')).toBeInTheDocument();
      });
    });
  });

  describe('tenant switching', () => {
    it('should call switchTenant when a different tenant is clicked', async () => {
      const switchTenantSpy = vi.fn().mockResolvedValue(undefined);
      useTenantStore.setState({ switchTenant: switchTenantSpy });

      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Beta Inc')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Beta Inc'));

      await waitFor(() => {
        expect(switchTenantSpy).toHaveBeenCalledWith('tenant-2');
      });
    });

    it('should not call switchTenant when clicking the current tenant', async () => {
      const switchTenantSpy = vi.fn().mockResolvedValue(undefined);
      useTenantStore.setState({ switchTenant: switchTenantSpy });

      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Switch Organization')).toBeInTheDocument();
      });

      // Click the already-active tenant (Acme Corp appears in dropdown too)
      const dropdownItems = screen.getAllByText('Acme Corp');
      // The second one is inside the dropdown
      if (dropdownItems.length > 1) {
        await user.click(dropdownItems[1]);
      }

      expect(switchTenantSpy).not.toHaveBeenCalled();
    });

    it('should show success toast after switching', async () => {
      const switchTenantSpy = vi.fn().mockResolvedValue(undefined);
      useTenantStore.setState({ switchTenant: switchTenantSpy });

      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Beta Inc')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Beta Inc'));

      await waitFor(() => {
        expect(mockSuccess).toHaveBeenCalledWith({
          title: 'Switched organization',
          description: 'Now viewing Beta Inc',
        });
      });
    });

    it('should show error toast when switching fails', async () => {
      const switchTenantSpy = vi
        .fn()
        .mockRejectedValue(new Error('Switch failed'));
      useTenantStore.setState({ switchTenant: switchTenantSpy });

      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Beta Inc')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Beta Inc'));

      await waitFor(() => {
        expect(mockShowError).toHaveBeenCalledWith({
          title: 'Failed to switch organization',
          description: 'Switch failed',
        });
      });
    });

    it('should reload the page after successful switch', async () => {
      const switchTenantSpy = vi.fn().mockResolvedValue(undefined);
      useTenantStore.setState({ switchTenant: switchTenantSpy });

      const { user } = render(<TenantSwitcher />);

      await user.click(screen.getByRole('button'));

      await waitFor(() => {
        expect(screen.getByText('Gamma LLC')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Gamma LLC'));

      await waitFor(() => {
        expect(mockReload).toHaveBeenCalled();
      });
    });
  });
});
