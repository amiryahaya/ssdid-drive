package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import my.ssdid.drive.data.local.ThemeMode

@Composable
fun AppearanceSection(
    themeMode: ThemeMode,
    compactViewEnabled: Boolean,
    showFileSizes: Boolean,
    onThemeModeChange: (ThemeMode) -> Unit,
    onCompactViewChange: (Boolean) -> Unit,
    onShowFileSizesChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    var showThemeMenu by remember { mutableStateOf(false) }

    Column(modifier = modifier) {
        Text(
            text = "Appearance",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        // Theme Mode
        Box {
            ListItem(
                headlineContent = { Text("Theme") },
                supportingContent = { Text(themeMode.displayName()) },
                leadingContent = {
                    Icon(
                        when (themeMode) {
                            ThemeMode.LIGHT -> Icons.Default.LightMode
                            ThemeMode.DARK -> Icons.Default.DarkMode
                            ThemeMode.SYSTEM -> Icons.Default.SettingsBrightness
                        },
                        contentDescription = null
                    )
                },
                trailingContent = {
                    Icon(Icons.Default.ChevronRight, contentDescription = null)
                },
                modifier = Modifier.clickable { showThemeMenu = true }
            )

            DropdownMenu(
                expanded = showThemeMenu,
                onDismissRequest = { showThemeMenu = false }
            ) {
                ThemeMode.entries.forEach { mode ->
                    DropdownMenuItem(
                        text = { Text(mode.displayName()) },
                        onClick = {
                            onThemeModeChange(mode)
                            showThemeMenu = false
                        },
                        leadingIcon = {
                            Icon(
                                when (mode) {
                                    ThemeMode.LIGHT -> Icons.Default.LightMode
                                    ThemeMode.DARK -> Icons.Default.DarkMode
                                    ThemeMode.SYSTEM -> Icons.Default.SettingsBrightness
                                },
                                contentDescription = null
                            )
                        },
                        trailingIcon = {
                            if (mode == themeMode) {
                                Icon(Icons.Default.Check, contentDescription = null)
                            }
                        }
                    )
                }
            }
        }

        Divider(modifier = Modifier.padding(vertical = 8.dp))

        Text(
            text = "Display",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        // Compact View
        ListItem(
            headlineContent = { Text("Compact View") },
            supportingContent = { Text("Show more items on screen") },
            leadingContent = {
                Icon(Icons.Default.ViewCompact, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = compactViewEnabled,
                    onCheckedChange = onCompactViewChange
                )
            }
        )

        // Show File Sizes
        ListItem(
            headlineContent = { Text("Show File Sizes") },
            supportingContent = { Text("Display file sizes in browser") },
            leadingContent = {
                Icon(Icons.Default.Storage, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = showFileSizes,
                    onCheckedChange = onShowFileSizesChange
                )
            }
        )
    }
}

@Composable
fun NotificationsSection(
    notificationsEnabled: Boolean,
    shareNotificationsEnabled: Boolean,
    recoveryNotificationsEnabled: Boolean,
    onNotificationsChange: (Boolean) -> Unit,
    onShareNotificationsChange: (Boolean) -> Unit,
    onRecoveryNotificationsChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = "Notifications",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        // Main toggle
        ListItem(
            headlineContent = { Text("Push Notifications") },
            supportingContent = { Text("Receive notifications") },
            leadingContent = {
                Icon(Icons.Default.Notifications, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = notificationsEnabled,
                    onCheckedChange = onNotificationsChange
                )
            }
        )

        // Share notifications
        ListItem(
            headlineContent = { Text("Share Notifications") },
            supportingContent = { Text("When someone shares with you") },
            leadingContent = {
                Icon(Icons.Default.Share, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = shareNotificationsEnabled && notificationsEnabled,
                    onCheckedChange = onShareNotificationsChange,
                    enabled = notificationsEnabled
                )
            }
        )

        // Recovery notifications
        ListItem(
            headlineContent = { Text("Recovery Notifications") },
            supportingContent = { Text("Recovery requests and approvals") },
            leadingContent = {
                Icon(Icons.Default.Shield, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = recoveryNotificationsEnabled && notificationsEnabled,
                    onCheckedChange = onRecoveryNotificationsChange,
                    enabled = notificationsEnabled
                )
            }
        )
    }
}

@Composable
fun AnalyticsSection(
    analyticsEnabled: Boolean,
    onAnalyticsChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = "Analytics",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        ListItem(
            headlineContent = { Text("Help improve SSDID Drive") },
            supportingContent = {
                Text("Share anonymous usage statistics. No personal data or file contents are ever collected.")
            },
            leadingContent = {
                Icon(Icons.Default.BarChart, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = analyticsEnabled,
                    onCheckedChange = onAnalyticsChange
                )
            }
        )
    }
}

