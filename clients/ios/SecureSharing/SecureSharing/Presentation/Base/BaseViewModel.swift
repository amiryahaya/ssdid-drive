import Foundation
import Combine

/// Base view model with common functionality
class BaseViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Properties

    var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {}

    // MARK: - Error Handling

    func handleError(_ error: Error) {
        isLoading = false

        if let apiError = error as? APIClient.APIError {
            errorMessage = apiError.errorDescription
        } else if let authError = error as? AuthError {
            errorMessage = authError.errorDescription
        } else {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}

/// Protocol for coordinator navigation callbacks
protocol ViewModelCoordinatorDelegate: AnyObject {
    func viewModelDidRequestNavigation(_ action: Any)
}
