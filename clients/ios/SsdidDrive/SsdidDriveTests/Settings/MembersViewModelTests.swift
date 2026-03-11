import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for MembersViewModel
@MainActor
final class MembersViewModelTests: XCTestCase {

    // MARK: - Properties

    var mockAPIClient: MockAPIClient!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Constants

    private let testTenantId = "ten_test123"
    private let currentUserId = "usr_current"

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockAPIClient = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createViewModel(
        callerRole: UserRole = .owner,
        currentUserId: String? = "usr_current"
    ) -> MembersViewModel {
        MembersViewModel(
            apiClient: mockAPIClient,
            tenantId: testTenantId,
            callerRole: callerRole,
            currentUserId: currentUserId
        )
    }

    private var membersResponseJSON: String {
        let joinedAt = ISO8601DateFormatter().string(from: Date())
        return """
        {
            "data": [
                {
                    "id": "usr_current",
                    "email": "me@example.com",
                    "display_name": "Current User",
                    "role": "owner",
                    "joined_at": "\(joinedAt)"
                },
                {
                    "id": "usr_other",
                    "email": "other@example.com",
                    "display_name": "Other User",
                    "role": "member",
                    "joined_at": "\(joinedAt)"
                },
                {
                    "id": "usr_admin",
                    "email": "admin@example.com",
                    "display_name": "Admin User",
                    "role": "admin",
                    "joined_at": "\(joinedAt)"
                }
            ]
        }
        """
    }

    private var membersEndpoint: String {
        Constants.API.Endpoints.tenantMembers
            .replacingOccurrences(of: "{id}", with: testTenantId)
    }

    private func memberEndpoint(userId: String) -> String {
        Constants.API.Endpoints.tenantMember
            .replacingOccurrences(of: "{id}", with: testTenantId)
            .replacingOccurrences(of: "{userId}", with: userId)
    }

    // MARK: - canManageMembers Tests

    func testCanManageMembers_admin_returnsTrue() {
        let vm = createViewModel(callerRole: .admin)
        XCTAssertTrue(vm.canManageMembers)
    }

    func testCanManageMembers_owner_returnsTrue() {
        let vm = createViewModel(callerRole: .owner)
        XCTAssertTrue(vm.canManageMembers)
    }

    func testCanManageMembers_member_returnsFalse() {
        let vm = createViewModel(callerRole: .member)
        XCTAssertFalse(vm.canManageMembers)
    }

    func testCanManageMembers_viewer_returnsFalse() {
        let vm = createViewModel(callerRole: .viewer)
        XCTAssertFalse(vm.canManageMembers)
    }

    // MARK: - canModify Tests

    func testCanModify_otherMember_asOwner_returnsTrue() async throws {
        let vm = createViewModel(callerRole: .owner)
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        let otherMember = vm.members.first { $0.id == "usr_other" }!
        XCTAssertTrue(vm.canModify(member: otherMember))
    }

    func testCanModify_selfMember_returnsFalse() async throws {
        let vm = createViewModel(callerRole: .owner)
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        let selfMember = vm.members.first { $0.id == currentUserId }!
        XCTAssertFalse(vm.canModify(member: selfMember))
    }

    func testCanModify_asMember_returnsFalse() async throws {
        let vm = createViewModel(callerRole: .member)
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        let otherMember = vm.members.first { $0.id == "usr_other" }!
        XCTAssertFalse(vm.canModify(member: otherMember))
    }

    // MARK: - assignableRoles Tests

    func testAssignableRoles_forOwner_returnsAdminMemberViewer() {
        let vm = createViewModel(callerRole: .owner)
        XCTAssertEqual(vm.assignableRoles, [.admin, .member, .viewer])
    }

    func testAssignableRoles_forAdmin_returnsMemberViewer() {
        let vm = createViewModel(callerRole: .admin)
        XCTAssertEqual(vm.assignableRoles, [.member, .viewer])
    }

    func testAssignableRoles_forMember_returnsEmpty() {
        let vm = createViewModel(callerRole: .member)
        XCTAssertTrue(vm.assignableRoles.isEmpty)
    }

    // MARK: - changeRole Tests

    func testChangeRole_success_updatesLocalState() async throws {
        let vm = createViewModel(callerRole: .owner)
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        let otherMember = vm.members.first { $0.id == "usr_other" }!
        XCTAssertEqual(otherMember.role, .member)

        // requestNoContent won't fail if no error is configured
        vm.changeRole(member: otherMember, to: .admin)
        try await Task.sleep(nanoseconds: 200_000_000)

        let updatedMember = vm.members.first { $0.id == "usr_other" }!
        XCTAssertEqual(updatedMember.role, .admin)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - removeMember Tests

    func testRemoveMember_success_removesFromArray() async throws {
        let vm = createViewModel(callerRole: .owner)
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.members.count, 3)

        let otherMember = vm.members.first { $0.id == "usr_other" }!

        vm.removeMember(otherMember)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.members.count, 2)
        XCTAssertFalse(vm.members.contains(where: { $0.id == "usr_other" }))
    }

    // MARK: - loadMembers Tests

    func testLoadMembers_error_setsErrorMessage() async throws {
        let vm = createViewModel()
        mockAPIClient.setError(MockError.testError("Load failed"), for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.errorMessage)
    }

    func testLoadMembers_success_clearsLoading() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.members.count, 3)
    }

    // MARK: - isCurrentUser Tests

    func testIsCurrentUser_matchingId_returnsTrue() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        let selfMember = vm.members.first { $0.id == currentUserId }!
        XCTAssertTrue(vm.isCurrentUser(member: selfMember))
    }

    func testIsCurrentUser_differentId_returnsFalse() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(membersResponseJSON, for: membersEndpoint)

        vm.loadMembers()
        try await Task.sleep(nanoseconds: 200_000_000)

        let otherMember = vm.members.first { $0.id == "usr_other" }!
        XCTAssertFalse(vm.isCurrentUser(member: otherMember))
    }
}
