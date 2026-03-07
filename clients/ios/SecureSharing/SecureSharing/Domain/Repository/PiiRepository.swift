import Foundation

/// Repository for PII service operations.
/// Handles conversation-based PII detection and token management
/// with KEM key registration for post-quantum secure DEK encryption.
protocol PiiRepository {

    // MARK: - Conversations

    /// Create a new PII service conversation
    /// - Parameters:
    ///   - title: Optional conversation title
    ///   - llmProvider: LLM provider name (e.g., "openai", "anthropic")
    ///   - llmModel: LLM model name (e.g., "gpt-4", "claude-3")
    /// - Returns: The created conversation
    func createConversation(
        title: String?,
        llmProvider: String,
        llmModel: String
    ) async throws -> PiiConversation

    /// Get a conversation by ID
    func getConversation(id: String) async throws -> PiiConversation

    /// List all conversations
    func listConversations() async throws -> [PiiConversation]

    // MARK: - KEM Key Registration

    /// Register KEM public keys for a conversation
    ///
    /// This generates new ML-KEM (and optionally KAZ-KEM) keypairs,
    /// registers the public keys with the PII service, and stores
    /// the secret keys locally for DEK unwrapping.
    ///
    /// - Parameters:
    ///   - conversationId: The conversation to register keys for
    ///   - includeKazKem: Whether to also generate KAZ-KEM keys for hybrid security
    /// - Returns: Registration result with timestamp
    func registerKemKeys(
        conversationId: String,
        includeKazKem: Bool
    ) async throws -> KemKeysRegistrationResult

    /// Check if KEM keys are registered and loaded for a conversation
    func hasKemKeysLoaded() -> Bool

    /// Clear KEM secret keys from memory
    func clearKemKeys()

    // MARK: - Ask AI

    /// Send a message to the PII service and get a response
    ///
    /// This automatically handles:
    /// - Sending the message to the LLM via the PII service
    /// - Unwrapping the KEM-encrypted DEK (if KEM keys were registered)
    /// - Decrypting the token map
    /// - Restoring original PII values in the response
    ///
    /// - Parameters:
    ///   - conversationId: The conversation to send the message to
    ///   - message: The user's message
    ///   - contextFiles: Optional file IDs to include as context
    /// - Returns: Decrypted response with PII restored
    func ask(
        conversationId: String,
        message: String,
        contextFiles: [String]?
    ) async throws -> PiiAskResponse
}

// MARK: - Models

/// A PII service conversation
struct PiiConversation: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let title: String?
    let status: String
    let llmProvider: String
    let llmModel: String
    let createdAt: String
    let mlKemPublicKey: String?
    let kazKemPublicKey: String?
    let kemKeysRegisteredAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case llmProvider = "llm_provider"
        case llmModel = "llm_model"
        case createdAt = "created_at"
        case mlKemPublicKey = "ml_kem_public_key"
        case kazKemPublicKey = "kaz_kem_public_key"
        case kemKeysRegisteredAt = "kem_keys_registered_at"
    }

    var hasKemKeysRegistered: Bool {
        mlKemPublicKey != nil
    }
}

/// Result of KEM key registration
struct KemKeysRegistrationResult: Codable, Sendable {
    let success: Bool
    let kemKeysRegisteredAt: String

    enum CodingKeys: String, CodingKey {
        case success
        case kemKeysRegisteredAt = "kem_keys_registered_at"
    }
}

/// Response from a PII service ask request
struct PiiAskResponse: Sendable {
    /// User message ID
    let userMessageId: String
    /// Assistant message ID
    let assistantMessageId: String
    /// Original content with PII restored
    let content: String
    /// Tokenized content (with PII replaced by tokens)
    let tokenizedContent: String
    /// Message role
    let role: String
    /// Number of PII tokens detected
    let tokensDetected: Int
    /// When the response was created
    let createdAt: String
}

/// Errors specific to PII service operations
enum PiiServiceError: Error, LocalizedError {
    case conversationNotFound
    case kemKeysNotRegistered
    case kemKeysNotLoaded
    case dekUnwrapFailed(String)
    case tokenMapDecryptionFailed(String)
    case invalidResponse(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .conversationNotFound:
            return "Conversation not found"
        case .kemKeysNotRegistered:
            return "KEM keys not registered for this conversation"
        case .kemKeysNotLoaded:
            return "KEM secret keys not loaded"
        case .dekUnwrapFailed(let reason):
            return "Failed to unwrap DEK: \(reason)"
        case .tokenMapDecryptionFailed(let reason):
            return "Failed to decrypt token map: \(reason)"
        case .invalidResponse(let reason):
            return "Invalid PII service response: \(reason)"
        case .networkError(let reason):
            return "PII service network error: \(reason)"
        }
    }
}
