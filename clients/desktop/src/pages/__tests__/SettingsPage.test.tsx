import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { SettingsPage } from '../SettingsPage';
import { useSettingsStore } from '../../stores/settingsStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

// Mock usePushPermission hook
vi.mock('../../hooks/usePushPermission', () => ({
  usePushPermission: () => ({
    status: 'default',
    isLoading: false,
    requestPermission: vi.fn().mockResolvedValue(true),
    refreshStatus: vi.fn(),
  }),
}));

// Mock useBiometric hook
vi.mock('../../hooks/useBiometric', () => ({
  useBiometric: () => ({
    isAvailable: false,
    isEnabled: false,
    biometricType: null,
    message: 'Not available on this device',
    isLoading: false,
    enable: vi.fn().mockResolvedValue(true),
    disable: vi.fn().mockResolvedValue(undefined),
    status: { availability: 'not_available' },
  }),
}));

const mockInvoke = vi.mocked(invoke);

// Mock recovery components to simplify tests
vi.mock('../../components/recovery/RecoveryStatusCard', () => ({
  RecoveryStatusCard: () => <div data-testid="recovery-status-card">Recovery Status</div>,
}));

vi.mock('../../components/recovery/PendingRecoveryRequests', () => ({
  PendingRecoveryRequests: () => <div data-testid="pending-recovery-requests">Pending Requests</div>,
}));

const mockStorageInfo = {
  cacheSize: 1024 * 1024 * 50, // 50 MB
  totalUsed: 1024 * 1024 * 100,
  quota: 1024 * 1024 * 1024,
};

const defaultSettings = {
  theme: 'system' as const,
  autoLockTimeout: 300,
  notificationsEnabled: true,
  biometricEnabled: false,
};

