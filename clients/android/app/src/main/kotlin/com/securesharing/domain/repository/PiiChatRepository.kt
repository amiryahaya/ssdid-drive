package com.securesharing.domain.repository

import com.securesharing.domain.model.ChatMessage
import com.securesharing.domain.model.Conversation
import com.securesharing.util.Result
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for PII chat operations.
 */
interface PiiChatRepository {

    // ==================== Conversations ====================

    /**
     * Create a new conversation.
     */
    suspend fun createConversation(
        title: String?,
        llmProvider: String,
        llmModel: String
    ): Result<Conversation>

    /**
     * Get a conversation by ID.
     */
    suspend fun getConversation(id: String): Result<Conversation>

    /**
     * List all conversations.
     */
    suspend fun listConversations(): Result<List<Conversation>>

    /**
     * Observe all conversations.
     */
    fun observeConversations(): Flow<List<Conversation>>

    /**
     * Delete a conversation (local only).
     */
    suspend fun deleteConversation(id: String)

    // ==================== Messages ====================

    /**
     * Send a message to the AI and get a response.
     */
    suspend fun sendMessage(
        conversationId: String,
        message: String,
        contextFiles: List<String>? = null
    ): Result<ChatMessage>

    /**
     * Get messages for a conversation.
     */
    suspend fun getMessages(conversationId: String): Result<List<ChatMessage>>

    /**
     * Observe messages for a conversation.
     */
    fun observeMessages(conversationId: String): Flow<List<ChatMessage>>

    // ==================== KEM Keys ====================

    /**
     * Register KEM keys for a conversation.
     */
    suspend fun registerKemKeys(
        conversationId: String,
        includeKazKem: Boolean = true
    ): Result<Unit>

    /**
     * Check if KEM keys are registered for a conversation.
     */
    fun hasKemKeysRegistered(conversationId: String): Boolean

    /**
     * Clear KEM keys from memory.
     */
    fun clearKemKeys()
}