@Composable
fun AboutSection(
    appVersion: String,
    onViewLicenses: () -> Unit,
    onViewPrivacyPolicy: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        Text(
            text = "About",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        ListItem(
            headlineContent = { Text("Version") },
            supportingContent = { Text(appVersion) },
            leadingContent = {
                Icon(Icons.Default.Info, contentDescription = null)
            }
        )

        ListItem(
            headlineContent = { Text("Open Source Licenses") },
            leadingContent = {
                Icon(Icons.Default.Code, contentDescription = null)
            },
            trailingContent = {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            },
            modifier = Modifier.clickable { onViewLicenses() }
        )

        ListItem(
            headlineContent = { Text("Privacy Policy") },
            leadingContent = {
                Icon(Icons.Default.Policy, contentDescription = null)
            },
            trailingContent = {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            },
            modifier = Modifier.clickable { onViewPrivacyPolicy() }
        )
    }
}

@Composable
fun StorageSection(
    totalCacheSize: String,
    previewCacheSize: String,
    offlineCacheSize: String,
    isClearingCache: Boolean,
    onClearPreviewCache: () -> Unit,
    onClearOfflineCache: () -> Unit,
    onClearAllCaches: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showClearAllDialog by remember { mutableStateOf(false) }
    var showClearOfflineDialog by remember { mutableStateOf(false) }

    Column(modifier = modifier) {
        Text(
            text = "Storage",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        // Total Cache Size
        ListItem(
            headlineContent = { Text("Total Cache") },
            supportingContent = { Text(totalCacheSize) },
            leadingContent = {
                Icon(Icons.Default.Folder, contentDescription = null)
            }
        )

        // Preview Cache
        ListItem(
            headlineContent = { Text("Preview Cache") },
            supportingContent = { Text("$previewCacheSize - Temporary file previews") },
            leadingContent = {
                Icon(Icons.Default.Preview, contentDescription = null)
            },
            trailingContent = {
                TextButton(
                    onClick = onClearPreviewCache,
                    enabled = !isClearingCache
                ) {
                    if (isClearingCache) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text("Clear")
                    }
                }
            }
        )

        // Offline Cache
        ListItem(
            headlineContent = { Text("Offline Files") },
            supportingContent = { Text("$offlineCacheSize - Saved for offline access") },
            leadingContent = {
                Icon(Icons.Default.OfflinePin, contentDescription = null)
            },
            trailingContent = {
                TextButton(
                    onClick = { showClearOfflineDialog = true },
                    enabled = !isClearingCache
                ) {
                    Text("Clear")
                }
            }
        )

        // Clear All
        ListItem(
            headlineContent = { Text("Clear All Caches") },
            supportingContent = { Text("Remove all cached files") },
            leadingContent = {
                Icon(
                    Icons.Default.DeleteSweep,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error
                )
            },
            trailingContent = {
                TextButton(
                    onClick = { showClearAllDialog = true },
                    enabled = !isClearingCache,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Clear All")
                }
            }
        )
    }

    // Clear Offline Confirmation Dialog
    if (showClearOfflineDialog) {
        AlertDialog(
            onDismissRequest = { showClearOfflineDialog = false },
            title = { Text("Clear Offline Files") },
            text = {
                Text("This will remove all files saved for offline access. You'll need to download them again when online.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showClearOfflineDialog = false
                        onClearOfflineCache()
                    }
                ) {
                    Text("Clear")
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearOfflineDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Clear All Confirmation Dialog
    if (showClearAllDialog) {
        AlertDialog(
            onDismissRequest = { showClearAllDialog = false },
            title = { Text("Clear All Caches") },
            text = {
                Text("This will remove all cached files including offline files. You'll need to download them again.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showClearAllDialog = false
                        onClearAllCaches()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Clear All")
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearAllDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

private fun ThemeMode.displayName(): String = when (this) {
    ThemeMode.LIGHT -> "Light"
    ThemeMode.DARK -> "Dark"
    ThemeMode.SYSTEM -> "System Default"
}
