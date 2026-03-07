import { useState } from 'react';
import { Shield, Eye, EyeOff, Loader2, Fingerprint, LogOut } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';
import { useBiometric } from '@/hooks/useBiometric';
import { Button } from '@/components/ui/Button';

export function UnlockScreen() {
  const { user, unlock, unlockWithBiometric, logout, isLoading, error, clearError } =
    useAuthStore();
  const { isAvailable: biometricAvailable, isEnabled: biometricEnabled, biometricType } =
    useBiometric();

  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await unlock(password);
    } catch (err) {
      // Error is handled by store
    }
  };

  const handleBiometricUnlock = async () => {
    try {
      await unlockWithBiometric();
    } catch (err) {
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
            {user?.email || 'Enter your password to unlock'}
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

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-2">Password</label>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full px-4 py-2 pr-10 border rounded-lg bg-background focus:outline-none focus:ring-2 focus:ring-primary"
                placeholder="Enter your password"
                required
                autoFocus
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                {showPassword ? (
                  <EyeOff className="h-4 w-4" />
                ) : (
                  <Eye className="h-4 w-4" />
                )}
              </button>
            </div>
          </div>

          <Button type="submit" className="w-full" disabled={isLoading}>
            {isLoading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Unlocking...
              </>
            ) : (
              'Unlock'
            )}
          </Button>
        </form>

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
