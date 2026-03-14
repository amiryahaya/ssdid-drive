import { useState } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { useAuthStore } from '../stores/authStore'

type Step = 'form' | 'totp' | 'backup' | 'error'

interface TotpSetup {
  secret: string
  otpauth_uri: string
  email: string
}

interface BootstrapResult {
  token: string
  backup_codes: string[]
  account_id: string
  display_name: string
  email: string
}

export default function BootstrapPage() {
  const login = useAuthStore((s) => s.login)
  const [step, setStep] = useState<Step>('form')
  const [email, setEmail] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [totpSetup, setTotpSetup] = useState<TotpSetup | null>(null)
  const [backupCodes, setBackupCodes] = useState<string[]>([])
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const handleSetup = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      const res = await fetch('/api/admin/bootstrap/setup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: email.trim(),
          display_name: displayName.trim(),
        }),
      })

      if (!res.ok) {
        const problem = await res.json().catch(() => null)
        throw new Error(problem?.detail || `Error: ${res.status}`)
      }

      const data: TotpSetup = await res.json()
      setTotpSetup(data)
      setStep('totp')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Setup failed')
    } finally {
      setLoading(false)
    }
  }

  const handleConfirm = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)

    try {
      const res = await fetch('/api/admin/bootstrap/confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email.trim(), code }),
      })

      if (!res.ok) {
        const problem = await res.json().catch(() => null)
        throw new Error(problem?.detail || `Error: ${res.status}`)
      }

      const data: BootstrapResult = await res.json()
      setBackupCodes(data.backup_codes)
      setStep('backup')

      // Pre-set the token so login just validates
      await login(data.token)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Verification failed')
    } finally {
      setLoading(false)
    }
  }

  const handleContinue = () => {
    window.location.href = '/admin/'
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-md">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
          <div className="text-center mb-6">
            <img src="/admin/icon-192.png" alt="SSDID Drive" className="w-12 h-12 rounded-xl mb-4 mx-auto" />
            <h1 className="text-xl font-bold text-gray-900">SSDID Drive Setup</h1>
            <p className="text-sm text-gray-500 mt-1">Create your SuperAdmin account</p>
          </div>

          {step === 'form' && (
            <form onSubmit={handleSetup} className="space-y-4">
              <div>
                <label htmlFor="display-name" className="block text-sm font-medium text-gray-700 mb-1">
                  Display Name
                </label>
                <input
                  id="display-name"
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder="Admin"
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg
                    focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  required
                  autoFocus
                />
              </div>
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
                  required
                />
              </div>

              {error && <p className="text-sm text-red-600 text-center">{error}</p>}

              <button
                type="submit"
                disabled={loading || !email.trim() || !displayName.trim()}
                className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white
                  hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                {loading ? 'Setting up...' : 'Continue'}
              </button>
            </form>
          )}

          {step === 'totp' && totpSetup && (
            <form onSubmit={handleConfirm} className="space-y-4">
              <p className="text-sm text-gray-600 text-center">
                Scan this QR code with your authenticator app
              </p>

              <div className="flex justify-center">
                <div className="bg-white p-3 rounded-lg border border-gray-100">
                  <QRCodeSVG value={totpSetup.otpauth_uri} size={180} level="M" />
                </div>
              </div>

              <div className="bg-gray-50 rounded-lg p-3">
                <p className="text-xs text-gray-500 mb-1">Manual entry key:</p>
                <p className="font-mono text-xs text-gray-700 break-all select-all">{totpSetup.secret}</p>
              </div>

              <div>
                <label htmlFor="totp-code" className="block text-sm font-medium text-gray-700 mb-1">
                  Enter 6-digit code
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
                {loading ? 'Verifying...' : 'Verify & Create Account'}
              </button>
            </form>
          )}

          {step === 'backup' && (
            <div className="space-y-4">
              <div className="bg-amber-50 border border-amber-200 rounded-lg p-4">
                <p className="text-sm font-medium text-amber-800 mb-2">Save your backup codes</p>
                <p className="text-xs text-amber-700 mb-3">
                  Store these codes in a safe place. Each code can only be used once if you lose access to your authenticator app.
                </p>
                <div className="grid grid-cols-2 gap-2">
                  {backupCodes.map((c, i) => (
                    <code key={i} className="bg-white px-2 py-1 rounded text-xs font-mono text-center border border-amber-200">
                      {c}
                    </code>
                  ))}
                </div>
              </div>

              <button
                onClick={() => {
                  navigator.clipboard.writeText(backupCodes.join('\n'))
                }}
                className="w-full rounded-lg bg-gray-100 px-4 py-2 text-sm font-medium text-gray-700
                  hover:bg-gray-200 transition-colors"
              >
                Copy Codes
              </button>

              <button
                onClick={handleContinue}
                className="w-full rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-medium text-white
                  hover:bg-blue-700 transition-colors"
              >
                Continue to Admin Portal
              </button>
            </div>
          )}

          {step === 'error' && (
            <div className="text-center py-4">
              <p className="text-sm text-red-600 mb-4">{error}</p>
              <button
                onClick={() => { setStep('form'); setError(null) }}
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors"
              >
                Try Again
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
