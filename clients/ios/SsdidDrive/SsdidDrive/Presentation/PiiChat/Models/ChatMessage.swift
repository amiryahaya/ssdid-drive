import Foundation

/// Represents a message in a PII chat conversation
struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: String
    let conversationId: String
    let role: MessageRole
    let content: String
    let tokenizedContent: String?
    let tokensDetected: Int
    let createdAt: Date

    enum MessageRole: String, Sendable {
        case user
        case assistant
    }

    /// Whether this is a temporary/optimistic message
    var isTemporary: Bool {
        id.hasPrefix("temp-")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// LLM Provider configuration
struct LlmProvider: Identifiable, Sendable {
    let id: String
    let name: String
    let models: [String]

    static let providers: [LlmProvider] = [
        LlmProvider(id: "openai", name: "OpenAI", models: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo"]),
        LlmProvider(id: "anthropic", name: "Anthropic", models: ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]),
        LlmProvider(id: "google", name: "Google", models: ["gemini-pro", "gemini-pro-vision"])
    ]

    static func provider(for id: String) -> LlmProvider? {
        providers.first { $0.id == id }
    }
}
