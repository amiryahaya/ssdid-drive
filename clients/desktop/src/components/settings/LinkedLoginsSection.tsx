import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/Button';
import { tauriService } from '@/services/tauri';
import type { LinkedLogin } from '@/services/tauri';
import { Loader2, Trash2, Plus, Mail, Globe } from 'lucide-react';
import { useToast } from '@/hooks/useToast';

export function LinkedLoginsSection() {
  const [logins, setLogins] = useState<LinkedLogin[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { success, error: showError } = useToast();

  useEffect(() => {
    loadLogins();
  }, []);

  const loadLogins = async () => {
    setIsLoading(true);
    try {
      const result = await tauriService.listLogins();
      setLogins(result);
    } catch {
      // API may not be implemented yet
    } finally {
      setIsLoading(false);
    }
  };

  const handleUnlink = async (login: LinkedLogin) => {
    if (logins.length <= 1) {
      showError({ title: 'Cannot remove', description: 'You must have at least one login method' });
      return;
    }
    try {
      await tauriService.unlinkLogin(login.id);
      success({ title: 'Login removed', description: `${login.provider} login has been removed` });
      await loadLogins();
    } catch (e) {
      showError({ title: 'Failed to remove login', description: String(e) });
    }
  };

  const handleAddOidc = async (provider: 'google' | 'microsoft') => {
    try {
      await tauriService.oidcLogin(provider);
      // Browser opens — linking continues via deep link callback
    } catch (e) {
      showError({ title: 'Failed to open browser', description: String(e) });
    }
  };

  const providerIcon = (provider: string) => {
    switch (provider.toLowerCase()) {
      case 'email':
        return <Mail className="h-5 w-5 text-muted-foreground" />;
      default:
        return <Globe className="h-5 w-5 text-muted-foreground" />;
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center py-8">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {logins.map((login) => (
        <div key={login.id} className="flex items-center justify-between p-4 rounded-lg border">
          <div className="flex items-center gap-3">
            {providerIcon(login.provider)}
            <div>
              <p className="font-medium capitalize">{login.provider}</p>
              <p className="text-sm text-muted-foreground">
                {login.email || login.provider_subject}
              </p>
            </div>
          </div>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => handleUnlink(login)}
            disabled={logins.length <= 1}
            title={logins.length <= 1 ? 'Cannot remove last login method' : 'Remove login'}
          >
            <Trash2 className="h-4 w-4 text-muted-foreground" />
          </Button>
        </div>
      ))}

      <div className="flex gap-2 pt-2">
        <Button variant="outline" size="sm" onClick={() => handleAddOidc('google')}>
          <Plus className="h-4 w-4 mr-1" />
          Link Google
        </Button>
        <Button variant="outline" size="sm" onClick={() => handleAddOidc('microsoft')}>
          <Plus className="h-4 w-4 mr-1" />
          Link Microsoft
        </Button>
      </div>
    </div>
  );
}
