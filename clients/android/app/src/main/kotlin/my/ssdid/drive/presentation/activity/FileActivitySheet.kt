package my.ssdid.drive.presentation.activity

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import my.ssdid.drive.domain.model.FileActivity
import my.ssdid.drive.domain.repository.ActivityRepository
import my.ssdid.drive.presentation.common.ListLoadingSkeleton
import my.ssdid.drive.util.Result
import kotlinx.coroutines.launch

/**
 * Bottom sheet showing activity log for a specific file or folder.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FileActivitySheet(
    resourceId: String,
    resourceName: String,
    activityRepository: ActivityRepository,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    var items by remember { mutableStateOf<List<FileActivity>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(resourceId) {
        isLoading = true
        error = null
        when (val result = activityRepository.getResourceActivity(resourceId)) {
            is Result.Success -> {
                items = result.data
                isLoading = false
            }
            is Result.Error -> {
                error = result.exception.message
                isLoading = false
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp)
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.History,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Activity",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = resourceName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(
                    onClick = {
                        scope.launch {
                            sheetState.hide()
                            onDismiss()
                        }
                    }
                ) {
                    Text("Close")
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // Content
            when {
                isLoading -> {
                    ListLoadingSkeleton(
                        itemCount = 4,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 400.dp)
                    )
                }
                error != null -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(32.dp)
                            .semantics { contentDescription = "Error: $error" },
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            imageVector = Icons.Default.ErrorOutline,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.error
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = error ?: "Unknown error",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                items.isEmpty() -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            imageVector = Icons.Default.History,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = "No activity recorded",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 400.dp),
                        contentPadding = PaddingValues(vertical = 4.dp)
                    ) {
                        itemsIndexed(
                            items = items,
                            key = { _, item -> item.id }
                        ) { _, activity ->
                            FileActivityListItem(activity = activity)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FileActivityListItem(
    activity: FileActivity
) {
    val actorLabel = activity.actorName ?: "Unknown"

    ListItem(
        headlineContent = {
            Text(
                text = activity.eventLabel,
                style = MaterialTheme.typography.bodyMedium
            )
        },
        supportingContent = {
            Text(
                text = "$actorLabel - ${activity.timeAgo}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        leadingContent = {
            Icon(
                imageVector = fileActivityIcon(activity.eventType),
                contentDescription = activity.eventLabel,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    )
}

@Composable
private fun fileActivityIcon(eventType: String): androidx.compose.ui.graphics.vector.ImageVector {
    return when (eventType) {
        "file.uploaded" -> Icons.Default.Upload
        "file.downloaded" -> Icons.Default.Download
        "file.deleted" -> Icons.Default.Delete
        "file.renamed" -> Icons.Default.DriveFileRenameOutline
        "file.moved" -> Icons.Default.DriveFileMove
        "file.shared" -> Icons.Default.Share
        "file.unshared" -> Icons.Default.PersonRemove
        "file.versioned" -> Icons.Default.History
        "folder.created" -> Icons.Default.CreateNewFolder
        "folder.deleted" -> Icons.Default.FolderDelete
        "folder.renamed" -> Icons.Default.DriveFileRenameOutline
        "folder.moved" -> Icons.Default.DriveFileMove
        "folder.shared" -> Icons.Default.FolderShared
        "folder.unshared" -> Icons.Default.PersonRemove
        else -> Icons.Default.Info
    }
}
