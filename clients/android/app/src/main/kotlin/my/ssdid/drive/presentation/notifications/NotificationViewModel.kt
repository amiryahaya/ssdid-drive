package my.ssdid.drive.presentation.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.Notification
import my.ssdid.drive.domain.model.NotificationActionType
import my.ssdid.drive.domain.repository.NotificationRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class NotificationUiState(
    val notifications: List<Notification> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val selectedFilter: NotificationFilter = NotificationFilter.ALL,
    val navigationEvent: NavigationEvent? = null
)

enum class NotificationFilter {
    ALL,
    UNREAD,
    SHARES,
    RECOVERY,
    SYSTEM
}

sealed class NavigationEvent {
    data class OpenShare(val shareId: String) : NavigationEvent()
    data class OpenFile(val fileId: String) : NavigationEvent()
    data class OpenFolder(val folderId: String) : NavigationEvent()
    data class OpenRecoveryRequest(val requestId: String) : NavigationEvent()
    data object OpenSettings : NavigationEvent()
}

@HiltViewModel
class NotificationViewModel @Inject constructor(
    private val notificationRepository: NotificationRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(NotificationUiState())
    val uiState: StateFlow<NotificationUiState> = _uiState.asStateFlow()

    val unreadCount: StateFlow<Int> = notificationRepository.observeUnreadCount()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = 0
        )

    init {
        loadNotifications()
        observeNotifications()
    }

    private fun observeNotifications() {
        viewModelScope.launch {
            notificationRepository.observeRecentNotifications(100).collect { notifications ->
                _uiState.update { state ->
                    state.copy(
                        notifications = filterNotifications(notifications, state.selectedFilter),
                        isLoading = false
                    )
                }
            }
        }
    }

    fun loadNotifications() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = notificationRepository.getNotifications()) {
                is Result.Success -> {
                    _uiState.update { state ->
                        state.copy(
                            notifications = filterNotifications(result.data, state.selectedFilter),
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

    fun setFilter(filter: NotificationFilter) {
        viewModelScope.launch {
            val allNotifications = when (val result = notificationRepository.getNotifications()) {
                is Result.Success -> result.data
                is Result.Error -> emptyList()
            }

            _uiState.update { state ->
                state.copy(
                    selectedFilter = filter,
                    notifications = filterNotifications(allNotifications, filter)
                )
            }
        }
    }

    fun markAsRead(notificationId: String) {
        viewModelScope.launch {
            notificationRepository.markAsRead(notificationId)
        }
    }

    fun markAllAsRead() {
        viewModelScope.launch {
            notificationRepository.markAllAsRead()
        }
    }

    fun deleteNotification(notificationId: String) {
        viewModelScope.launch {
            notificationRepository.deleteNotification(notificationId)
        }
    }

    fun deleteAllNotifications() {
        viewModelScope.launch {
            notificationRepository.deleteAllNotifications()
        }
    }

    fun handleNotificationClick(notification: Notification) {
        // Mark as read
        markAsRead(notification.id)

        // Handle navigation based on action type
        notification.action?.let { action ->
            val event = when (action.type) {
                NotificationActionType.OPEN_SHARE -> {
                    action.resourceId?.let { NavigationEvent.OpenShare(it) }
                }
                NotificationActionType.OPEN_FILE -> {
                    action.resourceId?.let { NavigationEvent.OpenFile(it) }
                }
                NotificationActionType.OPEN_FOLDER -> {
                    action.resourceId?.let { NavigationEvent.OpenFolder(it) }
                }
                NotificationActionType.OPEN_RECOVERY_REQUEST -> {
                    action.resourceId?.let { NavigationEvent.OpenRecoveryRequest(it) }
                }
                NotificationActionType.OPEN_SETTINGS -> NavigationEvent.OpenSettings
                NotificationActionType.RETRY_SYNC,
                NotificationActionType.NONE -> null
            }

            event?.let {
                _uiState.update { state -> state.copy(navigationEvent = it) }
            }
        }
    }

    fun clearNavigationEvent() {
        _uiState.update { it.copy(navigationEvent = null) }
    }

    private fun filterNotifications(
        notifications: List<Notification>,
        filter: NotificationFilter
    ): List<Notification> {
        return when (filter) {
            NotificationFilter.ALL -> notifications
            NotificationFilter.UNREAD -> notifications.filter { it.isUnread }
            NotificationFilter.SHARES -> notifications.filter {
                it.type.name.contains("SHARE") || it.type.name.contains("FILE") || it.type.name.contains("FOLDER")
            }
            NotificationFilter.RECOVERY -> notifications.filter {
                it.type.name.contains("RECOVERY")
            }
            NotificationFilter.SYSTEM -> notifications.filter {
                it.type.name.contains("SYNC") || it.type.name.contains("STORAGE") ||
                it.type.name.contains("SECURITY") || it.type.name == "INFO" ||
                it.type.name == "WARNING" || it.type.name == "ERROR"
            }
        }
    }
}
