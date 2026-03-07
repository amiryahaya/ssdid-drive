import Foundation
import CryptoKit

/// Implementation of PiiRepository for PII service operations with KEM key management.
final class PiiRepositoryImpl: PiiRepository {

    // MARK: - Properties

    private let keychainManager: KeychainManager
    private let session: URLSession
    private let baseURL: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Current ML-KEM secret key for DEK unwrapping
    private var mlKemSecretKey: Data?

    /// Current KAZ-KEM secret key for DEK unwrapping (optional, for hybrid)
    private var kazKemSecretKey: Data?

    /// Lock for thread-safe key access
    private let keyLock = NSLock()

    // MARK: - Initialization

    init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager

        // PII service has its own base URL
        self.baseURL = ProcessInfo.processInfo.environment["PII_SERVICE_URL"]
            ?? Constants.API.piiServiceURL

        // Create URL session without SSL pinning for PII service (internal service)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)

        // Configure JSON decoder
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        // Configure JSON encoder
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    // MARK: - Conversations

    func createConversation(
        title: String?,
        llmProvider: String,
        llmModel: String
    ) async throws -> PiiConversation {
        let request = CreateConversationRequest(
            title: title,
            llmProvider: llmProvider,
            llmModel: llmModel
        )

        return try await post("/conversations", body: request)
    }

    func getConversation(id: String) async throws -> PiiConversation {
        return try await get("/conversations/\(id)")
    }

    func listConversations() async throws -> [PiiConversation] {
        struct ListResponse: Codable {
            let conversations: [PiiConversation]
        }
        let response: ListResponse = try await get("/conversations")
        return response.conversations
    }

    // MARK: - KEM Key Registration

    func registerKemKeys(
        conversationId: String,
        includeKazKem: Bool
    ) async throws -> KemKeysRegistrationResult {
        // Generate ML-KEM keypair
        let (mlKemPk, mlKemSk) = try MLKEM.generateKeyPair()

        // Optionally generate KAZ-KEM keypair
        var kazKemPk: Data?
        var kazKemSk: Data?

        if includeKazKem {
            let keypair = try KAZKEM.generateKeyPair()
            kazKemPk = keypair.publicKey
            kazKemSk = keypair.privateKey
        }

        // Register public keys with PII service
        let request = RegisterKemKeysRequest(
            mlKemPublicKey: mlKemPk.base64EncodedString(),
            kazKemPublicKey: kazKemPk?.base64EncodedString()
        )

        let response: KemKeysRegistrationResult = try await post(
            "/conversations/\(conversationId)/keys",
            body: request
        )

        // Store secret keys for DEK unwrapping
        keyLock.lock()
        defer { keyLock.unlock() }

        self.mlKemSecretKey = mlKemSk
        self.kazKemSecretKey = kazKemSk

        return response
    }

    func hasKemKeysLoaded() -> Bool {
        keyLock.lock()
        defer { keyLock.unlock() }
        return mlKemSecretKey != nil
    }

    func clearKemKeys() {
        keyLock.lock()
        defer { keyLock.unlock() }

        // Securely zero keys
        if var key = mlKemSecretKey {
            secureZero(&key)
            mlKemSecretKey = nil
        }
        if var key = kazKemSecretKey {
            secureZero(&key)
            kazKemSecretKey = nil
        }
    }

    // MARK: - Ask AI

    func ask(
        conversationId: String,
        message: String,
        contextFiles: [String]?
    ) async throws -> PiiAskResponse {
        let request = AskRequest(
            message: message,
            contextFiles: contextFiles,
            sessionKey: nil
        )

        let response: RawAskResponse = try await post(
            "/conversations/\(conversationId)/ask",
            body: request
        )

        // Decrypt the response
        return try decryptResponse(response)
    }

    // MARK: - DEK Unwrapping & Decryption

    private func decryptResponse(_ response: RawAskResponse) throws -> PiiAskResponse {
        // Get the DEK (either from KEM unwrapping or directly from response)
        let dek: Data

        if let wrappedDekB64 = response.wrappedDek,
           let mlKemCtB64 = response.mlKemCiphertext {
            // Unwrap DEK using KEM
            dek = try unwrapDek(
                wrappedDekB64: wrappedDekB64,
                mlKemCtB64: mlKemCtB64,
                kazKemCtB64: response.kazKemCiphertext
            )
        } else if let sessionKeyB64 = response.sessionKey {
            // DEK provided directly (legacy/fallback mode)
            guard let decoded = Data(base64Encoded: sessionKeyB64) else {
                throw PiiServiceError.invalidResponse("Invalid session key encoding")
            }
            dek = decoded
        } else {
            throw PiiServiceError.invalidResponse("No DEK available in response")
        }

        // Decrypt token map
        guard let encryptedTokenMapData = Data(base64Encoded: response.encryptedTokenMap) else {
            throw PiiServiceError.invalidResponse("Invalid encrypted token map encoding")
        }

        let tokenMap = try decryptTokenMap(encryptedTokenMapData, dek: dek)

        // Restore original content from tokens
        let restoredContent = restoreTokens(in: response.content, tokenMap: tokenMap)

        return PiiAskResponse(
            userMessageId: response.userMessageId,
            assistantMessageId: response.assistantMessageId,
            content: restoredContent,
            tokenizedContent: response.content,
            role: response.role,
            tokensDetected: response.tokensDetected,
            createdAt: response.createdAt
        )
    }

