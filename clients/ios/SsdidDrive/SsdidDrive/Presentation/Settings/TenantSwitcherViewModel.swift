import Foundation
import Combine

/// View model for tenant switching functionality
final class TenantSwitcherViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentTenant: Tenant?
    @Published var availableTenants: [Tenant] = []
    @Published var isLoading: Bool = false
    @Published var isSwitching: Bool = false
    @Published var error: String?
    @Published var switchSuccess: Bool = false

    // MARK: - Properties

    private let tenantRepository: TenantRepository
    private var cancellables = Set<AnyCancellable>()

    /// Callback when tenant is successfully switched
    var onTenantSwitched: ((Tenant) -> Void)?

    // MARK: - Computed Properties

    var hasMultipleTenants: Bool {
        availableTenants.count > 1
    }

    var tenantCount: Int {
        availableTenants.count
    }

    // MARK: - Initialization

    init(tenantRepository: TenantRepository) {
        self.tenantRepository = tenantRepository
        observeTenantContext()
        loadTenants()
    }

    // MARK: - Private Methods

    private func observeTenantContext() {
        tenantRepository.tenantContextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] context in
                guard let self = self, let context = context else { return }
                self.currentTenant = context.currentTenant
                self.availableTenants = context.availableTenants
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func loadTenants() {
        isLoading = true
        error = nil

        Task {
            do {
                // Initialize context from storage first
                await tenantRepository.initializeTenantContext()

                // Then refresh from server
                let tenants = try await tenantRepository.refreshTenants()

                await MainActor.run {
                    self.availableTenants = tenants
                    self.isLoading = false

                    // Update current tenant if context exists
                    if let context = self.tenantRepository.currentTenantId,
                       let current = tenants.first(where: { $0.id == context }) {
                        self.currentTenant = current
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func switchTenant(_ tenant: Tenant) {
        guard tenant.id != currentTenant?.id else { return }

        isSwitching = true
        error = nil
        switchSuccess = false

        Task {
            do {
                let context = try await tenantRepository.switchTenant(tenantId: tenant.id)

                await MainActor.run {
                    self.currentTenant = context.currentTenant
                    self.availableTenants = context.availableTenants
                    self.isSwitching = false
                    self.switchSuccess = true
                    self.onTenantSwitched?(tenant)

                    // Add breadcrumb for tracking (no sensitive data - only tenant ID)
                    SentryConfig.shared.addBreadcrumb(
                        message: "Tenant switch completed",
                        category: "tenant",
                        level: .info,
                        data: ["tenant_id": tenant.id]
                    )
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isSwitching = false

                    // Capture error for monitoring (no sensitive tenant data)
                    SentryConfig.shared.captureError(error, extras: [
                        "action": "switch_tenant"
                    ])
                }
            }
        }
    }

    func leaveTenant(_ tenant: Tenant) {
        guard tenant.id != currentTenant?.id else {
            error = "Cannot leave your current organization"
            return
        }

        isLoading = true
        error = nil

        Task {
            do {
                try await tenantRepository.leaveTenant(tenantId: tenant.id)

                await MainActor.run {
                    self.availableTenants.removeAll { $0.id == tenant.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func clearError() {
        error = nil
    }

    func resetSwitchSuccess() {
        switchSuccess = false
    }
}
