import Foundation
import Combine

/// Implementation of TenantRepository
final class TenantRepositoryImpl: TenantRepository {

    // MARK: - Properties

    private let apiClient: APIClient
    private let keychainManager: KeychainManager

    private let tenantContextSubject = CurrentValueSubject<TenantContext?, Never>(nil)

    var tenantContextPublisher: AnyPublisher<TenantContext?, Never> {
        tenantContextSubject.eraseToAnyPublisher()
    }

    var currentTenantId: String? {
        keychainManager.tenantId
    }

    // MARK: - Initialization

    init(apiClient: APIClient, keychainManager: KeychainManager) {
        self.apiClient = apiClient
        self.keychainManager = keychainManager
    }

    // MARK: - Tenant Context

    func getCurrentTenantContext() async -> TenantContext? {
        // Return cached context if available
        if let context = tenantContextSubject.value {
            return context
        }

        // Try to load from storage
        guard let tenantId = keychainManager.tenantId else {
            return nil
        }

        let role = UserRole(rawValue: keychainManager.currentRole ?? "member") ?? .member
        let tenants = (try? keychainManager.loadUserTenants()) ?? []

        let context = TenantContext(
            currentTenantId: tenantId,
            currentRole: role,
            availableTenants: tenants
        )

        tenantContextSubject.send(context)
        return context
    }

    // MARK: - Tenant Operations

    func getUserTenants() async throws -> [Tenant] {
        let response: TenantsResponse = try await apiClient.request(
            Constants.API.Endpoints.tenants,
            method: .get
        )
        return response.data
    }

    func switchTenant(tenantId: String) async throws -> TenantContext {
        // Call API to switch tenant
        let request = TenantSwitchRequest(tenantId: tenantId)
        let response: TenantSwitchResponse = try await apiClient.request(
            Constants.API.Endpoints.switchTenant,
            method: .post,
            body: request
        )

        // Save new tokens and tenant context atomically
        try keychainManager.saveTokensWithTenantContext(
            accessToken: response.data.accessToken,
            refreshToken: response.data.refreshToken,
            tenantId: response.data.currentTenantId,
            role: response.data.role
        )

        // Refresh tenant list to get updated info
        let tenants = try await getUserTenants()
        try keychainManager.saveUserTenants(tenants)

        // Create and publish new context
        let context = TenantContext(
            currentTenantId: response.data.currentTenantId,
            currentRole: response.data.userRole,
            availableTenants: tenants
        )

        tenantContextSubject.send(context)

        // Update Sentry with new tenant context
        if let userId = keychainManager.userId {
            SentryConfig.shared.setUser(userId: userId, tenantId: response.data.currentTenantId)
        }
        // SECURITY: Hash the tenant ID before setting as tag to prevent PII exposure
        // (the unhashed tenant ID is already in the user context as tenant_hash)
        SentryConfig.shared.setTag("tenant_hash", value: SentryConfig.shared.anonymizeIdentifier(response.data.currentTenantId))

        return context
    }

    func leaveTenant(tenantId: String) async throws {
        let endpoint = Constants.API.Endpoints.leaveTenant.replacingOccurrences(of: "{id}", with: tenantId)
        try await apiClient.requestNoContent(endpoint, method: .delete)

        // Refresh tenant list
        _ = try await refreshTenants()
    }

    func refreshTenants() async throws -> [Tenant] {
        let tenants = try await getUserTenants()

        // Save to storage
        try keychainManager.saveUserTenants(tenants)

        // Update context if we have one
        if let currentId = keychainManager.tenantId,
           let role = keychainManager.currentRole {
            let context = TenantContext(
                currentTenantId: currentId,
                currentRole: UserRole(rawValue: role) ?? .member,
                availableTenants: tenants
            )
            tenantContextSubject.send(context)
        }

        return tenants
    }

    // MARK: - Local Storage

    func saveTenantContext(_ context: TenantContext) async throws {
        keychainManager.tenantId = context.currentTenantId
        keychainManager.currentRole = context.currentRole.rawValue
        try keychainManager.saveUserTenants(context.availableTenants)
        tenantContextSubject.send(context)
    }

    func clearTenantData() async {
        keychainManager.clearTenantData()
        tenantContextSubject.send(nil)
    }

    func initializeTenantContext() async {
        _ = await getCurrentTenantContext()
    }
}
