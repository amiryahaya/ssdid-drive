import { useState } from 'react';
import { useNavigate, Link, useSearchParams } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OtpInput } from '@/components/auth/OtpInput';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { Loader2, ArrowLeft, Ticket, Mail, Shield } from 'lucide-react';

type Step = 'invite' | 'email' | 'otp';

export function RegisterPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const initialInvite = searchParams.get('invite') || '';

  const { sendOtp, verifyOtp, isLoading, error, clearError } = useAuthStore();

  const [step, setStep] = useState<Step>(initialInvite ? 'email' : 'invite');
  const [inviteToken, setInviteToken] = useState(initialInvite);
  const [email, setEmail] = useState('');

  const handleInviteSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!inviteToken.trim()) return;
    setStep('email');
  };

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) return;
    try {
      await sendOtp(email.trim(), inviteToken.trim());
      setStep('otp');
    } catch {
      // Error handled by store
    }
  };

  const handleOtpComplete = async (code: string) => {
    try {
      const result = await verifyOtp(email, code, inviteToken.trim());
      if (result.totpSetupRequired) {
        navigate('/login/totp-setup');
      } else {
        navigate('/onboarding');
      }
    } catch {
      // Error handled by store
    }
  };

  const stepIcon = step === 'invite'
    ? <Ticket className="h-7 w-7 text-blue-600" />
    : step === 'email'
      ? <Mail className="h-7 w-7 text-blue-600" />
      : <Shield className="h-7 w-7 text-blue-600" />;

  const stepTitle = step === 'invite'
    ? 'Enter Invitation Code'
    : step === 'email'
      ? 'Create Account'
      : 'Verify Email';

  const stepSubtitle = step === 'invite'
    ? 'You need an invitation to register'
    : step === 'email'
      ? 'Enter your email to receive a verification code'
      : `Code sent to ${email}`;

  return (
    <div className="min-h-screen flex items-center justify-center bg-white px-4">
      <div className="w-full max-w-sm">
        <div className="border border-gray-200 rounded-xl p-8 shadow-sm">
          {/* Header */}
          <div className="flex flex-col items-center mb-6">
            <div className="h-14 w-14 rounded-xl bg-blue-50 flex items-center justify-center mb-3">
              {stepIcon}
            </div>
            <h1 className="text-xl font-bold text-gray-900">{stepTitle}</h1>
            <p className="text-sm text-gray-500 mt-1 text-center">{stepSubtitle}</p>
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

          {/* Step: Invitation */}
          {step === 'invite' && (
            <form onSubmit={handleInviteSubmit} className="space-y-4">
              <div>
                <label htmlFor="invite-code" className="block text-sm font-medium text-gray-700 mb-1">
                  Invitation Code
                </label>
                <Input
                  id="invite-code"
                  type="text"
                  placeholder="Paste your invitation code"
                  value={inviteToken}
                  onChange={(e) => setInviteToken(e.target.value)}
                  autoFocus
                />
              </div>
              <Button
                type="submit"
                className="w-full h-11 cursor-pointer"
                disabled={!inviteToken.trim()}
              >
                Continue
              </Button>
            </form>
          )}

          {/* Step: Email */}
          {step === 'email' && (
            <form onSubmit={handleEmailSubmit} className="space-y-4">
              <div className="text-sm text-gray-500 bg-gray-50 rounded-lg p-3 flex items-center gap-2">
                <Ticket className="h-4 w-4 shrink-0" />
                <span className="truncate">Invitation: {inviteToken.slice(0, 20)}...</span>
              </div>
              <div>
                <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
                  Email
                </label>
                <Input
                  id="email"
                  type="email"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={isLoading}
                  autoFocus
                />
              </div>
              <Button
                type="submit"
                className="w-full h-11 cursor-pointer"
                disabled={isLoading || !email.trim()}
              >
                {isLoading ? (
                  <><Loader2 className="h-4 w-4 mr-2 animate-spin" />Sending code...</>
                ) : (
                  'Send verification code'
                )}
              </Button>
              <button
                type="button"
                onClick={() => { setStep('invite'); clearError(); }}
                className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mx-auto cursor-pointer transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                Change invitation code
              </button>
            </form>
          )}

          {/* Step: OTP */}
          {step === 'otp' && (
            <div className="space-y-6">
              <OtpInput onComplete={handleOtpComplete} disabled={isLoading} error={error ?? undefined} />
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
                Use a different email
              </button>
            </div>
          )}

          {/* Sign in link */}
          <div className="mt-6 text-center text-sm">
            <p className="text-gray-500">
              Already have an account?{' '}
              <Link to="/login" className="text-blue-600 hover:underline font-medium">
                Sign in
              </Link>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