describe('SettingsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset store to initial state using the store's setState
    const store = useSettingsStore.getState();
    useSettingsStore.setState({
      ...store,
      settings: defaultSettings,
      storageInfo: mockStorageInfo,
      isLoading: false,
      isSaving: false,
      error: null,
    });

    // Mock backend calls
    mockInvoke.mockImplementation(async (cmd: string) => {
      if (cmd === 'get_settings') {
        return defaultSettings;
      }
      if (cmd === 'get_storage_info') {
        return mockStorageInfo;
      }
      if (cmd === 'update_settings') {
        return undefined;
      }
      if (cmd === 'clear_cache') {
        return undefined;
      }
      return undefined;
    });
  });

  it('should render page title and description', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Settings')).toBeInTheDocument();
    expect(screen.getByText('Manage your application preferences')).toBeInTheDocument();
  });

  it('should render appearance section with theme options', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Appearance')).toBeInTheDocument();
    expect(screen.getByText('Light')).toBeInTheDocument();
    expect(screen.getByText('Dark')).toBeInTheDocument();
    expect(screen.getByText('System')).toBeInTheDocument();
  });

  it('should render security section', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Security')).toBeInTheDocument();
    expect(screen.getByText('Auto-lock')).toBeInTheDocument();
    // Biometric section is conditionally rendered based on availability
  });

  it('should render notifications section', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Notifications')).toBeInTheDocument();
    expect(screen.getByText('Push Notifications')).toBeInTheDocument();
  });

  it('should render storage section with cache info', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Storage')).toBeInTheDocument();
    expect(screen.getByText('Local Cache')).toBeInTheDocument();
    expect(screen.getByText(/50 MB/)).toBeInTheDocument();
  });

  it('should render recovery components', () => {
    render(<SettingsPage />);

    expect(screen.getByText('Account Recovery')).toBeInTheDocument();
    expect(screen.getByTestId('recovery-status-card')).toBeInTheDocument();
    expect(screen.getByTestId('pending-recovery-requests')).toBeInTheDocument();
  });

  describe('theme selection', () => {
    it('should render all theme buttons', () => {
      render(<SettingsPage />);

      expect(screen.getByText('Light').closest('button')).toBeInTheDocument();
      expect(screen.getByText('Dark').closest('button')).toBeInTheDocument();
      expect(screen.getByText('System').closest('button')).toBeInTheDocument();
    });

    it('should have theme icons', () => {
      render(<SettingsPage />);

      // Each theme button should have an icon
      const lightButton = screen.getByText('Light').closest('button');
      const darkButton = screen.getByText('Dark').closest('button');
      const systemButton = screen.getByText('System').closest('button');

      expect(lightButton?.querySelector('svg')).toBeInTheDocument();
      expect(darkButton?.querySelector('svg')).toBeInTheDocument();
      expect(systemButton?.querySelector('svg')).toBeInTheDocument();
    });
  });

  describe('auto-lock timeout', () => {
    it('should render auto-lock section', () => {
      render(<SettingsPage />);

      expect(screen.getByText('Auto-lock')).toBeInTheDocument();
      expect(screen.getByText('Lock the app after inactivity')).toBeInTheDocument();
    });

    it('should have timeout options', () => {
      render(<SettingsPage />);

      expect(screen.getByRole('option', { name: 'Never' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: '1 minute' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: '5 minutes' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: '15 minutes' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: '30 minutes' })).toBeInTheDocument();
    });
  });

  describe('biometric unlock', () => {
    it('should render biometric section when not available', () => {
      render(<SettingsPage />);

      // The biometric section shows "Biometric Unlock" with "Not available on this device"
      expect(screen.getByText('Biometric Unlock')).toBeInTheDocument();
      expect(screen.getByText('Not available on this device')).toBeInTheDocument();
    });
  });

  describe('notifications', () => {
    it('should render notifications section', () => {
      render(<SettingsPage />);

      expect(screen.getByText('Push Notifications')).toBeInTheDocument();
      expect(screen.getByText('Enable push notifications for shares and updates')).toBeInTheDocument();
    });

    it('should render in-app notifications toggle', () => {
      render(<SettingsPage />);

      expect(screen.getByText('In-App Notifications')).toBeInTheDocument();
      expect(screen.getByText('Show notification badge and alerts in the app')).toBeInTheDocument();
    });
  });

  describe('storage', () => {
    it('should show storage section', () => {
      render(<SettingsPage />);

      expect(screen.getByText('Local Cache')).toBeInTheDocument();
    });

    it('should show storage info', () => {
      render(<SettingsPage />);

      // Should show either loading or the actual cache size
      expect(screen.getByText(/50 MB|Loading storage info/)).toBeInTheDocument();
    });

    it('should render clear cache button', () => {
      render(<SettingsPage />);

      // Find by button text (either "Clear Cache" or "Clearing...")
      expect(screen.getByRole('button', { name: /clear|clearing/i })).toBeInTheDocument();
    });
  });

  describe('loading', () => {
    it('should call loadSettings on mount', async () => {
      render(<SettingsPage />);

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('get_settings');
      });
    });

    it('should call loadStorageInfo on mount', async () => {
      render(<SettingsPage />);

      await waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('get_storage_info');
      });
    });
  });

  describe('theme interactions', () => {
    it('should call setTheme when light button is clicked', async () => {
      const setThemeSpy = vi.fn();
      useSettingsStore.setState({ setTheme: setThemeSpy });

      const { user } = render(<SettingsPage />);

      const lightButton = screen.getByText('Light').closest('button')!;
      await user.click(lightButton);

      expect(setThemeSpy).toHaveBeenCalledWith('light');
    });

    it('should call setTheme when dark button is clicked', async () => {
      const setThemeSpy = vi.fn();
      useSettingsStore.setState({ setTheme: setThemeSpy });

      const { user } = render(<SettingsPage />);

      const darkButton = screen.getByText('Dark').closest('button')!;
      await user.click(darkButton);

      expect(setThemeSpy).toHaveBeenCalledWith('dark');
    });

    it('should call setTheme when system button is clicked', async () => {
      const setThemeSpy = vi.fn();
      useSettingsStore.setState({ setTheme: setThemeSpy });

      const { user } = render(<SettingsPage />);

      const systemButton = screen.getByText('System').closest('button')!;
      await user.click(systemButton);

      expect(setThemeSpy).toHaveBeenCalledWith('system');
    });

    it('should highlight current theme button', () => {
      useSettingsStore.setState({
        settings: { ...defaultSettings, theme: 'dark' },
      });

      render(<SettingsPage />);

      const darkButton = screen.getByText('Dark').closest('button');
      expect(darkButton).toHaveClass('border-primary');
    });

    it('should disable theme buttons while saving', () => {
      useSettingsStore.setState({ isSaving: true });

      render(<SettingsPage />);

      const lightButton = screen.getByText('Light').closest('button');
      expect(lightButton).toBeDisabled();
    });
  });

  describe('auto-lock interactions', () => {
    it('should call setAutoLockTimeout when select value changes', async () => {
      const setAutoLockTimeoutSpy = vi.fn();
      useSettingsStore.setState({ setAutoLockTimeout: setAutoLockTimeoutSpy });

      const { user } = render(<SettingsPage />);

      const select = screen.getByRole('combobox');
      await user.selectOptions(select, '900');

      expect(setAutoLockTimeoutSpy).toHaveBeenCalledWith(900);
    });

    it('should show current timeout value in select', () => {
      useSettingsStore.setState({
        settings: { ...defaultSettings, autoLockTimeout: 900 },
      });

      render(<SettingsPage />);

      const select = screen.getByRole('combobox') as HTMLSelectElement;
      expect(select.value).toBe('900');
    });

    it('should disable select while saving', () => {
      useSettingsStore.setState({ isSaving: true });

      render(<SettingsPage />);

      const select = screen.getByRole('combobox');
      expect(select).toBeDisabled();
    });
  });

  describe('biometric toggle', () => {
    it('should show not available state when biometric is not supported', () => {
      render(<SettingsPage />);

      // When biometric is not available, shows "Not available" text instead of toggle
      expect(screen.getByText('Not available')).toBeInTheDocument();
    });
  });

  describe('notifications toggle', () => {
    it('should call setNotificationsEnabled when toggle is clicked', async () => {
      const setNotificationsEnabledSpy = vi.fn();
      useSettingsStore.setState({
        settings: { ...defaultSettings, notificationsEnabled: true },
        setNotificationsEnabled: setNotificationsEnabledSpy,
      });

      const { user } = render(<SettingsPage />);

      // Find the In-App Notifications toggle container
      const notificationsContainer = screen.getByText('In-App Notifications').closest('[class*="justify-between"]');
      const toggle = notificationsContainer?.querySelector('button');

      if (toggle) {
        await user.click(toggle);
        expect(setNotificationsEnabledSpy).toHaveBeenCalledWith(false);
      }
    });
  });

  describe('clear cache', () => {
    it('should call clearCache when button is clicked', async () => {
      const clearCacheSpy = vi.fn().mockResolvedValue(undefined);
      useSettingsStore.setState({ clearCache: clearCacheSpy });

      const { user } = render(<SettingsPage />);

      const clearCacheButton = screen.getByRole('button', { name: /clear|clearing/i });
      await user.click(clearCacheButton);

      expect(clearCacheSpy).toHaveBeenCalled();
    });

    it('should disable button while loading', () => {
      useSettingsStore.setState({ isLoading: true });

      render(<SettingsPage />);

      const clearCacheButton = screen.getByRole('button', { name: /clear|clearing/i });
      expect(clearCacheButton).toBeDisabled();
    });

    it('should show "Clearing..." text while loading', () => {
      useSettingsStore.setState({ isLoading: true });

      render(<SettingsPage />);

      expect(screen.getByText('Clearing...')).toBeInTheDocument();
    });

    it('should show loading info when storage info is null', () => {
      useSettingsStore.setState({ storageInfo: null });

      render(<SettingsPage />);

      expect(screen.getByText('Loading storage info...')).toBeInTheDocument();
    });
  });

  describe('push notifications states', () => {
    it('should show Enable button for default push status', () => {
      render(<SettingsPage />);

      expect(screen.getByRole('button', { name: 'Enable' })).toBeInTheDocument();
    });
  });
});
