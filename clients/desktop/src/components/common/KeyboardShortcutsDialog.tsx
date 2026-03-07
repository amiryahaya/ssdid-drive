import { useEffect, useState, useMemo } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';

interface ShortcutItem {
  keys: string[];
  description: string;
}

interface ShortcutSection {
  title: string;
  shortcuts: ShortcutItem[];
}

// Detect if running on macOS
const isMac = typeof navigator !== 'undefined' && navigator.platform.toLowerCase().includes('mac');
const modKey = isMac ? '⌘' : 'Ctrl';
const altKey = isMac ? '⌥' : 'Alt';

const getShortcutSections = (): ShortcutSection[] => [
  {
    title: 'Navigation',
    shortcuts: [
      { keys: [modKey, '1'], description: 'Go to Files' },
      { keys: [modKey, '2'], description: 'Go to Shared with Me' },
      { keys: [modKey, '3'], description: 'Go to My Shares' },
      { keys: [modKey, '4'], description: 'Go to Settings' },
      { keys: [modKey, ','], description: 'Open Settings' },
      { keys: [altKey, '←'], description: 'Go back' },
    ],
  },
  {
    title: 'Search',
    shortcuts: [
      { keys: [modKey, 'F'], description: 'Focus search' },
      { keys: ['/'], description: 'Focus search' },
    ],
  },
  {
    title: 'File Actions',
    shortcuts: [
      { keys: ['Enter'], description: 'Open selected item' },
      { keys: [modKey, 'O'], description: 'Open selected item' },
      { keys: [modKey, 'U'], description: 'Upload files' },
      { keys: [modKey, 'Shift', 'N'], description: 'New folder' },
      { keys: [modKey, 'D'], description: 'Download selected file' },
      { keys: [modKey, 'Shift', 'S'], description: 'Share selected item' },
      { keys: ['F2'], description: 'Rename selected item' },
      { keys: ['Del'], description: 'Delete selected items' },
    ],
  },
  {
    title: 'Selection',
    shortcuts: [
      { keys: [modKey, 'A'], description: 'Select all items' },
      { keys: ['Esc'], description: 'Clear selection' },
      { keys: [modKey, 'Click'], description: 'Toggle selection' },
    ],
  },
  {
    title: 'View',
    shortcuts: [
      { keys: [modKey, 'G'], description: 'Grid view' },
      { keys: [modKey, 'L'], description: 'List view' },
    ],
  },
  {
    title: 'Help',
    shortcuts: [
      { keys: ['?'], description: 'Show keyboard shortcuts' },
    ],
  },
];

function ShortcutKey({ children }: { children: string }) {
  return (
    <kbd className="inline-flex items-center justify-center px-2 py-1 min-w-[24px] text-xs font-semibold bg-muted border border-border rounded">
      {children}
    </kbd>
  );
}

export function KeyboardShortcutsDialog() {
  const [open, setOpen] = useState(false);
  const shortcutSections = useMemo(() => getShortcutSections(), []);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      // Don't trigger when typing in input fields
      const target = event.target as HTMLElement;
      if (
        target.tagName === 'INPUT' ||
        target.tagName === 'TEXTAREA' ||
        target.isContentEditable
      ) {
        return;
      }

      if (event.key === '?' && !event.ctrlKey && !event.metaKey && !event.altKey) {
        event.preventDefault();
        setOpen(true);
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="sm:max-w-lg max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Keyboard Shortcuts</DialogTitle>
        </DialogHeader>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 py-4">
          {shortcutSections.map((section) => (
            <div key={section.title}>
              <h3 className="text-sm font-semibold text-primary mb-2">
                {section.title}
              </h3>
              <div className="space-y-1.5">
                {section.shortcuts.map((shortcut, index) => (
                  <div
                    key={index}
                    className="flex items-center justify-between gap-2"
                  >
                    <span className="text-sm text-muted-foreground truncate">
                      {shortcut.description}
                    </span>
                    <div className="flex items-center gap-0.5 flex-shrink-0">
                      {shortcut.keys.map((key, keyIndex) => (
                        <span key={keyIndex} className="flex items-center">
                          <ShortcutKey>{key}</ShortcutKey>
                          {keyIndex < shortcut.keys.length - 1 && (
                            <span className="text-muted-foreground text-xs mx-0.5">+</span>
                          )}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
        <div className="text-xs text-muted-foreground text-center border-t pt-3">
          Press <ShortcutKey>Esc</ShortcutKey> to close
        </div>
      </DialogContent>
    </Dialog>
  );
}
