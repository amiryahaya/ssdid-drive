package com.securesharing.presentation.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.securesharing.domain.model.DeviceEnrollment
import com.securesharing.domain.model.DeviceEnrollmentStatus
import com.securesharing.domain.model.DevicePlatform

@Composable
fun DevicesSection(
    isEnrolled: Boolean,
    currentEnrollmentId: String?,
    enrollments: List<DeviceEnrollment>,
    isLoading: Boolean,
    isEnrolling: Boolean,
    onEnrollDevice: () -> Unit,
    onRevokeDevice: (String) -> Unit,
    onRenameDevice: (String, String) -> Unit,
    modifier: Modifier = Modifier
) {
    var showRevokeDialog by remember { mutableStateOf<DeviceEnrollment?>(null) }
    var showRenameDialog by remember { mutableStateOf<DeviceEnrollment?>(null) }

    Column(modifier = modifier) {
        Text(
            text = "Devices",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        // Enrollment Status
        ListItem(
            headlineContent = { Text("Device Enrollment") },
            supportingContent = {
                Text(
                    if (isEnrolled) "This device is enrolled"
                    else "Enroll this device for enhanced security"
                )
            },
            leadingContent = {
                Icon(
                    if (isEnrolled) Icons.Default.PhoneAndroid else Icons.Default.MobileOff,
                    contentDescription = null,
                    tint = if (isEnrolled) MaterialTheme.colorScheme.primary
                           else MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            trailingContent = {
                if (isEnrolled) {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = "Enrolled",
                        tint = MaterialTheme.colorScheme.primary
                    )
                } else {
                    if (isEnrolling) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        TextButton(onClick = onEnrollDevice) {
                            Text("Enroll")
                        }
                    }
                }
            }
        )

        Divider(modifier = Modifier.padding(horizontal = 16.dp))

        // Enrolled Devices List
        Text(
            text = "Enrolled Devices",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )

        if (isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(32.dp),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else if (enrollments.isEmpty()) {
            Text(
                text = "No devices enrolled",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
        } else {
            enrollments.forEach { enrollment ->
                DeviceItem(
                    enrollment = enrollment,
                    isCurrentDevice = enrollment.id == currentEnrollmentId,
                    onRename = { showRenameDialog = enrollment },
                    onRevoke = { showRevokeDialog = enrollment }
                )
            }
        }
    }

    // Revoke Dialog
    showRevokeDialog?.let { enrollment ->
        AlertDialog(
            onDismissRequest = { showRevokeDialog = null },
            title = { Text("Revoke Device") },
            text = {
                Column {
                    Text("Are you sure you want to revoke this device?")
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        enrollment.deviceName ?: "Unknown Device",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                    if (enrollment.id == currentEnrollmentId) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            "This is your current device. You will need to re-enroll to use device signing.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRevokeDevice(enrollment.id)
                        showRevokeDialog = null
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Revoke")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRevokeDialog = null }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Rename Dialog
    showRenameDialog?.let { enrollment ->
        var newName by remember { mutableStateOf(enrollment.deviceName ?: "") }

        AlertDialog(
            onDismissRequest = { showRenameDialog = null },
            title = { Text("Rename Device") },
            text = {
                OutlinedTextField(
                    value = newName,
                    onValueChange = { newName = it },
                    label = { Text("Device Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRenameDevice(enrollment.id, newName)
                        showRenameDialog = null
                    },
                    enabled = newName.isNotBlank()
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRenameDialog = null }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun DeviceItem(
    enrollment: DeviceEnrollment,
    isCurrentDevice: Boolean,
    onRename: () -> Unit,
    onRevoke: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }

    ListItem(
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = enrollment.deviceName ?: "Unknown Device",
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (isCurrentDevice) {
                    Spacer(modifier = Modifier.width(8.dp))
                    AssistChip(
                        onClick = { },
                        label = { Text("This device") },
                        modifier = Modifier.height(24.dp)
                    )
                }
            }
        },
        supportingContent = {
            Column {
                Text(
                    text = enrollment.device?.let { device ->
                        "${device.deviceInfo?.manufacturer ?: ""} ${device.deviceInfo?.model ?: ""}"
                    } ?: "Unknown",
                    style = MaterialTheme.typography.bodySmall
                )
                Text(
                    text = "Enrolled: ${formatDate(enrollment.enrolledAt)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        leadingContent = {
            Icon(
                imageVector = when (enrollment.device?.platform) {
                    DevicePlatform.ANDROID -> Icons.Default.PhoneAndroid
                    DevicePlatform.IOS -> Icons.Default.PhoneIphone
                    DevicePlatform.WINDOWS -> Icons.Default.Computer
                    DevicePlatform.MACOS -> Icons.Default.LaptopMac
                    DevicePlatform.LINUX -> Icons.Default.Computer
                    else -> Icons.Default.Devices
                },
                contentDescription = null,
                tint = if (enrollment.status == DeviceEnrollmentStatus.ACTIVE)
                    MaterialTheme.colorScheme.primary
                else
                    MaterialTheme.colorScheme.error
            )
        },
        trailingContent = {
            Box {
                IconButton(onClick = { showMenu = true }) {
                    Icon(Icons.Default.MoreVert, contentDescription = "Options")
                }
                DropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("Rename") },
                        onClick = {
                            showMenu = false
                            onRename()
                        },
                        leadingIcon = {
                            Icon(Icons.Default.Edit, contentDescription = null)
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Revoke", color = MaterialTheme.colorScheme.error) },
                        onClick = {
                            showMenu = false
                            onRevoke()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error
                            )
                        }
                    )
                }
            }
        }
    )
}

private fun formatDate(isoDate: String): String {
    // Simple date formatting - in a real app, use proper date parsing
    return try {
        isoDate.split("T").firstOrNull()?.replace("-", "/") ?: isoDate
    } catch (e: Exception) {
        isoDate
    }
}
