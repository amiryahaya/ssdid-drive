package my.ssdid.drive.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import my.ssdid.drive.domain.model.Conversation
import java.time.Instant
import java.util.UUID

/**
 * Room entity for storing PII chat conversations locally.
 */
@Entity(
    tableName = "pii_conversations",
    indices = [
        Index(value = ["userId"]),
        Index(value = ["createdAt"])
    ]
)
data class ConversationEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val userId: String,
    val title: String?,
    val status: String = "active",
    val llmProvider: String,
    val llmModel: String,
    val hasKemKeysRegistered: Boolean = false,
    val createdAt: Instant = Instant.now()
) {
    /**
     * Convert to domain model.
     */
    fun toDomain(): Conversation = Conversation(
        id = id,
        title = title,
        status = status,
        llmProvider = llmProvider,
        llmModel = llmModel,
        hasKemKeysRegistered = hasKemKeysRegistered,
        createdAt = createdAt
    )

    companion object {
        /**
         * Create from domain model.
         */
        fun fromDomain(conversation: Conversation, userId: String): ConversationEntity =
            ConversationEntity(
                id = conversation.id,
                userId = userId,
                title = conversation.title,
                status = conversation.status,
                llmProvider = conversation.llmProvider,
                llmModel = conversation.llmModel,
                hasKemKeysRegistered = conversation.hasKemKeysRegistered,
                createdAt = conversation.createdAt
            )
    }
}
