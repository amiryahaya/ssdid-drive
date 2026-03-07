import Foundation
import Combine

/// Delegate for login view model coordinator events
protocol LoginViewModelCoordinatorDelegate: AnyObject {
    func loginViewModelDidRequestRegister()
    func loginViewModelDidLogin()
}

/// View model for login screen
final class LoginViewModel: BaseViewModel {

    // MARK: - Properties

    private let authRepository: AuthRepository
    weak var coordinatorDelegate: LoginViewModelCoordinatorDelegate?

    // MARK: - Initialization

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
        super.init()
    }

    // MARK: - Actions

    func login(email: String, password: String) {
        isLoading = true
        clearError()

        Task {
            do {
                _ = try await authRepository.login(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    coordinatorDelegate?.loginViewModelDidLogin()
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func requestRegister() {
        coordinatorDelegate?.loginViewModelDidRequestRegister()
    }
}
