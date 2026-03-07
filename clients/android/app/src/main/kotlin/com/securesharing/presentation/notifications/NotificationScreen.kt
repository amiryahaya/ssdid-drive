package com.securesharing.presentation.notifications

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.securesharing.domain.model.Notification
import com.securesharing.domain.model.NotificationIcon
import com.securesharing.domain.model.NotificationType

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationScreen(
    onNavigateBack: () -> Unit,
    onNavigateToShare: (String) -> Unit,
    onNavigateToFile: (String) -> Unit,
    onNavigateToFolder: (String) -> Unit,
    onNavigateToRecoveryRequest: (String) -> Unit,
    onNavigateToSettings: () -> Unit,
    viewModel: NotificationViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    // Handle navigation events
    LaunchedEffect(uiState.navigationEvent) {
        uiState.navigationEvent?.let { event ->
            when (event) {
                is NavigationEvent.OpenShare -> onNavigateToShare(event.shareId)
                is NavigationEvent.OpenFile -> onNavigateToFile(event.fileId)
                is NavigationEvent.OpenFolder -> onNavigateToFolder(event.folderId)
                is NavigationEvent.OpenRecoveryRequest -> onNavigateToRecoveryRequest(event.requestId)
                NavigationEvent.OpenSettings -> onNavigateToSettings()
            }
            viewModel.clearNavigationEvent()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Notifications") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                },
                actions = {
                    // Mark all as read
                    if (uiState.notifications.any { it.isUnread }) {
                        IconButton(onClick = { viewModel.markAllAsRead() }) {
                            Icon(Icons.Default.DoneAll, "Mark all as read")
                        }
                    }
                    // More options
                    var showMenu by remember { mutableStateOf(false) }
                    IconButton(onClick = { showMenu = true }) {
                        Icon(Icons.Default.MoreVert, "More options")
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Delete all") },
                            onClick = {
                                viewModel.deleteAllNotifications()
                                showMenu = false
                            },
                            leadingIcon = {
                                Icon(Icons.Default.DeleteSweep, null)
                            }
                        )
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Filter chips
            NotificationFilterChips(
                selectedFilter = uiState.selectedFilter,
                onFilterSelected = { viewModel.setFilter(it) }
            )

            // Content
            when {
                uiState.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
                uiState.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = uiState.error!!,
                                color = MaterialTheme.colorScheme.error
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Button(onClick = { viewModel.loadNotifications() }) {
                                Text("Retry")
                            }
                        }
                    }
                }
                uiState.notifications.isEmpty() -> {
                    EmptyNotificationsState(filter = uiState.selectedFilter)
                }
                else -> {
                    NotificationList(
                        notifications = uiState.notifications,
                        onNotificationClick = { viewModel.handleNotificationClick(it) },
                        onDeleteNotification = { viewModel.deleteNotification(it.id) }
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NotificationFilterChips(
    selectedFilter: NotificationFilter,
    onFilterSelected: (NotificationFilter) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        NotificationFilter.entries.forEach { filter ->
            FilterChip(
                selected = selectedFilter == filter,
                onClick = { onFilterSelected(filter) },
                label = {
                    Text(
                        text = when (filter) {
                            NotificationFilter.ALL -> "All"
                            NotificationFilter.UNREAD -> "Unread"
                            NotificationFilter.SHARES -> "Shares"
                            NotificationFilter.RECOVERY -> "Recovery"
                            NotificationFilter.SYSTEM -> "System"
                        }
                    )
                }
            )
        }
    }
}

@Composable
private fun NotificationList(
    notifications: List<Notification>,
    onNotificationClick: (Notification) -> Unit,
    onDeleteNotification: (Notification) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 8.dp)
    ) {
        items(notifications, key = { it.id }) { notification ->
            NotificationItem(
                notification = notification,
                onClick = { onNotificationClick(notification) },
                onDelete = { onDeleteNotification(notification) }
            )
        }
    }
}

@Composable
private fun NotificationItem(
    notification: Notification,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    val backgroundColor by animateColorAsState(
        targetValue = if (notification.isUnread) {
            MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.1f)
        } else {
            Color.Transparent
        },
        label = "background"
    )

    ListItem(
        modifier = Modifier
            .fillMaxWidth()
            .background(backgroundColor)
            .clickable(onClick = onClick),
        headlineContent = {
            Text(
                text = notification.title,
                fontWeight = if (notification.isUnread) FontWeight.Bold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        },
        supportingContent = {
            Column {
                Text(
                    text = notification.message,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = notification.getRelativeTime(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        leadingContent = {
            NotificationIconComponent(
                icon = notification.type.getIcon(),
                isUnread = notification.isUnread
            )
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (notification.isUnread) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .background(
                                MaterialTheme.colorScheme.primary,
                                shape = MaterialTheme.shapes.small
                            )
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = "Delete",
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
    )
}

@Composable
private fun NotificationIconComponent(
    icon: NotificationIcon,
    isUnread: Boolean
) {
    val tint = if (isUnread) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Box(
        modifier = Modifier
            .size(40.dp)
            .background(
                color = tint.copy(alpha = 0.1f),
                shape = MaterialTheme.shapes.medium
            ),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = when (icon) {
                NotificationIcon.SHARE -> Icons.Default.Share
                NotificationIcon.SHARE_OFF -> Icons.Default.LinkOff
                NotificationIcon.KEY -> Icons.Default.Key
                NotificationIcon.FILE -> Icons.Default.InsertDriveFile
                NotificationIcon.DELETE -> Icons.Default.Delete
                NotificationIcon.FOLDER -> Icons.Default.Folder
                NotificationIcon.SYNC -> Icons.Default.Sync
                NotificationIcon.SYNC_ERROR -> Icons.Default.SyncProblem
                NotificationIcon.STORAGE -> Icons.Default.Storage
                NotificationIcon.SECURITY -> Icons.Default.Security
                NotificationIcon.INFO -> Icons.Default.Info
                NotificationIcon.WARNING -> Icons.Default.Warning
                NotificationIcon.ERROR -> Icons.Default.Error
            },
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(24.dp)
        )
    }
}

@Composable
private fun EmptyNotificationsState(filter: NotificationFilter) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = Icons.Default.Notifications,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = when (filter) {
                    NotificationFilter.ALL -> "No notifications"
                    NotificationFilter.UNREAD -> "No unread notifications"
                    NotificationFilter.SHARES -> "No share notifications"
                    NotificationFilter.RECOVERY -> "No recovery notifications"
                    NotificationFilter.SYSTEM -> "No system notifications"
                },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "You're all caught up!",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
            )
        }
    }
}

/**
 * Notification badge component for app bars.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationBadge(
    unreadCount: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    IconButton(
        onClick = onClick,
        modifier = modifier
    ) {
        BadgedBox(
            badge = {
                if (unreadCount > 0) {
                    Badge {
                        Text(
                            text = if (unreadCount > 99) "99+" else unreadCount.toString()
                        )
                    }
                }
            }
        ) {
            Icon(
                imageVector = Icons.Default.Notifications,
                contentDescription = "Notifications"
            )
        }
    }
}
