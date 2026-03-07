import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { invoke } from '@tauri-apps/api/core';

type Theme = 'light' | 'dark' | 'system';

interface Settings {
  theme: Theme;
  autoLockTimeout: number; // seconds, 0 = never
  notificationsEnabled: boolean;
  biometricEnabled: boolean;
}

interface StorageInfo {
  cacheSize: number;
  totalUsed: number;
  quota: number;
}

interface SettingsState {
  settings: Settings;
  storageInfo: StorageInfo | null;
  isLoading: boolean;
  isSaving: boolean;
  error: string | null;

  // Actions
  loadSettings: () => Promise<void>;
  updateSettings: (updates: Partial<Settings>) => Promise<void>;
  setTheme: (theme: Theme) => void;
  setAutoLockTimeout: (timeout: number) => void;
  setNotificationsEnabled: (enabled: boolean) => void;
  setBiometricEnabled: (enabled: boolean) => void;
  loadStorageInfo: () => Promise<void>;
  clearCache: () => Promise<void>;
  applyTheme: () => void;
}

const DEFAULT_SETTINGS: Settings = {
  theme: 'system',
  autoLockTimeout: 300,
  notificationsEnabled: true,
  biometricEnabled: false,
};

// Helper to get system theme preference
function getSystemTheme(): 'light' | 'dark' {
  if (typeof window !== 'undefined' && window.matchMedia) {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return 'light';
}

// Helper to apply theme to document
function applyThemeToDocument(theme: Theme) {
  const effectiveTheme = theme === 'system' ? getSystemTheme() : theme;
  const root = document.documentElement;

  if (effectiveTheme === 'dark') {
    root.classList.add('dark');
  } else {
    root.classList.remove('dark');
  }
}

export const useSettingsStore = create<SettingsState>()(
  persist(
    (set, get) => ({
      settings: DEFAULT_SETTINGS,
      storageInfo: null,
      isLoading: false,
      isSaving: false,
      error: null,

      loadSettings: async () => {
        set({ isLoading: true, error: null });
        try {
          const response = await invoke<Settings>('get_settings');
          set({ settings: response, isLoading: false });
          get().applyTheme();
        } catch (error) {
          // If backend call fails, use persisted local settings
          console.warn('Failed to load settings from backend, using local:', error);
          set({ isLoading: false });
          get().applyTheme();
        }
      },

      updateSettings: async (updates) => {
        const currentSettings = get().settings;
        const newSettings = { ...currentSettings, ...updates };

        set({ isSaving: true, error: null, settings: newSettings });

        try {
          await invoke('update_settings', { settings: newSettings });
          set({ isSaving: false });

          // Apply theme if it was updated
          if (updates.theme !== undefined) {
            get().applyTheme();
          }
        } catch (error) {
          // Keep local changes even if backend fails
          console.warn('Failed to save settings to backend:', error);
          set({ isSaving: false });

          // Still apply theme locally
          if (updates.theme !== undefined) {
            get().applyTheme();
          }
        }
      },

      setTheme: (theme) => {
        get().updateSettings({ theme });
      },

      setAutoLockTimeout: (timeout) => {
        get().updateSettings({ autoLockTimeout: timeout });
      },

      setNotificationsEnabled: (enabled) => {
        get().updateSettings({ notificationsEnabled: enabled });
      },

      setBiometricEnabled: (enabled) => {
        get().updateSettings({ biometricEnabled: enabled });
      },

      loadStorageInfo: async () => {
        try {
          const info = await invoke<StorageInfo>('get_storage_info');
          set({ storageInfo: info });
        } catch (error) {
          console.warn('Failed to load storage info:', error);
        }
      },

      clearCache: async () => {
        set({ isLoading: true, error: null });
        try {
          await invoke('clear_cache');
          await get().loadStorageInfo();
          set({ isLoading: false });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          set({ error: message, isLoading: false });
          throw error;
        }
      },

      applyTheme: () => {
        const { theme } = get().settings;
        applyThemeToDocument(theme);
      },
    }),
    {
      name: 'securesharing-settings',
      partialize: (state) => ({ settings: state.settings }),
      onRehydrateStorage: () => {
        // Apply theme after rehydration
        return (state: SettingsState | undefined) => {
          if (state) {
            setTimeout(() => state.applyTheme(), 0);
          }
        };
      },
    }
  )
);

// Listen for system theme changes
if (typeof window !== 'undefined' && window.matchMedia) {
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    const store = useSettingsStore.getState();
    if (store.settings.theme === 'system') {
      store.applyTheme();
    }
  });
}
