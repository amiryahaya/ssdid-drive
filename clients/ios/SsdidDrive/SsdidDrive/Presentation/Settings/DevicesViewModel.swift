import Foundation
import Combine

/// View model for devices screen
final class DevicesViewModel: BaseViewModel {

    // MARK: - Properties

    private let authRepository: AuthRepository

    @Published var devices: [Device] = []
    @Published var isRefreshing: Bool = false

    var currentDeviceId: String? {
        authRepository.currentDeviceId
    }

    // MARK: - Initialization

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
        super.init()
    }

    // MARK: - Data Loading

    func loadDevices() {
        isLoading = true
        clearError()

        Task {
            do {
                let fetchedDevices = try await authRepository.getDevices()
                await MainActor.run {
                    self.devices = fetchedDevices
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

    func refreshDevices() {
        isRefreshing = true
        loadDevices()
    }

    // MARK: - Actions

    func revokeDevice(_ device: Device) {
        isLoading = true

        Task {
            do {
                try await authRepository.revokeDevice(deviceId: device.id)
                await MainActor.run {
                    self.devices.removeAll { $0.id == device.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Computed

    var isEmpty: Bool {
        devices.isEmpty && !isLoading
    }
}
