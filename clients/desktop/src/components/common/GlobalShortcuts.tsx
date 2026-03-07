import { useCallback } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useKeyboardShortcuts, SHORTCUT_KEYS } from '@/hooks/useKeyboardShortcuts';
import { useAuthStore } from '@/stores/authStore';

/**
 * Global keyboard shortcuts for navigation and app-wide actions
 * These shortcuts work throughout the app when authenticated
 */
export function GlobalShortcuts() {
  const navigate = useNavigate();
  const location = useLocation();
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);

  // Navigation shortcuts
  const goToFiles = useCallback(() => {
    navigate('/files');
  }, [navigate]);

  const goToSharedWithMe = useCallback(() => {
    navigate('/shared-with-me');
  }, [navigate]);

  const goToMyShares = useCallback(() => {
    navigate('/my-shares');
  }, [navigate]);

  const goToSettings = useCallback(() => {
    navigate('/settings');
  }, [navigate]);

  // Focus search
  const focusSearch = useCallback(() => {
    // Find the search input in the header
    const searchInput = document.querySelector('input[placeholder*="Search"]') as HTMLInputElement;
    if (searchInput) {
      searchInput.focus();
      searchInput.select();
    }
  }, []);

  // Navigate back/up
  const goBack = useCallback(() => {
    // If in a subfolder, navigate to parent
    if (location.pathname.startsWith('/files/')) {
      navigate('/files');
    } else if (window.history.length > 1) {
      navigate(-1);
    }
  }, [navigate, location]);

  useKeyboardShortcuts(
    [
      // Navigation: Ctrl+1 to Ctrl+4
      {
        key: SHORTCUT_KEYS.ONE,
        ctrl: true,
        action: goToFiles,
        description: 'Go to Files',
      },
      {
        key: SHORTCUT_KEYS.TWO,
        ctrl: true,
        action: goToSharedWithMe,
        description: 'Go to Shared with Me',
      },
      {
        key: SHORTCUT_KEYS.THREE,
        ctrl: true,
        action: goToMyShares,
        description: 'Go to My Shares',
      },
      {
        key: SHORTCUT_KEYS.FOUR,
        ctrl: true,
        action: goToSettings,
        description: 'Go to Settings',
      },
      // Settings shortcut: Ctrl+,
      {
        key: SHORTCUT_KEYS.COMMA,
        ctrl: true,
        action: goToSettings,
        description: 'Open Settings',
      },
      // Search: Ctrl+F or /
      {
        key: SHORTCUT_KEYS.F,
        ctrl: true,
        action: focusSearch,
        description: 'Focus search',
        allowInInput: true, // Allow Ctrl+F even in inputs
      },
      {
        key: SHORTCUT_KEYS.SLASH,
        action: focusSearch,
        description: 'Focus search',
      },
      // Go back: Alt+Left or Backspace (when not in Files page - handled there)
      {
        key: SHORTCUT_KEYS.ARROW_LEFT,
        alt: true,
        action: goBack,
        description: 'Go back',
      },
    ],
    { enabled: isAuthenticated }
  );

  // This component doesn't render anything
  return null;
}
