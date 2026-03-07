import { Shield, Loader2, Fingerprint, LogOut, Unlock } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';
import { useBiometric } from '@/hooks/useBiometric';
import { Button } from '@/components/ui/Button';

export function UnlockScreen() {
  const { user, unlock, unlockWithBiometric, logout, isLoading, error, clearError } =
    useAuthStore();
  const { isAvailable: biometricAvailable, isEnabled: biometricEnabled, biometricType } =
    useBiometric();

  const handleUnlock = async () => {
    try {
      await unlock();
    } catch {
      // Error is handled by store
    }
  };

  const handleBiometricUnlock = async () => {
    try {
      await unlockWithBiometric();
    } catch {
      // Error is handled by store
    }
  };

  const handleLogout = async () => {
    await logout();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10 backdrop-blur-sm">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-2xl bg-primary flex items-center justify-center mb-4">
            <Shield className="h-10 w-10 text-primary-foreground" />
          </div>
          <h1 className="text-2xl font-bold">Locked</h1>
          <p className="text-muted-foreground text-sm mt-1">
            {user?.email || 'Unlock to continue'}
          </p>
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button
              onClick={clearError}
              className="ml-2 underline hover:no-underline"
            >
              Dismiss
            </button>
          </div>
        )}

        {/* Unlock button */}
        <Button className="w-full" onClick={handleUnlock} disabled={isLoading}>
          {isLoading ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Unlocking...
            </>
          ) : (
            <>
              <Unlock className="mr-2 h-4 w-4" />
              Unlock
            </>
          )}
        </Button>

        {/* Biometric unlock - only show if available and enabled */}
        {biometricAvailable && biometricEnabled && (
          <div className="mt-4">
            <Button
              type="button"
              variant="outline"
              className="w-full"
              onClick={handleBiometricUnlock}
              disabled={isLoading}
            >
              <Fingerprint className="mr-2 h-4 w-4" />
              Unlock with {biometricType || 'Biometrics'}
            </Button>
          </div>
        )}

        {/* Sign out option */}
        <div className="mt-6 text-center">
          <button
            onClick={handleLogout}
            className="text-sm text-muted-foreground hover:text-foreground inline-flex items-center gap-1"
          >
            <LogOut className="h-3 w-3" />
            Sign out and use a different account
          </button>
        </div>
      </div>
    </div>
  );
}
