import { useState, useEffect, useCallback, useRef } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { useAuthStore } from '../stores/authStore'

type Tab = 'wallet' | 'email'
type QrState = 'loading' | 'qr' | 'scanned' | 'error'
type EmailStep = 'email' | 'totp'

interface QrPayload {
  challenge_id: string
  subscriber_secret: string
  qr_payload: Record<string, unknown>
}

function WalletLogin({ login }: { login: (token: string) => Promise<void> }) {
  const [state, setState] = useState<QrState>('loading')
  const [qrData, setQrData] = useState<QrPayload | null>(null)
  const [error, setError] = useState<string | null>(null)
  const eventSourceRef = useRef<EventSource | null>(null)

  const initiate = useCallback(async () => {
    setState('loading')
    setError(null)
    eventSourceRef.current?.close()

    try {
      const res = await fetch('/api/auth/ssdid/login/initiate', { method: 'POST' })
      if (!res.ok) throw new Error(`Server error: ${res.status}`)
      const data: QrPayload = await res.json()
      setQrData(data)
      setState('qr')

      const params = new URLSearchParams({
        challenge_id: data.challenge_id,
        subscriber_secret: data.subscriber_secret,
      })
      const es = new EventSource(`/api/auth/ssdid/events?${params}`)
      eventSourceRef.current = es

      es.addEventListener('authenticated', async (event) => {
        es.close()
        setState('scanned')
        try {
          const { session_token } = JSON.parse(event.data)
          await login(session_token)
        } catch (err) {
          setError(err instanceof Error ? err.message : 'Login failed')
          setState('error')
        }
      })

      es.addEventListener('timeout', () => {
        es.close()
        setError('QR code expired. Please try again.')
        setState('error')
      })

      es.onerror = () => {
        es.close()
        setError('Connection lost. Please try again.')
        setState('error')
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to generate QR code')
      setState('error')
    }
  }, [login])

  useEffect(() => {
    initiate()
    return () => { eventSourceRef.current?.close() }
  }, [initiate])

  if (state === 'loading') {
    return (
      <div className="flex flex-col items-center py-8">
        <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin" />
        <p className="text-sm text-gray-500 mt-4">Generating QR code...</p>
      </div>
    )
  }

  if (state === 'qr' && qrData) {
    return (
      <div className="flex flex-col items-center">
        <div className="bg-white p-3 rounded-lg border border-gray-100">
          <QRCodeSVG value={JSON.stringify(qrData.qr_payload)} size={200} level="M" />
        </div>
        <p className="text-sm text-gray-600 mt-4 text-center">
          Scan with your SSDID Wallet to sign in
        </p>
        <p className="text-xs text-gray-400 mt-1">Waiting for authentication...</p>
      </div>
    )
  }

  if (state === 'scanned') {
    return (
      <div className="flex flex-col items-center py-8">
        <div className="w-8 h-8 border-2 border-green-600 border-t-transparent rounded-full animate-spin" />
        <p className="text-sm text-gray-600 mt-4">Authenticated. Loading...</p>
      </div>
    )
  }

  return (
    <div className="flex flex-col items-center py-4">
      <div className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-red-50 mb-3">
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} className="text-red-500">
          <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
        </svg>
      </div>
      <p className="text-sm text-red-600 text-center mb-4">{error}</p>
      <button onClick={initiate} className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors">
        Try Again
      </button>
    </div>
  )
}

