package my.ssdid.drive.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import my.ssdid.drive.data.local.entity.ChatMessageEntity
import kotlinx.coroutines.flow.Flow

/**
 * Data Access Object for PII chat messages.
 */
@Dao
interface ChatMessageDao {

    // ==================== Insert Operations ====================

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(message: ChatMessageEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(messages: List<ChatMessageEntity>)

    // ==================== Query Operations ====================

    /**
     * Get all messages for a conversation, ordered by creation date.
     */
    @Query("SELECT * FROM pii_chat_messages WHERE conversationId = :conversationId ORDER BY createdAt ASC")
    suspend fun getByConversation(conversationId: String): List<ChatMessageEntity>

    /**
     * Observe all messages for a conversation.
     */
    @Query("SELECT * FROM pii_chat_messages WHERE conversationId = :conversationId ORDER BY createdAt ASC")
    fun observeByConversation(conversationId: String): Flow<List<ChatMessageEntity>>

    /**
     * Get a message by ID.
     */
    @Query("SELECT * FROM pii_chat_messages WHERE id = :id")
    suspend fun getById(id: String): ChatMessageEntity?

    /**
     * Get message count for a conversation.
     */
    @Query("SELECT COUNT(*) FROM pii_chat_messages WHERE conversationId = :conversationId")
    suspend fun getMessageCount(conversationId: String): Int

    // ==================== Delete Operations ====================

    /**
     * Delete a message by ID.
     */
    @Query("DELETE FROM pii_chat_messages WHERE id = :id")
    suspend fun deleteById(id: String)

    /**
     * Delete all messages for a conversation.
     */
    @Query("DELETE FROM pii_chat_messages WHERE conversationId = :conversationId")
    suspend fun deleteByConversation(conversationId: String)

    /**
     * Delete temporary messages (those with IDs starting with "temp-").
     */
    @Query("DELETE FROM pii_chat_messages WHERE conversationId = :conversationId AND id LIKE 'temp-%'")
    suspend fun deleteTempMessages(conversationId: String)
}
