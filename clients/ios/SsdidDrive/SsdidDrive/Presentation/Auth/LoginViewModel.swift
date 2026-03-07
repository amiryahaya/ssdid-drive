import Foundation
import Combine
import UIKit

/// Delegate for login view model coordinator events
protocol LoginViewModelCoordinatorDelegate: AnyObject {
    func loginViewModelDidLogin()
}

/// View model for SSDID wallet-based login.
/// Generates a QR code payload containing a challenge for the SSDID Wallet to scan,
/// then listens via SSE for the wallet's authentication response.
@MainActor
final class LoginViewModel: BaseViewModel {

    // MARK: - Properties

    private let keychainManager: KeychainManager
    weak var coordinatorDelegate: LoginViewModelCoordinatorDelegate?

    @Published var qrPayload: String?
    @Published var walletDeepLink: URL?
    @Published var isExpired = false

    private var eventTask: URLSessionDataTask?
    private var challengeId: String?

    // MARK: - Initialization

    init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
        super.init()
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Actions

    /// Create a new SSDID authentication challenge and display QR code
    func createChallenge() {
        isLoading = true
        isExpired = false
        clearError()

        Task {
            do {
                let serverInfo = try await SsdidAuthService.shared.getServerInfo()
                let newChallengeId = UUID().uuidString
                self.challengeId = newChallengeId

                let payload: [String: String] = [
                    "server_url": SsdidAuthService.shared.baseURL,
                    "server_did": serverInfo.serverDid,
                    "action": "authenticate",
                    "challenge_id": newChallengeId
                ]

                let jsonData = try JSONSerialization.data(withJSONObject: payload)
                self.qrPayload = String(data: jsonData, encoding: .utf8)

                // Build wallet deep link for same-device flow (iPhone)
                var components = URLComponents()
                components.scheme = "ssdid"
                components.host = "authenticate"
                components.queryItems = [
                    URLQueryItem(name: "server_url", value: SsdidAuthService.shared.baseURL),
                    URLQueryItem(name: "server_did", value: serverInfo.serverDid),
                    URLQueryItem(name: "challenge_id", value: newChallengeId),
                    URLQueryItem(name: "callback", value: "ssdid-drive://auth/callback")
                ]
                self.walletDeepLink = components.url

                self.isLoading = false

                // Listen for SSE completion from server
                listenForCompletion(challengeId: newChallengeId)
            } catch {
                self.handleError(error)
            }
        }
    }

    /// Open the SSDID Wallet app via deep link (same-device flow)
    func openWallet() {
        guard let url = walletDeepLink else { return }
        UIApplication.shared.open(url)
    }

    /// Handle authentication callback from the wallet app
    /// Called when the app receives ssdid-drive://auth/callback?session_token=...
    func handleAuthCallback(sessionToken: String) {
        saveSession(token: sessionToken)
    }

    // MARK: - Private

    /// Listen for SSE events indicating authentication completion (cross-device QR flow)
    private func listenForCompletion(challengeId: String) {
        eventTask?.cancel()

        let urlString = "\(SsdidAuthService.shared.baseURL)/api/auth/ssdid/events?challenge_id=\(challengeId)"
        guard let url = URL(string: urlString) else { return }

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data,
                  let text = String(data: data, encoding: .utf8) else { return }

            Task { @MainActor [weak self] in
                if text.contains("event: authenticated") {
                    // Extract session token from SSE data
                    if let range = text.range(of: "\"session_token\":\""),
                       let endRange = text[range.upperBound...].range(of: "\"") {
                        let token = String(text[range.upperBound..<endRange.lowerBound])
                        self?.saveSession(token: token)
                    }
                } else if text.contains("event: timeout") {
                    self?.isExpired = true
                }
            }
        }
        task.resume()
        eventTask = task
    }

    /// Save session token and notify coordinator
    private func saveSession(token: String) {
        keychainManager.accessToken = token

        // Write to shared keychain for File Provider extension
        if let tokenData = token.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
        }

        // Update shared defaults for menu bar helper
        let shared = SharedDefaults.shared
        shared.writeIsAuthenticated(true)
        shared.notifyHelper()

        coordinatorDelegate?.loginViewModelDidLogin()
    }
}
