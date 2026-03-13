package my.ssdid.drive.data.repository

import my.ssdid.drive.data.local.dao.ChatMessageDao
import my.ssdid.drive.data.local.dao.ConversationDao
import my.ssdid.drive.data.local.entity.ChatMessageEntity
import my.ssdid.drive.data.local.entity.ConversationEntity
import my.ssdid.drive.data.remote.ApiClient
import my.ssdid.drive.domain.model.ChatMessage
import my.ssdid.drive.domain.model.Conversation
import my.ssdid.drive.domain.model.MessageRole
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.PiiChatRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of PiiChatRepository.
 * Handles PII chat conversations with local caching.
 */
@Singleton
class PiiChatRepositoryImpl @Inject constructor(
    private val apiClient: ApiClient,
    private val conversationDao: ConversationDao,
    private val chatMessageDao: ChatMessageDao,
    private val authRepository: AuthRepository
) : PiiChatRepository {

    // Track KEM keys registration state in memory
    private val kemKeysRegistered = ConcurrentHashMap<String, Boolean>()

    private suspend fun getCurrentUserId(): String {
        return when (val result = authRepository.getCurrentUser()) {
            is Result.Success -> result.data.id
            is Result.Error -> throw IllegalStateException("User not authenticated: ${result.exception.message}")
        }
    }

    // ==================== Conversations ====================

    override suspend fun createConversation(
        title: String?,
        llmProvider: String,
        llmModel: String
    ): Result<Conversation> {
        return try {
            val userId = getCurrentUserId()

            // Call API to create conversation
            val response = apiClient.piiCreateConversation(
                title = title,
                llmProvider = llmProvider,
                llmModel = llmModel
            )

            val conversation = Conversation(
                id = response.id,
                title = response.title,
                status = response.status,
                llmProvider = response.llmProvider,
                llmModel = response.llmModel,
                hasKemKeysRegistered = response.mlKemPublicKey != null,
                createdAt = parseInstant(response.createdAt)
            )

            // Cache locally
            conversationDao.insert(ConversationEntity.fromDomain(conversation, userId))

            Result.Success(conversation)
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun getConversation(id: String): Result<Conversation> {
        return try {
            // Try local cache first
            val cached = conversationDao.getById(id)
            if (cached != null) {
                return Result.Success(cached.toDomain())
            }

            // Fetch from API
            val response = apiClient.piiGetConversation(id)
            val conversation = Conversation(
                id = response.id,
                title = response.title,
                status = response.status,
                llmProvider = response.llmProvider,
                llmModel = response.llmModel,
                hasKemKeysRegistered = response.mlKemPublicKey != null,
                createdAt = parseInstant(response.createdAt)
            )

            // Cache locally
            val userId = getCurrentUserId()
            conversationDao.insert(ConversationEntity.fromDomain(conversation, userId))

            Result.Success(conversation)
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun listConversations(): Result<List<Conversation>> {
        return try {
            // Fetch from API
            val response = apiClient.piiListConversations()
            val userId = getCurrentUserId()

            val conversations = response.map { dto ->
                Conversation(
                    id = dto.id,
                    title = dto.title,
                    status = dto.status,
                    llmProvider = dto.llmProvider,
                    llmModel = dto.llmModel,
                    hasKemKeysRegistered = dto.mlKemPublicKey != null,
                    createdAt = parseInstant(dto.createdAt)
                )
            }

            // Update local cache
            conversations.forEach { conversation ->
                conversationDao.insert(ConversationEntity.fromDomain(conversation, userId))
            }

            Result.Success(conversations.sortedByDescending { it.createdAt })
        } catch (e: Exception) {
            // Fall back to local cache
            try {
                val userId = getCurrentUserId()
                val cached = conversationDao.getAll(userId).map { it.toDomain() }
                Result.Success(cached)
            } catch (cacheError: Exception) {
                Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
            }
        }
    }

    override fun observeConversations(): Flow<List<Conversation>> {
        // This will throw if user is not authenticated, but in practice
        // this is called only when authenticated
        val userId = runCatching {
            kotlinx.coroutines.runBlocking { getCurrentUserId() }
        }.getOrElse { "" }

        return conversationDao.observeAll(userId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun deleteConversation(id: String) {
        conversationDao.deleteById(id)
        kemKeysRegistered.remove(id)
    }

    // ==================== Messages ====================

    override suspend fun sendMessage(
        conversationId: String,
        message: String,
        contextFiles: List<String>?
    ): Result<ChatMessage> {
        return try {
            // Auto-register KEM keys if not registered
            if (!hasKemKeysRegistered(conversationId)) {
                val kemResult = registerKemKeys(conversationId, true)
                if (kemResult is Result.Error) {
                    return kemResult as Result.Error
                }
            }

            // Send to API
            val response = apiClient.piiAsk(
                conversationId = conversationId,
                message = message,
                contextFiles = contextFiles
            )

            val createdAt = parseInstant(response.createdAt)

            // Save user message
            val userMessage = ChatMessage(
                id = response.userMessageId,
                conversationId = conversationId,
                role = MessageRole.USER,
                content = message,
                tokenizedContent = null,
                tokensDetected = response.tokensDetected,
                createdAt = createdAt
            )
            chatMessageDao.insert(ChatMessageEntity.fromDomain(userMessage))

            // Save assistant message
            val assistantMessage = ChatMessage(
                id = response.assistantMessageId,
                conversationId = conversationId,
                role = MessageRole.ASSISTANT,
                content = response.content,
                tokenizedContent = response.tokenizedContent,
                tokensDetected = response.tokensDetected,
                createdAt = createdAt
            )
            chatMessageDao.insert(ChatMessageEntity.fromDomain(assistantMessage))

            // Delete temp messages
            chatMessageDao.deleteTempMessages(conversationId)

            Result.Success(assistantMessage)
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun getMessages(conversationId: String): Result<List<ChatMessage>> {
        return try {
            val messages = chatMessageDao.getByConversation(conversationId)
                .map { it.toDomain() }
            Result.Success(messages)
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override fun observeMessages(conversationId: String): Flow<List<ChatMessage>> {
        return chatMessageDao.observeByConversation(conversationId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    // ==================== KEM Keys ====================

    override suspend fun registerKemKeys(
        conversationId: String,
        includeKazKem: Boolean
    ): Result<Unit> {
        return try {
            apiClient.piiRegisterKemKeys(conversationId, includeKazKem)
            kemKeysRegistered[conversationId] = true
            conversationDao.updateKemKeysRegistered(conversationId, true)
            Result.Success(Unit)
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override fun hasKemKeysRegistered(conversationId: String): Boolean {
        return kemKeysRegistered[conversationId] == true
    }

    override fun clearKemKeys() {
        kemKeysRegistered.clear()
    }

    // ==================== Helpers ====================

    private fun parseInstant(dateString: String): Instant {
        return try {
            java.time.OffsetDateTime.parse(dateString).toInstant()
        } catch (e: Exception) {
            Instant.now()
        }
    }
}
