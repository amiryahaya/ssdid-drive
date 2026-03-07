package com.securesharing.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securesharing.data.local.entity.ConversationEntity
import kotlinx.coroutines.flow.Flow

/**
 * Data Access Object for PII chat conversations.
 */
@Dao
interface ConversationDao {

    // ==================== Insert Operations ====================

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(conversation: ConversationEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(conversations: List<ConversationEntity>)

    // ==================== Query Operations ====================

    /**
     * Get all conversations for a user, ordered by creation date.
     */
    @Query("SELECT * FROM pii_conversations WHERE userId = :userId ORDER BY createdAt DESC")
    suspend fun getAll(userId: String): List<ConversationEntity>

    /**
     * Observe all conversations for a user.
     */
    @Query("SELECT * FROM pii_conversations WHERE userId = :userId ORDER BY createdAt DESC")
    fun observeAll(userId: String): Flow<List<ConversationEntity>>

    /**
     * Get a conversation by ID.
     */
    @Query("SELECT * FROM pii_conversations WHERE id = :id")
    suspend fun getById(id: String): ConversationEntity?

    /**
     * Check if a conversation exists.
     */
    @Query("SELECT EXISTS(SELECT 1 FROM pii_conversations WHERE id = :id)")
    suspend fun exists(id: String): Boolean

    // ==================== Update Operations ====================

    @Update
    suspend fun update(conversation: ConversationEntity)

    /**
     * Update KEM keys registered status.
     */
    @Query("UPDATE pii_conversations SET hasKemKeysRegistered = :registered WHERE id = :id")
    suspend fun updateKemKeysRegistered(id: String, registered: Boolean)

    // ==================== Delete Operations ====================

    /**
     * Delete a conversation by ID.
     */
    @Query("DELETE FROM pii_conversations WHERE id = :id")
    suspend fun deleteById(id: String)

    /**
     * Delete all conversations for a user.
     */
    @Query("DELETE FROM pii_conversations WHERE userId = :userId")
    suspend fun deleteAll(userId: String)
}
