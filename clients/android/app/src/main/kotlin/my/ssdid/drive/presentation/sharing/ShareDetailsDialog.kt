package my.ssdid.drive.presentation.sharing

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import my.ssdid.drive.domain.model.ResourceType
import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.domain.model.SharePermission
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Dialog showing share details with options to manage the share.
 */
@Composable
fun ShareDetailsDialog(
    share: Share,
    onDismiss: () -> Unit,
    onRevoke: () -> Unit,
    onUpdatePermission: ((SharePermission) -> Unit)? = null,
    onUpdateExpiry: ((Int?) -> Unit)? = null
) {
    var showRevokeConfirmation by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                imageVector = when (share.resourceType) {
                    ResourceType.FILE -> Icons.Default.InsertDriveFile
                    ResourceType.FOLDER -> Icons.Default.Folder
                },
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(32.dp)
            )
        },
        title = {
            Text("Share Details")
        },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Shared with
                DetailRow(
                    icon = Icons.Default.Person,
                    label = "Shared with",
                    value = share.grantee?.displayName ?: share.grantee?.email ?: "Unknown user"
                )

                // Resource type
                DetailRow(
                    icon = if (share.resourceType == ResourceType.FILE) Icons.Default.InsertDriveFile else Icons.Default.Folder,
                    label = "Type",
                    value = if (share.resourceType == ResourceType.FILE) "File" else "Folder"
                )

                // Permission
                DetailRow(
                    icon = Icons.Default.Security,
                    label = "Permission",
                    value = share.permission.displayName()
                )

                // Recursive (for folders)
                if (share.resourceType == ResourceType.FOLDER) {
                    DetailRow(
                        icon = Icons.Default.AccountTree,
                        label = "Include subfolders",
                        value = if (share.recursive) "Yes" else "No"
                    )
                }

                // Created date
                DetailRow(
                    icon = Icons.Default.CalendarToday,
                    label = "Shared on",
                    value = formatDate(share.createdAt.toEpochMilli())
                )

                // Expiry
                DetailRow(
                    icon = Icons.Default.Schedule,
                    label = "Expires",
                    value = share.expiresAt?.let { formatDate(it.toEpochMilli()) } ?: "Never"
                )

                // Status
                val status = when {
                    share.revokedAt != null -> "Revoked"
                    share.expiresAt != null && java.time.Instant.now().isAfter(share.expiresAt) -> "Expired"
                    else -> "Active"
                }
                DetailRow(
                    icon = if (share.isValid()) Icons.Default.CheckCircle else Icons.Default.Cancel,
                    label = "Status",
                    value = status,
                    valueColor = when (status) {
                        "Active" -> MaterialTheme.colorScheme.primary
                        "Revoked", "Expired" -> MaterialTheme.colorScheme.error
                        else -> MaterialTheme.colorScheme.onSurface
                    }
                )
            }
        },
        confirmButton = {
            if (share.isValid()) {
                TextButton(
                    onClick = { showRevokeConfirmation = true },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Icon(Icons.Default.LinkOff, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Revoke")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        }
    )

    // Revoke confirmation dialog
    if (showRevokeConfirmation) {
        AlertDialog(
            onDismissRequest = { showRevokeConfirmation = false },
            icon = {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error
                )
            },
            title = { Text("Revoke Share?") },
            text = {
                Text(
                    "This will immediately remove ${share.grantee?.displayName ?: share.grantee?.email ?: "the user"}'s access. This action cannot be undone."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showRevokeConfirmation = false
                        onRevoke()
                        onDismiss()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Revoke")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRevokeConfirmation = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun DetailRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    valueColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth()
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = valueColor
            )
        }
    }
}

private fun formatDate(millis: Long): String {
    val instant = java.time.Instant.ofEpochMilli(millis)
    val zonedDateTime = instant.atZone(ZoneId.systemDefault())
    val formatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)
    return zonedDateTime.format(formatter)
}
