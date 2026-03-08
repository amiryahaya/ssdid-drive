import { useEffect, useState, useRef, createContext, useContext, ReactNode } from 'react';

type Politeness = 'polite' | 'assertive';

interface LiveRegionContextValue {
  announce: (message: string, politeness?: Politeness) => void;
}

const LiveRegionContext = createContext<LiveRegionContextValue | null>(null);

/**
 * Hook to announce messages to screen readers.
 * Must be used within a LiveRegionProvider.
 */
// eslint-disable-next-line react-refresh/only-export-components
export function useAnnounce() {
  const context = useContext(LiveRegionContext);
  if (!context) {
    throw new Error('useAnnounce must be used within a LiveRegionProvider');
  }
  return context.announce;
}

interface LiveRegionProviderProps {
  children: ReactNode;
}

/**
 * Provider component for screen reader announcements.
 * Renders hidden live regions that screen readers will announce.
 */
export function LiveRegionProvider({ children }: LiveRegionProviderProps) {
  const [politeMessage, setPoliteMessage] = useState('');
  const [assertiveMessage, setAssertiveMessage] = useState('');
  const timeoutRef = useRef<number>();

  const announce = (message: string, politeness: Politeness = 'polite') => {
    // Clear any pending timeout
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }

    // Set the appropriate message
    if (politeness === 'assertive') {
      setAssertiveMessage(message);
    } else {
      setPoliteMessage(message);
    }

    // Clear the message after a short delay to allow repeated announcements
    timeoutRef.current = window.setTimeout(() => {
      setPoliteMessage('');
      setAssertiveMessage('');
    }, 1000);
  };

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  return (
    <LiveRegionContext.Provider value={{ announce }}>
      {children}
      {/* Visually hidden live regions for screen reader announcements */}
      <div
        role="status"
        aria-live="polite"
        aria-atomic="true"
        className="sr-only"
      >
        {politeMessage}
      </div>
      <div
        role="alert"
        aria-live="assertive"
        aria-atomic="true"
        className="sr-only"
      >
        {assertiveMessage}
      </div>
    </LiveRegionContext.Provider>
  );
}
