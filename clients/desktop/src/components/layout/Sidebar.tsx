import { useEffect } from 'react';
import { NavLink } from 'react-router-dom';
import {
  Files,
  Share2,
  FolderInput,
  Settings,
  Shield,
  Star,
  Bot,
} from 'lucide-react';
import { cn, formatBytes } from '@/lib/utils';
import { useSettingsStore } from '@/stores/settingsStore';
import { useFavoritesStore } from '@/stores/favoritesStore';

const navigation = [
  { name: 'My Files', href: '/files', icon: Files },
  { name: 'Favorites', href: '/favorites', icon: Star },
  { name: 'Shared with Me', href: '/shared-with-me', icon: FolderInput },
  { name: 'My Shares', href: '/my-shares', icon: Share2 },
  { name: 'AI Chat', href: '/pii-chat', icon: Bot },
  { name: 'Settings', href: '/settings', icon: Settings },
];

export function Sidebar() {
  const { storageInfo, loadStorageInfo } = useSettingsStore();
  const favoritesCount = useFavoritesStore((state) => state.favorites.size);

  useEffect(() => {
    loadStorageInfo();
  }, [loadStorageInfo]);

  const usedBytes = storageInfo?.totalUsed ?? 0;
  const quotaBytes = storageInfo?.quota ?? 10 * 1024 * 1024 * 1024; // Default 10GB
  const usagePercent = quotaBytes > 0 ? (usedBytes / quotaBytes) * 100 : 0;

  return (
    <div className="w-64 border-r bg-card flex flex-col">
      {/* Logo */}
      <div className="h-16 flex items-center px-6 border-b">
        <Shield className="h-8 w-8 text-primary" />
        <span className="ml-3 text-xl font-semibold">SSDID Drive</span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-4 py-6 space-y-1">
        {navigation.map((item) => (
          <NavLink
            key={item.name}
            to={item.href}
            className={({ isActive }) =>
              cn(
                'flex items-center px-4 py-3 text-sm font-medium rounded-lg transition-colors',
                isActive
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
              )
            }
          >
            <item.icon className={cn(
              'h-5 w-5 mr-3',
              item.name === 'Favorites' && favoritesCount > 0 && 'text-yellow-500 fill-yellow-500'
            )} />
            <span className="flex-1">{item.name}</span>
            {item.name === 'Favorites' && favoritesCount > 0 && (
              <span className="ml-2 px-2 py-0.5 text-xs rounded-full bg-yellow-500/20 text-yellow-600 dark:text-yellow-400">
                {favoritesCount}
              </span>
            )}
          </NavLink>
        ))}
      </nav>

      {/* Storage usage */}
      <div className="p-4 border-t">
        <div className="flex justify-between text-sm text-muted-foreground mb-2">
          <span>Storage</span>
          <span>{formatBytes(usedBytes)} / {formatBytes(quotaBytes)}</span>
        </div>
        <div className="h-2 bg-muted rounded-full overflow-hidden">
          <div
            className="h-full bg-primary transition-all"
            style={{ width: `${Math.min(usagePercent, 100)}%` }}
          />
        </div>
      </div>
    </div>
  );
}
