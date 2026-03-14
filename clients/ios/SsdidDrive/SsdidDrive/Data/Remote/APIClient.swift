import Foundation
import CryptoKit
import Security

/// Protocol for API client abstraction (enables testing with mock)
protocol APIClientProtocol: Sendable {
    func request<T: Decodable>(
        _ endpoint: String,
        method: APIClient.HTTPMethod,
        body: (any Encodable)?,
        queryItems: [URLQueryItem]?,
        requiresAuth: Bool
    ) async throws -> T

    func requestNoContent(
        _ endpoint: String,
        method: APIClient.HTTPMethod,
        body: (any Encodable)?,
        queryItems: [URLQueryItem]?,
        requiresAuth: Bool
    ) async throws
}

/// HTTP client for API communication with SSL certificate pinning
actor APIClient: APIClientProtocol {

    // MARK: - Types

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int, message: String?)
        case decodingError(Error)
        case encodingError(Error)
        case networkError(Error)
        case unauthorized
        case forbidden
        case notFound
        case serverError
        case tokenRefreshFailed
        case sslPinningFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .invalidResponse:
                return "Invalid server response"
            case .httpError(let code, let message):
                return message ?? "HTTP error \(code)"
            case .decodingError(let error):
                return "Decoding error: \(error.localizedDescription)"
            case .encodingError(let error):
                return "Encoding error: \(error.localizedDescription)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .unauthorized:
                return "Unauthorized - please log in again"
            case .forbidden:
                return "Access forbidden"
            case .notFound:
                return "Resource not found"
            case .serverError:
                return "Server error - please try again"
            case .tokenRefreshFailed:
                return "Session expired - please log in again"
            case .sslPinningFailed:
                return "Security error - SSL certificate verification failed"
            }
        }
    }

    // MARK: - Properties

    private let baseURL: String
    private let session: URLSession
    private let keychainManager: KeychainManager
    private weak var authRepository: (any AuthRepository)?
    private weak var tenantRepository: (any TenantRepository)?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var refreshTask: Task<Void, Error>?
    private let sslPinningDelegate: SSLPinningDelegate
    private lazy var iso8601Formatter: ISO8601DateFormatter = ISO8601DateFormatter()

    // MARK: - Initialization

    init(
        baseURL: String = Constants.API.fullBaseURL,
        keychainManager: KeychainManager,
        authRepository: (any AuthRepository)? = nil,
        pinnedCertificateHashes: [String] = Constants.API.pinnedCertificateHashes
    ) {
        self.baseURL = baseURL
        self.keychainManager = keychainManager
        self.authRepository = authRepository

        // Configure SSL pinning delegate
        self.sslPinningDelegate = SSLPinningDelegate(pinnedHashes: pinnedCertificateHashes)

        // Verify SSL pinning is configured for production
        #if !DEBUG
        if !Constants.API.isSSLPinningConfigured {
            // SECURITY: Fail fast in production if SSL pinning is not configured
            // This prevents the app from running without proper MITM protection
            fatalError("""
                SECURITY ERROR: SSL certificate pinning is not configured!

                This makes the app vulnerable to MITM attacks.
                Replace placeholder hashes in Constants.API.pinnedCertificateHashes before release.

                Generate hashes using:
                echo | openssl s_client -connect api.ssdid-drive.app:443 2>/dev/null | \\
                  openssl x509 -pubkey -noout | \\
                  openssl pkey -pubin -outform der | \\
                  openssl dgst -sha256 -binary | base64
                """)
        }
        #endif

        // Configure URLSession with SSL pinning
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.API.timeout
        config.timeoutIntervalForResource = Constants.API.timeout * 2
        self.session = URLSession(configuration: config, delegate: sslPinningDelegate, delegateQueue: nil)

        // Configure decoder
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Configure encoder
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Make a request and decode the response
    func request<T: Decodable>(
        _ endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        let data = try await makeRequest(
            endpoint,
            method: method,
            body: body,
            queryItems: queryItems,
            requiresAuth: requiresAuth
        )

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Make a request without expecting a response body
    func requestNoContent(
        _ endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) async throws {
        _ = try await makeRequest(
            endpoint,
            method: method,
            body: body,
            queryItems: queryItems,
            requiresAuth: requiresAuth
        )
    }

    /// Upload a file with progress
    func upload(
        _ endpoint: String,
        fileURL: URL,
        mimeType: String,
        fileName: String,
        additionalFields: [String: String]? = nil,
        progress: @escaping (Double) -> Void,
        isRetryAfterRefresh: Bool = false
    ) async throws -> Data {
        guard let urlComponents = URLComponents(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue

        // Add auth headers
        try await addAuthHeaders(to: &request)

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Add additional fields
        if let fields = additionalFields {
            for (key, value) in fields {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
        }

        // Add file
        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // For now, report 50% when starting (proper progress would use URLSessionDelegate)
        progress(0.5)

        do {
            let (data, response) = try await session.data(for: request)

            progress(1.0)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Handle 401 with token refresh (only retry once)
            if httpResponse.statusCode == 401 && !isRetryAfterRefresh {
                try await refreshTokenAndRetry()
                return try await upload(endpoint, fileURL: fileURL, mimeType: mimeType, fileName: fileName, additionalFields: additionalFields, progress: progress, isRetryAfterRefresh: true)
            }

            try validateResponse(httpResponse, data: data)
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// Download a file with progress
    func download(
        _ endpoint: String,
        progress: @escaping (Double) -> Void,
        isRetryAfterRefresh: Bool = false
    ) async throws -> Data {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue

        try await addAuthHeaders(to: &request)

        progress(0.1)

        do {
            let (data, response) = try await session.data(for: request)

            progress(1.0)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Handle 401 with token refresh (only retry once)
            if httpResponse.statusCode == 401 && !isRetryAfterRefresh {
                try await refreshTokenAndRetry()
                return try await download(endpoint, progress: progress, isRetryAfterRefresh: true)
            }

            try validateResponse(httpResponse, data: data)
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Private Methods

    private func makeRequest(
        _ endpoint: String,
        method: HTTPMethod,
        body: Encodable?,
        queryItems: [URLQueryItem]?,
        requiresAuth: Bool,
        isRetryAfterRefresh: Bool = false
    ) async throws -> Data {
        guard var urlComponents = URLComponents(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        if let queryItems = queryItems {
            urlComponents.queryItems = queryItems
        }

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: Constants.API.Headers.accept)

        if requiresAuth {
            try await addAuthHeaders(to: &request)
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: Constants.API.Headers.contentType)
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.encodingError(error)
            }
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Handle 401 with token refresh (only retry once to prevent infinite recursion)
            if httpResponse.statusCode == 401 && requiresAuth && !isRetryAfterRefresh {
                try await refreshTokenAndRetry()
                return try await makeRequest(endpoint, method: method, body: body, queryItems: queryItems, requiresAuth: requiresAuth, isRetryAfterRefresh: true)
            }

            try validateResponse(httpResponse, data: data)
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func addAuthHeaders(to request: inout URLRequest) async throws {
        guard let token = keychainManager.accessToken else {
            throw APIError.unauthorized
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: Constants.API.Headers.authorization)

        // Add tenant ID if available and validated
        if let tenantId = keychainManager.tenantId {
            // Validate tenant ID exists in user's available tenants (defense-in-depth)
            if validateTenantAccess(tenantId) {
                request.setValue(tenantId, forHTTPHeaderField: Constants.API.Headers.tenantId)
            } else {
                // Log security event - tenant ID in keychain doesn't match available tenants
                SentryConfig.shared.captureMessage(
                    "Invalid tenant ID in keychain - clearing tenant context",
                    level: .warning
                )
                // Clear invalid tenant data
                keychainManager.clearTenantData()
                // Don't include invalid tenant ID in request
            }
        }

        // Add device headers if available
        if let deviceId = keychainManager.deviceId {
            request.setValue(deviceId, forHTTPHeaderField: Constants.API.Headers.deviceId)
        }

        // Add timestamp
        let timestamp = iso8601Formatter.string(from: Date())
        request.setValue(timestamp, forHTTPHeaderField: Constants.API.Headers.timestamp)
    }

    /// Validate that the given tenant ID exists in the user's available tenants
    private func validateTenantAccess(_ tenantId: String) -> Bool {
        // Try to load user's tenants from keychain
        guard let tenants = try? keychainManager.loadUserTenants() else {
            // If no tenants cached, allow the request (server will validate)
            // This handles the initial login case
            return true
        }

        // Check if the tenant ID exists in available tenants
        return tenants.contains { $0.id == tenantId }
    }

    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return // Success
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 500...599:
            throw APIError.serverError
        default:
            let message = try? decoder.decode(ErrorResponse.self, from: data).message
            throw APIError.httpError(statusCode: response.statusCode, message: message)
        }
    }

    private func refreshTokenAndRetry() async throws {
        // If a refresh is already in flight, wait for it
        if let existing = refreshTask {
            try await existing.value
            return
        }

        let task = Task<Void, Error> {
            defer { self.refreshTask = nil }

            guard let refreshToken = keychainManager.refreshToken else {
                throw APIError.tokenRefreshFailed
            }

            // Call refresh endpoint with isRetryAfterRefresh: true
            // to prevent recursive retry if the refresh endpoint itself returns 401
            let refreshRequest = RefreshTokenRequest(refreshToken: refreshToken)

            do {
                let responseData = try await makeRequest(
                    Constants.API.Endpoints.refreshToken,
                    method: .post,
                    body: refreshRequest,
                    queryItems: nil,
                    requiresAuth: false,
                    isRetryAfterRefresh: true
                )

                let tokens = try decoder.decode(AuthTokens.self, from: responseData)
                keychainManager.accessToken = tokens.accessToken
                keychainManager.refreshToken = tokens.refreshToken
            } catch {
                throw APIError.tokenRefreshFailed
            }
        }

        refreshTask = task
        try await task.value
    }
}

// MARK: - Helper Types

private struct ErrorResponse: Codable {
    let message: String?
    let error: String?
}

private struct RefreshTokenRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

/// Type-erased Encodable wrapper
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - SSL Certificate Pinning

/// URLSession delegate that implements SSL certificate pinning using public key hashes
final class SSLPinningDelegate: NSObject, URLSessionDelegate {

    /// SHA-256 hashes of pinned certificate public keys (base64 encoded)
    private let pinnedHashes: Set<String>

    /// Whether SSL pinning is enabled (disabled if no hashes provided)
    private let isPinningEnabled: Bool

    init(pinnedHashes: [String]) {
        self.pinnedHashes = Set(pinnedHashes)
        self.isPinningEnabled = !pinnedHashes.isEmpty
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // If pinning is disabled, allow the connection
        guard isPinningEnabled else {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        // Evaluate the server trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard isValid else {
            print("[SSL Pinning] Server trust evaluation failed: \(error?.localizedDescription ?? "Unknown error")")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get certificate chain
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              !certificateChain.isEmpty else {
            print("[SSL Pinning] No certificates in chain")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check each certificate in the chain against pinned hashes
        for certificate in certificateChain {
            if let publicKeyHash = getPublicKeyHash(from: certificate) {
                if pinnedHashes.contains(publicKeyHash) {
                    // Found a matching pinned certificate
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            }
        }

        // No matching certificate found
        print("[SSL Pinning] Certificate pinning failed - no matching hash found")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    /// Extract public key from certificate and compute SHA-256 hash
    private func getPublicKeyHash(from certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Add ASN.1 header for known key types
        guard let keyWithHeader = addRSAHeader(to: publicKeyData) else {
            // Unknown key type — cannot produce a correct hash
            return nil
        }

        // Compute SHA-256 hash
        let hash = SHA256.hash(data: keyWithHeader)
        return Data(hash).base64EncodedString()
    }

    /// Add ASN.1 header for RSA public keys
    /// This is needed because SecKeyCopyExternalRepresentation returns raw key data without the header
    private func addRSAHeader(to keyData: Data) -> Data? {
        // RSA 2048-bit public key ASN.1 header
        let rsa2048Header: [UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]

        // RSA 4096-bit public key ASN.1 header
        let rsa4096Header: [UInt8] = [
            0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
        ]

        // ECDSA P-256 public key ASN.1 header
        let ecdsaP256Header: [UInt8] = [
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
            0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
            0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
            0x42, 0x00
        ]

        // ECDSA P-384 public key ASN.1 header
        let ecdsaP384Header: [UInt8] = [
            0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86,
            0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
            0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
        ]

        // Choose header based on key size
        let header: [UInt8]
        switch keyData.count {
        case 270: // RSA 2048
            header = rsa2048Header
        case 526: // RSA 4096
            header = rsa4096Header
        case 65: // ECDSA P-256
            header = ecdsaP256Header
        case 97: // ECDSA P-384
            header = ecdsaP384Header
        default:
            // Unknown key type, cannot produce a correct hash
            return nil
        }

        return Data(header) + keyData
    }
}
