import { useState, useEffect } from 'react';
import { ShieldAlert, X } from 'lucide-react';
import { tauriService } from '../../services/tauri';

interface RecoveryBannerProps {
  onSetupClick: () => void;
}

export function RecoveryBanner({ onSetupClick }: RecoveryBannerProps) {
  const [visible, setVisible] = useState(false);
  const [dismissCount, setDismissCount] = useState(0);
  const [canDismiss, setCanDismiss] = useState(true);

  useEffect(() => {
    checkRecoveryStatus();
  }, []);

  async function checkRecoveryStatus() {
    try {
      const status = await tauriService.getRecoveryStatus();
      if (!status.is_active) {
        setVisible(true);
        const count = parseInt(localStorage.getItem('recovery_dismiss_count') || '0');
        setDismissCount(count);
        setCanDismiss(count < 3);
      }
    } catch {
      // Not authenticated yet or error — don't show
    }
  }

  function handleDismiss() {
    const newCount = dismissCount + 1;
    localStorage.setItem('recovery_dismiss_count', String(newCount));
    setDismissCount(newCount);
    if (newCount >= 3) {
      setCanDismiss(false);
    } else {
      setVisible(false);
    }
  }

  if (!visible) return null;

  return (
    <div className="bg-red-900/80 border border-red-700 text-red-100 px-4 py-3 flex items-center gap-3">
      <ShieldAlert className="h-5 w-5 flex-shrink-0 text-red-400" />
      <p className="flex-1 text-sm font-medium">
        Your files are at risk. If you lose this device, your encrypted files will be
        permanently unrecoverable.
      </p>
      <button
        onClick={onSetupClick}
        className="bg-red-600 hover:bg-red-500 text-white px-4 py-1.5 rounded text-sm font-medium whitespace-nowrap"
      >
        Set Up Recovery
      </button>
      {canDismiss && (
        <button onClick={handleDismiss} className="text-red-400 hover:text-red-300">
          <X className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}
