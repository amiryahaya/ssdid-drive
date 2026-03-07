package my.ssdid.drive.data.remote

import my.ssdid.drive.data.remote.dto.PiiAskRequest
import my.ssdid.drive.data.remote.dto.PiiAskResponse
import my.ssdid.drive.data.remote.dto.PiiConversationDto
import my.ssdid.drive.data.remote.dto.PiiCreateConversationRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import javax.inject.Inject
import javax.inject.Singleton

/**
 * API client for PII chat service.
 * Wraps Retrofit calls and handles responses.
 */
@Singleton
class ApiClient @Inject constructor(
    private val piiApiService: PiiApiService
) {
    /**
     * Create a new PII chat conversation.
     */
    suspend fun piiCreateConversation(
        title: String?,
        llmProvider: String,
        llmModel: String
    ): PiiConversationDto {
        val request = PiiCreateConversationRequest(
            title = title,
            llmProvider = llmProvider,
            llmModel = llmModel
        )
        val response = piiApiService.createConversation(request)
        if (response.isSuccessful) {
            return response.body() ?: throw Exception("Empty response body")
        }
        throw Exception("Failed to create conversation: ${response.code()}")
    }

    /**
     * Get a conversation by ID.
     */
    suspend fun piiGetConversation(id: String): PiiConversationDto {
        val response = piiApiService.getConversation(id)
        if (response.isSuccessful) {
            return response.body() ?: throw Exception("Empty response body")
        }
        throw Exception("Failed to get conversation: ${response.code()}")
    }

    /**
     * List all conversations for the current user.
     */
    suspend fun piiListConversations(): List<PiiConversationDto> {
        val response = piiApiService.listConversations()
        if (response.isSuccessful) {
            return response.body()?.conversations ?: emptyList()
        }
        throw Exception("Failed to list conversations: ${response.code()}")
    }

    /**
     * Send a message and get AI response.
     */
    suspend fun piiAsk(
        conversationId: String,
        message: String,
        contextFiles: List<String>?
    ): PiiAskResponse {
        val request = PiiAskRequest(
            message = message,
            contextFiles = contextFiles
        )
        val response = piiApiService.ask(conversationId, request)
        if (response.isSuccessful) {
            return response.body() ?: throw Exception("Empty response body")
        }
        throw Exception("Failed to send message: ${response.code()}")
    }

    /**
     * Register KEM keys for a conversation.
     */
    suspend fun piiRegisterKemKeys(conversationId: String, includeKazKem: Boolean) {
        val response = piiApiService.registerKemKeys(
            conversationId,
            PiiRegisterKemKeysRequest(includeKazKem = includeKazKem)
        )
        if (!response.isSuccessful) {
            throw Exception("Failed to register KEM keys: ${response.code()}")
        }
    }
}

/**
 * Retrofit interface for PII API endpoints.
 */
interface PiiApiService {
    @POST("pii/conversations")
    suspend fun createConversation(
        @Body request: PiiCreateConversationRequest
    ): retrofit2.Response<PiiConversationDto>

    @GET("pii/conversations/{id}")
    suspend fun getConversation(
        @Path("id") id: String
    ): retrofit2.Response<PiiConversationDto>

    @GET("pii/conversations")
    suspend fun listConversations(): retrofit2.Response<PiiConversationsResponse>

    @POST("pii/conversations/{id}/ask")
    suspend fun ask(
        @Path("id") conversationId: String,
        @Body request: PiiAskRequest
    ): retrofit2.Response<PiiAskResponse>

    @POST("pii/conversations/{id}/kem-keys")
    suspend fun registerKemKeys(
        @Path("id") conversationId: String,
        @Body request: PiiRegisterKemKeysRequest
    ): retrofit2.Response<Unit>
}

data class PiiConversationsResponse(
    val conversations: List<PiiConversationDto>
)

data class PiiRegisterKemKeysRequest(
    val includeKazKem: Boolean
)
