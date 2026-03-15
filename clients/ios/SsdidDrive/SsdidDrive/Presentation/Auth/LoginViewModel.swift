import Foundation
import Combine
import UIKit

/// Delegate for login view model coordinator events
protocol LoginViewModelCoordinatorDelegate: AnyObject {
    func loginViewModelDidLogin()
    func loginViewModelDidRequestJoinTenant()
}

/// View model for SSDID wallet-based login.
/// Calls the backend to initiate a challenge, displays a QR code for the SSDID Wallet,
/// then listens via SSE for the wallet's authentication response.
@MainActor
final class LoginViewModel: BaseViewModel {

    // MARK: - Properties

    private let keychainManager: KeychainManager
    weak var coordinatorDelegate: LoginViewModelCoordinatorDelegate?

    @Published var email: String = ""
    @Published var navigateToTotp: String?
    @Published var qrPayload: String?
    @Published var walletDeepLink: URL?
    @Published var isExpired = false

    private var sseStreamTask: Task<Void, Never>?
    private var challengeId: String?

    // MARK: - Token Validation

    /// Minimum session token length (UUIDs are 32 hex chars without hyphens)
    private static let minTokenLength = 16

    /// Maximum session token length
    private static let maxTokenLength = 512

    /// Allowed characters in session tokens (alphanumeric + common token chars)
    private static let tokenCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))

    // MARK: - Initialization

    init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
        super.init()
    }

    deinit {
        sseStreamTask?.cancel()
    }

    // MARK: - Actions

    /// Create a new SSDID authentication challenge by calling the backend.
    /// Builds a `ssdid://login?...` URL used for both QR display and same-device deep link.
    func createChallenge() {
        isLoading = true
        isExpired = false
        clearError()

        Task {
            do {
                let response = try await SsdidAuthService.shared.initiateLogin()
                self.challengeId = response.challengeId

                // Build ssdid://login?... URL that the wallet understands
                var components = URLComponents()
                components.scheme = "ssdid"
                components.host = "login"

                // Extract fields from the backend's qr_payload
                let qr = response.qrPayload
                var queryItems = [
                    URLQueryItem(name: "server_url", value: qr["service_url"] as? String ?? SsdidAuthService.shared.baseURL),
                    URLQueryItem(name: "service_name", value: qr["service_name"] as? String ?? "ssdid-drive"),
                    URLQueryItem(name: "challenge_id", value: response.challengeId),
                    URLQueryItem(name: "callback_url", value: "ssdid-drive://auth/callback"),
                ]

                // Include requested_claims if present
                if let claims = qr["requested_claims"],
                   let claimsData = try? JSONSerialization.data(withJSONObject: claims),
                   let claimsString = String(data: claimsData, encoding: .utf8) {
                    queryItems.append(URLQueryItem(name: "requested_claims", value: claimsString))
                }

                components.queryItems = queryItems

                guard let loginUrl = components.url else {
                    self.handleError(URLError(.badURL))
                    return
                }

                // QR code contains the URL string (wallet scans → parses as ssdid:// URL)
                self.qrPayload = loginUrl.absoluteString

                // Same URL for same-device deep link
                self.walletDeepLink = loginUrl

                self.isLoading = false

                // Listen for SSE completion from server
                listenForCompletion(
                    challengeId: response.challengeId,
                    subscriberSecret: response.subscriberSecret
                )
            } catch {
                self.handleError(error)
            }
        }
    }

    /// Open the SSDID Wallet app via deep link (same-device flow)
    func openWallet() {
        guard let url = walletDeepLink else { return }
        guard UIApplication.shared.canOpenURL(url) else {
            errorMessage = "SSDID Wallet app is not installed"
            return
        }
        UIApplication.shared.open(url)
    }

    /// Handle authentication callback from the wallet app
    /// Called when the app receives ssdid-drive://auth/callback?session_token=...
    /// (D4 fix: validates token format before saving)
    func handleAuthCallback(sessionToken: String) {
        guard Self.isValidSessionToken(sessionToken) else {
            errorMessage = "Invalid session token received"
            return
        }
        saveSession(token: sessionToken)
    }

    // MARK: - Email Login

    /// Initiate email-based login. On success the server returns whether TOTP is required.
    func emailLogin() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Email is required"
            return
        }

        isLoading = true
        clearError()

        Task {
            do {
                guard let url = URL(string: "\(SsdidAuthService.shared.baseURL)/api/auth/email/login") else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["email": trimmed])

                let (data, response) = try await SsdidAuthService.shared.urlSession.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw URLError(.cannotParseResponse)
                }

                let requiresTotp = json["requires_totp"] as? Bool ?? false
                let responseEmail = json["email"] as? String ?? trimmed

                if requiresTotp {
                    self.navigateToTotp = responseEmail
                }

                self.isLoading = false
            } catch {
                self.isLoading = false
                self.handleError(error)
            }
        }
    }

    // MARK: - OIDC

    /// Handle the result of an OIDC authentication flow (e.g. Google / Apple sign-in).
    /// Sends the provider name and ID token to the backend for verification.
    func handleOidcResult(provider: String, idToken: String) {
        isLoading = true
        clearError()

        Task {
            do {
                guard let url = URL(string: "\(SsdidAuthService.shared.baseURL)/api/auth/oidc/verify") else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: ["provider": provider, "id_token": idToken]
                )

                let (data, response) = try await SsdidAuthService.shared.urlSession.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessionToken = json["session_token"] as? String,
                      Self.isValidSessionToken(sessionToken) else {
                    throw URLError(.cannotParseResponse)
                }

                self.saveSession(token: sessionToken)
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.handleError(error)
            }
        }
    }

    // MARK: - Private

    /// Listen for SSE events indicating authentication completion (cross-device QR flow)
    /// (D2 fix: uses URLSession.bytes streaming instead of buffered dataTask)
    private func listenForCompletion(challengeId: String, subscriberSecret: String) {
        sseStreamTask?.cancel()

        // Build SSE URL with subscriber_secret for authorization
        var components = URLComponents(
            string: "\(SsdidAuthService.shared.baseURL)/api/auth/ssdid/events"
        )
        components?.queryItems = [
            URLQueryItem(name: "challenge_id", value: challengeId),
            URLQueryItem(name: "subscriber_secret", value: subscriberSecret)
        ]
        guard let url = components?.url else { return }

        sseStreamTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 310 // slightly longer than server's 5min SSE timeout

                let (bytes, response) = try await SsdidAuthService.shared.urlSession.bytes(for: request)

                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    await MainActor.run {
                        self?.errorMessage = "Failed to connect to authentication service"
                    }
                    return
                }

                // Parse SSE frames from the byte stream
                var currentEvent = ""
                var currentData = ""

                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }

                    if line.hasPrefix("event: ") {
                        currentEvent = String(line.dropFirst(7))
                    } else if line.hasPrefix("data: ") {
                        currentData = String(line.dropFirst(6))
                    } else if line.isEmpty {
                        // Empty line = end of SSE frame
                        if !currentEvent.isEmpty {
                            await self?.handleSSEEvent(
                                event: currentEvent,
                                data: currentData
                            )
                        }
                        currentEvent = ""
                        currentData = ""
                    }
                    // Lines starting with ":" are SSE comments (keep-alive), ignore them
                }
            } catch is CancellationError {
                // Normal cancellation, do nothing
            } catch {
                await MainActor.run {
                    self?.isExpired = true
                }
            }
        }
    }

    /// Process a parsed SSE event
    private func handleSSEEvent(event: String, data: String) {
        switch event {
        case "authenticated":
            // Parse session_token from JSON data
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let token = json["session_token"] as? String,
                  Self.isValidSessionToken(token) else {
                errorMessage = "Invalid authentication response"
                return
            }
            saveSession(token: token)

        case "timeout":
            isExpired = true

        default:
            break
        }
    }

    /// Validate session token format before storing
    /// (D4: prevents storing malformed/injected tokens in Keychain)
    static func isValidSessionToken(_ token: String) -> Bool {
        guard !token.isEmpty,
              token.count >= minTokenLength,
              token.count <= maxTokenLength else {
            return false
        }
        return token.unicodeScalars.allSatisfy { tokenCharacterSet.contains($0) }
    }

    /// Request to show the join tenant screen
    func requestJoinTenant() {
        coordinatorDelegate?.loginViewModelDidRequestJoinTenant()
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
