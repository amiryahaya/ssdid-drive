package com.securesharing.presentation.piichat

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.ChatMessage
import com.securesharing.domain.model.Conversation
import com.securesharing.domain.model.LlmProvider
import com.securesharing.domain.model.MessageRole
import com.securesharing.domain.repository.PiiChatRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import javax.inject.Inject

data class ChatUiState(
    val conversation: Conversation? = null,
    val messages: List<ChatMessage> = emptyList(),
    val isLoading: Boolean = false,
    val isSending: Boolean = false,
    val isKemRegistered: Boolean = false,
    val messageInput: String = "",
    val error: String? = null
)

@HiltViewModel
class ChatViewModel @Inject constructor(
    private val piiChatRepository: PiiChatRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val conversationId: String = savedStateHandle.get<String>("conversationId")
        ?: throw IllegalArgumentException("conversationId is required")

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    init {
        loadConversation()
        observeMessages()
    }

    private fun loadConversation() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = piiChatRepository.getConversation(conversationId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            conversation = result.data,
                            isKemRegistered = result.data.hasKemKeysRegistered ||
                                piiChatRepository.hasKemKeysRegistered(conversationId),
                            isLoading = false
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    private fun observeMessages() {
        viewModelScope.launch {
            piiChatRepository.observeMessages(conversationId).collect { messages ->
                _uiState.update { it.copy(messages = messages) }
            }
        }
    }

    fun setMessageInput(text: String) {
        _uiState.update { it.copy(messageInput = text) }
    }

    fun sendMessage() {
        val message = _uiState.value.messageInput.trim()
        if (message.isEmpty()) return

        viewModelScope.launch {
            // Clear input immediately
            _uiState.update { it.copy(messageInput = "", isSending = true, error = null) }

            // Add optimistic message
            val tempMessage = ChatMessage(
                id = "temp-${System.currentTimeMillis()}",
                conversationId = conversationId,
                role = MessageRole.USER,
                content = message,
                tokenizedContent = null,
                tokensDetected = 0,
                createdAt = Instant.now()
            )
            _uiState.update { it.copy(messages = it.messages + tempMessage) }

            when (val result = piiChatRepository.sendMessage(conversationId, message)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isSending = false,
                            isKemRegistered = true
                        )
                    }
                }
                is Result.Error -> {
                    // Remove optimistic message
                    _uiState.update {
                        it.copy(
                            messages = it.messages.filter { m -> !m.isTemporary },
                            isSending = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    val providerName: String
        get() = _uiState.value.conversation?.let {
            LlmProvider.findById(it.llmProvider)?.name ?: it.llmProvider
        } ?: ""
}
