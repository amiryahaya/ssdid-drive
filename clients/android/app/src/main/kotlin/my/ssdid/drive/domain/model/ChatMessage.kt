package my.ssdid.drive.domain.model

import java.time.Instant

/**
 * Domain model for a chat message in a PII conversation.
 */
data class ChatMessage(
    val id: String,
    val conversationId: String,
    val role: MessageRole,
    val content: String,
    val tokenizedContent: String?,
    val tokensDetected: Int,
    val createdAt: Instant
) {
    /**
     * Whether this is a temporary/optimistic message.
     */
    val isTemporary: Boolean
        get() = id.startsWith("temp-")
}

/**
 * Message role enum.
 */
enum class MessageRole {
    USER,
    ASSISTANT
}
