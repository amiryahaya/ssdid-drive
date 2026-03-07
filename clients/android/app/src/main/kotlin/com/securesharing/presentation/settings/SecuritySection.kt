package com.securesharing.presentation.settings

import android.util.Base64
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.securesharing.data.local.AutoLockTimeout
import com.securesharing.domain.model.PublicKeys

@Composable
fun SecuritySection(
    biometricEnabled: Boolean,
    biometricAvailable: Boolean,
    autoLockEnabled: Boolean,
    autoLockTimeout: AutoLockTimeout,
    publicKeys: PublicKeys?,
    isChangingPassword: Boolean,
    changePasswordError: String?,
    onBiometricChange: (Boolean) -> Unit,
    onAutoLockChange: (Boolean) -> Unit,
    onAutoLockTimeoutChange: (AutoLockTimeout) -> Unit,
    onChangePassword: (currentPassword: String, newPassword: String) -> Unit,
    onNavigateToRecoverySetup: () -> Unit,
    onNavigateToTrusteeDashboard: () -> Unit,
    onNavigateToInitiateRecovery: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showChangePasswordDialog by remember { mutableStateOf(false) }
    var showKeyInfoDialog by remember { mutableStateOf(false) }
    var showAutoLockMenu by remember { mutableStateOf(false) }

    Column(modifier = modifier) {
        Text(
            text = "Security",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        // Change Password
        ListItem(
            headlineContent = { Text("Change Password") },
            supportingContent = { Text("Update your account password") },
            leadingContent = {
                Icon(Icons.Default.Lock, contentDescription = null)
            },
            trailingContent = {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            },
            modifier = Modifier.clickable { showChangePasswordDialog = true }
        )

        // Biometric Unlock
        ListItem(
            headlineContent = { Text("Biometric Unlock") },
            supportingContent = {
                Text(
                    if (biometricAvailable) "Use fingerprint or face to unlock"
                    else "Biometric authentication not available"
                )
            },
            leadingContent = {
                Icon(Icons.Default.Fingerprint, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = biometricEnabled,
                    onCheckedChange = onBiometricChange,
                    enabled = biometricAvailable
                )
            }
        )

        // Auto Lock
        ListItem(
            headlineContent = { Text("Auto Lock") },
            supportingContent = { Text("Lock app when inactive") },
            leadingContent = {
                Icon(Icons.Default.LockClock, contentDescription = null)
            },
            trailingContent = {
                Switch(
                    checked = autoLockEnabled,
                    onCheckedChange = onAutoLockChange
                )
            }
        )

        // Auto Lock Timeout
        if (autoLockEnabled) {
            Box {
                ListItem(
                    headlineContent = { Text("Lock After") },
                    supportingContent = { Text(autoLockTimeout.displayName) },
                    leadingContent = {
                        Icon(Icons.Default.Timer, contentDescription = null)
                    },
                    trailingContent = {
                        Icon(Icons.Default.ChevronRight, contentDescription = null)
                    },
                    modifier = Modifier.clickable { showAutoLockMenu = true }
                )

                DropdownMenu(
                    expanded = showAutoLockMenu,
                    onDismissRequest = { showAutoLockMenu = false }
                ) {
                    AutoLockTimeout.entries.forEach { timeout ->
                        DropdownMenuItem(
                            text = { Text(timeout.displayName) },
                            onClick = {
                                onAutoLockTimeoutChange(timeout)
                                showAutoLockMenu = false
                            },
                            leadingIcon = {
                                if (timeout == autoLockTimeout) {
                                    Icon(Icons.Default.Check, contentDescription = null)
                                }
                            }
                        )
                    }
                }
            }
        }

        // View Key Info
        ListItem(
            headlineContent = { Text("Encryption Keys") },
            supportingContent = { Text("View your public key fingerprints") },
            leadingContent = {
                Icon(Icons.Default.Key, contentDescription = null)
            },
            trailingContent = {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            },
            modifier = Modifier.clickable { showKeyInfoDialog = true }
        )

        Divider(modifier = Modifier.padding(vertical = 8.dp))

        Text(
            text = "Account Recovery",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.primary
        )

        // Recovery Setup
        ListItem(
            headlineContent = { Text("Recovery Setup") },
            supportingContent = { Text("Configure account recovery") },
            leadingContent = {
                Icon(Icons.Default.Restore, contentDescription = null)
            },
            trailingContent = {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            },
            modifier = Modifier.clickable { onNavigateToRecoverySetup() }
        )

        // Trustee Dashboard
        ListItem(
            headlineContent = { Text("Trustee Dashboard") },
            supportingContent = { Text("Manage shares you hold for others") },
            leadingContent = {
                Icon(Icons.Default.Shield, contentDescription = null)
            },
            trailingContent = {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            },
            modifier = Modifier.clickable { onNavigateToTrusteeDashboard() }
        )

        // Initiate Recovery
        ListItem(
            headlineContent = { Text("Recover Account") },
            supportingContent = { Text("Start account recovery process") },
            leadingContent = {
                Icon(Icons.Default.LockReset, contentDescription = null)
            },
            trailingContent = {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            },
            modifier = Modifier.clickable { onNavigateToInitiateRecovery() }
        )
    }

    // Change Password Dialog
    if (showChangePasswordDialog) {
        ChangePasswordDialog(
            isLoading = isChangingPassword,
            error = changePasswordError,
            onDismiss = { showChangePasswordDialog = false },
            onConfirm = { current, new ->
                onChangePassword(current, new)
            }
        )
    }

    // Key Info Dialog
    if (showKeyInfoDialog && publicKeys != null) {
        KeyInfoDialog(
            publicKeys = publicKeys,
            onDismiss = { showKeyInfoDialog = false }
        )
    }
}

@Composable
private fun ChangePasswordDialog(
    isLoading: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    onConfirm: (currentPassword: String, newPassword: String) -> Unit
) {
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var showPasswords by remember { mutableStateOf(false) }

    val passwordsMatch = newPassword == confirmPassword
    val canConfirm = currentPassword.isNotEmpty() &&
            newPassword.length >= 8 &&
            passwordsMatch &&
            !isLoading

    AlertDialog(
        onDismissRequest = { if (!isLoading) onDismiss() },
        title = { Text("Change Password") },
        text = {
            Column {
                OutlinedTextField(
                    value = currentPassword,
                    onValueChange = { currentPassword = it },
                    label = { Text("Current Password") },
                    visualTransformation = if (showPasswords) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading
                )

                Spacer(modifier = Modifier.height(12.dp))

                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    label = { Text("New Password") },
                    visualTransformation = if (showPasswords) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    supportingText = {
                        if (newPassword.isNotEmpty() && newPassword.length < 8) {
                            Text("Must be at least 8 characters")
                        }
                    },
                    isError = newPassword.isNotEmpty() && newPassword.length < 8
                )

                Spacer(modifier = Modifier.height(12.dp))

                OutlinedTextField(
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    label = { Text("Confirm New Password") },
                    visualTransformation = if (showPasswords) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                    supportingText = {
                        if (confirmPassword.isNotEmpty() && !passwordsMatch) {
                            Text("Passwords do not match")
                        }
                    },
                    isError = confirmPassword.isNotEmpty() && !passwordsMatch
                )

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = showPasswords,
                        onCheckedChange = { showPasswords = it },
                        enabled = !isLoading
                    )
                    Text("Show passwords")
                }

                if (error != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = error,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { onConfirm(currentPassword, newPassword) },
                enabled = canConfirm
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                } else {
                    Text("Change")
                }
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                enabled = !isLoading
            ) {
                Text("Cancel")
            }
        }
    )
}

