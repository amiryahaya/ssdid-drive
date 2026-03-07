package com.securesharing.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.securesharing.domain.model.User
import com.securesharing.domain.model.UserRole

@Composable
fun ProfileSection(
    user: User?,
    tenantName: String,
    onEditProfile: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {
            // Edit button in top right
            IconButton(
                onClick = onEditProfile,
                modifier = Modifier.align(Alignment.TopEnd)
            ) {
                Icon(
                    imageVector = Icons.Default.Edit,
                    contentDescription = "Edit profile",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Avatar
                Box(
                    modifier = Modifier
                        .size(80.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primary),
                    contentAlignment = Alignment.Center
                ) {
                    // Use display name initial if available, otherwise email
                    val initial = user?.displayName?.firstOrNull()?.uppercase()
                        ?: user?.email?.firstOrNull()?.uppercase()
                        ?: "?"
                    Text(
                        text = initial,
                        style = MaterialTheme.typography.headlineLarge,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Display name (if set)
                user?.displayName?.let { displayName ->
                    Text(
                        text = displayName,
                        style = MaterialTheme.typography.titleLarge
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                }

                // Email
                Text(
                    text = user?.email ?: "Loading...",
                    style = if (user?.displayName != null) {
                        MaterialTheme.typography.bodyMedium
                    } else {
                        MaterialTheme.typography.titleLarge
                    },
                    color = if (user?.displayName != null) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    }
                )

                Spacer(modifier = Modifier.height(4.dp))

                // Tenant
                Text(
                    text = tenantName,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Role badge
                user?.role?.let { role ->
                    AssistChip(
                        onClick = {},
                        label = { Text(role.displayName()) },
                        leadingIcon = {
                            Icon(
                                imageVector = when (role) {
                                    UserRole.OWNER -> Icons.Default.AdminPanelSettings
                                    UserRole.ADMIN -> Icons.Default.ManageAccounts
                                    UserRole.USER -> Icons.Default.Person
                                },
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                        },
                        colors = AssistChipDefaults.assistChipColors(
                            containerColor = when (role) {
                                UserRole.OWNER -> MaterialTheme.colorScheme.primaryContainer
                                UserRole.ADMIN -> MaterialTheme.colorScheme.secondaryContainer
                                UserRole.USER -> MaterialTheme.colorScheme.surfaceVariant
                            }
                        )
                    )
                }

                // Storage usage
                user?.let {
                    if (it.storageQuota != null && it.storageUsed != null) {
                        Spacer(modifier = Modifier.height(16.dp))
                        StorageUsageIndicator(
                            used = it.storageUsed,
                            quota = it.storageQuota
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StorageUsageIndicator(
    used: Long,
    quota: Long,
    modifier: Modifier = Modifier
) {
    val usagePercentage = if (quota > 0) (used.toFloat() / quota.toFloat()) else 0f
    val usageColor = when {
        usagePercentage > 0.9f -> MaterialTheme.colorScheme.error
        usagePercentage > 0.7f -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.primary
    }

    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Storage",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = "${formatBytes(used)} / ${formatBytes(quota)}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.height(4.dp))

        LinearProgressIndicator(
            progress = usagePercentage.coerceIn(0f, 1f),
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(MaterialTheme.shapes.small)
        )

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            text = "${(usagePercentage * 100).toInt()}% used",
            style = MaterialTheme.typography.bodySmall,
            color = usageColor,
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.End
        )
    }
}

private fun formatBytes(bytes: Long): String {
    return when {
        bytes >= 1_073_741_824 -> String.format("%.1f GB", bytes / 1_073_741_824.0)
        bytes >= 1_048_576 -> String.format("%.1f MB", bytes / 1_048_576.0)
        bytes >= 1024 -> String.format("%.1f KB", bytes / 1024.0)
        else -> "$bytes B"
    }
}

private fun UserRole.displayName(): String = when (this) {
    UserRole.OWNER -> "Owner"
    UserRole.ADMIN -> "Administrator"
    UserRole.USER -> "User"
}
