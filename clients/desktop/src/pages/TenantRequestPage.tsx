import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Building2, Shield, Loader2, CheckCircle, ArrowLeft } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { useAuthStore } from '@/stores/authStore';
import { invoke } from '@tauri-apps/api/core';

async function getApiBaseUrl(): Promise<string> {
  try {
    const info = await invoke<{ api_base_url: string }>('get_api_base_url');
    return info.api_base_url;
  } catch {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (import.meta as any).env?.VITE_API_BASE_URL ?? 'http://localhost:5147';
  }
}

async function getAuthHeaders(): Promise<Record<string, string>> {
  try {
    const token = await invoke<string>('get_auth_token');
    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
  } catch {
    return { 'Content-Type': 'application/json' };
  }
}

async function submitTenantRequest(
  organizationName: string,
  reason: string | null
): Promise<void> {
  const baseUrl = await getApiBaseUrl();
  const headers = await getAuthHeaders();
  const resp = await fetch(`${baseUrl}/api/tenant-requests`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      organization_name: organizationName,
      reason: reason || undefined,
    }),
  });

  if (!resp.ok) {
    if (resp.status === 409) {
      throw new Error('You already have a pending organization request.');
    }
    throw new Error(`Failed to submit request (${resp.status})`);
  }
}

export function TenantRequestPage() {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);

  const [organizationName, setOrganizationName] = useState('');
  const [reason, setReason] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isSubmitted, setIsSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async () => {
    const name = organizationName.trim();
    if (!name) {
      setError('Organization name is required');
      return;
    }

    if (!isAuthenticated) {
      setError('Please sign in first to submit a request.');
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      await submitTenantRequest(name, reason.trim() || null);
      setIsSubmitted(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && organizationName.trim() && !isSubmitting) {
      handleSubmit();
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Header */}
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-2xl bg-primary flex items-center justify-center mb-4">
            {isSubmitted ? (
              <CheckCircle className="h-10 w-10 text-primary-foreground" />
            ) : (
              <Building2 className="h-10 w-10 text-primary-foreground" />
            )}
          </div>
          <h1 className="text-2xl font-bold">
            {isSubmitted ? 'Request Submitted!' : 'Request Organization'}
          </h1>
          <p className="text-muted-foreground text-sm mt-1 text-center">
            {isSubmitted
              ? `Your request for "${organizationName}" has been submitted.`
              : 'Request a new organization for your team'}
          </p>
        </div>

        {isSubmitted ? (
          /* Success state */
          <div className="space-y-4 text-center">
            <p className="text-sm text-muted-foreground">
              An administrator will review and approve your request.
              You'll be notified when your organization is ready.
            </p>

            <div className="pt-4">
              <Link to={isAuthenticated ? '/files' : '/login'}>
                <Button className="w-full">
                  {isAuthenticated ? 'Back to Files' : 'Back to Login'}
                </Button>
              </Link>
            </div>
          </div>
        ) : (
          /* Form */
          <div className="space-y-4">
            {/* Error */}
            {error && (
              <div className="p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
                {error}
              </div>
            )}

            {/* Organization name */}
            <div>
              <label
                htmlFor="org-name"
                className="block text-sm font-medium mb-2"
              >
                Organization Name
              </label>
              <input
                id="org-name"
                type="text"
                value={organizationName}
                onChange={(e) => {
                  setOrganizationName(e.target.value);
                  if (error) setError(null);
                }}
                onKeyDown={handleKeyDown}
                placeholder="Acme Corp"
                autoFocus
                className="w-full px-4 py-3 rounded-lg border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
              />
            </div>

            {/* Reason */}
            <div>
              <label
                htmlFor="org-reason"
                className="block text-sm font-medium mb-2"
              >
                Reason <span className="text-muted-foreground">(optional)</span>
              </label>
              <textarea
                id="org-reason"
                value={reason}
                onChange={(e) => {
                  if (e.target.value.length <= 500) {
                    setReason(e.target.value);
                  }
                }}
                placeholder="Tell us about your team..."
                rows={3}
                className="w-full px-4 py-3 rounded-lg border bg-background text-sm resize-none focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
              />
              <p className="text-xs text-muted-foreground text-right mt-1">
                {reason.length}/500
              </p>
            </div>

            {/* Submit */}
            <Button
              onClick={handleSubmit}
              disabled={!organizationName.trim() || isSubmitting}
              className="w-full"
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Submitting...
                </>
              ) : (
                'Submit Request'
              )}
            </Button>

            {!isAuthenticated && (
              <p className="text-xs text-center text-muted-foreground">
                You need to{' '}
                <Link to="/login" className="text-primary hover:underline">
                  sign in
                </Link>
                {' '}first to submit a request.
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
            <Link
              to="/login"
              className="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground transition-colors"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to Login
            </Link>
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
