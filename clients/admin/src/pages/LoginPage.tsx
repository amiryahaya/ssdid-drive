import { useState, useEffect, useCallback, useRef } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { useAuthStore } from '../stores/authStore'

type LoginState = 'loading' | 'qr' | 'scanned' | 'error'

interface QrPayload {
  challenge_id: string
  subscriber_secret: string
  qr_payload: Record<string, unknown>
}

export default function LoginPage() {
  const login = useAuthStore((s) => s.login)
  const [state, setState] = useState<LoginState>('loading')
  const [qrData, setQrData] = useState<QrPayload | null>(null)
  const [error, setError] = useState<string | null>(null)
  const eventSourceRef = useRef<EventSource | null>(null)

  const initiate = useCallback(async () => {
    setState('loading')
    setError(null)

    // Close previous SSE connection
    eventSourceRef.current?.close()

    try {
      const res = await fetch('/api/auth/ssdid/login/initiate', { method: 'POST' })
      if (!res.ok) throw new Error(`Server error: ${res.status}`)
      const data: QrPayload = await res.json()
      setQrData(data)
      setState('qr')

      // Open SSE connection to wait for wallet authentication
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

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-sm">
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
          <div className="text-center mb-6">
            <img src="/icon-192.png" alt="SSDID Drive" className="w-12 h-12 rounded-xl mb-4" />
            <h1 className="text-xl font-bold text-gray-900">SSDID Drive</h1>
            <p className="text-sm text-gray-500 mt-1">Admin Portal</p>
          </div>

          {state === 'loading' && (
            <div className="flex flex-col items-center py-8">
              <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin" />
              <p className="text-sm text-gray-500 mt-4">Generating QR code...</p>
            </div>
          )}

          {state === 'qr' && qrData && (
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

          {state === 'scanned' && (
            <div className="flex flex-col items-center py-8">
              <div className="w-8 h-8 border-2 border-green-600 border-t-transparent rounded-full animate-spin" />
              <p className="text-sm text-gray-600 mt-4">Authenticated. Loading...</p>
            </div>
          )}

          {state === 'error' && (
            <div className="flex flex-col items-center py-4">
              <div className="inline-flex items-center justify-center w-10 h-10 rounded-full bg-red-50 mb-3">
                <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} className="text-red-500">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
                </svg>
              </div>
              <p className="text-sm text-red-600 text-center mb-4">{error}</p>
              <button
                onClick={initiate}
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium
                  text-white hover:bg-blue-700 focus:outline-none focus:ring-2
                  focus:ring-blue-500 focus:ring-offset-2 transition-colors"
              >
                Try Again
              </button>
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
