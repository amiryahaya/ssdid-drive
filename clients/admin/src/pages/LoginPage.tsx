import { useState, type FormEvent } from 'react'
import { useAuthStore } from '../stores/authStore'

export default function LoginPage() {
  const login = useAuthStore((s) => s.login)
  const [token, setToken] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    const trimmed = token.trim()
    if (!trimmed) return

    setError(null)
    setLoading(true)
    try {
      await login(trimmed)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-8">
          <div className="text-center mb-8">
            <h1 className="text-xl font-bold text-gray-900">SSDID Drive</h1>
            <p className="text-sm text-gray-500 mt-1">Admin Portal</p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="token" className="block text-sm font-medium text-gray-700 mb-1">
                Bearer Token
              </label>
              <input
                id="token"
                type="password"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                placeholder="Paste your session token"
                className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm
                  placeholder:text-gray-400 focus:outline-none focus:ring-2
                  focus:ring-blue-500 focus:border-transparent"
                autoFocus
                disabled={loading}
              />
            </div>

            {error && (
              <p className="text-sm text-red-600">{error}</p>
            )}

            <button
              type="submit"
              disabled={loading || !token.trim()}
              className="w-full rounded-md bg-blue-600 px-3 py-2 text-sm font-medium
                text-white hover:bg-blue-700 focus:outline-none focus:ring-2
                focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50
                disabled:cursor-not-allowed"
            >
              {loading ? 'Authenticating...' : 'Sign In'}
            </button>
          </form>

          <p className="text-xs text-gray-400 text-center mt-6">
            Authenticate using your SSDID session token.
          </p>
        </div>
      </div>
    </div>
  )
}
