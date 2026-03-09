import { useEffect, useState } from 'react'
import { api } from '../services/api'
import StatsCard from '../components/StatsCard'

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

function formatStorage(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`
}

export default function DashboardPage() {
  const [stats, setStats] = useState<StatsResponse | null>(null)
  const [sessions, setSessions] = useState<SessionsResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function fetchData() {
      try {
        const [statsData, sessionsData] = await Promise.all([
          api.get<StatsResponse>('/api/admin/stats'),
          api.get<SessionsResponse>('/api/admin/sessions'),
        ])
        setStats(statsData)
        setSessions(sessionsData)
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to load dashboard data')
      } finally {
        setLoading(false)
      }
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

  if (error) {
    return (
      <div>
        <h2 className="text-2xl font-semibold mb-6">Dashboard</h2>
        <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4">
          {error}
        </div>
      </div>
    )
  }

  const sessionCount = sessions?.active_sessions ?? stats?.active_session_count ?? 0

  return (
    <div>
      <h2 className="text-2xl font-semibold mb-6">Dashboard</h2>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
        <StatsCard title="Users" value={stats?.user_count ?? 0} />
        <StatsCard title="Tenants" value={stats?.tenant_count ?? 0} />
        <StatsCard title="Files" value={stats?.file_count ?? 0} />
        <StatsCard
          title="Storage"
          value={formatStorage(stats?.total_storage_bytes ?? 0)}
        />
        <StatsCard title="Active Sessions" value={sessionCount} />
      </div>
    </div>
  )
}
