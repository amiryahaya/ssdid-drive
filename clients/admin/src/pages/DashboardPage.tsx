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
    let mounted = true
    async function fetchData() {
      const errs: string[] = []

      const [statsResult, sessionsResult] = await Promise.allSettled([
        api.get<StatsResponse>('/api/admin/stats'),
        api.get<SessionsResponse>('/api/admin/sessions'),
      ])

      if (!mounted) return

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
    return () => { mounted = false }
  }, [])

  if (loading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="bg-white rounded-xl shadow-sm border border-gray-100 p-5 animate-pulse">
            <div className="h-3 bg-gray-100 rounded w-20 mb-3" />
            <div className="h-7 bg-gray-100 rounded w-16" />
          </div>
        ))}
      </div>
    )
  }

  const sessionCount = sessions?.active_sessions ?? stats?.active_session_count ?? 0

  return (
    <div>
      {errors.length > 0 && (
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-4">
          {errors.join('. ')}
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <StatsCard title="Users" value={stats?.user_count ?? '\u2014'} accent="blue" />
        <StatsCard title="Tenants" value={stats?.tenant_count ?? '\u2014'} accent="purple" />
        <StatsCard title="Files" value={stats?.file_count ?? '\u2014'} accent="green" />
        <StatsCard
          title="Storage"
          value={stats ? formatStorageQuota(stats.total_storage_bytes) : '\u2014'}
          accent="amber"
        />
        <StatsCard title="Active Sessions" value={sessionCount} accent="blue" />
      </div>
    </div>
  )
}
