import { useState } from 'react'
import { useAuthStore } from '../stores/authStore'

type EmailStep = 'email' | 'totp'

export default function LoginPage() {
  const login = useAuthStore((s) => s.login)
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
      await login(data.session_token)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Authentication failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
          <div className="text-center mb-6">
            <img src="/admin/icon-192.png" alt="SSDID Drive" className="w-12 h-12 rounded-xl mb-4 mx-auto" />
            <h1 className="text-xl font-bold text-gray-900">SSDID Drive</h1>
            <p className="text-sm text-gray-500 mt-1">Admin Portal</p>
          </div>

          {step === 'totp' ? (
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
          ) : (
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
            </form>
          )}

          <p className="text-xs text-gray-400 text-center mt-6">
            SuperAdmin access only. Email + TOTP required.
          </p>
        </div>
      </div>
    </div>
  )
}
