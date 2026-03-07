package my.ssdid.drive.domain.model

import java.time.Instant

/**
 * Domain model for a PII chat conversation.
 */
data class Conversation(
    val id: String,
    val title: String?,
    val status: String,
    val llmProvider: String,
    val llmModel: String,
    val hasKemKeysRegistered: Boolean,
    val createdAt: Instant
)
