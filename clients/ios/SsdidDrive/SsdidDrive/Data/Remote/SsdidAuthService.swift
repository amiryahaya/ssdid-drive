import CryptoKit
import Foundation

/// Service for SSDID wallet-based authentication.
/// Communicates with the server's SSDID auth endpoints to retrieve server identity
/// and facilitate QR-code / deep-link authentication flows.
final class SsdidAuthService {

    // MARK: - Singleton

    static let shared = SsdidAuthService()

    // MARK: - Properties

    let baseURL: String

    /// URLSession configured with SSL pinning when available.
    /// Exposed for use by SSE connections that need the same pinning policy.
    let urlSession: URLSession

    // MARK: - Types

    struct ServerInfo: Codable {
        let serverDid: String
        let serverKeyId: String
        let serviceName: String
        let registryUrl: String

        enum CodingKeys: String, CodingKey {
            case serverDid = "server_did"
            case serverKeyId = "server_key_id"
            case serviceName = "service_name"
            case registryUrl = "registry_url"
        }
    }

    /// Response from POST /api/auth/ssdid/login/initiate
    struct LoginInitiateResponse {
        let challengeId: String
        let subscriberSecret: String
        let qrPayload: [String: Any]
    }

    // MARK: - Initialization

    private init() {
        baseURL = ProcessInfo.processInfo.environment["API_URL"]
            ?? Constants.API.baseURL

        // D8: Use pinning-aware URLSession when SSL pinning is configured
        if Constants.API.isSSLPinningConfigured {
            let config = URLSessionConfiguration.default
            urlSession = URLSession(
                configuration: config,
                delegate: SsdidAuthSSLPinningDelegate(),
                delegateQueue: nil
            )
        } else {
            urlSession = URLSession.shared
        }
    }

    // MARK: - Endpoints

    /// Fetch server identity information needed to build the QR challenge payload.
    func getServerInfo() async throws -> ServerInfo {
        guard let url = URL(string: "\(baseURL)/api/auth/ssdid/server-info") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await urlSession.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(ServerInfo.self, from: data)
    }

    /// Initiate a login challenge on the server.
    /// Returns the challenge_id, subscriber_secret (for SSE auth), and the full QR payload
    /// with the server's signed challenge.
    /// (D1: replaces client-side UUID generation with proper backend call)
    func initiateLogin() async throws -> LoginInitiateResponse {
        guard let url = URL(string: "\(baseURL)/api/auth/ssdid/login/initiate") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challengeId = json["challenge_id"] as? String,
              let subscriberSecret = json["subscriber_secret"] as? String,
              let qrPayload = json["qr_payload"] as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        return LoginInitiateResponse(
            challengeId: challengeId,
            subscriberSecret: subscriberSecret,
            qrPayload: qrPayload
        )
    }
}

// MARK: - SSL Pinning Delegate (D8)

/// URLSession delegate for SsdidAuthService that validates server certificates
/// against pinned hashes. Uses the same pinning logic as APIClient but with a
/// simpler interface since it reads hashes from Constants directly.
private final class SsdidAuthSSLPinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Extract server public key hash
        guard let serverCertificate = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let certificate = serverCertificate.first,
              let publicKey = SecCertificateCopyKey(certificate) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // SHA-256 hash of the public key
        let digest = SHA256.hash(data: publicKeyData)
        let hash = Data(digest).base64EncodedString()

        // Check against pinned hashes
        if Constants.API.pinnedCertificateHashes.contains(hash) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
