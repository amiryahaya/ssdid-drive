import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Shield, Loader2, UserPlus, ArrowLeft, Clock, Users } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { useAuthStore } from '@/stores/authStore';
import { useTenantStore, type TenantRole } from '@/stores/tenantStore';
import { useToast } from '@/hooks/useToast';
import { invoke } from '@tauri-apps/api/core';
import { formatDate } from '@/lib/utils';

interface InvitationPreview {
  id: string;
  tenant_name: string;
  role: TenantRole;
  short_code: string;
  expires_at: string | null;
}

async function getApiBaseUrl(): Promise<string> {
  try {
    const info = await invoke<{ api_base_url: string }>('get_api_base_url');
    return info.api_base_url;
  } catch {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (import.meta as any).env?.VITE_API_BASE_URL ?? 'http://localhost:5147';
  }
}

async function lookUpInviteCode(code: string): Promise<InvitationPreview> {
  const baseUrl = await getApiBaseUrl();
  const resp = await fetch(`${baseUrl}/api/invitations/code/${encodeURIComponent(code)}`);

  if (!resp.ok) {
    if (resp.status === 404) {
      throw new Error('Invalid invite code. Please check and try again.');
    }
    if (resp.status === 410) {
      throw new Error('This invite code has expired.');
    }
    throw new Error(`Failed to look up invite code (${resp.status})`);
  }

  return resp.json();
}

function getRoleLabel(role: TenantRole): string {
  switch (role) {
    case 'owner':
      return 'Owner';
    case 'admin':
      return 'Admin';
    case 'member':
      return 'Member';
    default:
      return role;
  }
}

export function JoinTenantPage() {
  const navigate = useNavigate();
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const { acceptInvitation, loadTenants } = useTenantStore();
  const { success, error: showError } = useToast();

  const [code, setCode] = useState('');
  const [isLookingUp, setIsLookingUp] = useState(false);
  const [isJoining, setIsJoining] = useState(false);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [preview, setPreview] = useState<InvitationPreview | null>(null);

  const handleCodeChange = (value: string) => {
    // Uppercase and allow alphanumeric + hyphens
    setCode(value.toUpperCase().replace(/[^A-Z0-9-]/g, ''));
    // Clear previous results when code changes
    if (preview) {
      setPreview(null);
    }
    if (lookupError) {
      setLookupError(null);
    }
  };

  const handleLookUp = async () => {
    if (!code.trim()) return;

    setIsLookingUp(true);
    setLookupError(null);
    setPreview(null);

    try {
      const result = await lookUpInviteCode(code.trim());
      setPreview(result);
    } catch (err) {
      setLookupError(err instanceof Error ? err.message : String(err));
    } finally {
      setIsLookingUp(false);
    }
  };

  const handleJoin = async () => {
    if (!preview) return;

    if (!isAuthenticated) {
      // Not logged in: redirect to register with invite context
      navigate(`/register?invite=${encodeURIComponent(preview.short_code)}`);
      return;
    }

    setIsJoining(true);
    try {
      await acceptInvitation(preview.id);
      await loadTenants();
      success({
        title: 'Joined tenant',
        description: `You have joined ${preview.tenant_name} as ${getRoleLabel(preview.role).toLowerCase()}`,
      });
      navigate('/files');
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (message.toLowerCase().includes('already')) {
        showError({
          title: 'Already a member',
          description: `You are already a member of ${preview.tenant_name}`,
        });
      } else {
        showError({
          title: 'Failed to join',
          description: message,
        });
      }
    } finally {
      setIsJoining(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && code.trim() && !isLookingUp) {
      handleLookUp();
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Header */}
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-2xl bg-primary flex items-center justify-center mb-4">
            <UserPlus className="h-10 w-10 text-primary-foreground" />
          </div>
          <h1 className="text-2xl font-bold">Join a Tenant</h1>
          <p className="text-muted-foreground text-sm mt-1">
            Enter your invite code to join an organization
          </p>
        </div>

        {/* Error message */}
        {lookupError && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {lookupError}
          </div>
        )}

        {/* Code input */}
        {!preview && (
          <div className="space-y-4">
            <div>
              <label
                htmlFor="invite-code"
                className="block text-sm font-medium mb-2"
              >
                Invite Code
              </label>
              <input
                id="invite-code"
                type="text"
                value={code}
                onChange={(e) => handleCodeChange(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="ACME-7K9X"
                autoFocus
                className="w-full px-4 py-3 rounded-lg border bg-background text-center text-lg font-mono tracking-widest uppercase placeholder:text-muted-foreground/50 placeholder:tracking-widest focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
              />
            </div>

            <Button
              onClick={handleLookUp}
              disabled={!code.trim() || isLookingUp}
              className="w-full"
            >
              {isLookingUp ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Looking up...
                </>
              ) : (
                'Look Up'
              )}
            </Button>
          </div>
        )}

        {/* Preview card */}
        {preview && (
          <div className="space-y-4">
            <div className="p-4 rounded-lg border bg-muted/30 space-y-3">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center">
                  <Users className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <p className="font-semibold text-lg">{preview.tenant_name}</p>
                  <p className="text-sm text-muted-foreground">
                    Role: <span className="font-medium text-foreground">{getRoleLabel(preview.role)}</span>
                  </p>
                </div>
              </div>

              {preview.expires_at && (
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                  <Clock className="h-4 w-4" />
                  <span>Expires {formatDate(preview.expires_at)}</span>
                </div>
              )}

              <p className="text-sm text-muted-foreground">
                Code: <span className="font-mono">{preview.short_code}</span>
              </p>
            </div>

            <div className="flex gap-3">
              <Button
                variant="outline"
                onClick={() => {
                  setPreview(null);
                  setCode('');
                }}
                className="flex-1"
                disabled={isJoining}
              >
                Cancel
              </Button>
              <Button
                onClick={handleJoin}
                disabled={isJoining}
                className="flex-1"
              >
                {isJoining ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Joining...
                  </>
                ) : isAuthenticated ? (
                  'Join'
                ) : (
                  'Continue'
                )}
              </Button>
            </div>

            {!isAuthenticated && (
              <p className="text-xs text-center text-muted-foreground">
                You will be redirected to register before joining.
              </p>
            )}
          </div>
        )}

        {/* Back links */}
        <div className="mt-6 text-center text-sm">
          {isAuthenticated ? (
            <Link
              to="/files"
              className="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to Files
            </Link>
          ) : (
            <p className="text-muted-foreground">
              <Link to="/login" className="text-primary hover:underline font-medium">
                Sign in
              </Link>
              {' or '}
              <Link to="/register" className="text-primary hover:underline font-medium">
                Register
              </Link>
            </p>
          )}
        </div>

        {/* Footer */}
        <div className="mt-4 text-center text-sm text-muted-foreground">
          <p className="flex items-center justify-center gap-1">
            <Shield className="h-3.5 w-3.5" />
            Protected with post-quantum cryptography
          </p>
        </div>
      </div>
    </div>
  );
}
