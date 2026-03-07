import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { listen } from '@tauri-apps/api/event';
import { useAuthStore } from '@/stores/authStore';
import { useToast } from './useToast';

/**
 * Deep link URL structure:
 * - securesharing://invite/{token} - Accept a tenant invitation
 * - securesharing://share/{shareId} - Open a shared file/folder
 * - securesharing://recovery/{requestId} - Handle recovery request
 * - securesharing://file/{fileId} - Open a specific file
 * - securesharing://folder/{folderId} - Open a specific folder
 */

interface DeepLinkPayload {
  urls: string[];
}

interface ParsedDeepLink {
  action: 'invite' | 'share' | 'recovery' | 'file' | 'folder' | 'oidc-callback' | 'unknown';
  id: string;
  params?: Record<string, string>;
}

/**
 * Parse a deep link URL into action and parameters
 */
function parseDeepLink(url: string): ParsedDeepLink {
  try {
    // Remove the protocol prefix
    const withoutProtocol = url.replace(/^securesharing:\/\//, '');
    const [path, queryString] = withoutProtocol.split('?');
    const segments = path.split('/').filter(Boolean);

    // Parse query parameters
    const params: Record<string, string> = {};
    if (queryString) {
      const searchParams = new URLSearchParams(queryString);
      searchParams.forEach((value, key) => {
        params[key] = value;
      });
    }

    if (segments.length < 2) {
      return { action: 'unknown', id: '', params };
    }

    const [action, id] = segments;

    switch (action) {
      case 'invite':
      case 'share':
      case 'recovery':
      case 'file':
      case 'folder':
        return { action, id, params };
      case 'oidc':
        // OIDC callback: securesharing://oidc/callback?code=X&state=Y
        return { action: 'oidc-callback', id: segments[1] ?? '', params };
      default:
        return { action: 'unknown', id: '', params };
    }
  } catch (error) {
    console.error('Failed to parse deep link:', error);
    return { action: 'unknown', id: '' };
  }
}

/**
 * Hook to handle deep links in the desktop app.
 *
 * Supports the following URL schemes:
 * - securesharing://invite/{token} - Accept tenant invitation
 * - securesharing://share/{shareId} - View shared item
 * - securesharing://recovery/{requestId} - Handle recovery request
 * - securesharing://file/{fileId} - Open file
 * - securesharing://folder/{folderId} - Open folder
 */
export function useDeepLink() {
  const navigate = useNavigate();
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const { success, error: showError, info } = useToast();

  const handleDeepLink = useCallback(
    async (url: string) => {
      console.log('Handling deep link:', url);

      const parsed = parseDeepLink(url);
      console.log('Parsed deep link:', parsed);

      // Check if user needs to authenticate first
      if (!isAuthenticated && parsed.action !== 'invite') {
        info({
          title: 'Authentication required',
          description: 'Please log in to access this link',
        });
        // Store the deep link to handle after login
        sessionStorage.setItem('pendingDeepLink', url);
        navigate('/login');
        return;
      }

      switch (parsed.action) {
        case 'invite':
          // Handle tenant invitation
          // The invite token should be handled by the registration or a special accept page
          info({
            title: 'Invitation link detected',
            description: 'Processing your invitation...',
          });
          // Navigate to register with the invitation token
          navigate(`/register?invite=${parsed.id}`);
          break;

        case 'share':
          // Navigate to shared-with-me and highlight the specific share
          success({
            title: 'Opening shared item',
            description: 'Navigating to the shared file...',
          });
          navigate('/shared-with-me', { state: { highlightShare: parsed.id } });
          break;

        case 'recovery':
          // Navigate to settings with the recovery section open
          info({
            title: 'Recovery request',
            description: 'Opening recovery section...',
          });
          navigate('/settings', { state: { section: 'recovery', requestId: parsed.id } });
          break;

        case 'file':
          // Navigate directly to the file (will trigger preview)
          navigate('/files', { state: { openFile: parsed.id } });
          break;

        case 'folder':
          // Navigate to the specific folder
          navigate(`/files/${parsed.id}`);
          break;

        case 'oidc-callback':
          // OIDC callback is handled by OidcProviderButtons via the 'oidc-callback' event
          // The deep-link listener in lib.rs emits 'oidc-callback' directly
          console.log('OIDC callback received via deep link');
          break;

        case 'unknown':
        default:
          showError({
            title: 'Invalid link',
            description: 'The link you clicked is not recognized',
          });
          break;
      }
    },
    [isAuthenticated, navigate, success, showError, info]
  );

  // Handle pending deep link after authentication
  useEffect(() => {
    if (isAuthenticated) {
      const pendingLink = sessionStorage.getItem('pendingDeepLink');
      if (pendingLink) {
        sessionStorage.removeItem('pendingDeepLink');
        handleDeepLink(pendingLink);
      }
    }
  }, [isAuthenticated, handleDeepLink]);

  // Listen for deep link events from Tauri
  useEffect(() => {
    let unlistenFn: (() => void) | undefined;

    const setupListener = async () => {
      try {
        // Listen for deep-link events
        unlistenFn = await listen<DeepLinkPayload>('deep-link://new-url', (event) => {
          console.log('Deep link event received:', event.payload);
          const urls = event.payload.urls;
          if (urls && urls.length > 0) {
            // Handle the first URL (typically only one)
            handleDeepLink(urls[0]);
          }
        });
      } catch (error) {
        console.error('Failed to setup deep link listener:', error);
      }
    };

    setupListener();

    return () => {
      if (unlistenFn) {
        unlistenFn();
      }
    };
  }, [handleDeepLink]);

  return {
    handleDeepLink,
    parseDeepLink,
  };
}
