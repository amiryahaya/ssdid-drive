import Foundation
import Combine

/// View model for the members management screen (Admin/Owner only)
final class MembersViewModel: BaseViewModel {

    // MARK: - Published Properties

    @Published var members: [TenantMember] = []
    @Published var isRefreshing: Bool = false

    // MARK: - Properties

    private let apiClient: APIClient
    private let tenantId: String
    private let callerRole: UserRole
    private let currentUserId: String?

    // MARK: - Computed Properties

    /// Whether the current user can manage members (change roles, remove)
    var canManageMembers: Bool {
        callerRole == .admin
    }

    var isEmpty: Bool {
        members.isEmpty && !isLoading
    }

    // MARK: - Initialization

    init(apiClient: APIClient, tenantId: String, callerRole: UserRole, currentUserId: String?) {
        self.apiClient = apiClient
        self.tenantId = tenantId
        self.callerRole = callerRole
        self.currentUserId = currentUserId
        super.init()
    }

    // MARK: - Data Loading

    func loadMembers() {
        isLoading = true
        clearError()

        let endpoint = Constants.API.Endpoints.tenantMembers
            .replacingOccurrences(of: "{id}", with: tenantId)

        Task {
            do {
                let response: TenantMembersResponse = try await apiClient.request(
                    endpoint,
                    method: .get,
                    requiresAuth: true
                )

                await MainActor.run {
                    self.members = response.data
                    self.isLoading = false
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                    self.isRefreshing = false
                }
            }
        }
    }

    func refresh() {
        isRefreshing = true
        loadMembers()
    }

    // MARK: - Member Actions

    /// Whether the current user can modify this member
    func canModify(member: TenantMember) -> Bool {
        guard canManageMembers else { return false }
        // Cannot modify self
        return member.id != currentUserId
    }

    /// Whether the member is the current user
    func isCurrentUser(member: TenantMember) -> Bool {
        member.id == currentUserId
    }

    /// Available roles to assign to a member
    var assignableRoles: [UserRole] {
        switch callerRole {
        case .admin:
            return [.member, .admin, .viewer]
        default:
            return []
        }
    }

    /// Change a member's role
    func changeRole(member: TenantMember, to newRole: UserRole) {
        guard canModify(member: member) else { return }

        isLoading = true

        let endpoint = Constants.API.Endpoints.tenantMember
            .replacingOccurrences(of: "{id}", with: tenantId)
            .replacingOccurrences(of: "{userId}", with: member.id)

        let request = UpdateMemberRoleRequest(role: newRole.rawValue)

        Task {
            do {
                try await apiClient.requestNoContent(
                    endpoint,
                    method: .put,
                    body: request,
                    requiresAuth: true
                )

                await MainActor.run {
                    // Update the member locally
                    if let index = self.members.firstIndex(where: { $0.id == member.id }) {
                        let updated = TenantMember(
                            id: member.id,
                            email: member.email,
                            displayName: member.displayName,
                            role: newRole,
                            joinedAt: member.joinedAt
                        )
                        self.members[index] = updated
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    /// Remove a member from the tenant
    func removeMember(_ member: TenantMember) {
        guard canModify(member: member) else { return }

        isLoading = true

        let endpoint = Constants.API.Endpoints.tenantMember
            .replacingOccurrences(of: "{id}", with: tenantId)
            .replacingOccurrences(of: "{userId}", with: member.id)

        Task {
            do {
                try await apiClient.requestNoContent(
                    endpoint,
                    method: .delete,
                    requiresAuth: true
                )

                await MainActor.run {
                    self.members.removeAll { $0.id == member.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
}
