import { WifiOff, Wifi, X } from 'lucide-react';
import { useOnlineStatus } from '@/hooks/useOnlineStatus';
import { useState, useEffect } from 'react';

export function OfflineBanner() {
  const { isOnline, wasOffline } = useOnlineStatus();
  const [showReconnected, setShowReconnected] = useState(false);

  useEffect(() => {
    if (wasOffline && isOnline) {
      setShowReconnected(true);
      const timer = setTimeout(() => setShowReconnected(false), 3000);
      return () => clearTimeout(timer);
    }
  }, [wasOffline, isOnline]);

  if (isOnline && !showReconnected) {
    return null;
  }

  return (
    <div
      role="alert"
      aria-live="polite"
      className={`fixed top-0 left-0 right-0 z-50 px-4 py-2 text-sm font-medium flex items-center justify-center gap-2 transition-colors ${
        isOnline
          ? 'bg-green-500 text-white'
          : 'bg-amber-500 text-amber-950'
      }`}
    >
      {isOnline ? (
        <>
          <Wifi className="h-4 w-4" />
          <span>Back online - syncing changes...</span>
        </>
      ) : (
        <>
          <WifiOff className="h-4 w-4" />
          <span>You're offline. Some features may be unavailable.</span>
        </>
      )}
      {showReconnected && (
        <button
          onClick={() => setShowReconnected(false)}
          className="ml-2 p-0.5 rounded hover:bg-white/20"
          aria-label="Dismiss"
        >
          <X className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}
