package my.ssdid.drive.presentation.activity

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.FileActivity
import my.ssdid.drive.presentation.common.AnimatedListItem
import my.ssdid.drive.presentation.common.EmptyState
import my.ssdid.drive.presentation.common.ErrorState
import my.ssdid.drive.presentation.common.ListLoadingSkeleton

private val FILTERS = listOf("All", "Uploads", "Downloads", "Shares", "Renames", "Deletes", "Folders")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityScreen(
    onNavigateBack: () -> Unit,
    viewModel: ActivityViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Show snackbar for errors
    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            val result = snackbarHostState.showSnackbar(
                message = error,
                actionLabel = "Retry",
                duration = SnackbarDuration.Long
            )
            if (result == SnackbarResult.ActionPerformed) {
                viewModel.loadActivity()
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Activity") },
                navigationIcon = {
                    IconButton(
                        onClick = onNavigateBack,
                        modifier = Modifier.semantics { contentDescription = "Navigate back" }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.loadActivity() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                }
            )
        },
        snackbarHost = {
            SnackbarHost(hostState = snackbarHostState) { data ->
                Snackbar(
                    snackbarData = data,
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                    actionColor = MaterialTheme.colorScheme.primary
                )
            }
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Filter chips row
            LazyRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(FILTERS) { filter ->
                    FilterChip(
                        selected = uiState.selectedFilter == filter,
                        onClick = { viewModel.setFilter(filter) },
                        label = { Text(filter) },
                        modifier = Modifier.semantics {
                            contentDescription = "Filter: $filter"
                        }
                    )
                }
            }

            // Content area
            Box(modifier = Modifier.fillMaxSize()) {
                when {
                    // Loading skeleton on initial load
                    uiState.isLoading && uiState.items.isEmpty() -> {
                        ListLoadingSkeleton(
                            itemCount = 8,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    // Error state with no items
                    !uiState.isLoading && uiState.items.isEmpty() && uiState.error != null -> {
                        ErrorState(
                            message = uiState.error ?: "Unknown error",
                            onRetry = { viewModel.loadActivity() },
                            modifier = Modifier.align(Alignment.Center)
                        )
                    }
                    // Empty state
                    !uiState.isLoading && uiState.items.isEmpty() && uiState.error == null -> {
                        EmptyState(
                            icon = Icons.Default.History,
                            title = "No activity yet",
                            description = "File activity will appear here as you upload, download, share, and manage files.",
                            modifier = Modifier.align(Alignment.Center)
                        )
                    }
                    // Activity list
                    else -> {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(vertical = 8.dp)
                        ) {
                            itemsIndexed(
                                items = uiState.items,
                                key = { _, item -> item.id }
                            ) { index, activity ->
                                AnimatedListItem(index = index) {
                                    ActivityListItem(activity = activity)
                                }
                            }
                        }
                    }
                }

                // Pull-to-refresh loading indicator
                if (uiState.isLoading && uiState.items.isNotEmpty()) {
                    LinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .align(Alignment.TopCenter)
                    )
                }
            }
        }
    }
}

@Composable
private fun ActivityListItem(
    activity: FileActivity
) {
    val icon = activityIcon(activity.eventType)
    val iconTint = activityIconTint(activity.eventType)
    val actorLabel = activity.actorName ?: "Unknown"
    val description = "$actorLabel ${activity.eventLabel.lowercase()} ${activity.resourceName}"

    ListItem(
        headlineContent = {
            Text(
                text = "${activity.eventLabel}: ${activity.resourceName}",
                style = MaterialTheme.typography.bodyLarge
            )
        },
        supportingContent = {
            Column {
                Text(
                    text = "by $actorLabel",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = activity.timeAgo,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        leadingContent = {
            Icon(
                imageVector = icon,
                contentDescription = activity.eventLabel,
                tint = iconTint
            )
        },
        modifier = Modifier.semantics { contentDescription = description }
    )
}

@Composable
private fun activityIcon(eventType: String): ImageVector {
    return when (eventType) {
        "file_uploaded" -> Icons.Default.Upload
        "file_downloaded" -> Icons.Default.Download
        "file_deleted" -> Icons.Default.Delete
        "file_renamed" -> Icons.Default.DriveFileRenameOutline
        "file_moved" -> Icons.Default.DriveFileMove
        "file_shared" -> Icons.Default.Share
        "share_revoked" -> Icons.Default.PersonRemove
        "share_permission_changed" -> Icons.Default.ManageAccounts
        "file_previewed" -> Icons.Default.Visibility
        "folder_created" -> Icons.Default.CreateNewFolder
        "folder_deleted" -> Icons.Default.FolderDelete
        "folder_renamed" -> Icons.Default.DriveFileRenameOutline
        else -> Icons.Default.Info
    }
}

@Composable
private fun activityIconTint(eventType: String): androidx.compose.ui.graphics.Color {
    return when {
        eventType.contains("deleted") -> MaterialTheme.colorScheme.error
        eventType.contains("shared") -> MaterialTheme.colorScheme.tertiary
        eventType.contains("uploaded") || eventType.contains("created") -> MaterialTheme.colorScheme.primary
        eventType.contains("downloaded") -> MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}
