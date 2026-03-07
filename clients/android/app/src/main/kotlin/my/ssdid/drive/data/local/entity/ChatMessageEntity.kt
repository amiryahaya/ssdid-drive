package my.ssdid.drive.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import my.ssdid.drive.domain.model.ChatMessage
import my.ssdid.drive.domain.model.MessageRole
import java.time.Instant
import java.util.UUID

/**
 * Room entity for storing PII chat messages locally.
 */
@Entity(
    tableName = "pii_chat_messages",
    indices = [
        Index(value = ["conversationId"]),
        Index(value = ["createdAt"])
    ],
    foreignKeys = [
        ForeignKey(
            entity = ConversationEntity::class,
            parentColumns = ["id"],
            childColumns = ["conversationId"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class ChatMessageEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val conversationId: String,
    val role: String, // "user" or "assistant"
    val content: String,
    val tokenizedContent: String?,
    val tokensDetected: Int = 0,
    val createdAt: Instant = Instant.now()
) {
    /**
     * Convert to domain model.
     */
    fun toDomain(): ChatMessage = ChatMessage(
        id = id,
        conversationId = conversationId,
        role = MessageRole.valueOf(role.uppercase()),
        content = content,
        tokenizedContent = tokenizedContent,
        tokensDetected = tokensDetected,
        createdAt = createdAt
    )

    companion object {
        /**
         * Create from domain model.
         */
        fun fromDomain(message: ChatMessage): ChatMessageEntity =
            ChatMessageEntity(
                id = message.id,
                conversationId = message.conversationId,
                role = message.role.name.lowercase(),
                content = message.content,
                tokenizedContent = message.tokenizedContent,
                tokensDetected = message.tokensDetected,
                createdAt = message.createdAt
            )
    }
}
