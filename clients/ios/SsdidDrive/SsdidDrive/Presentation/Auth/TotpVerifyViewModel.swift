import Foundation
import Combine

/// Delegate for TOTP verify view model coordinator events
protocol TotpVerifyViewModelCoordinatorDelegate: AnyObject {
    func totpVerifyDidComplete()
    func totpVerifyDidRequestRecovery(email: String)
}

/// View model for TOTP two-factor authentication verification.
/// Posts the 6-digit code to the backend and saves the session token on success.
@MainActor
final class TotpVerifyViewModel: BaseViewModel {

    // MARK: - Properties

    let email: String
    private let apiClient: APIClient
    private let keychainManager: KeychainManager
    weak var coordinatorDelegate: TotpVerifyViewModelCoordinatorDelegate?

    @Published var code: String = ""
    @Published var isAuthenticated: Bool = false

    private var verifyTask: Task<Void, Never>?

    // MARK: - Initialization

    init(email: String, apiClient: APIClient, keychainManager: KeychainManager) {
        self.email = email
        self.apiClient = apiClient
        self.keychainManager = keychainManager
        super.init()
    }

    deinit {
        verifyTask?.cancel()
    }

    // MARK: - Actions

    /// Verify the TOTP code against the backend.
    /// On success, saves the session token and notifies the coordinator.
    func verify() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCode.count == 6 else {
            errorMessage = "Enter a 6-digit code"
            return
        }

        guard !isLoading else { return }

        isLoading = true
        clearError()

        verifyTask?.cancel()
        verifyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let request = TotpVerifyRequest(email: email, code: trimmedCode)
                let response: TotpVerifyResponse = try await apiClient.request(
                    "/auth/totp/verify",
                    method: .post,
                    body: request,
                    requiresAuth: false
                )
                guard !Task.isCancelled else { return }

                // Save session token
                keychainManager.accessToken = response.sessionToken

                // Write to shared keychain for File Provider extension
                if let tokenData = response.sessionToken.data(using: .utf8) {
                    try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
                }

                // Update shared defaults for menu bar helper
                SharedDefaults.shared.writeIsAuthenticated(true)
                SharedDefaults.shared.notifyHelper()

                isLoading = false
                isAuthenticated = true
                coordinatorDelegate?.totpVerifyDidComplete()
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                handleError(error)
            }
        }
    }

    /// Request recovery access when the user has lost their authenticator
    func requestRecovery() {
        coordinatorDelegate?.totpVerifyDidRequestRecovery(email: email)
    }
}

// MARK: - Request / Response Types

private struct TotpVerifyRequest: Encodable {
    let email: String
    let code: String
}

private struct TotpVerifyResponse: Decodable {
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
    }
}
