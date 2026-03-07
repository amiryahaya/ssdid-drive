package my.ssdid.drive.presentation.common

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import my.ssdid.drive.data.sync.SyncState
import my.ssdid.drive.data.sync.SyncStatus

/**
 * Sync status indicator component that shows the current sync state.
 * Can be placed in a top bar or as a floating indicator.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncStatusIndicator(
    syncStatus: SyncStatus,
    onRetryClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val backgroundColor = when (syncStatus.state) {
        SyncState.SYNCING -> MaterialTheme.colorScheme.primaryContainer
        SyncState.WAITING_FOR_NETWORK -> MaterialTheme.colorScheme.tertiaryContainer
        SyncState.ERROR -> MaterialTheme.colorScheme.errorContainer
        SyncState.IDLE -> if (syncStatus.hasPendingOperations) {
            MaterialTheme.colorScheme.secondaryContainer
        } else {
            Color.Transparent
        }
    }

    val contentColor = when (syncStatus.state) {
        SyncState.SYNCING -> MaterialTheme.colorScheme.onPrimaryContainer
        SyncState.WAITING_FOR_NETWORK -> MaterialTheme.colorScheme.onTertiaryContainer
        SyncState.ERROR -> MaterialTheme.colorScheme.onErrorContainer
        SyncState.IDLE -> MaterialTheme.colorScheme.onSecondaryContainer
    }

    // Only show when there's something to display
    val shouldShow = syncStatus.state != SyncState.IDLE || syncStatus.hasPendingOperations

    AnimatedVisibility(
        visible = shouldShow,
        enter = fadeIn() + slideInVertically(),
        exit = fadeOut() + slideOutVertically(),
        modifier = modifier
    ) {
        Surface(
            shape = RoundedCornerShape(8.dp),
            color = backgroundColor,
            modifier = Modifier
                .clickable(enabled = syncStatus.state == SyncState.ERROR) { onRetryClick() }
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SyncIcon(syncStatus.state, contentColor)

                Text(
                    text = getSyncStatusText(syncStatus),
                    style = MaterialTheme.typography.labelMedium,
                    color = contentColor
                )
            }
        }
    }
}

@Composable
private fun SyncIcon(
    state: SyncState,
    tint: Color
) {
    when (state) {
        SyncState.SYNCING -> {
            val infiniteTransition = rememberInfiniteTransition(label = "sync_rotation")
            val rotation by infiniteTransition.animateFloat(
                initialValue = 0f,
                targetValue = 360f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1000, easing = LinearEasing),
                    repeatMode = RepeatMode.Restart
                ),
                label = "rotation"
            )
            Icon(
                imageVector = Icons.Default.Sync,
                contentDescription = "Syncing",
                tint = tint,
                modifier = Modifier
                    .size(16.dp)
                    .rotate(rotation)
            )
        }
        SyncState.WAITING_FOR_NETWORK -> {
            Icon(
                imageVector = Icons.Default.CloudOff,
                contentDescription = "Waiting for network",
                tint = tint,
                modifier = Modifier.size(16.dp)
            )
        }
        SyncState.ERROR -> {
            Icon(
                imageVector = Icons.Default.Error,
                contentDescription = "Sync error",
                tint = tint,
                modifier = Modifier.size(16.dp)
            )
        }
        SyncState.IDLE -> {
            Icon(
                imageVector = Icons.Default.CloudUpload,
                contentDescription = "Pending uploads",
                tint = tint,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

private fun getSyncStatusText(syncStatus: SyncStatus): String {
    return when (syncStatus.state) {
        SyncState.SYNCING -> "Syncing${if (syncStatus.pendingCount > 0) " (${syncStatus.pendingCount})" else ""}"
        SyncState.WAITING_FOR_NETWORK -> "Waiting for connection (${syncStatus.pendingCount})"
        SyncState.ERROR -> "Sync failed - tap to retry"
        SyncState.IDLE -> if (syncStatus.hasPendingOperations) {
            "${syncStatus.pendingCount} pending"
        } else {
            ""
        }
    }
}

/**
 * Compact sync status badge for app bars.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SyncStatusBadge(
    syncStatus: SyncStatus,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val shouldShow = syncStatus.state != SyncState.IDLE || syncStatus.hasPendingOperations

    AnimatedVisibility(
        visible = shouldShow,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = modifier
    ) {
        IconButton(onClick = onClick) {
            BadgedBox(
                badge = {
                    if (syncStatus.pendingCount > 0) {
                        Badge {
                            Text(
                                text = if (syncStatus.pendingCount > 99) "99+" else syncStatus.pendingCount.toString()
                            )
                        }
                    }
                }
            ) {
                val tint = when (syncStatus.state) {
                    SyncState.SYNCING -> MaterialTheme.colorScheme.primary
                    SyncState.WAITING_FOR_NETWORK -> MaterialTheme.colorScheme.tertiary
                    SyncState.ERROR -> MaterialTheme.colorScheme.error
                    SyncState.IDLE -> MaterialTheme.colorScheme.onSurfaceVariant
                }

                when (syncStatus.state) {
                    SyncState.SYNCING -> {
                        val infiniteTransition = rememberInfiniteTransition(label = "sync_badge_rotation")
                        val rotation by infiniteTransition.animateFloat(
                            initialValue = 0f,
                            targetValue = 360f,
                            animationSpec = infiniteRepeatable(
                                animation = tween(1000, easing = LinearEasing),
                                repeatMode = RepeatMode.Restart
                            ),
                            label = "badge_rotation"
                        )
                        Icon(
                            imageVector = Icons.Default.Sync,
                            contentDescription = "Syncing",
                            tint = tint,
                            modifier = Modifier.rotate(rotation)
                        )
                    }
                    SyncState.WAITING_FOR_NETWORK -> {
                        Icon(
                            imageVector = Icons.Default.CloudOff,
                            contentDescription = "Offline",
                            tint = tint
                        )
                    }
                    SyncState.ERROR -> {
                        Icon(
                            imageVector = Icons.Default.SyncProblem,
                            contentDescription = "Sync error",
                            tint = tint
                        )
                    }
                    SyncState.IDLE -> {
                        Icon(
                            imageVector = Icons.Default.CloudUpload,
                            contentDescription = "Pending",
                            tint = tint
                        )
                    }
                }
            }
        }
    }
}

/**
 * Bottom sheet content for sync status details.
 */
