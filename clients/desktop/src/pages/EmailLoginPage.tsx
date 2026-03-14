import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OtpInput } from '@/components/auth/OtpInput';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { ArrowLeft, Loader2, Mail, Shield } from 'lucide-react';

type Step = 'email' | 'totp';

export function EmailLoginPage() {
  const navigate = useNavigate();
  const emailLogin = useAuthStore((s) => s.emailLogin);
  const totpVerify = useAuthStore((s) => s.totpVerify);
  const isLoading = useAuthStore((s) => s.isLoading);
  const error = useAuthStore((s) => s.error);
  const clearError = useAuthStore((s) => s.clearError);

  const [step, setStep] = useState<Step>('email');
  const [email, setEmail] = useState('');

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) return;
    try {
      const result = await emailLogin(email.trim());
      if (result.requiresTotp) {
        setStep('totp');
      }
    } catch {
      // Error handled by store
    }
  };

  const handleTotpComplete = async (code: string) => {
    try {
      await totpVerify(email, code);
      navigate('/files');
    } catch {
      // Error handled by store
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Header */}
        <div className="flex flex-col items-center mb-8">
          <div className="h-16 w-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            {step === 'email' ? (
              <Mail className="h-8 w-8 text-primary" />
            ) : (
              <Shield className="h-8 w-8 text-primary" />
            )}
          </div>
          <h1 className="text-2xl font-bold">
            {step === 'email' ? 'Sign in with Email' : 'Enter Authenticator Code'}
          </h1>
          <p className="text-muted-foreground text-sm mt-1 text-center">
            {step === 'email'
              ? 'Enter your email to continue'
              : 'Open your authenticator app and enter the 6-digit code'}
          </p>
        </div>

        {/* Error */}
        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg">
            {error}
            <button onClick={clearError} className="ml-2 underline hover:no-underline">
              Dismiss
            </button>
          </div>
        )}

        {/* Email Step */}
        {step === 'email' && (
          <form onSubmit={handleEmailSubmit} className="space-y-4">
            <Input
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={isLoading}
              autoFocus
            />
            <Button type="submit" className="w-full" disabled={isLoading || !email.trim()}>
              {isLoading ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Checking...
                </>
              ) : (
                'Continue'
              )}
            </Button>
          </form>
        )}

        {/* TOTP Step */}
        {step === 'totp' && (
          <div className="space-y-6">
            <OtpInput onComplete={handleTotpComplete} disabled={isLoading} error={error ?? undefined} />
            {isLoading && (
              <div className="flex justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            <button
              onClick={() => { setStep('email'); clearError(); }}
              className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground mx-auto"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to email
            </button>
          </div>
        )}

        {/* Back to login */}
        <div className="mt-6 text-center text-sm">
          <Link to="/login" className="text-muted-foreground hover:text-foreground">
            <ArrowLeft className="h-4 w-4 inline mr-1" />
            Back to all sign-in options
          </Link>
        </div>
      </div>
    </div>
  );
}
