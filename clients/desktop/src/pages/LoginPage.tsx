import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Shield, Eye, EyeOff, Loader2 } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';
import { Button } from '@/components/ui/Button';
import { OidcProviderButtons } from '@/components/auth/OidcProviderButtons';
import { PasskeyButton } from '@/components/auth/PasskeyButton';

export function LoginPage() {
  const navigate = useNavigate();
  const { login, isLoading, error, clearError } = useAuthStore();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await login(email, password);
      navigate('/files');
    } catch (err) {
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
            Sign in to your account
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

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-2">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg bg-background focus:outline-none focus:ring-2 focus:ring-primary"
              placeholder="you@example.com"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium mb-2">Password</label>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full px-4 py-2 pr-10 border rounded-lg bg-background focus:outline-none focus:ring-2 focus:ring-primary"
                placeholder="Enter your password"
                required
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                {showPassword ? (
                  <EyeOff className="h-4 w-4" />
                ) : (
                  <Eye className="h-4 w-4" />
                )}
              </button>
            </div>
          </div>

          <Button type="submit" className="w-full" disabled={isLoading}>
            {isLoading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Signing in...
              </>
            ) : (
              'Sign in'
            )}
          </Button>
        </form>

        {/* Passkey login */}
        <div className="mt-4">
          <PasskeyButton email={email || undefined} />
        </div>

        {/* OIDC providers */}
        <div className="mt-4">
          <OidcProviderButtons tenantSlug="default" />
        </div>

        {/* Register link */}
        <div className="mt-6 text-center text-sm">
          <p className="text-muted-foreground">
            Don't have an account?{' '}
            <Link to="/register" className="text-primary hover:underline font-medium">
              Sign up
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
