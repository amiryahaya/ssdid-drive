import { useState, useEffect, useCallback } from 'react';
import { KeyRound, Globe, Trash2, Pencil, Plus, Loader2 } from 'lucide-react';
import { tauriService } from '@/services/tauri';
import { Button } from '@/components/ui/Button';
import type { UserCredential } from '@/types';

export function CredentialManager() {
  const [credentials, setCredentials] = useState<UserCredential[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');
  const [error, setError] = useState<string | null>(null);

  const loadCredentials = useCallback(async () => {
    try {
      setIsLoading(true);
      const creds = await tauriService.listCredentials();
      setCredentials(creds ?? []);
    } catch (err) {
      console.error('Failed to load credentials:', err);
      setError('Failed to load credentials');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadCredentials();
  }, [loadCredentials]);

  const handleRename = async (credentialId: string) => {
    if (!editName.trim()) return;
    try {
      const updated = await tauriService.renameCredential(credentialId, editName.trim());
      setCredentials((prev) =>
        prev.map((c) => (c.id === credentialId ? updated : c))
      );
      setEditingId(null);
      setEditName('');
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
    }
  };

  const handleDelete = async (credentialId: string) => {
    try {
      await tauriService.deleteCredential(credentialId);
      setCredentials((prev) => prev.filter((c) => c.id !== credentialId));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
    }
  };

  const handleAddPasskey = async () => {
    try {
      setIsLoading(true);
      const beginResponse = await tauriService.webauthnAddCredentialBegin();

      const publicKeyOptions = beginResponse.options as unknown as PublicKeyCredentialCreationOptions;
      const credential = await navigator.credentials.create({
        publicKey: publicKeyOptions,
      }) as PublicKeyCredential;

      if (!credential) {
        throw new Error('No credential returned');
      }

      const attestationResponse = credential.response as AuthenticatorAttestationResponse;
      const attestation = {
        id: credential.id,
        rawId: arrayBufferToBase64(credential.rawId),
        type: credential.type,
        response: {
          attestationObject: arrayBufferToBase64(attestationResponse.attestationObject),
          clientDataJSON: arrayBufferToBase64(attestationResponse.clientDataJSON),
        },
      };

      await tauriService.webauthnAddCredentialComplete({
        challenge_id: beginResponse.challenge_id,
        attestation,
        credential_name: 'Desktop Passkey',
      });

      await loadCredentials();
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setError(message);
    } finally {
      setIsLoading(false);
    }
  };

  const getCredentialIcon = (type: string) => {
    if (type === 'webauthn') return <KeyRound className="h-4 w-4" />;
    if (type === 'oidc') return <Globe className="h-4 w-4" />;
    return <KeyRound className="h-4 w-4" />;
  };

  if (isLoading && credentials.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Login Credentials</h3>
        <Button variant="outline" size="sm" onClick={handleAddPasskey} disabled={isLoading}>
          <Plus className="mr-1 h-4 w-4" />
          Add Passkey
        </Button>
      </div>

      {error && (
        <div className="p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
          {error}
          <button onClick={() => setError(null)} className="ml-2 underline">
            Dismiss
          </button>
        </div>
      )}

      <div className="space-y-2">
        {(credentials ?? []).map((cred) => (
          <div
            key={cred.id}
            className="flex items-center justify-between p-3 border rounded-lg"
          >
            <div className="flex items-center gap-3">
              {getCredentialIcon(cred.credential_type)}
              <div>
                {editingId === cred.id ? (
                  <input
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') handleRename(cred.id);
                      if (e.key === 'Escape') setEditingId(null);
                    }}
                    className="px-2 py-1 border rounded text-sm bg-background"
                    autoFocus
                  />
                ) : (
                  <p className="text-sm font-medium">
                    {cred.name ?? cred.credential_type}
                  </p>
                )}
                <p className="text-xs text-muted-foreground">
                  {cred.credential_type === 'webauthn' ? 'Passkey' : cred.provider_name ?? 'Password'}
                  {cred.last_used_at && ` \u00b7 Last used ${new Date(cred.last_used_at).toLocaleDateString()}`}
                </p>
              </div>
            </div>
            <div className="flex items-center gap-1">
              {editingId === cred.id ? (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleRename(cred.id)}
                >
                  Save
                </Button>
              ) : (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setEditingId(cred.id);
                    setEditName(cred.name ?? '');
                  }}
                >
                  <Pencil className="h-3 w-3" />
                </Button>
              )}
              <Button
                variant="ghost"
                size="sm"
                onClick={() => handleDelete(cred.id)}
                disabled={credentials.length <= 1}
              >
                <Trash2 className="h-3 w-3 text-destructive" />
              </Button>
            </div>
          </div>
        ))}
      </div>

      {credentials.length === 0 && (
        <p className="text-sm text-muted-foreground text-center py-4">
          No credentials found. Add a passkey for passwordless login.
        </p>
      )}
    </div>
  );
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}