@Composable
private fun KeyInfoDialog(
    publicKeys: PublicKeys,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Encryption Keys") },
        text = {
            Column {
                Text(
                    "Your public key fingerprints:",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Spacer(modifier = Modifier.height(16.dp))

                KeyFingerprint(
                    label = "KAZ-KEM",
                    fingerprint = publicKeys.kem.fingerprint()
                )

                Spacer(modifier = Modifier.height(8.dp))

                KeyFingerprint(
                    label = "KAZ-SIGN",
                    fingerprint = publicKeys.sign.fingerprint()
                )

                publicKeys.mlKem?.let { key ->
                    Spacer(modifier = Modifier.height(8.dp))
                    KeyFingerprint(
                        label = "ML-KEM-768",
                        fingerprint = key.fingerprint()
                    )
                }

                publicKeys.mlDsa?.let { key ->
                    Spacer(modifier = Modifier.height(8.dp))
                    KeyFingerprint(
                        label = "ML-DSA-65",
                        fingerprint = key.fingerprint()
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        Icon(
                            Icons.Default.Info,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onSecondaryContainer
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            "These fingerprints can be used to verify your identity when sharing files securely.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSecondaryContainer
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        }
    )
}

@Composable
private fun KeyFingerprint(
    label: String,
    fingerprint: String
) {
    Column {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary
        )
        Text(
            text = fingerprint,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
        )
    }
}

private fun ByteArray.fingerprint(): String {
    // Create a simple fingerprint from the first 16 bytes
    val hash = java.security.MessageDigest.getInstance("SHA-256").digest(this)
    return hash.take(16)
        .chunked(2)
        .joinToString(":") { bytes ->
            bytes.joinToString("") { byte ->
                String.format("%02X", byte)
            }
        }
}
