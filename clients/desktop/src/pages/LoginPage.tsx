import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OidcButtons } from '@/components/auth/OidcButtons';
import { QrChallenge } from '@/components/auth/QrChallenge';
import { Button } from '@/components/ui/Button';
import { Mail, ChevronDown, ChevronUp } from 'lucide-react';

export function LoginPage() {
  const navigate = useNavigate();
  const { loginWithSession, loginWithOidc, error, clearError, isLoading } = useAuthStore();
  const [showQr, setShowQr] = useState(false);
  const [oidcLoading, setOidcLoading] = useState<'google' | 'microsoft' | null>(null);

  const handleAuthenticated = async (sessionToken: string) => {
    try {
      await loginWithSession(sessionToken);
      navigate('/files');
    } catch {
      // Error handled by store
    }
  };

  const handleOidcLogin = async (provider: 'google' | 'microsoft') => {
    setOidcLoading(provider);
    try {
      await loginWithOidc(provider);
      // Browser opens — continue via deep link callback
    } catch {
      // Error handled by store
    } finally {
      setOidcLoading(null);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <img
            src="/app-icon.png"
            alt="SSDID Drive"
            className="h-24 w-24 rounded-2xl mb-4"
          />
          <h1 className="text-2xl font-bold">SSDID Drive</h1>
          <p className="text-muted-foreground text-sm mt-1">
            Sign in to your account
          </p>
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button onClick={clearError} className="ml-2 underline hover:no-underline">
              Dismiss
            </button>
          </div>
        )}

        {/* Email login */}
        <Button
          variant="default"
          className="w-full h-11 mb-3"
          onClick={() => navigate('/login/email')}
          disabled={isLoading}
        >
          <Mail className="h-5 w-5 mr-2" />
          Sign in with Email
        </Button>

        {/* Divider */}
        <div className="relative my-4">
          <div className="absolute inset-0 flex items-center">
            <span className="w-full border-t" />
          </div>
          <div className="relative flex justify-center text-xs uppercase">
            <span className="bg-card px-2 text-muted-foreground">or</span>
          </div>
        </div>

        {/* OIDC buttons */}
        <OidcButtons
          onProviderClick={handleOidcLogin}
          disabled={isLoading}
          loading={oidcLoading}
        />

        {/* SSDID Wallet (legacy, collapsible) */}
        <div className="mt-4">
          <button
            onClick={() => setShowQr(!showQr)}
            className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground mx-auto"
          >
            {showQr ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
            Sign in with SSDID Wallet
          </button>
          {showQr && (
            <div className="mt-4">
              <QrChallenge action="authenticate" onAuthenticated={handleAuthenticated} />
            </div>
          )}
        </div>

        {/* Register link */}
        <div className="mt-6 text-center text-sm">
          <p className="text-muted-foreground">
            New to SSDID Drive?{' '}
            <Link to="/register" className="text-primary hover:underline font-medium">
              Register
            </Link>
          </p>
        </div>

        {/* Invite code link */}
        <div className="mt-2 text-center text-sm">
          <p className="text-muted-foreground">
            <Link to="/join" className="text-primary hover:underline font-medium">
              Have an invite code?
            </Link>
          </p>
        </div>

        {/* Recovery link */}
        <div className="mt-2 text-center text-sm">
          <Link to="/recover" className="text-muted-foreground hover:text-foreground text-sm">
            Lost your device? Recover your account
          </Link>
        </div>
      </div>
    </div>
  );
}
