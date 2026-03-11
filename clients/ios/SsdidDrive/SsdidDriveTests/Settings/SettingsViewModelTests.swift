import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for SettingsViewModel
@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Properties

    var mockAuthRepository: MockAuthRepository!
    var mockTenantRepository: MockTenantRepository!
    var userDefaultsManager: UserDefaultsManager!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockAuthRepository = MockAuthRepository()
        mockTenantRepository = MockTenantRepository()
        // Use a separate suite to avoid polluting real UserDefaults
        let testDefaults = UserDefaults(suiteName: "SettingsViewModelTests")!
        testDefaults.removePersistentDomain(forName: "SettingsViewModelTests")
        userDefaultsManager = UserDefaultsManager(defaults: testDefaults)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockAuthRepository = nil
        mockTenantRepository = nil
        userDefaultsManager = nil
        cancellables = nil
        UserDefaults.standard.removePersistentDomain(forName: "SettingsViewModelTests")
        super.tearDown()
    }

    // MARK: - Helpers

    private func createViewModel() -> SettingsViewModel {
        SettingsViewModel(
            authRepository: mockAuthRepository,
            tenantRepository: mockTenantRepository,
            userDefaultsManager: userDefaultsManager
        )
    }

    private func makeTenant(role: UserRole) -> Tenant {
        Tenant(
            id: "ten_test",
            name: "Test Corp",
            slug: "test-corp",
            role: role,
            joinedAt: Date()
        )
    }

    private func makeTenantContext(role: UserRole) -> TenantContext {
        let tenant = makeTenant(role: role)
        return TenantContext(
            currentTenantId: tenant.id,
            currentRole: role,
            availableTenants: [tenant]
        )
    }

    // MARK: - isAdminOrOwner Tests

    func testIsAdminOrOwner_withAdminRole_returnsTrue() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .admin))

        // Wait for Combine to propagate
        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(vm.isAdminOrOwner)
    }

    func testIsAdminOrOwner_withOwnerRole_returnsTrue() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .owner))

        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(vm.isAdminOrOwner)
    }

    func testIsAdminOrOwner_withMemberRole_returnsFalse() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .member))

        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(vm.isAdminOrOwner)
    }

    func testIsAdminOrOwner_withViewerRole_returnsFalse() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .viewer))

        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(vm.isAdminOrOwner)
    }

    // MARK: - items(for:) Tests

    func testItems_forOrganization_adminIncludesInvitationAndMemberItems() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .admin))

        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        let items = vm.items(for: .organization)
        XCTAssertTrue(items.contains(.createInvitation))
        XCTAssertTrue(items.contains(.members))
        XCTAssertTrue(items.contains(.tenant))
        XCTAssertTrue(items.contains(.joinTenant))
    }

    func testItems_forOrganization_ownerIncludesInvitationAndMemberItems() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .owner))

        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        let items = vm.items(for: .organization)
        XCTAssertTrue(items.contains(.createInvitation))
        XCTAssertTrue(items.contains(.members))
    }

    func testItems_forOrganization_memberExcludesInvitationAndMemberItems() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .member))

        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        let items = vm.items(for: .organization)
        XCTAssertFalse(items.contains(.createInvitation))
        XCTAssertFalse(items.contains(.members))
        XCTAssertTrue(items.contains(.tenant))
        XCTAssertTrue(items.contains(.joinTenant))
    }

    func testItems_forOrganization_viewerExcludesInvitationAndMemberItems() {
        let vm = createViewModel()
        mockTenantRepository.publishTenantContext(makeTenantContext(role: .viewer))

        let expectation = expectation(description: "tenant context update")
        vm.$currentTenant
            .dropFirst()
            .sink { tenant in
                if tenant != nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)

        let items = vm.items(for: .organization)
        XCTAssertFalse(items.contains(.createInvitation))
        XCTAssertFalse(items.contains(.members))
    }

    // MARK: - Account Section Tests

    func testItems_forAccount_containsExpectedItems() {
        let vm = createViewModel()
        let items = vm.items(for: .account)
        XCTAssertTrue(items.contains(.profile))
        XCTAssertTrue(items.contains(.devices))
        XCTAssertTrue(items.contains(.invitationsList))
    }

    // MARK: - Recovery Section Tests

    func testItems_forRecovery_containsExpectedItems() {
        let vm = createViewModel()
        let items = vm.items(for: .recovery)
        XCTAssertTrue(items.contains(.recoverySetup))
        XCTAssertTrue(items.contains(.trusteeDashboard))
        XCTAssertTrue(items.contains(.initiateRecovery))
    }

    // MARK: - About Section Tests

    func testItems_forAbout_containsLogout() {
        let vm = createViewModel()
        let items = vm.items(for: .about)
        XCTAssertTrue(items.contains(.logout))
        XCTAssertTrue(items.contains(.version))
    }
}