    private func unwrapDek(
        wrappedDekB64: String,
        mlKemCtB64: String,
        kazKemCtB64: String?
    ) throws -> Data {
        keyLock.lock()
        guard let mlKemSk = mlKemSecretKey else {
            keyLock.unlock()
            throw PiiServiceError.kemKeysNotLoaded
        }
        let kazKemSk = kazKemSecretKey
        keyLock.unlock()

        guard let mlKemCt = Data(base64Encoded: mlKemCtB64) else {
            throw PiiServiceError.dekUnwrapFailed("Invalid ML-KEM ciphertext encoding")
        }

        guard let wrappedDek = Data(base64Encoded: wrappedDekB64) else {
            throw PiiServiceError.dekUnwrapFailed("Invalid wrapped DEK encoding")
        }

        // ML-KEM decapsulation to get shared secret
        let mlSs = try MLKEM.decapsulate(ciphertext: mlKemCt, privateKey: mlKemSk)

        // If KAZ-KEM was used, combine shared secrets
        var combinedSs: Data
        if let kazCtB64 = kazKemCtB64, let kazSk = kazKemSk {
            guard let kazCt = Data(base64Encoded: kazCtB64) else {
                throw PiiServiceError.dekUnwrapFailed("Invalid KAZ-KEM ciphertext encoding")
            }

            let kazSs = try KAZKEM.decapsulate(ciphertext: kazCt, privateKey: kazSk)

            // Combine ML-KEM and KAZ-KEM shared secrets
            combinedSs = mlSs + kazSs
        } else {
            combinedSs = mlSs
        }

        // Derive KEK using HKDF (must match server-side derivation)
        let kek = try deriveKek(from: combinedSs)

        // Unwrap DEK with AES-GCM
        let dek = try decryptAesGcm(ciphertext: wrappedDek, key: kek)

        return dek
    }

    private func deriveKek(from sharedSecret: Data) throws -> SymmetricKey {
        // Use HKDF-SHA256 to derive KEK
        let info = "PII-Service-Hybrid-KEM-KEK-v1".data(using: .utf8)!
        let inputKey = SymmetricKey(data: sharedSecret)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            info: info,
            outputByteCount: 32
        )

        return derivedKey
    }

    private func decryptAesGcm(ciphertext: Data, key: SymmetricKey) throws -> Data {
        // Format: nonce (12) || ciphertext || tag (16)
        guard ciphertext.count > 28 else {
            throw PiiServiceError.dekUnwrapFailed("Ciphertext too short")
        }

        let nonce = ciphertext.prefix(12)
        let taggedCiphertext = ciphertext.suffix(from: 12)

        do {
            let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: taggedCiphertext.dropLast(16), tag: taggedCiphertext.suffix(16))
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return decrypted
        } catch {
            throw PiiServiceError.dekUnwrapFailed(error.localizedDescription)
        }
    }

    private func decryptTokenMap(_ encrypted: Data, dek: Data) throws -> [String: String] {
        // Token map format: nonce (12) || ciphertext || tag (16)
        guard encrypted.count > 28 else {
            throw PiiServiceError.tokenMapDecryptionFailed("Encrypted token map too short")
        }

        let key = SymmetricKey(data: dek)
        let decrypted = try decryptAesGcm(ciphertext: encrypted, key: key)

        guard let tokenMap = try? JSONDecoder().decode([String: String].self, from: decrypted) else {
            throw PiiServiceError.tokenMapDecryptionFailed("Invalid token map JSON")
        }

        return tokenMap
    }

    private func restoreTokens(in text: String, tokenMap: [String: String]) -> String {
        var restored = text
        for (token, value) in tokenMap {
            restored = restored.replacingOccurrences(of: token, with: value)
        }
        return restored
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(_ endpoint: String) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw PiiServiceError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PiiServiceError.invalidResponse("Decoding failed: \(error)")
        }
    }

    private func post<B: Encodable, T: Decodable>(
        _ endpoint: String,
        body: B
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw PiiServiceError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw PiiServiceError.networkError("Encoding failed: \(error)")
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PiiServiceError.invalidResponse("Decoding failed: \(error)")
        }
    }

    private func addAuthHeaders(to request: inout URLRequest) {
        if let token = keychainManager.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PiiServiceError.networkError("Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw PiiServiceError.networkError("Unauthorized")
        case 404:
            throw PiiServiceError.conversationNotFound
        default:
            throw PiiServiceError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - Secure Memory

    private func secureZero(_ data: inout Data) {
        data.withUnsafeMutableBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                memset(baseAddress, 0, ptr.count)
            }
        }
        data = Data()
    }

    deinit {
        clearKemKeys()
    }
}

// MARK: - Request Types

private struct CreateConversationRequest: Encodable {
    let title: String?
    let llmProvider: String
    let llmModel: String
}

private struct RegisterKemKeysRequest: Encodable {
    let mlKemPublicKey: String
    let kazKemPublicKey: String?
}

private struct AskRequest: Encodable {
    let message: String
    let contextFiles: [String]?
    let sessionKey: String?
}

// MARK: - Response Types

private struct RawAskResponse: Decodable {
    let userMessageId: String
    let assistantMessageId: String
    let content: String
    let role: String
    let tokensDetected: Int
    let llmTokensUsed: Int
    let createdAt: String
    let encryptedTokenMap: String
    let sessionKey: String?
    let tokenMapVersion: Int
    let wrappedDek: String?
    let mlKemCiphertext: String?
    let kazKemCiphertext: String?
}
