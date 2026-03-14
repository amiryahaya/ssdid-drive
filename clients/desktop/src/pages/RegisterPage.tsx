import { useState } from 'react';
import { useNavigate, Link, useSearchParams } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OtpInput } from '@/components/auth/OtpInput';
import { OidcButtons } from '@/components/auth/OidcButtons';
import { QrChallenge } from '@/components/auth/QrChallenge';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { Loader2, UserPlus, ChevronDown, ChevronUp } from 'lucide-react';

type Step = 'email' | 'otp';

export function RegisterPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const inviteToken = searchParams.get('invite') || '';

  const { sendOtp, verifyOtp, loginWithSession, loginWithOidc, isLoading, error, clearError } = useAuthStore();

  const [step, setStep] = useState<Step>('email');
  const [email, setEmail] = useState('');
  const [showQr, setShowQr] = useState(false);

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) return;
    try {
      await sendOtp(email.trim(), inviteToken || undefined);
      setStep('otp');
    } catch {
      // Error handled by store
    }
  };

  const handleOtpComplete = async (code: string) => {
    try {
      const result = await verifyOtp(email, code, inviteToken || undefined);
      if (result.totpSetupRequired) {
        navigate('/login/totp-setup');
      } else {
        navigate('/onboarding');
      }
    } catch {
      // Error handled by store
    }
  };

  const handleOidcRegister = async (provider: 'google' | 'microsoft') => {
    try {
      await loginWithOidc(provider);
      // Browser opens — registration continues via deep link callback
    } catch {
      // Error handled by store
    }
  };

  const handleQrAuthenticated = async (sessionToken: string) => {
    try {
      await loginWithSession(sessionToken);
      navigate('/onboarding');
    } catch {
      // Error handled by store
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            <UserPlus className="h-8 w-8 text-primary" />
          </div>
          <h1 className="text-2xl font-bold">Create Account</h1>
          <p className="text-muted-foreground text-sm mt-1">
            {step === 'email' ? 'Register for SSDID Drive' : 'Enter the verification code sent to your email'}
          </p>
        </div>

        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button onClick={clearError} className="ml-2 underline hover:no-underline">Dismiss</button>
          </div>
        )}

        {step === 'email' && (
          <>
            <form onSubmit={handleEmailSubmit} className="space-y-4">
              <Input
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={isLoading}
                autoFocus
              />
              {inviteToken && (
                <div className="text-sm text-muted-foreground bg-muted rounded-lg p-3">
                  Registering with invitation code
                </div>
              )}
              <Button type="submit" className="w-full" disabled={isLoading || !email.trim()}>
                {isLoading ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Sending code...</> : 'Send verification code'}
              </Button>
            </form>

            <div className="relative my-4">
              <div className="absolute inset-0 flex items-center"><span className="w-full border-t" /></div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-card px-2 text-muted-foreground">or register with</span>
              </div>
            </div>

            <OidcButtons onProviderClick={handleOidcRegister} disabled={isLoading} />

            <div className="mt-4">
              <button
                onClick={() => setShowQr(!showQr)}
                className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground mx-auto"
              >
                {showQr ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
                Register with SSDID Wallet
              </button>
              {showQr && (
                <div className="mt-4">
                  <QrChallenge action="register" onAuthenticated={handleQrAuthenticated} />
                </div>
              )}
            </div>
          </>
        )}

        {step === 'otp' && (
          <div className="space-y-6">
            <p className="text-sm text-muted-foreground text-center">
              Code sent to <strong>{email}</strong>
            </p>
            <OtpInput onComplete={handleOtpComplete} disabled={isLoading} error={error ?? undefined} />
            {isLoading && (
              <div className="flex justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            <button
              onClick={() => { setStep('email'); clearError(); }}
              className="text-sm text-muted-foreground hover:text-foreground mx-auto block"
            >
              Use a different email
            </button>
          </div>
        )}

        <div className="mt-6 text-center text-sm">
          <p className="text-muted-foreground">
            Already registered?{' '}
            <Link to="/login" className="text-primary hover:underline font-medium">Sign in</Link>
          </p>
        </div>
      </div>
    </div>
  );
}
