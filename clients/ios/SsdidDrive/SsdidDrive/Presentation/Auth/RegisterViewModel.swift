import Foundation
import Combine

/// Delegate for register view model coordinator events
protocol RegisterViewModelCoordinatorDelegate: AnyObject {
    func registerViewModelDidRequestLogin()
    func registerViewModelDidRegister()
}

/// View model for register screen
final class RegisterViewModel: BaseViewModel {

    // MARK: - Properties

    private let authRepository: AuthRepository
    weak var coordinatorDelegate: RegisterViewModelCoordinatorDelegate?

    // MARK: - Initialization

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
        super.init()
    }

    // MARK: - Actions

    func register(email: String, password: String) {
        isLoading = true
        clearError()

        Task {
            do {
                _ = try await authRepository.register(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    coordinatorDelegate?.registerViewModelDidRegister()
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func requestLogin() {
        coordinatorDelegate?.registerViewModelDidRequestLogin()
    }
}
