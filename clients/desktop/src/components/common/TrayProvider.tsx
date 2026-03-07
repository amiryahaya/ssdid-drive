import { useTray } from '@/hooks/useTray';

/**
 * TrayProvider component that initializes system tray integration.
 * Should be placed inside ProtectedRoute so it only runs when authenticated.
 *
 * This component:
 * - Syncs recent files to the tray menu
 * - Syncs notification count to the tray
 * - Listens for tray menu events and handles navigation
 */
export function TrayProvider() {
  // Initialize tray integration - this hook handles all the tray state syncing
  useTray();

  // This is a side-effect only provider, no UI
  return null;
}
