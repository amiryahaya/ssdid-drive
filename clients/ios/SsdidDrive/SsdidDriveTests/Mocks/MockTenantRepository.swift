import Foundation
import Combine
@testable import SsdidDrive

/// Mock implementation of TenantRepository for testing
final class MockTenantRepository: TenantRepository {

    // MARK: - Stub Results

    var stubbedTenantContext: TenantContext?
    var getUserTenantsResult: Result<[Tenant], Error> = .success([])
    var switchTenantResult: Result<TenantContext, Error> = .failure(MockError.notImplemented)
    var leaveTenantResult: Result<Void, Error> = .success(())
    var refreshTenantsResult: Result<[Tenant], Error> = .success([])
    var saveTenantContextResult: Result<Void, Error> = .success(())

    // MARK: - Call Tracking

    var getUserTenantsCallCount = 0
    var switchTenantCallCount = 0
    var leaveTenantCallCount = 0
    var refreshTenantsCallCount = 0
    var saveTenantContextCallCount = 0
    var clearTenantDataCallCount = 0
    var initializeTenantContextCallCount = 0

    // MARK: - Publisher

    private let tenantContextSubject = CurrentValueSubject<TenantContext?, Never>(nil)

    var tenantContextPublisher: AnyPublisher<TenantContext?, Never> {
        tenantContextSubject.eraseToAnyPublisher()
    }

    var currentTenantId: String? {
        stubbedTenantContext?.currentTenantId
    }

    // MARK: - Methods

    func getCurrentTenantContext() async -> TenantContext? {
        stubbedTenantContext
    }

    func getUserTenants() async throws -> [Tenant] {
        getUserTenantsCallCount += 1
        return try getUserTenantsResult.get()
    }

    func switchTenant(tenantId: String) async throws -> TenantContext {
        switchTenantCallCount += 1
        return try switchTenantResult.get()
    }

    func leaveTenant(tenantId: String) async throws {
        leaveTenantCallCount += 1
        try leaveTenantResult.get()
    }

    func refreshTenants() async throws -> [Tenant] {
        refreshTenantsCallCount += 1
        return try refreshTenantsResult.get()
    }

    func saveTenantContext(_ context: TenantContext) async throws {
        saveTenantContextCallCount += 1
        try saveTenantContextResult.get()
    }

    func clearTenantData() async {
        clearTenantDataCallCount += 1
    }

    func initializeTenantContext() async {
        initializeTenantContextCallCount += 1
    }

    // MARK: - Test Helpers

    func publishTenantContext(_ context: TenantContext?) {
        stubbedTenantContext = context
        tenantContextSubject.send(context)
    }

    func reset() {
        getUserTenantsCallCount = 0
        switchTenantCallCount = 0
        leaveTenantCallCount = 0
        refreshTenantsCallCount = 0
        saveTenantContextCallCount = 0
        clearTenantDataCallCount = 0
        initializeTenantContextCallCount = 0
        stubbedTenantContext = nil
        tenantContextSubject.send(nil)
    }
}
