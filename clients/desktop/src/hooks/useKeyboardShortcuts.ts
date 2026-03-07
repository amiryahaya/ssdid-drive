import { useEffect, useCallback } from 'react';

export interface ShortcutConfig {
  key: string;
  ctrl?: boolean; // Also matches Cmd on Mac
  shift?: boolean;
  alt?: boolean;
  action: () => void;
  description?: string;
  /** If true, allow this shortcut even in input fields */
  allowInInput?: boolean;
}

interface UseKeyboardShortcutsOptions {
  enabled?: boolean;
}

/**
 * Hook for registering keyboard shortcuts
 * @param shortcuts Array of shortcut configurations
 * @param options Optional configuration
 */
export function useKeyboardShortcuts(
  shortcuts: ShortcutConfig[],
  options: UseKeyboardShortcutsOptions = {}
) {
  const { enabled = true } = options;

  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (!enabled) return;

      const target = event.target as HTMLElement;
      const isInInput =
        target.tagName === 'INPUT' ||
        target.tagName === 'TEXTAREA' ||
        target.isContentEditable;

      for (const shortcut of shortcuts) {
        // Skip non-input-allowed shortcuts when in input
        if (isInInput && !shortcut.allowInInput) {
          continue;
        }

        const keyMatch = event.key.toLowerCase() === shortcut.key.toLowerCase();
        const ctrlMatch = shortcut.ctrl
          ? event.ctrlKey || event.metaKey
          : !event.ctrlKey && !event.metaKey;
        const shiftMatch = shortcut.shift ? event.shiftKey : !event.shiftKey;
        const altMatch = shortcut.alt ? event.altKey : !event.altKey;

        if (keyMatch && ctrlMatch && shiftMatch && altMatch) {
          event.preventDefault();
          shortcut.action();
          return;
        }
      }
    },
    [shortcuts, enabled]
  );

  useEffect(() => {
    if (enabled) {
      window.addEventListener('keydown', handleKeyDown);
      return () => window.removeEventListener('keydown', handleKeyDown);
    }
  }, [handleKeyDown, enabled]);
}

// Pre-defined shortcut key constants
export const SHORTCUT_KEYS = {
  // File operations
  DELETE: 'Delete',
  BACKSPACE: 'Backspace',
  ESCAPE: 'Escape',
  ENTER: 'Enter',
  SPACE: ' ',
  F2: 'F2',

  // Letters
  A: 'a',
  D: 'd',
  E: 'e',
  F: 'f',
  G: 'g',
  L: 'l',
  N: 'n',
  O: 'o',
  R: 'r',
  S: 's',
  U: 'u',

  // Numbers for navigation
  ONE: '1',
  TWO: '2',
  THREE: '3',
  FOUR: '4',

  // Special
  QUESTION: '?',
  SLASH: '/',
  COMMA: ',',

  // Arrow keys
  ARROW_UP: 'ArrowUp',
  ARROW_DOWN: 'ArrowDown',
  ARROW_LEFT: 'ArrowLeft',
  ARROW_RIGHT: 'ArrowRight',
} as const;

/**
 * Get the display string for a shortcut (for UI)
 */
export function getShortcutDisplay(shortcut: ShortcutConfig): string {
  const parts: string[] = [];

  if (shortcut.ctrl) {
    // Use Cmd symbol on Mac, Ctrl on others
    const isMac = navigator.platform.toLowerCase().includes('mac');
    parts.push(isMac ? '⌘' : 'Ctrl');
  }
  if (shortcut.shift) parts.push('Shift');
  if (shortcut.alt) {
    const isMac = navigator.platform.toLowerCase().includes('mac');
    parts.push(isMac ? '⌥' : 'Alt');
  }

  // Format the key for display
  let keyDisplay = shortcut.key;
  if (keyDisplay === ' ') keyDisplay = 'Space';
  else if (keyDisplay === 'ArrowUp') keyDisplay = '↑';
  else if (keyDisplay === 'ArrowDown') keyDisplay = '↓';
  else if (keyDisplay === 'ArrowLeft') keyDisplay = '←';
  else if (keyDisplay === 'ArrowRight') keyDisplay = '→';
  else if (keyDisplay.length === 1) keyDisplay = keyDisplay.toUpperCase();

  parts.push(keyDisplay);

  return parts.join('+');
}