function EmailLogin({ login }: { login: (token: string) => Promise<void> }) {
  const [step, setStep] = useState<EmailStep>('email')
  const [email, setEmail] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      const res = await fetch('/api/auth/email/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email.trim() }),
      })

      if (!res.ok) {
        const problem = await res.json().catch(() => null)
        throw new Error(problem?.detail || `Error: ${res.status}`)
      }

      setStep('totp')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to verify email')
    } finally {
      setLoading(false)
    }
  }

  const handleTotpSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      const res = await fetch('/api/auth/totp/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email.trim(), code }),
      })

      if (!res.ok) {
        const problem = await res.json().catch(() => null)
        throw new Error(problem?.detail || `Error: ${res.status}`)
      }

      const data = await res.json()
      await login(data.token)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Authentication failed')
    } finally {
      setLoading(false)
    }
  }

  if (step === 'totp') {
    return (
      <form onSubmit={handleTotpSubmit} className="space-y-4">
        <div>
          <p className="text-sm text-gray-600 mb-3 text-center">
            Enter the 6-digit code from your authenticator app
          </p>
          <label htmlFor="totp-code" className="block text-sm font-medium text-gray-700 mb-1">
            TOTP Code
          </label>
          <input
            id="totp-code"
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
            placeholder="000000"
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-center text-lg tracking-widest
              focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            autoFocus
          />
        </div>

        {error && <p className="text-sm text-red-600 text-center">{error}</p>}

        <button
          type="submit"
          disabled={loading || code.length < 6}
          className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white
            hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {loading ? 'Verifying...' : 'Verify'}
        </button>

        <button
          type="button"
          onClick={() => { setStep('email'); setCode(''); setError(null) }}
          className="w-full text-sm text-gray-500 hover:text-gray-700"
        >
          Back
        </button>
      </form>
    )
  }

  return (
    <form onSubmit={handleEmailSubmit} className="space-y-4">
      <div>
        <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
          Email
        </label>
        <input
          id="email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="admin@example.com"
          className="w-full px-3 py-2 border border-gray-300 rounded-lg
            focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          autoFocus
          required
        />
      </div>

      {error && <p className="text-sm text-red-600 text-center">{error}</p>}

      <button
        type="submit"
        disabled={loading || !email.trim()}
        className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white
          hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
      >
        {loading ? 'Checking...' : 'Continue'}
      </button>

      <div className="relative my-4">
        <div className="absolute inset-0 flex items-center">
          <div className="w-full border-t border-gray-200" />
        </div>
        <div className="relative flex justify-center text-xs">
          <span className="bg-white px-2 text-gray-400">or sign in with</span>
        </div>
      </div>

      <div className="flex gap-3">
        <a
          href="/api/auth/oidc/google/authorize"
          className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 border border-gray-300
            rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors"
        >
          <svg width="18" height="18" viewBox="0 0 24 24">
            <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
            <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
            <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
            <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
          </svg>
          Google
        </a>
        <a
          href="/api/auth/oidc/microsoft/authorize"
          className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 border border-gray-300
            rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors"
        >
          <svg width="18" height="18" viewBox="0 0 23 23">
            <rect x="1" y="1" width="10" height="10" fill="#f25022"/>
            <rect x="12" y="1" width="10" height="10" fill="#7fba00"/>
            <rect x="1" y="12" width="10" height="10" fill="#00a4ef"/>
            <rect x="12" y="12" width="10" height="10" fill="#ffb900"/>
          </svg>
          Microsoft
        </a>
      </div>
    </form>
  )
}

export default function LoginPage() {
  const login = useAuthStore((s) => s.login)
  const [tab, setTab] = useState<Tab>('email')

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
          <div className="text-center mb-6">
            <img src="/admin/icon-192.png" alt="SSDID Drive" className="w-12 h-12 rounded-xl mb-4 mx-auto" />
            <h1 className="text-xl font-bold text-gray-900">SSDID Drive</h1>
            <p className="text-sm text-gray-500 mt-1">Admin Portal</p>
          </div>

          <div className="flex border-b border-gray-200 mb-6">
            <button
              onClick={() => setTab('email')}
              className={`flex-1 pb-2 text-sm font-medium border-b-2 transition-colors ${
                tab === 'email'
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              Email
            </button>
            <button
              onClick={() => setTab('wallet')}
              className={`flex-1 pb-2 text-sm font-medium border-b-2 transition-colors ${
                tab === 'wallet'
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              SSDID Wallet
            </button>
          </div>

          {tab === 'email' ? <EmailLogin login={login} /> : <WalletLogin login={login} />}

          <p className="text-xs text-gray-400 text-center mt-6">
            Requires SuperAdmin role to access.
          </p>
        </div>
      </div>
    </div>
  )
}
