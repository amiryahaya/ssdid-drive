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
      } else {
        navigate('/files');
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
    <div className="min-h-screen flex items-center justify-center bg-white px-4">
      <div className="w-full max-w-sm">
        <div className="border border-gray-200 rounded-xl p-8 shadow-sm">
          {/* Header */}
          <div className="flex flex-col items-center mb-6">
            <div className="h-14 w-14 rounded-xl bg-blue-50 flex items-center justify-center mb-3">
              {step === 'email' ? (
                <Mail className="h-7 w-7 text-blue-600" />
              ) : (
                <Shield className="h-7 w-7 text-blue-600" />
              )}
            </div>
            <h1 className="text-xl font-bold text-gray-900">
              {step === 'email' ? 'Sign in with Email' : 'Enter Authenticator Code'}
            </h1>
            <p className="text-sm text-gray-500 mt-1 text-center">
              {step === 'email'
                ? 'Enter your email to continue'
                : 'Open your authenticator app and enter the 6-digit code'}
            </p>
          </div>

          {/* Error */}
          {error && (
            <div className="mb-4 p-3 bg-red-50 text-red-700 text-sm rounded-lg">
              {error}
              <button onClick={clearError} className="ml-2 underline hover:no-underline cursor-pointer">
                Dismiss
              </button>
            </div>
          )}

          {/* Email Step */}
          {step === 'email' && (
            <form onSubmit={handleEmailSubmit} className="space-y-4">
              <div>
                <label htmlFor="login-email" className="block text-sm font-medium text-gray-700 mb-1">
                  Email
                </label>
                <Input
                  id="login-email"
                  type="email"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={isLoading}
                  autoFocus
                />
              </div>
              <Button type="submit" className="w-full h-11 cursor-pointer" disabled={isLoading || !email.trim()}>
                {isLoading ? (
                  <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Checking...</>
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
                  <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
                </div>
              )}
              <button
                onClick={() => { setStep('email'); clearError(); }}
                className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mx-auto cursor-pointer transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                Back to email
              </button>
            </div>
          )}

          {/* Back */}
          <div className="mt-6 text-center text-sm">
            <Link to="/login" className="text-gray-500 hover:text-gray-700 transition-colors">
              <ArrowLeft className="h-4 w-4 inline mr-1" />
              Back to all sign-in options
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}