@Composable
fun SyncStatusSheet(
    syncStatus: SyncStatus,
    onRetryAll: () -> Unit,
    onDismiss: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    ) {
        Text(
            text = "Sync Status",
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(bottom = 16.dp)
        )

        // Connection status
        ListItem(
            headlineContent = { Text("Connection") },
            supportingContent = {
                Text(if (syncStatus.isOnline) "Online" else "Offline")
            },
            leadingContent = {
                Icon(
                    imageVector = if (syncStatus.isOnline) Icons.Default.Wifi else Icons.Default.WifiOff,
                    contentDescription = null,
                    tint = if (syncStatus.isOnline) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                )
            }
        )

        // Sync state
        ListItem(
            headlineContent = { Text("Sync State") },
            supportingContent = {
                Text(
                    when (syncStatus.state) {
                        SyncState.IDLE -> "Idle"
                        SyncState.SYNCING -> "Syncing..."
                        SyncState.WAITING_FOR_NETWORK -> "Waiting for network"
                        SyncState.ERROR -> "Error"
                    }
                )
            },
            leadingContent = {
                Icon(
                    imageVector = when (syncStatus.state) {
                        SyncState.IDLE -> Icons.Default.CheckCircle
                        SyncState.SYNCING -> Icons.Default.Sync
                        SyncState.WAITING_FOR_NETWORK -> Icons.Default.HourglassEmpty
                        SyncState.ERROR -> Icons.Default.Error
                    },
                    contentDescription = null,
                    tint = when (syncStatus.state) {
                        SyncState.IDLE -> MaterialTheme.colorScheme.primary
                        SyncState.SYNCING -> MaterialTheme.colorScheme.tertiary
                        SyncState.WAITING_FOR_NETWORK -> MaterialTheme.colorScheme.secondary
                        SyncState.ERROR -> MaterialTheme.colorScheme.error
                    }
                )
            }
        )

        // Pending operations
        if (syncStatus.pendingCount > 0) {
            ListItem(
                headlineContent = { Text("Pending Operations") },
                supportingContent = { Text("${syncStatus.pendingCount} operations waiting") },
                leadingContent = {
                    Icon(
                        imageVector = Icons.Default.Schedule,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Action buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.weight(1f)
            ) {
                Text("Close")
            }

            if (syncStatus.state == SyncState.ERROR) {
                Button(
                    onClick = onRetryAll,
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Retry All")
                }
            }
        }
    }
}
