import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { listen } from '@tauri-apps/api/event';
import { open } from '@tauri-apps/plugin-shell';
import { Loader2, Globe } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';
import { Button } from '@/components/ui/Button';

interface OidcProviderButtonsProps {
  tenantSlug?: string;
}

export function OidcProviderButtons({ tenantSlug }: OidcProviderButtonsProps) {
  const navigate = useNavigate();
  const {
    providers,
    isLoadingProviders,
    isLoading,
    loginWithOidc,
    handleOidcCallback,
    loadProviders,
  } = useAuthStore();

  // Load providers on mount
  useEffect(() => {
    if (tenantSlug) {
      loadProviders(tenantSlug);
    }
  }, [tenantSlug, loadProviders]);

  // Listen for OIDC callback deep-link events
  useEffect(() => {
    let unlistenFn: (() => void) | undefined;

    const setupListener = async () => {
      unlistenFn = await listen<{ code: string; state: string }>(
        'oidc-callback',
        async (event) => {
          const { code, state } = event.payload;
          try {
            const response = await handleOidcCallback(code, state);
            if (response.status === 'authenticated') {
              navigate('/files');
            } else if (response.status === 'new_user') {
              // Navigate to OIDC registration with key material
              navigate('/register', {
                state: {
                  oidc: true,
                  keyMaterial: response.key_material,
                  keySalt: response.key_salt,
                },
              });
            }
          } catch (err) {
            console.error('OIDC callback failed:', err);
          }
        }
      );
    };

    setupListener();
    return () => unlistenFn?.();
  }, [handleOidcCallback, navigate]);

  const handleOidcLogin = async (providerId: string) => {
    try {
      const authUrl = await loginWithOidc(providerId);
      // Open authorization URL in system browser
      await open(authUrl);
    } catch (err) {
      console.error('OIDC login failed:', err);
    }
  };

  // Filter to only OIDC providers
  const oidcProviders = (providers ?? []).filter(
    (p) => p.provider_type === 'oidc' && p.enabled
  );

  if (isLoadingProviders || oidcProviders.length === 0) {
    return null;
  }

  return (
    <div className="space-y-3">
      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-card px-2 text-muted-foreground">
            Or continue with
          </span>
        </div>
      </div>

      {oidcProviders.map((provider) => (
        <Button
          key={provider.id}
          type="button"
          variant="outline"
          className="w-full"
          disabled={isLoading}
          onClick={() => handleOidcLogin(provider.id)}
        >
          {isLoading ? (
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
          ) : (
            <Globe className="mr-2 h-4 w-4" />
          )}
          {provider.name}
        </Button>
      ))}
    </div>
  );
}
