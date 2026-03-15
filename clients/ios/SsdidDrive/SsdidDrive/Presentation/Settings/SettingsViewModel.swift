import Foundation
import Combine
import LocalAuthentication

/// Delegate for settings view model coordinator events
protocol SettingsViewModelCoordinatorDelegate: AnyObject {
    func settingsDidRequestRecoverySetup()
    func settingsDidRequestTrusteeDashboard()
    func settingsDidRequestInitiateRecovery()
    func settingsDidRequestDevices()
    func settingsDidRequestInvitations()
    func settingsDidRequestInvitationsList()
    func settingsDidRequestCreateInvitation()
    func settingsDidRequestMembers()
    func settingsDidRequestCredentials()
    func settingsDidRequestTenantSwitcher()
    func settingsDidRequestJoinTenant()
    func settingsDidRequestRequestTenant()
    func settingsDidRequestLogout()
}

/// View model for settings screen
final class SettingsViewModel: BaseViewModel {

    // MARK: - Properties

    private let authRepository: AuthRepository
    private let tenantRepository: TenantRepository
    private let userDefaultsManager: UserDefaultsManager
    weak var coordinatorDelegate: SettingsViewModelCoordinatorDelegate?

    @Published var user: User?
    @Published var currentTenant: Tenant?
    @Published var tenantCount: Int = 0
    @Published var isBiometricEnabled: Bool = false
    @Published var isAutoLockEnabled: Bool = true
    @Published var autoLockTimeout: Int = 5 // minutes
    @Published var biometricType: LABiometryType = .none

    // MARK: - Sections

    enum SettingsSection: CaseIterable {
        case account
        case organization
        case security
        case recovery
        case about

        var title: String {
            switch self {
            case .account: return "Account"
            case .organization: return "Organization"
            case .security: return "Security"
            case .recovery: return "Recovery"
            case .about: return "About"
            }
        }
    }

    enum SettingsItem: Hashable {
        case profile
        case devices
        case invitations
        case invitationsList
        case createInvitation
        case members
        case credentials
        case tenant
        case joinTenant
        case requestTenant
        case biometric
        case autoLock
        case autoLockTimeout
        case recoverySetup
        case trusteeDashboard
        case initiateRecovery
        case version
        case privacy
        case terms
        case logout
    }

    // MARK: - Initialization

    init(authRepository: AuthRepository, tenantRepository: TenantRepository, userDefaultsManager: UserDefaultsManager) {
        self.authRepository = authRepository
        self.tenantRepository = tenantRepository
        self.userDefaultsManager = userDefaultsManager
        super.init()

        loadSettings()
        checkBiometricAvailability()
        observeTenantContext()
    }

    private func observeTenantContext() {
        tenantRepository.tenantContextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] context in
                self?.currentTenant = context?.currentTenant
                self?.tenantCount = context?.availableTenants.count ?? 0
            }
            .store(in: &cancellables)
    }

    func loadTenantContext() {
        Task {
            await tenantRepository.initializeTenantContext()
            if let context = await tenantRepository.getCurrentTenantContext() {
                await MainActor.run {
                    self.currentTenant = context.currentTenant
                    self.tenantCount = context.availableTenants.count
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadSettings() {
        isBiometricEnabled = userDefaultsManager.biometricEnabled
        isAutoLockEnabled = userDefaultsManager.autoLockEnabled
        autoLockTimeout = userDefaultsManager.autoLockTimeout.minutes
    }

    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        }
    }

    func loadUser() {
        isLoading = true

        Task {
            do {
                let fetchedUser = try await authRepository.getCurrentUser()
                await MainActor.run {
                    self.user = fetchedUser
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Settings Updates

    func setBiometricEnabled(_ enabled: Bool) {
        if enabled {
            // Verify biometric before enabling
            let context = LAContext()
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable biometric unlock") { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success {
                        self?.isBiometricEnabled = true
                        self?.userDefaultsManager.biometricEnabled = true
                    }
                }
            }
        } else {
            isBiometricEnabled = false
            userDefaultsManager.biometricEnabled = false
        }
    }

    func setAutoLockEnabled(_ enabled: Bool) {
        isAutoLockEnabled = enabled
        userDefaultsManager.autoLockEnabled = enabled
    }

    func setAutoLockTimeout(_ minutes: Int) {
        autoLockTimeout = minutes
        // Convert minutes to AutoLockTimeout
        let timeout: Constants.AutoLockTimeout
        switch minutes {
        case 0: timeout = .immediately
        case 1: timeout = .oneMinute
        case 5: timeout = .fiveMinutes
        case 15: timeout = .fifteenMinutes
        case 30: timeout = .thirtyMinutes
        default: timeout = .never
        }
        userDefaultsManager.autoLockTimeout = timeout
    }

    // MARK: - Navigation

    func showRecoverySetup() {
        coordinatorDelegate?.settingsDidRequestRecoverySetup()
    }

    func showTrusteeDashboard() {
        coordinatorDelegate?.settingsDidRequestTrusteeDashboard()
    }

    func showInitiateRecovery() {
        coordinatorDelegate?.settingsDidRequestInitiateRecovery()
    }

    func showDevices() {
        coordinatorDelegate?.settingsDidRequestDevices()
    }

    func showInvitations() {
        coordinatorDelegate?.settingsDidRequestInvitations()
    }

    func showInvitationsList() {
        coordinatorDelegate?.settingsDidRequestInvitationsList()
    }

    func showCreateInvitation() {
        coordinatorDelegate?.settingsDidRequestCreateInvitation()
    }

    func showMembers() {
        coordinatorDelegate?.settingsDidRequestMembers()
    }

    func logout() {
        Task {
            do {
                try await authRepository.logout()
                await MainActor.run {
                    coordinatorDelegate?.settingsDidRequestLogout()
                }
            } catch {
                await MainActor.run {
                    // Still logout locally even if server request fails
                    coordinatorDelegate?.settingsDidRequestLogout()
                }
            }
        }
    }

    // MARK: - Helpers

    func showCredentials() {
        coordinatorDelegate?.settingsDidRequestCredentials()
    }

    func items(for section: SettingsSection) -> [SettingsItem] {
        switch section {
        case .account:
            return [.profile, .devices, .invitationsList]
        case .organization:
            var items: [SettingsItem] = [.tenant, .joinTenant, .requestTenant]
            // Admin/Owner-only items
            if isAdminOrOwner {
                items.append(.createInvitation)
                items.append(.members)
            }
            return items
        case .security:
            var items: [SettingsItem] = []
            if biometricType != .none {
                items.append(.biometric)
            }
            items.append(contentsOf: [.autoLock, .autoLockTimeout])
            return items
        case .recovery:
            return [.recoverySetup, .trusteeDashboard, .initiateRecovery]
        case .about:
            return [.version, .privacy, .terms, .logout]
        }
    }

    // MARK: - Tenant Navigation

    func showTenantSwitcher() {
        coordinatorDelegate?.settingsDidRequestTenantSwitcher()
    }

    func showJoinTenant() {
        coordinatorDelegate?.settingsDidRequestJoinTenant()
    }

    func showRequestTenant() {
        coordinatorDelegate?.settingsDidRequestRequestTenant()
    }

    /// Whether the current user is admin or owner in the current tenant
    var isAdminOrOwner: Bool {
        currentTenant?.role == .admin || currentTenant?.role == .owner
    }

    /// Current user's role in the current tenant
    var currentTenantRole: UserRole {
        currentTenant?.role ?? .member
    }

    var biometricLabel: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometric"
        }
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
