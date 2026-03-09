import { useEffect, useState } from 'react'
import { api } from '../services/api'
import StatsCard from '../components/StatsCard'
import { formatStorageQuota } from '../utils/format'

interface StatsResponse {
  user_count: number
  tenant_count: number
  file_count: number
  total_storage_bytes: number
  active_session_count: number
}

interface SessionsResponse {
  active_sessions: number
  active_challenges: number
}

export default function DashboardPage() {
  const [stats, setStats] = useState<StatsResponse | null>(null)
  const [sessions, setSessions] = useState<SessionsResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [errors, setErrors] = useState<string[]>([])

  useEffect(() => {
    async function fetchData() {
      const errs: string[] = []

      const [statsResult, sessionsResult] = await Promise.allSettled([
        api.get<StatsResponse>('/api/admin/stats'),
        api.get<SessionsResponse>('/api/admin/sessions'),
      ])

      if (statsResult.status === 'fulfilled') {
        setStats(statsResult.value)
      } else {
        errs.push('Failed to load stats')
      }

      if (sessionsResult.status === 'fulfilled') {
        setSessions(sessionsResult.value)
      } else {
        errs.push('Failed to load sessions')
      }

      setErrors(errs)
      setLoading(false)
    }
    fetchData()
  }, [])

  if (loading) {
    return (
      <div>
        <h2 className="text-2xl font-semibold mb-6">Dashboard</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="bg-white rounded-lg shadow p-6 animate-pulse">
              <div className="h-4 bg-gray-200 rounded w-24 mb-4" />
              <div className="h-8 bg-gray-200 rounded w-20" />
            </div>
          ))}
        </div>
      </div>
    )
  }

  const sessionCount = sessions?.active_sessions ?? stats?.active_session_count ?? 0

  return (
    <div>
      <h2 className="text-2xl font-semibold mb-6">Dashboard</h2>

      {errors.length > 0 && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {errors.join('. ')}
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
        <StatsCard title="Users" value={stats?.user_count ?? '\u2014'} />
        <StatsCard title="Tenants" value={stats?.tenant_count ?? '\u2014'} />
        <StatsCard title="Files" value={stats?.file_count ?? '\u2014'} />
        <StatsCard
          title="Storage"
          value={stats ? formatStorageQuota(stats.total_storage_bytes) : '\u2014'}
        />
        <StatsCard title="Active Sessions" value={sessionCount} />
      </div>
    </div>
  )
}
