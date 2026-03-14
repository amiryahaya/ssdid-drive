import { useEffect, useState } from 'react'
import { useSearchParams, useNavigate } from 'react-router-dom'
import { useAuthStore } from '../stores/authStore'
import { api } from '../services/api'

/** Map backend error codes to user-friendly messages */
const ERROR_MESSAGES: Record<string, string> = {
  no_account: 'No account linked to this provider. Please register first.',
  suspended: 'Your account has been suspended.',
  session_limit: 'Too many active sessions. Please try again later.',
  invalid_code: 'Invalid authorization request. Please try again.',
  invalid_state: 'Session expired. Please try signing in again.',
  provider_error: 'Authentication provider error. Please try again.',
}

interface ExchangeResponse {
  token: string
  mfa_required: boolean
  totp_setup_required: boolean
}

export default function AuthCallbackPage() {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const login = useAuthStore((s) => s.login)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const errorCode = searchParams.get('error')
    if (errorCode) {
      setError(ERROR_MESSAGES[errorCode] ?? 'An unexpected error occurred. Please try again.')
      return
    }

    const code = searchParams.get('code')
    if (!code) {
      setError('Invalid callback. Please try signing in again.')
      return
    }

    // Exchange the one-time code for a session token via POST
    api
      .post<ExchangeResponse>('/api/auth/oidc/exchange', { code })
      .then(async (result) => {
        if (result.mfa_required) {
          // Redirect to login page with MFA token for TOTP verification
          navigate('/', {
            state: { mfaToken: result.token, step: 'totp' },
            replace: true,
          })
          return
        }

        if (result.totp_setup_required) {
          // Admin without TOTP — they have a restricted session, redirect to setup
          setError(
            'TOTP setup is required for admin access. Please set up two-factor authentication in your account settings.'
          )
          return
        }

        // Full session — complete login
        await login(result.token)
      })
      .catch((err) => {
        setError(err instanceof Error ? err.message : 'Login failed. Please try again.')
      })
  }, [searchParams, login, navigate])

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
        <div className="w-full max-w-sm">
          <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
            <div className="flex flex-col items-center py-4">
              <div className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-red-50 mb-3">
                <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} className="text-red-500">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
                </svg>
              </div>
              <p className="text-sm text-red-600 text-center mb-4">{error}</p>
              <a
                href="/admin"
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium
                  text-white hover:bg-blue-700 focus:outline-none focus:ring-2
                  focus:ring-blue-500 focus:ring-offset-2 transition-colors"
              >
                Back to Login
              </a>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
          <div className="flex flex-col items-center py-8">
            <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin" />
            <p className="text-sm text-gray-500 mt-4">Completing sign in...</p>
          </div>
        </div>
      </div>
    </div>
  )
}
