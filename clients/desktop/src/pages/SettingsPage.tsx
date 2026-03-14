import { useEffect } from 'react';
import {
  Moon,
  Sun,
  Monitor,
  Lock,
  Bell,
  BellRing,
  BellOff,
  HardDrive,
  Fingerprint,
  Loader2,
  CheckCircle2,
  XCircle,
  AlertCircle,
  Smartphone,
  Info,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { RecoveryStatusCard } from '@/components/recovery/RecoveryStatusCard';
import { PendingRecoveryRequests } from '@/components/recovery/PendingRecoveryRequests';
import { ProfileSection, DevicesList } from '@/components/settings';
import { LinkedLoginsSection } from '@/components/settings/LinkedLoginsSection';
import { useSettingsStore } from '@/stores/settingsStore';
import { usePushPermission } from '@/hooks/usePushPermission';
import { useBiometric } from '@/hooks/useBiometric';
import { formatBytes } from '@/lib/utils';
import { useToast } from '@/hooks/useToast';

export function SettingsPage() {
  const {
    settings,
    storageInfo,
    isLoading,
    isSaving,
    loadSettings,
    loadStorageInfo,
    setTheme,
    setAutoLockTimeout,
    setNotificationsEnabled,
    clearCache,
  } = useSettingsStore();

  const { theme, autoLockTimeout, notificationsEnabled } = settings;
  const { success, error: showError } = useToast();
  const {
    status: pushStatus,
    isLoading: isPushLoading,
    requestPermission: requestPushPermission,
  } = usePushPermission();
  const {
    isAvailable: biometricAvailable,
    isEnabled: biometricEnabled,
    biometricType,
    message: biometricMessage,
    isLoading: isBiometricLoading,
    enable: enableBiometric,
    disable: disableBiometric,
    status: biometricStatus,
  } = useBiometric();
  useEffect(() => {
    loadSettings();
    loadStorageInfo();
  }, [loadSettings, loadStorageInfo]);

  return (
    <div className="max-w-2xl space-y-8">
      <div>
        <h1 className="text-2xl font-bold">Settings</h1>
        <p className="text-muted-foreground mt-1">
          Manage your application preferences
        </p>
      </div>

      {/* Account */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Account</h2>
        <ProfileSection />
      </div>

      {/* Linked Logins */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Linked Logins</h2>
        <LinkedLoginsSection />
      </div>

      {/* Devices */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold flex items-center gap-2">
          <Smartphone className="h-5 w-5" />
          Devices
        </h2>
        <DevicesList />
      </div>

      {/* Appearance */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Appearance</h2>
        <div className="flex gap-4">
          <button
            onClick={() => setTheme('light')}
            disabled={isSaving}
            className={`flex flex-col items-center p-4 rounded-lg border-2 transition-colors ${
              theme === 'light' ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/50'
            } ${isSaving ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            <Sun className="h-8 w-8 mb-2" />
            <span className="text-sm">Light</span>
          </button>
          <button
            onClick={() => setTheme('dark')}
            disabled={isSaving}
            className={`flex flex-col items-center p-4 rounded-lg border-2 transition-colors ${
              theme === 'dark' ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/50'
            } ${isSaving ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            <Moon className="h-8 w-8 mb-2" />
            <span className="text-sm">Dark</span>
          </button>
          <button
            onClick={() => setTheme('system')}
            disabled={isSaving}
            className={`flex flex-col items-center p-4 rounded-lg border-2 transition-colors ${
              theme === 'system' ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/50'
            } ${isSaving ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            <Monitor className="h-8 w-8 mb-2" />
            <span className="text-sm">System</span>
          </button>
        </div>
      </div>

      {/* Security */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Security</h2>

        <div className="flex items-center justify-between p-4 rounded-lg border">
          <div className="flex items-center gap-4">
            <Lock className="h-5 w-5 text-muted-foreground" />
            <div>
              <p className="font-medium">Auto-lock</p>
              <p className="text-sm text-muted-foreground">
                Lock the app after inactivity
              </p>
            </div>
          </div>
          <select
            value={autoLockTimeout}
            onChange={(e) => setAutoLockTimeout(Number(e.target.value))}
            disabled={isSaving}
            className="px-3 py-2 rounded-lg border bg-background disabled:opacity-50"
          >
            <option value={0}>Never</option>
            <option value={60}>1 minute</option>
            <option value={300}>5 minutes</option>
            <option value={900}>15 minutes</option>
            <option value={1800}>30 minutes</option>
          </select>
        </div>

        {/* Biometric - only show if available or if device has hardware but not configured */}
        {(biometricAvailable || biometricStatus?.availability === 'not_configured') && (
          <div className="flex items-center justify-between p-4 rounded-lg border">
            <div className="flex items-center gap-4">
              <Fingerprint className={`h-5 w-5 ${biometricAvailable ? 'text-muted-foreground' : 'text-amber-500'}`} />
              <div>
                <p className="font-medium">
                  {biometricType || 'Biometric'} Unlock
                </p>
                <p className="text-sm text-muted-foreground">
                  {biometricAvailable
                    ? `Use ${biometricType || 'biometric'} to unlock the app`
                    : biometricMessage}
                </p>
              </div>
            </div>
            {isBiometricLoading ? (
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            ) : biometricAvailable ? (
              <button
                onClick={async () => {
                  if (biometricEnabled) {
                    await disableBiometric();
                    success({ title: 'Biometric disabled', description: `${biometricType || 'Biometric'} unlock has been disabled` });
                  } else {
                    const enabled = await enableBiometric();
                    if (enabled) {
                      success({ title: 'Biometric enabled', description: `${biometricType || 'Biometric'} unlock has been enabled` });
                    } else {
                      showError({ title: 'Failed to enable biometric', description: 'Please try again' });
                    }
                  }
                }}
                disabled={isSaving}
                className={`w-12 h-6 rounded-full transition-colors ${
                  biometricEnabled ? 'bg-primary' : 'bg-muted'
                } ${isSaving ? 'opacity-50 cursor-not-allowed' : ''}`}
              >
                <div
                  className={`w-5 h-5 rounded-full bg-white shadow transition-transform ${
                    biometricEnabled ? 'translate-x-6' : 'translate-x-0.5'
                  }`}
                />
              </button>
            ) : (
              <span className="flex items-center gap-1 text-sm text-amber-600 dark:text-amber-400">
                <Info className="h-4 w-4" />
                Setup required
              </span>
            )}
          </div>
        )}

        {/* Show message when biometric is not available at all */}
        {!isBiometricLoading && !biometricAvailable && biometricStatus?.availability !== 'not_configured' && (
          <div className="flex items-center justify-between p-4 rounded-lg border opacity-60">
            <div className="flex items-center gap-4">
              <Fingerprint className="h-5 w-5 text-muted-foreground" />
              <div>
                <p className="font-medium">Biometric Unlock</p>
                <p className="text-sm text-muted-foreground">
                  {biometricMessage || 'Not available on this device'}
                </p>
              </div>
            </div>
            <span className="text-sm text-muted-foreground">Not available</span>
          </div>
        )}
      </div>

      {/* Recovery */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Account Recovery</h2>
        <PendingRecoveryRequests />
        <RecoveryStatusCard />
      </div>

      {/* Notifications */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Notifications</h2>

        {/* Push Permission Status */}
        <div className="p-4 rounded-lg border">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              {pushStatus === 'granted' ? (
                <BellRing className="h-5 w-5 text-green-500" />
              ) : pushStatus === 'denied' ? (
                <BellOff className="h-5 w-5 text-destructive" />
              ) : (
                <Bell className="h-5 w-5 text-muted-foreground" />
              )}
              <div>
                <p className="font-medium">Push Notifications</p>
                <p className="text-sm text-muted-foreground">
                  {pushStatus === 'granted'
                    ? 'Push notifications are enabled'
                    : pushStatus === 'denied'
                    ? 'Push notifications are blocked'
                    : pushStatus === 'unsupported'
                    ? 'Push notifications are not supported'
                    : 'Enable push notifications for shares and updates'}
                </p>
              </div>
            </div>

            {/* Permission Status Badge */}
            <div className="flex items-center gap-2">
              {isPushLoading ? (
                <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
              ) : pushStatus === 'granted' ? (
                <span className="flex items-center gap-1 text-sm text-green-600 dark:text-green-400">
                  <CheckCircle2 className="h-4 w-4" />
                  Enabled
                </span>
              ) : pushStatus === 'denied' ? (
                <span className="flex items-center gap-1 text-sm text-destructive">
                  <XCircle className="h-4 w-4" />
                  Blocked
                </span>
              ) : pushStatus === 'unsupported' ? (
                <span className="flex items-center gap-1 text-sm text-muted-foreground">
                  <AlertCircle className="h-4 w-4" />
                  Unsupported
                </span>
              ) : (
                <Button
                  size="sm"
                  onClick={async () => {
                    const granted = await requestPushPermission();
                    if (granted) {
                      success({
                        title: 'Notifications enabled',
                        description: 'You will now receive push notifications',
                      });
                    }
                  }}
                  disabled={isPushLoading}
                >
                  Enable
                </Button>
              )}
            </div>
          </div>

          {/* Help text for blocked state */}
          {pushStatus === 'denied' && (
            <div className="mt-3 p-3 rounded-lg bg-muted/50 text-sm text-muted-foreground">
              <p>
                Push notifications are blocked by your browser. To enable them:
              </p>
              <ol className="list-decimal list-inside mt-2 space-y-1">
                <li>Click the lock/info icon in your browser's address bar</li>
                <li>Find "Notifications" in the permissions</li>
                <li>Change the setting to "Allow"</li>
                <li>Refresh the page</li>
              </ol>
            </div>
          )}
        </div>

        {/* In-App Notifications Toggle */}
        <div className="flex items-center justify-between p-4 rounded-lg border">
          <div className="flex items-center gap-4">
            <Bell className="h-5 w-5 text-muted-foreground" />
            <div>
              <p className="font-medium">In-App Notifications</p>
              <p className="text-sm text-muted-foreground">
                Show notification badge and alerts in the app
              </p>
            </div>
          </div>
          <button
            onClick={() => setNotificationsEnabled(!notificationsEnabled)}
            disabled={isSaving}
            className={`w-12 h-6 rounded-full transition-colors ${
              notificationsEnabled ? 'bg-primary' : 'bg-muted'
            } ${isSaving ? 'opacity-50 cursor-not-allowed' : ''}`}
          >
            <div
              className={`w-5 h-5 rounded-full bg-white shadow transition-transform ${
                notificationsEnabled ? 'translate-x-6' : 'translate-x-0.5'
              }`}
            />
          </button>
        </div>
      </div>

      {/* Storage */}
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Storage</h2>

        <div className="p-4 rounded-lg border">
          <div className="flex items-center gap-4 mb-4">
            <HardDrive className="h-5 w-5 text-muted-foreground" />
            <div>
              <p className="font-medium">Local Cache</p>
              <p className="text-sm text-muted-foreground">
                {storageInfo
                  ? `${formatBytes(storageInfo.cacheSize)} used for offline access`
                  : 'Loading storage info...'}
              </p>
            </div>
          </div>
          <Button
            variant="outline"
            size="sm"
            disabled={isLoading}
            onClick={async () => {
              try {
                await clearCache();
                success({ title: 'Cache cleared', description: 'Local cache has been cleared' });
              } catch (err) {
                showError({ title: 'Failed to clear cache', description: String(err) });
              }
            }}
          >
            {isLoading ? (
              <>
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                Clearing...
              </>
            ) : (
              'Clear Cache'
            )}
          </Button>
        </div>
      </div>

    </div>
  );
}
