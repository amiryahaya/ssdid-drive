package my.ssdid.drive.presentation.piichat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.Conversation
import my.ssdid.drive.domain.model.LlmProvider
import my.ssdid.drive.domain.repository.PiiChatRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ConversationsUiState(
    val conversations: List<Conversation> = emptyList(),
    val isLoading: Boolean = false,
    val isCreating: Boolean = false,
    val error: String? = null,
    val showNewConversationDialog: Boolean = false,
    val newConversationTitle: String = "",
    val selectedProviderId: String = "openai",
    val selectedModel: String = "gpt-4o",
    val navigateToChat: String? = null // conversation ID to navigate to
)

@HiltViewModel
class ConversationsViewModel @Inject constructor(
    private val piiChatRepository: PiiChatRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(ConversationsUiState())
    val uiState: StateFlow<ConversationsUiState> = _uiState.asStateFlow()

    init {
        loadConversations()
    }

    fun loadConversations() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = piiChatRepository.listConversations()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            conversations = result.data,
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

    fun showNewConversationDialog() {
        _uiState.update { it.copy(showNewConversationDialog = true) }
    }

    fun hideNewConversationDialog() {
        _uiState.update {
            it.copy(
                showNewConversationDialog = false,
                newConversationTitle = "",
                selectedProviderId = "openai",
                selectedModel = "gpt-4o"
            )
        }
    }

    fun setNewConversationTitle(title: String) {
        _uiState.update { it.copy(newConversationTitle = title) }
    }

    fun selectProvider(providerId: String) {
        val provider = LlmProvider.findById(providerId)
        val firstModel = provider?.models?.firstOrNull() ?: "gpt-4o"
        _uiState.update {
            it.copy(
                selectedProviderId = providerId,
                selectedModel = firstModel
            )
        }
    }

    fun selectModel(model: String) {
        _uiState.update { it.copy(selectedModel = model) }
    }

    fun createConversation() {
        val state = _uiState.value
        viewModelScope.launch {
            _uiState.update { it.copy(isCreating = true, error = null) }

            val title = state.newConversationTitle.takeIf { it.isNotBlank() }
            when (val result = piiChatRepository.createConversation(
                title = title,
                llmProvider = state.selectedProviderId,
                llmModel = state.selectedModel
            )) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            conversations = listOf(result.data) + it.conversations,
                            isCreating = false,
                            showNewConversationDialog = false,
                            newConversationTitle = "",
                            selectedProviderId = "openai",
                            selectedModel = "gpt-4o",
                            navigateToChat = result.data.id
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isCreating = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    fun deleteConversation(conversationId: String) {
        viewModelScope.launch {
            piiChatRepository.deleteConversation(conversationId)
            _uiState.update {
                it.copy(
                    conversations = it.conversations.filter { c -> c.id != conversationId }
                )
            }
        }
    }

    fun clearNavigationEvent() {
        _uiState.update { it.copy(navigateToChat = null) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
