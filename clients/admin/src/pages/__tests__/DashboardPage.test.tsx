import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import DashboardPage from '../DashboardPage'

vi.mock('../../services/api', () => ({
  api: {
    get: vi.fn(),
  },
}))

import { api } from '../../services/api'

const mockGet = api.get as ReturnType<typeof vi.fn>

beforeEach(() => {
  vi.clearAllMocks()
})

describe('DashboardPage', () => {
  it('shows loading skeletons initially', () => {
    // Never resolve the API calls
    mockGet.mockReturnValue(new Promise(() => {}))
    const { container } = render(<DashboardPage />)
    const skeletons = container.querySelectorAll('.animate-pulse')
    expect(skeletons.length).toBe(5)
  })

  it('displays stats after successful fetch', async () => {
    mockGet
      .mockResolvedValueOnce({
        user_count: 42,
        tenant_count: 8,
        file_count: 350,
        total_storage_bytes: 5368709120, // 5 GB
        active_session_count: 3,
      })
      .mockResolvedValueOnce({
        active_sessions: 7,
        active_challenges: 2,
      })

    render(<DashboardPage />)

    await waitFor(() => {
      expect(screen.getByText('Users')).toBeInTheDocument()
      expect(screen.getByText('42')).toBeInTheDocument()
      expect(screen.getByText('Tenants')).toBeInTheDocument()
      expect(screen.getByText('8')).toBeInTheDocument()
      expect(screen.getByText('Files')).toBeInTheDocument()
      expect(screen.getByText('350')).toBeInTheDocument()
      expect(screen.getByText('Storage')).toBeInTheDocument()
      expect(screen.getByText('5 GB')).toBeInTheDocument()
      expect(screen.getByText('Active Sessions')).toBeInTheDocument()
      // Session count should prefer sessions endpoint (7) over stats endpoint (3)
      expect(screen.getByText('7')).toBeInTheDocument()
    })
  })

  it('shows error banner when stats fetch fails', async () => {
    mockGet
      .mockRejectedValueOnce(new Error('Server error'))
      .mockResolvedValueOnce({ active_sessions: 0, active_challenges: 0 })

    render(<DashboardPage />)

    await waitFor(() => {
      expect(screen.getByText('Failed to load stats')).toBeInTheDocument()
    })
  })

  it('shows error banner when sessions fetch fails', async () => {
    mockGet
      .mockResolvedValueOnce({
        user_count: 10, tenant_count: 2, file_count: 50,
        total_storage_bytes: 0, active_session_count: 1,
      })
      .mockRejectedValueOnce(new Error('fail'))

    render(<DashboardPage />)

    await waitFor(() => {
      expect(screen.getByText('Failed to load sessions')).toBeInTheDocument()
    })
  })

  it('shows both errors when both fail', async () => {
    mockGet
      .mockRejectedValueOnce(new Error('fail'))
      .mockRejectedValueOnce(new Error('fail'))

    render(<DashboardPage />)

    await waitFor(() => {
      expect(screen.getByText('Failed to load stats. Failed to load sessions')).toBeInTheDocument()
    })
  })

  it('shows dash for stats when stats fetch failed but sessions succeeded', async () => {
    mockGet
      .mockRejectedValueOnce(new Error('fail'))
      .mockResolvedValueOnce({ active_sessions: 5, active_challenges: 0 })

    render(<DashboardPage />)

    await waitFor(() => {
      // Stats values should show em-dash
      const dashes = screen.getAllByText('\u2014')
      expect(dashes.length).toBeGreaterThanOrEqual(3) // Users, Tenants, Files, Storage
    })
  })

  it('falls back to active_session_count from stats when sessions endpoint fails', async () => {
    mockGet
      .mockResolvedValueOnce({
        user_count: 10, tenant_count: 2, file_count: 50,
        total_storage_bytes: 0, active_session_count: 3,
      })
      .mockRejectedValueOnce(new Error('fail'))

    render(<DashboardPage />)

    await waitFor(() => {
      expect(screen.getByText('3')).toBeInTheDocument()
    })
  })
})
