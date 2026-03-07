package com.securesharing.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateBack: () -> Unit,
    onLogout: () -> Unit,
    onNavigateToRecoverySetup: () -> Unit = {},
    onNavigateToTrusteeDashboard: () -> Unit = {},
    onNavigateToInitiateRecovery: () -> Unit = {},
    onNavigateToInvitations: () -> Unit = {},
    onNavigateToPiiChat: () -> Unit = {},
    onNavigateToCredentials: () -> Unit = {},
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val scrollState = rememberScrollState()

    var showLogoutDialog by remember { mutableStateOf(false) }
    var showLicensesDialog by remember { mutableStateOf(false) }
    var showPrivacyPolicyDialog by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.isLoggedOut) {
        if (uiState.isLoggedOut) {
            onLogout()
        }
    }

    LaunchedEffect(uiState.changePasswordSuccess) {
        if (uiState.changePasswordSuccess) {
            // Show success message and clear state
            viewModel.clearChangePasswordState()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            if (uiState.isLoading && uiState.user == null) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center)
                )
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(scrollState)
                ) {
                    // Profile Section
                    ProfileSection(
                        user = uiState.user,
                        tenantName = uiState.tenantName,
                        onEditProfile = { viewModel.showEditProfileDialog() },
                        modifier = Modifier.padding(16.dp)
                    )

                    // Edit Profile Dialog
                    if (uiState.showEditProfileDialog) {
                        EditProfileDialog(
                            currentDisplayName = uiState.user?.displayName,
                            isLoading = uiState.isUpdatingProfile,
                            error = uiState.profileUpdateError,
                            onDismiss = { viewModel.hideEditProfileDialog() },
                            onSave = { displayName -> viewModel.updateProfile(displayName) }
                        )
                    }

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // Invitations Section
                    InvitationsSectionButton(
                        onNavigateToInvitations = onNavigateToInvitations
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    // AI Chat Section
                    AiChatSectionButton(
                        onNavigateToPiiChat = onNavigateToPiiChat
                    )

                    // Security Keys & Passkeys Section
                    CredentialsSectionButton(
                        onNavigateToCredentials = onNavigateToCredentials
                    )

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // Security Section
                    SecuritySection(
                        biometricEnabled = uiState.biometricEnabled,
                        biometricAvailable = uiState.biometricAvailable,
                        autoLockEnabled = uiState.autoLockEnabled,
                        autoLockTimeout = uiState.autoLockTimeout,
                        publicKeys = uiState.publicKeys,
                        isChangingPassword = uiState.isChangingPassword,
                        changePasswordError = uiState.changePasswordError,
                        onBiometricChange = { viewModel.setBiometricEnabled(it) },
                        onAutoLockChange = { viewModel.setAutoLockEnabled(it) },
                        onAutoLockTimeoutChange = { viewModel.setAutoLockTimeout(it) },
                        onChangePassword = { current, new ->
                            viewModel.changePassword(current, new)
                        },
                        onNavigateToRecoverySetup = onNavigateToRecoverySetup,
                        onNavigateToTrusteeDashboard = onNavigateToTrusteeDashboard,
                        onNavigateToInitiateRecovery = onNavigateToInitiateRecovery
                    )

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // Devices Section
                    DevicesSection(
                        isEnrolled = uiState.isDeviceEnrolled,
                        currentEnrollmentId = uiState.currentEnrollmentId,
                        enrollments = uiState.deviceEnrollments,
                        isLoading = uiState.isLoadingDevices,
                        isEnrolling = uiState.isEnrollingDevice,
                        onEnrollDevice = { viewModel.enrollDevice() },
                        onRevokeDevice = { viewModel.revokeDevice(it) },
                        onRenameDevice = { id, name -> viewModel.renameDevice(id, name) }
                    )

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // Appearance Section
                    AppearanceSection(
                        themeMode = uiState.themeMode,
                        compactViewEnabled = uiState.compactViewEnabled,
                        showFileSizes = uiState.showFileSizes,
                        onThemeModeChange = { viewModel.setThemeMode(it) },
                        onCompactViewChange = { viewModel.setCompactViewEnabled(it) },
                        onShowFileSizesChange = { viewModel.setShowFileSizes(it) }
                    )

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // Notifications Section
                    NotificationsSection(
                        notificationsEnabled = uiState.notificationsEnabled,
                        shareNotificationsEnabled = uiState.shareNotificationsEnabled,
                        recoveryNotificationsEnabled = uiState.recoveryNotificationsEnabled,
                        onNotificationsChange = { viewModel.setNotificationsEnabled(it) },
                        onShareNotificationsChange = { viewModel.setShareNotificationsEnabled(it) },
                        onRecoveryNotificationsChange = { viewModel.setRecoveryNotificationsEnabled(it) }
                    )

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // Analytics Section
                    AnalyticsSection(
                        analyticsEnabled = uiState.analyticsEnabled,
                        onAnalyticsChange = { viewModel.setAnalyticsEnabled(it) }
                    )

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // Storage Section
                    StorageSection(
                        totalCacheSize = uiState.totalCacheSize,
                        previewCacheSize = uiState.previewCacheSize,
                        offlineCacheSize = uiState.offlineCacheSize,
                        isClearingCache = uiState.isClearingCache,
                        onClearPreviewCache = { viewModel.clearPreviewCache() },
                        onClearOfflineCache = { viewModel.clearOfflineCache() },
                        onClearAllCaches = { viewModel.clearAllCaches() }
                    )

                    Divider(modifier = Modifier.padding(vertical = 8.dp))

                    // About Section
                    AboutSection(
                        appVersion = "1.0.0",
                        onViewLicenses = { showLicensesDialog = true },
                        onViewPrivacyPolicy = { showPrivacyPolicyDialog = true }
                    )

                    // Licenses Dialog
                    if (showLicensesDialog) {
                        LicensesDialog(onDismiss = { showLicensesDialog = false })
                    }

                    // Privacy Policy Dialog
                    if (showPrivacyPolicyDialog) {
                        PrivacyPolicyDialog(onDismiss = { showPrivacyPolicyDialog = false })
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Logout Button
                    Button(
                        onClick = { showLogoutDialog = true },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error
                        )
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Logout")
                    }

                    Spacer(modifier = Modifier.height(32.dp))
                }
            }

            // Error Snackbar
            if (uiState.error != null) {
                Snackbar(
                    action = {
                        TextButton(onClick = { viewModel.clearError() }) {
                            Text("Dismiss")
                        }
                    },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(16.dp)
                ) {
                    Text(uiState.error!!)
                }
            }
        }
    }

    // Logout Confirmation Dialog
    if (showLogoutDialog) {
        AlertDialog(
            onDismissRequest = { showLogoutDialog = false },
            title = { Text("Logout") },
            text = {
                Text("Are you sure you want to logout? Your encrypted keys will be cleared from this device.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showLogoutDialog = false
                        viewModel.logout()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Logout")
                }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InvitationsSectionButton(
    onNavigateToInvitations: () -> Unit
) {
    Card(
        onClick = onNavigateToInvitations,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Mail,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Organization Invitations",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = "View and respond to pending invitations",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AiChatSectionButton(
    onNavigateToPiiChat: () -> Unit
) {
    Card(
        onClick = onNavigateToPiiChat,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.SmartToy,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "AI Chat",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = "Secure conversations with post-quantum encryption",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CredentialsSectionButton(
    onNavigateToCredentials: () -> Unit
) {
    Card(
        onClick = onNavigateToCredentials,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Fingerprint,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Security Keys & Passkeys",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = "Manage WebAuthn and OIDC credentials",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
