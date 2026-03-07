import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { useSettingsStore } from '../settingsStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockSettings = {
  theme: 'dark' as const,
  autoLockTimeout: 600,
  notificationsEnabled: false,
  biometricEnabled: true,
};

const mockStorageInfo = {
  cacheSize: 1024 * 1024 * 50, // 50 MB
  totalUsed: 1024 * 1024 * 100,
  quota: 1024 * 1024 * 1024,
};

describe('settingsStore', () => {
  // Store original document methods
  const originalClassList = {
    add: vi.fn(),
    remove: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();

    // Mock document.documentElement.classList
    Object.defineProperty(document, 'documentElement', {
      value: {
        classList: originalClassList,
      },
      writable: true,
    });

    // Reset store to initial state
    useSettingsStore.setState({
      settings: {
        theme: 'system',
        autoLockTimeout: 300,
        notificationsEnabled: true,
        biometricEnabled: false,
      },
      storageInfo: null,
      isLoading: false,
      isSaving: false,
      error: null,
    });

    // Reset classList mocks
    originalClassList.add.mockClear();
    originalClassList.remove.mockClear();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('initial state', () => {
    it('should have default settings initially', () => {
      const state = useSettingsStore.getState();
      expect(state.settings.theme).toBe('system');
      expect(state.settings.autoLockTimeout).toBe(300);
      expect(state.settings.notificationsEnabled).toBe(true);
      expect(state.settings.biometricEnabled).toBe(false);
      expect(state.storageInfo).toBeNull();
      expect(state.isLoading).toBe(false);
      expect(state.isSaving).toBe(false);
      expect(state.error).toBeNull();
    });
  });

  describe('loadSettings', () => {
    it('should set loading state while fetching', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockSettings), 100))
      );

      const loadPromise = useSettingsStore.getState().loadSettings();

      expect(useSettingsStore.getState().isLoading).toBe(true);
      expect(useSettingsStore.getState().error).toBeNull();

      await loadPromise;
    });

    it('should load settings from backend', async () => {
      mockInvoke.mockResolvedValueOnce(mockSettings);

      await useSettingsStore.getState().loadSettings();

      expect(mockInvoke).toHaveBeenCalledWith('get_settings');
      expect(useSettingsStore.getState().settings).toEqual(mockSettings);
      expect(useSettingsStore.getState().isLoading).toBe(false);
    });

    it('should apply theme after loading', async () => {
      mockInvoke.mockResolvedValueOnce({ ...mockSettings, theme: 'dark' });

      await useSettingsStore.getState().loadSettings();

      expect(originalClassList.add).toHaveBeenCalledWith('dark');
    });

    it('should use local settings on backend failure', async () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      mockInvoke.mockRejectedValueOnce(new Error('Backend unavailable'));

      await useSettingsStore.getState().loadSettings();

      // Should keep current settings and not set error
      expect(useSettingsStore.getState().isLoading).toBe(false);
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('updateSettings', () => {
    it('should set saving state while updating', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(undefined), 100))
      );

      const updatePromise = useSettingsStore.getState().updateSettings({ theme: 'dark' });

      expect(useSettingsStore.getState().isSaving).toBe(true);

      await updatePromise;
    });

    it('should update settings optimistically', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().updateSettings({ theme: 'dark' });

      expect(mockInvoke).toHaveBeenCalledWith('update_settings', {
        settings: expect.objectContaining({ theme: 'dark' }),
      });
      expect(useSettingsStore.getState().settings.theme).toBe('dark');
      expect(useSettingsStore.getState().isSaving).toBe(false);
    });

    it('should apply theme when theme is updated', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().updateSettings({ theme: 'dark' });

      expect(originalClassList.add).toHaveBeenCalledWith('dark');
    });

    it('should keep local changes even on backend failure', async () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      mockInvoke.mockRejectedValueOnce(new Error('Save failed'));

      await useSettingsStore.getState().updateSettings({ theme: 'light' });

      // Should still have the updated theme locally
      expect(useSettingsStore.getState().settings.theme).toBe('light');
      expect(useSettingsStore.getState().isSaving).toBe(false);

      consoleSpy.mockRestore();
    });
  });

  describe('setTheme', () => {
    it('should update theme setting', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setTheme('dark');

      expect(useSettingsStore.getState().settings.theme).toBe('dark');
    });

    it('should apply light theme', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setTheme('light');

      expect(originalClassList.remove).toHaveBeenCalledWith('dark');
    });
  });

  describe('setAutoLockTimeout', () => {
    it('should update auto-lock timeout', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setAutoLockTimeout(900);

      expect(useSettingsStore.getState().settings.autoLockTimeout).toBe(900);
    });

    it('should allow setting timeout to 0 (never)', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setAutoLockTimeout(0);

      expect(useSettingsStore.getState().settings.autoLockTimeout).toBe(0);
    });
  });

  describe('setNotificationsEnabled', () => {
    it('should enable notifications', async () => {
      useSettingsStore.setState({
        settings: { ...useSettingsStore.getState().settings, notificationsEnabled: false },
      });
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setNotificationsEnabled(true);

      expect(useSettingsStore.getState().settings.notificationsEnabled).toBe(true);
    });

    it('should disable notifications', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setNotificationsEnabled(false);

      expect(useSettingsStore.getState().settings.notificationsEnabled).toBe(false);
    });
  });

  describe('setBiometricEnabled', () => {
    it('should enable biometric', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setBiometricEnabled(true);

      expect(useSettingsStore.getState().settings.biometricEnabled).toBe(true);
    });

    it('should disable biometric', async () => {
      useSettingsStore.setState({
        settings: { ...useSettingsStore.getState().settings, biometricEnabled: true },
      });
      mockInvoke.mockResolvedValueOnce(undefined);

      await useSettingsStore.getState().setBiometricEnabled(false);

      expect(useSettingsStore.getState().settings.biometricEnabled).toBe(false);
    });
  });

  describe('loadStorageInfo', () => {
    it('should load storage info', async () => {
      mockInvoke.mockResolvedValueOnce(mockStorageInfo);

      await useSettingsStore.getState().loadStorageInfo();

      expect(mockInvoke).toHaveBeenCalledWith('get_storage_info');
      expect(useSettingsStore.getState().storageInfo).toEqual(mockStorageInfo);
    });

    it('should handle load failure gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      mockInvoke.mockRejectedValueOnce(new Error('Failed to load'));

      await useSettingsStore.getState().loadStorageInfo();

      // Should not set error, just log warning
      expect(useSettingsStore.getState().storageInfo).toBeNull();
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('clearCache', () => {
    beforeEach(() => {
      useSettingsStore.setState({ storageInfo: mockStorageInfo });
    });

    it('should set loading state while clearing', async () => {
      mockInvoke.mockImplementation((cmd) => {
        if (cmd === 'clear_cache') {
          return new Promise((resolve) => setTimeout(() => resolve(undefined), 100));
        }
        return Promise.resolve({ ...mockStorageInfo, cacheSize: 0 });
      });

      const clearPromise = useSettingsStore.getState().clearCache();

      expect(useSettingsStore.getState().isLoading).toBe(true);

      await clearPromise;
    });

    it('should clear cache and reload storage info', async () => {
      const updatedStorageInfo = { ...mockStorageInfo, cacheSize: 0 };
      mockInvoke
        .mockResolvedValueOnce(undefined) // clear_cache
        .mockResolvedValueOnce(updatedStorageInfo); // get_storage_info

      await useSettingsStore.getState().clearCache();

      expect(mockInvoke).toHaveBeenCalledWith('clear_cache');
      expect(useSettingsStore.getState().storageInfo?.cacheSize).toBe(0);
      expect(useSettingsStore.getState().isLoading).toBe(false);
    });

    it('should set error and throw on failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Clear failed'));

      await expect(useSettingsStore.getState().clearCache()).rejects.toThrow('Clear failed');

      expect(useSettingsStore.getState().error).toBe('Clear failed');
      expect(useSettingsStore.getState().isLoading).toBe(false);
    });
  });

  describe('applyTheme', () => {
    it('should add dark class for dark theme', () => {
      useSettingsStore.setState({
        settings: { ...useSettingsStore.getState().settings, theme: 'dark' },
      });

      useSettingsStore.getState().applyTheme();

      expect(originalClassList.add).toHaveBeenCalledWith('dark');
    });

    it('should remove dark class for light theme', () => {
      useSettingsStore.setState({
        settings: { ...useSettingsStore.getState().settings, theme: 'light' },
      });

      useSettingsStore.getState().applyTheme();

      expect(originalClassList.remove).toHaveBeenCalledWith('dark');
    });

    it('should use system preference for system theme', () => {
      // Mock matchMedia for dark mode
      Object.defineProperty(window, 'matchMedia', {
        writable: true,
        value: vi.fn().mockImplementation((query) => ({
          matches: query === '(prefers-color-scheme: dark)',
          media: query,
          onchange: null,
          addListener: vi.fn(),
          removeListener: vi.fn(),
          addEventListener: vi.fn(),
          removeEventListener: vi.fn(),
          dispatchEvent: vi.fn(),
        })),
      });

      useSettingsStore.setState({
        settings: { ...useSettingsStore.getState().settings, theme: 'system' },
      });

      useSettingsStore.getState().applyTheme();

      expect(originalClassList.add).toHaveBeenCalledWith('dark');
    });
  });
});
