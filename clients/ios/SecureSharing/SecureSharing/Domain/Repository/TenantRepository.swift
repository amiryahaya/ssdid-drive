import Foundation
import Combine

/// Repository for tenant operations
protocol TenantRepository: AnyObject {

    // MARK: - Tenant Context

    /// Observe tenant context changes
    var tenantContextPublisher: AnyPublisher<TenantContext?, Never> { get }

    /// Get current tenant context
    func getCurrentTenantContext() async -> TenantContext?

    /// Get current tenant ID (synchronous for headers)
    var currentTenantId: String? { get }

    // MARK: - Tenant Operations

    /// Get list of user's tenants from server
    func getUserTenants() async throws -> [Tenant]

    /// Switch to a different tenant
    func switchTenant(tenantId: String) async throws -> TenantContext

    /// Leave a tenant (remove self from tenant)
    func leaveTenant(tenantId: String) async throws

    /// Refresh tenant list from server
    func refreshTenants() async throws -> [Tenant]

    // MARK: - Local Storage

    /// Save tenant context locally
    func saveTenantContext(_ context: TenantContext) async throws

    /// Clear all tenant data (on logout)
    func clearTenantData() async

    /// Initialize tenant context from storage
    func initializeTenantContext() async
}
