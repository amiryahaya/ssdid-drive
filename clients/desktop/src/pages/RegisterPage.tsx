import { useState } from 'react';
import { useNavigate, Link, useSearchParams } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { OtpInput } from '@/components/auth/OtpInput';
import { QrChallenge } from '@/components/auth/QrChallenge';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { Loader2, ArrowLeft, Ticket, Mail, Shield } from 'lucide-react';

type Step = 'invite' | 'choose' | 'email' | 'otp';

export function RegisterPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const initialInvite = searchParams.get('invite') || '';

  const { sendOtp, verifyOtp, loginWithSession, loginWithOidc, isLoading, error, clearError } = useAuthStore();

  const [step, setStep] = useState<Step>(initialInvite ? 'choose' : 'invite');
  const [inviteToken, setInviteToken] = useState(initialInvite);
  const [email, setEmail] = useState('');
  const [showQr, setShowQr] = useState(false);

  const handleInviteSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!inviteToken.trim()) return;
    setStep('choose');
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

  const stepIcon = step === 'invite'
    ? <Ticket className="h-7 w-7 text-blue-600" />
    : step === 'otp'
      ? <Shield className="h-7 w-7 text-blue-600" />
      : <Mail className="h-7 w-7 text-blue-600" />;

  const stepTitle = step === 'invite'
    ? 'Enter Invitation Code'
    : step === 'otp'
      ? 'Verify Email'
      : 'Create Account';

  const stepSubtitle = step === 'invite'
    ? 'You need an invitation to register'
    : step === 'otp'
      ? `Code sent to ${email}`
      : 'Choose how to create your account';

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

          {/* Step: Choose method */}
          {step === 'choose' && (
            <div className="space-y-3">
              <div className="text-sm text-gray-500 bg-gray-50 rounded-lg p-3 flex items-center gap-2">
                <Ticket className="h-4 w-4 shrink-0" />
                <span className="truncate">Invitation: {inviteToken.slice(0, 20)}{inviteToken.length > 20 ? '...' : ''}</span>
              </div>

              {/* Email registration */}
              <Button
                variant="default"
                className="w-full h-11 cursor-pointer"
                onClick={() => setStep('email')}
                disabled={isLoading}
              >
                <Mail className="h-4 w-4 mr-2" />
                Register with Email
              </Button>

              {/* Divider */}
              <div className="relative my-4">
                <div className="absolute inset-0 flex items-center">
                  <div className="w-full border-t border-gray-200" />
                </div>
                <div className="relative flex justify-center text-xs">
                  <span className="bg-white px-2 text-gray-400">or register with</span>
                </div>
              </div>

              {/* OIDC */}
              <div className="flex gap-3">
                <button
                  onClick={() => handleOidcRegister('google')}
                  disabled={isLoading}
                  className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 border border-gray-300
                    rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors
                    disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24">
                    <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
                    <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
                    <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
                    <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
                  </svg>
                  Google
                </button>
                <button
                  onClick={() => handleOidcRegister('microsoft')}
                  disabled={isLoading}
                  className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 border border-gray-300
                    rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors
                    disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
                >
                  <svg width="18" height="18" viewBox="0 0 23 23">
                    <rect x="1" y="1" width="10" height="10" fill="#f25022"/>
                    <rect x="12" y="1" width="10" height="10" fill="#7fba00"/>
                    <rect x="1" y="12" width="10" height="10" fill="#00a4ef"/>
                    <rect x="12" y="12" width="10" height="10" fill="#ffb900"/>
                  </svg>
                  Microsoft
                </button>
              </div>

              {/* SSDID Wallet */}
              <div className="mt-2">
                <button
                  onClick={() => setShowQr(!showQr)}
                  className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mx-auto cursor-pointer transition-colors"
                >
                  {showQr ? 'Hide' : 'Register with SSDID Wallet'}
                </button>
                {showQr && (
                  <div className="mt-4">
                    <QrChallenge action="register" onAuthenticated={handleQrAuthenticated} />
                  </div>
                )}
              </div>

              <button
                onClick={() => { setStep('invite'); clearError(); }}
                className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mx-auto cursor-pointer transition-colors mt-2"
              >
                <ArrowLeft className="h-4 w-4" />
                Change invitation code
              </button>
            </div>
          )}

          {/* Step: Email */}
          {step === 'email' && (
            <form onSubmit={handleEmailSubmit} className="space-y-4">
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
                onClick={() => { setStep('choose'); clearError(); }}
                className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mx-auto cursor-pointer transition-colors"
              >
                <ArrowLeft className="h-4 w-4" />
                Back
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
