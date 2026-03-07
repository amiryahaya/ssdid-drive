import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Shield, Eye, EyeOff, Loader2, UserPlus } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';
import { Button } from '@/components/ui/Button';

export function RegisterPage() {
  const navigate = useNavigate();
  const { register, isLoading, error, clearError } = useAuthStore();

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [invitationToken, setInvitationToken] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setValidationError(null);

    // Validate password length
    if (password.length < 8) {
      setValidationError('Password must be at least 8 characters');
      return;
    }

    // Validate password match
    if (password !== confirmPassword) {
      setValidationError('Passwords do not match');
      return;
    }

    try {
      await register(email, password, name, invitationToken);
      navigate('/onboarding');
    } catch (err) {
      // Error is handled by store
    }
  };

  const displayError = validationError || error;

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
            Create your account
          </p>
        </div>

        {/* Error message */}
        {displayError && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {displayError}
            <button
              onClick={() => {
                setValidationError(null);
                clearError();
              }}
              className="ml-2 underline hover:no-underline"
            >
              Dismiss
            </button>
          </div>
        )}

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-2">Full Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg bg-background focus:outline-none focus:ring-2 focus:ring-primary"
              placeholder="John Doe"
              required
            />
          </div>

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
                placeholder="Minimum 8 characters"
                required
                minLength={8}
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

          <div>
            <label className="block text-sm font-medium mb-2">Confirm Password</label>
            <input
              type={showPassword ? 'text' : 'password'}
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg bg-background focus:outline-none focus:ring-2 focus:ring-primary"
              placeholder="Re-enter your password"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium mb-2">Invitation Token</label>
            <input
              type="text"
              value={invitationToken}
              onChange={(e) => setInvitationToken(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg bg-background focus:outline-none focus:ring-2 focus:ring-primary"
              placeholder="Enter your invitation token"
              required
            />
            <p className="text-xs text-muted-foreground mt-1">
              You need an invitation token from your organization
            </p>
          </div>

          <Button type="submit" className="w-full" disabled={isLoading}>
            {isLoading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Creating account...
              </>
            ) : (
              <>
                <UserPlus className="mr-2 h-4 w-4" />
                Create Account
              </>
            )}
          </Button>
        </form>

        {/* Footer */}
        <div className="mt-6 text-center text-sm">
          <p className="text-muted-foreground">
            Already have an account?{' '}
            <Link to="/login" className="text-primary hover:underline font-medium">
              Sign in
            </Link>
          </p>
        </div>

        <div className="mt-4 text-center text-sm text-muted-foreground">
          <p>Protected with post-quantum cryptography</p>
        </div>
      </div>
    </div>
  );
}
