import { useState, useEffect, useCallback, useRef } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { useLocation } from 'react-router-dom'
import { useAuthStore } from '../stores/authStore'
import { api } from '../services/api'

type LoginState = 'loading' | 'qr' | 'scanned' | 'error'
type AuthTab = 'wallet' | 'email'

interface QrPayload {
  challenge_id: string
  subscriber_secret: string
  qr_payload: Record<string, unknown>
}

export default function LoginPage() {
  const login = useAuthStore((s) => s.login)
  const location = useLocation()
  const [activeTab, setActiveTab] = useState<AuthTab>('email')

  // SSDID Wallet QR state
  const [qrState, setQrState] = useState<LoginState>('loading')
  const [qrData, setQrData] = useState<QrPayload | null>(null)
  const [qrError, setQrError] = useState<string | null>(null)
  const eventSourceRef = useRef<EventSource | null>(null)

  // Email + TOTP state
  const [email, setEmail] = useState('')
  const [totpCode, setTotpCode] = useState('')
  const [emailStep, setEmailStep] = useState<'email' | 'totp'>('email')
  const [emailLoading, setEmailLoading] = useState(false)
  const [emailError, setEmailError] = useState<string | null>(null)

  // MFA session token from OIDC callback (for MFA upgrade flow)
  const [mfaSessionToken, setMfaSessionToken] = useState<string | null>(null)

  // Check for MFA state passed from AuthCallbackPage via navigate()
  useEffect(() => {
    const navState = location.state as { mfaToken?: string; step?: string } | null
    if (navState?.mfaToken && navState?.step === 'totp') {
      setMfaSessionToken(navState.mfaToken)
      setEmailStep('totp')
      setActiveTab('email')
      // Clear the navigation state so refresh doesn't replay
      window.history.replaceState({}, '')
    }
  }, [location.state])

  // SSDID Wallet QR code flow
  const initiateWallet = useCallback(async () => {
    setQrState('loading')
    setQrError(null)
    eventSourceRef.current?.close()

    try {
      const res = await fetch('/api/auth/ssdid/login/initiate', { method: 'POST' })
      if (!res.ok) throw new Error(`Server error: ${res.status}`)
      const data: QrPayload = await res.json()
      setQrData(data)
      setQrState('qr')

      const params = new URLSearchParams({
        challenge_id: data.challenge_id,
        subscriber_secret: data.subscriber_secret,
      })
      const es = new EventSource(`/api/auth/ssdid/events?${params}`)
      eventSourceRef.current = es

      es.addEventListener('authenticated', async (event) => {
        es.close()
        setQrState('scanned')
        try {
          const { session_token } = JSON.parse(event.data)
          await login(session_token)
        } catch (err) {
          setQrError(err instanceof Error ? err.message : 'Login failed')
          setQrState('error')
        }
      })

      es.addEventListener('timeout', () => {
        es.close()
        setQrError('QR code expired. Please try again.')
        setQrState('error')
      })

      es.onerror = () => {
        es.close()
        setQrError('Connection lost. Please try again.')
        setQrState('error')
      }
    } catch (err) {
      setQrError(err instanceof Error ? err.message : 'Failed to generate QR code')
      setQrState('error')
    }
  }, [login])

  // Only initiate wallet QR when wallet tab is active
  useEffect(() => {
    if (activeTab === 'wallet') {
      initiateWallet()
    }
    return () => { eventSourceRef.current?.close() }
  }, [activeTab, initiateWallet])

  // Email login step 1: submit email
  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email.trim()) return

    setEmailLoading(true)
    setEmailError(null)

    try {
      await api.post<{ requires_totp: boolean; email: string }>('/api/auth/email/login', {
        email: email.trim(),
      })
      setEmailStep('totp')
    } catch (err) {
      setEmailError(err instanceof Error ? err.message : 'Failed to verify email')
    } finally {
      setEmailLoading(false)
    }
  }

  // Email login step 2: submit TOTP code (or MFA upgrade)
  const handleTotpSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!totpCode.trim()) return

    setEmailLoading(true)
    setEmailError(null)

    try {
      const body: Record<string, string> = { code: totpCode.trim() }
      if (mfaSessionToken) {
        // MFA session upgrade flow (from OIDC)
        body.session_token = mfaSessionToken
      } else {
        // Email login flow
        body.email = email.trim()
      }
      const result = await api.post<{ token: string }>('/api/auth/totp/verify', body)
      setMfaSessionToken(null)
      await login(result.token)
    } catch (err) {
      setEmailError(err instanceof Error ? err.message : 'Invalid TOTP code')
    } finally {
      setEmailLoading(false)
    }
  }

  // OIDC: redirect to provider
  const handleOidc = (provider: string) => {
    window.location.href = `/api/auth/oidc/${provider}/authorize`
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
          {/* Header */}
          <div className="text-center mb-6">
            <img src="/icon-192.png" alt="SSDID Drive" className="w-12 h-12 rounded-xl mb-4 mx-auto" />
            <h1 className="text-xl font-bold text-gray-900">SSDID Drive</h1>
            <p className="text-sm text-gray-500 mt-1">Admin Portal</p>
          </div>

          {/* Auth method tabs */}
          <div className="flex border-b border-gray-200 mb-6">
            <button
              onClick={() => { setActiveTab('email'); setEmailError(null) }}
              className={`flex-1 pb-2 text-sm font-medium border-b-2 transition-colors ${
                activeTab === 'email'
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              Email / SSO
            </button>
            <button
              onClick={() => { setActiveTab('wallet'); setEmailError(null) }}
              className={`flex-1 pb-2 text-sm font-medium border-b-2 transition-colors ${
                activeTab === 'wallet'
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              SSDID Wallet
            </button>
          </div>

          {/* Email / SSO Tab */}
          {activeTab === 'email' && (
            <div>
              {emailStep === 'email' ? (
                <form onSubmit={handleEmailSubmit} className="space-y-4">
                  <div>
                    <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
                      Email address
                    </label>
                    <input
                      id="email"
                      type="email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="admin@example.com"
                      required
                      autoFocus
                      className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm
                        focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500
                        placeholder:text-gray-400"
                    />
                  </div>
                  {emailError && (
                    <p className="text-sm text-red-600">{emailError}</p>
                  )}
                  <button
                    type="submit"
                    disabled={emailLoading || !email.trim()}
                    className="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium
                      text-white hover:bg-blue-700 focus:outline-none focus:ring-2
                      focus:ring-blue-500 focus:ring-offset-2 transition-colors
                      disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {emailLoading ? 'Checking...' : 'Continue with Email'}
                  </button>
                </form>
              ) : (
                <form onSubmit={handleTotpSubmit} className="space-y-4">
                  <div className="text-center mb-2">
                    <p className="text-sm text-gray-600">
                      Enter the 6-digit code from your authenticator app
                    </p>
                    {mfaSessionToken ? (
                      <p className="text-xs text-gray-400 mt-1">MFA verification required</p>
                    ) : (
                      <p className="text-xs text-gray-400 mt-1">{email}</p>
                    )}
                  </div>
                  <div>
                    <input
                      type="text"
                      value={totpCode}
                      onChange={(e) => {
                        const val = e.target.value.replace(/\D/g, '').slice(0, 6)
                        setTotpCode(val)
                      }}
                      placeholder="000000"
                      maxLength={6}
                      autoFocus
                      inputMode="numeric"
                      autoComplete="one-time-code"
                      className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm
                        text-center tracking-[0.3em] font-mono text-lg
                        focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500
                        placeholder:text-gray-400 placeholder:tracking-[0.3em]"
                    />
                  </div>
                  {emailError && (
                    <p className="text-sm text-red-600">{emailError}</p>
                  )}
                  <button
                    type="submit"
                    disabled={emailLoading || totpCode.length !== 6}
                    className="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium
                      text-white hover:bg-blue-700 focus:outline-none focus:ring-2
                      focus:ring-blue-500 focus:ring-offset-2 transition-colors
                      disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {emailLoading ? 'Verifying...' : 'Verify'}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setEmailStep('email')
                      setTotpCode('')
                      setEmailError(null)
                      setMfaSessionToken(null)
                    }}
                    className="w-full text-sm text-gray-500 hover:text-gray-700 transition-colors"
                  >
                    {mfaSessionToken ? 'Back to login' : 'Use a different email'}
                  </button>
                </form>
              )}

              {/* Divider */}
              {emailStep === 'email' && (
                <>
                  <div className="relative my-5">
                    <div className="absolute inset-0 flex items-center">
                      <div className="w-full border-t border-gray-200" />
                    </div>
                    <div className="relative flex justify-center text-xs">
                      <span className="bg-white px-2 text-gray-400">or</span>
                    </div>
                  </div>

                  {/* OIDC Buttons */}
                  <div className="space-y-2">
                    <button
                      onClick={() => handleOidc('google')}
                      className="w-full flex items-center justify-center gap-2 rounded-lg border
                        border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700
                        hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500
                        focus:ring-offset-2 transition-colors"
                    >
                      <svg width="16" height="16" viewBox="0 0 24 24">
                        <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/>
                        <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                        <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                        <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                      </svg>
                      Continue with Google
                    </button>
                    <button
                      onClick={() => handleOidc('microsoft')}
                      className="w-full flex items-center justify-center gap-2 rounded-lg border
                        border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700
                        hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500
                        focus:ring-offset-2 transition-colors"
                    >
                      <svg width="16" height="16" viewBox="0 0 21 21">
                        <rect x="1" y="1" width="9" height="9" fill="#F25022"/>
                        <rect x="11" y="1" width="9" height="9" fill="#7FBA00"/>
                        <rect x="1" y="11" width="9" height="9" fill="#00A4EF"/>
                        <rect x="11" y="11" width="9" height="9" fill="#FFB900"/>
                      </svg>
                      Continue with Microsoft
                    </button>
                  </div>
                </>
              )}
            </div>
          )}

          {/* SSDID Wallet Tab */}
          {activeTab === 'wallet' && (
            <div>
              {qrState === 'loading' && (
                <div className="flex flex-col items-center py-8">
                  <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin" />
                  <p className="text-sm text-gray-500 mt-4">Generating QR code...</p>
                </div>
              )}

              {qrState === 'qr' && qrData && (
                <div className="flex flex-col items-center">
                  <div className="bg-white p-3 rounded-lg border border-gray-100">
                    <QRCodeSVG
                      value={JSON.stringify(qrData.qr_payload)}
                      size={200}
                      level="M"
                    />
                  </div>
                  <p className="text-sm text-gray-600 mt-4 text-center">
                    Scan with your SSDID Wallet to sign in
                  </p>
                  <p className="text-xs text-gray-400 mt-1">
                    Waiting for authentication...
                  </p>
                </div>
              )}

              {qrState === 'scanned' && (
                <div className="flex flex-col items-center py-8">
                  <div className="w-8 h-8 border-2 border-green-600 border-t-transparent rounded-full animate-spin" />
                  <p className="text-sm text-gray-600 mt-4">Authenticated. Loading...</p>
                </div>
              )}

              {qrState === 'error' && (
                <div className="flex flex-col items-center py-4">
                  <div className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-red-50 mb-3">
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} className="text-red-500">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
                    </svg>
                  </div>
                  <p className="text-sm text-red-600 text-center mb-4">{qrError}</p>
                  <button
                    onClick={initiateWallet}
                    className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium
                      text-white hover:bg-blue-700 focus:outline-none focus:ring-2
                      focus:ring-blue-500 focus:ring-offset-2 transition-colors"
                  >
                    Try Again
                  </button>
                </div>
              )}
            </div>
          )}

          <p className="text-xs text-gray-400 text-center mt-6">
            Requires SuperAdmin role to access.
          </p>
        </div>
      </div>
    </div>
  )
}
