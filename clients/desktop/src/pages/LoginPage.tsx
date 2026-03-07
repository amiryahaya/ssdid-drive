import { useNavigate, Link } from 'react-router-dom';
import { Shield } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';
import { QrChallenge } from '@/components/auth/QrChallenge';

export function LoginPage() {
  const navigate = useNavigate();
  const { loginWithSession, error, clearError } = useAuthStore();

  const handleAuthenticated = async (sessionToken: string) => {
    try {
      await loginWithSession(sessionToken);
      navigate('/files');
    } catch {
      // Error is handled by store
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-2xl bg-primary flex items-center justify-center mb-4">
            <Shield className="h-10 w-10 text-primary-foreground" />
          </div>
          <h1 className="text-2xl font-bold">SSDID Drive</h1>
          <p className="text-muted-foreground text-sm mt-1">
            Sign in with your SSDID Wallet
          </p>
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button
              onClick={clearError}
              className="ml-2 underline hover:no-underline"
            >
              Dismiss
            </button>
          </div>
        )}

        {/* QR Challenge */}
        <QrChallenge action="authenticate" onAuthenticated={handleAuthenticated} />

        {/* Download link */}
        <div className="mt-6 text-center text-sm">
          <p className="text-muted-foreground">
            Don't have SSDID Wallet?{' '}
            <a
              href="https://ssdid.io/wallet"
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary hover:underline font-medium"
            >
              Download it &rarr;
            </a>
          </p>
        </div>

        {/* Register link */}
        <div className="mt-2 text-center text-sm">
          <p className="text-muted-foreground">
            New to SSDID Drive?{' '}
            <Link to="/register" className="text-primary hover:underline font-medium">
              Register
            </Link>
          </p>
        </div>

        {/* Footer */}
        <div className="mt-4 text-center text-sm text-muted-foreground">
          <p>Protected with post-quantum cryptography</p>
        </div>
      </div>
    </div>
  );
}
