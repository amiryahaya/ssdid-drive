import { useEffect, useState } from 'react';
import {
  Loader2,
  Smartphone,
  Monitor,
  Laptop,
  Tablet,
  Trash2,
  CheckCircle2,
  Clock,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Skeleton } from '@/components/ui/Skeleton';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { useAuthStore, type Device } from '@/stores/authStore';
import { useToast } from '@/hooks/useToast';

function getDeviceIcon(deviceType: string) {
  const type = deviceType.toLowerCase();
  if (type.includes('mobile') || type.includes('phone')) {
    return Smartphone;
  }
  if (type.includes('tablet')) {
    return Tablet;
  }
  if (type.includes('laptop')) {
    return Laptop;
  }
  return Monitor;
}

function formatLastActive(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / (1000 * 60));
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffMins < 1) {
    return 'Just now';
  }
  if (diffMins < 60) {
    return `${diffMins} minute${diffMins > 1 ? 's' : ''} ago`;
  }
  if (diffHours < 24) {
    return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
  }
  if (diffDays < 7) {
    return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
  }
  return date.toLocaleDateString();
}

function DeviceCard({
  device,
  onRevoke,
}: {
  device: Device;
  onRevoke: (device: Device) => void;
}) {
  const Icon = getDeviceIcon(device.device_type);

  return (
    <div
      className={`flex items-center justify-between p-4 rounded-lg border ${
        device.is_current ? 'border-primary bg-primary/5' : ''
      }`}
    >
      <div className="flex items-center gap-4">
        <div
          className={`flex items-center justify-center h-10 w-10 rounded-lg ${
            device.is_current ? 'bg-primary/20 text-primary' : 'bg-muted text-muted-foreground'
          }`}
        >
          <Icon className="h-5 w-5" />
        </div>
        <div>
          <div className="flex items-center gap-2">
            <p className="font-medium">
              {device.name || device.device_type}
            </p>
            {device.is_current && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-primary/20 text-primary">
                <CheckCircle2 className="h-3 w-3" />
                Current
              </span>
            )}
          </div>
          <div className="flex items-center gap-1 text-sm text-muted-foreground">
            <Clock className="h-3 w-3" />
            <span>Last active: {formatLastActive(device.last_active)}</span>
          </div>
        </div>
      </div>

      {!device.is_current && (
        <Button
          variant="ghost"
          size="sm"
          onClick={() => onRevoke(device)}
          className="text-destructive hover:text-destructive hover:bg-destructive/10"
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      )}
    </div>
  );
}

function DeviceCardSkeleton() {
  return (
    <div className="flex items-center justify-between p-4 rounded-lg border">
      <div className="flex items-center gap-4">
        <Skeleton className="h-10 w-10 rounded-lg" />
        <div className="space-y-2">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-3 w-24" />
        </div>
      </div>
    </div>
  );
}

export function DevicesList() {
  const { devices, isLoadingDevices, loadDevices, revokeDevice } = useAuthStore();
  const [deviceToRevoke, setDeviceToRevoke] = useState<Device | null>(null);
  const [isRevoking, setIsRevoking] = useState(false);
  const { success, error: showError } = useToast();

  useEffect(() => {
    loadDevices();
  }, [loadDevices]);

  const handleRevoke = async () => {
    if (!deviceToRevoke) return;

    setIsRevoking(true);
    try {
      await revokeDevice(deviceToRevoke.id);
      success({
        title: 'Device removed',
        description: `${deviceToRevoke.name || deviceToRevoke.device_type} has been logged out`,
      });
      setDeviceToRevoke(null);
    } catch (err) {
      showError({
        title: 'Failed to remove device',
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setIsRevoking(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-muted-foreground">
            Manage devices where you're logged in. Removing a device will log it out.
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => loadDevices()}
          disabled={isLoadingDevices}
        >
          {isLoadingDevices ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            'Refresh'
          )}
        </Button>
      </div>

      <div className="space-y-2">
        {isLoadingDevices && (!devices || devices.length === 0) ? (
          <>
            <DeviceCardSkeleton />
            <DeviceCardSkeleton />
          </>
        ) : !devices || devices.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">
            No devices found
          </div>
        ) : (
          devices.map((device) => (
            <DeviceCard
              key={device.id}
              device={device}
              onRevoke={setDeviceToRevoke}
            />
          ))
        )}
      </div>

      {/* Revoke Confirmation Dialog */}
      <Dialog open={!!deviceToRevoke} onOpenChange={(open) => !open && setDeviceToRevoke(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Remove Device</DialogTitle>
            <DialogDescription>
              Are you sure you want to remove{' '}
              <strong>{deviceToRevoke?.name || deviceToRevoke?.device_type}</strong>? This will log
              out the device and it will need to sign in again.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDeviceToRevoke(null)}
              disabled={isRevoking}
            >
              Cancel
            </Button>
            <Button variant="destructive" onClick={handleRevoke} disabled={isRevoking}>
              {isRevoking ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Removing...
                </>
              ) : (
                'Remove Device'
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
