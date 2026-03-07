package my.ssdid.drive.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * DTO for PII chat conversation.
 */
data class PiiConversationDto(
    val id: String,
    val title: String?,
    val status: String,
    @SerializedName("llm_provider")
    val llmProvider: String,
    @SerializedName("llm_model")
    val llmModel: String,
    @SerializedName("ml_kem_public_key")
    val mlKemPublicKey: String?,
    @SerializedName("kaz_kem_public_key")
    val kazKemPublicKey: String?,
    @SerializedName("created_at")
    val createdAt: String
)

/**
 * Request to create a new conversation.
 */
data class PiiCreateConversationRequest(
    val title: String?,
    @SerializedName("llm_provider")
    val llmProvider: String,
    @SerializedName("llm_model")
    val llmModel: String
)

/**
 * Request to send a message.
 */
data class PiiAskRequest(
    val message: String,
    @SerializedName("context_files")
    val contextFiles: List<String>?
)

/**
 * Response from sending a message.
 */
data class PiiAskResponse(
    @SerializedName("user_message_id")
    val userMessageId: String,
    @SerializedName("assistant_message_id")
    val assistantMessageId: String,
    val content: String,
    @SerializedName("tokenized_content")
    val tokenizedContent: String?,
    @SerializedName("tokens_detected")
    val tokensDetected: Int,
    @SerializedName("created_at")
    val createdAt: String
)
