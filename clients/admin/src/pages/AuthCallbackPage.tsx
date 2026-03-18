import { useEffect, useState, useRef, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useAuthStore } from '../stores/authStore'

export default function AuthCallbackPage() {
  const [searchParams] = useSearchParams()
  const login = useAuthStore((s) => s.login)
  const loginError = useAuthStore((s) => s.loginError)
  const [loginCallError, setLoginCallError] = useState<string | null>(null)
  const attempted = useRef(false)

  // Derive URL-based errors during render (not in an effect)
  const token = useMemo(() => searchParams.get('token'), [searchParams])
  const callbackError = useMemo(() => searchParams.get('error'), [searchParams])
  const urlError = callbackError ?? (!token ? 'No token received' : null)

  useEffect(() => {
    if (attempted.current) return
    attempted.current = true

    if (urlError || !token) return

    login(token).catch((err) => {
      setLoginCallError(err instanceof Error ? err.message : 'Login failed')
    })
  }, [token, urlError, login])

  const displayError = urlError || loginCallError || loginError

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8 text-center">
          {displayError ? (
            <>
              <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-red-50 mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} className="text-red-500">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                </svg>
              </div>
              <h2 className="text-lg font-semibold text-gray-900 mb-2">Access Denied</h2>
              <p className="text-sm text-gray-600 mb-6">{displayError}</p>
              <a
                href="/admin/"
                className="inline-block rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors"
              >
                Back to Login
              </a>
            </>
          ) : (
            <>
              <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto" />
              <p className="text-sm text-gray-500 mt-4">Signing you in...</p>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
