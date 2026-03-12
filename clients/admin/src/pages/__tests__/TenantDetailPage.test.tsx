import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import TenantDetailPage from '../TenantDetailPage'
import { useAdminStore } from '../../stores/adminStore'

vi.mock('../../stores/adminStore', () => ({
  useAdminStore: vi.fn(),
}))

const mockStore = {
  tenants: [{ id: 't1', name: 'Acme', slug: 'acme', disabled: false, storage_quota_bytes: null, user_count: 2, created_at: '2026-03-01T00:00:00Z' }],
  tenantMembers: [
    { user_id: 'u1', did: 'did:ssdid:abc', display_name: 'John', email: 'john@acme.com', role: 'Owner' },
  ],
  tenantMembersLoading: false,
  tenantInvitations: [],
  tenantInvitationsLoading: false,
  tenantInvitationsTotal: 0,
  fetchTenantById: vi.fn(),
  fetchTenantMembers: vi.fn().mockResolvedValue(undefined),
  fetchTenantInvitations: vi.fn().mockResolvedValue(undefined),
  revokeAdminInvitation: vi.fn().mockResolvedValue(undefined),
  createAdminInvitation: vi.fn(),
}

beforeEach(() => {
  vi.clearAllMocks()
  // Reset mocked functions so they carry resolved state correctly
  mockStore.fetchTenantMembers = vi.fn().mockResolvedValue(undefined)
  mockStore.fetchTenantInvitations = vi.fn().mockResolvedValue(undefined)
  mockStore.revokeAdminInvitation = vi.fn().mockResolvedValue(undefined)
  mockStore.fetchTenantById = vi.fn()
  mockStore.createAdminInvitation = vi.fn()
  ;(useAdminStore as unknown as ReturnType<typeof vi.fn>).mockImplementation(
    (selector?: (s: unknown) => unknown) =>
      selector ? selector(mockStore) : mockStore
  )
})

function renderPage() {
  return render(
    <MemoryRouter initialEntries={['/tenants/t1']}>
      <Routes>
        <Route path="/tenants/:id" element={<TenantDetailPage />} />
      </Routes>
    </MemoryRouter>
  )
}

describe('TenantDetailPage — Invitations', () => {
  it('shows Invite User button', () => {
    renderPage()
    expect(screen.getByText('Invite User')).toBeInTheDocument()
  })

  it('shows empty state when no invitations', () => {
    renderPage()
    expect(screen.getByText('No invitations for this tenant.')).toBeInTheDocument()
  })

  it('renders pending invitations table', () => {
    mockStore.tenantInvitations = [
      { id: 'i1', tenant_id: 't1', invited_by_id: 'u1', email: 'new@acme.com', invited_user_id: null, role: 'owner', status: 'pending', short_code: 'ACME-X7K2', message: null, expires_at: '2026-03-19T00:00:00Z', created_at: '2026-03-12T00:00:00Z' },
    ]

    renderPage()
    expect(screen.getByText('new@acme.com')).toBeInTheDocument()
    expect(screen.getByText('ACME-X7K2')).toBeInTheDocument()
    expect(screen.getByText('Revoke')).toBeInTheDocument()
  })

  it('opens invite dialog on button click', async () => {
    const user = userEvent.setup()
    mockStore.tenantInvitations = []

    renderPage()
    await user.click(screen.getByText('Invite User'))

    await waitFor(() => {
      expect(screen.getByText(/Invite a user to/)).toBeInTheDocument()
    })
  })

  it('shows revoke button only for pending invitations', () => {
    mockStore.tenantInvitations = [
      { id: 'i1', tenant_id: 't1', invited_by_id: 'u1', email: 'a@b.com', invited_user_id: null, role: 'admin', status: 'accepted', short_code: 'ACME-1234', message: null, expires_at: '2026-03-19T00:00:00Z', created_at: '2026-03-12T00:00:00Z' },
    ]

    renderPage()
    expect(screen.queryByText('Revoke')).not.toBeInTheDocument()
  })
})
