package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.UserRole

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateBack: () -> Unit,
    onLogout: () -> Unit,
    onNavigateToRecoverySetup: () -> Unit = {},
    onNavigateToTrusteeDashboard: () -> Unit = {},
    onNavigateToInitiateRecovery: () -> Unit = {},
    onNavigateToInvitations: () -> Unit = {},
    onNavigateToCreateInvitation: () -> Unit = {},
    onNavigateToSentInvitations: () -> Unit = {},
    onNavigateToMembers: () -> Unit = {},
    onNavigateToPiiChat: () -> Unit = {},
    onNavigateToJoinTenant: () -> Unit = {},
    onNavigateToLinkedLogins: () -> Unit = {},
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

                    // Organization Section (Members + Invitations)
                    OrganizationSection(
                        userRole = uiState.user?.getEffectiveRole(),
                        onNavigateToMembers = onNavigateToMembers,
                        onNavigateToInvitations = onNavigateToInvitations,
                        onNavigateToCreateInvitation = onNavigateToCreateInvitation,
                        onNavigateToSentInvitations = onNavigateToSentInvitations
                    )

                    // Join Organization (invite code entry)
                    Spacer(modifier = Modifier.height(4.dp))
                    Box(modifier = Modifier.padding(horizontal = 16.dp)) {
                        SettingsNavigationCard(
                            icon = Icons.Default.GroupAdd,
                            title = "Join Organization",
                            subtitle = "Enter an invite code to join a new organization",
                            onClick = onNavigateToJoinTenant
                        )
                    }

                    Spacer(modifier = Modifier.height(8.dp))

                    // AI Chat Section
                    AiChatSectionButton(
                        onNavigateToPiiChat = onNavigateToPiiChat
                    )

                    // Linked Logins
                    Spacer(modifier = Modifier.height(4.dp))
                    Box(modifier = Modifier.padding(horizontal = 16.dp)) {
                        SettingsNavigationCard(
                            icon = Icons.Default.VpnKey,
                            title = "Linked Logins",
                            subtitle = "Manage your sign-in methods",
                            onClick = onNavigateToLinkedLogins
                        )
                    }

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
                        onChangePassword = { _, _ ->
                            // Password change not supported with SSDID Wallet auth
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

@Composable
private fun OrganizationSection(
    userRole: UserRole?,
    onNavigateToMembers: () -> Unit,
    onNavigateToInvitations: () -> Unit,
    onNavigateToCreateInvitation: () -> Unit,
    onNavigateToSentInvitations: () -> Unit
) {
    val isAdminOrOwner = userRole == UserRole.ADMIN || userRole == UserRole.OWNER

    Column(
        modifier = Modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = "Organization",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(vertical = 4.dp)
        )

        // Members (Admin/Owner only)
        if (isAdminOrOwner) {
            SettingsNavigationCard(
                icon = Icons.Default.People,
                title = "Members",
                subtitle = "View and manage organization members",
                onClick = onNavigateToMembers
            )
        }

        // Received Invitations (all users)
        SettingsNavigationCard(
            icon = Icons.Default.Mail,
            title = "Received Invitations",
            subtitle = "View and respond to pending invitations",
            onClick = onNavigateToInvitations
        )

        // Create Invitation (Admin/Owner only)
        if (isAdminOrOwner) {
            SettingsNavigationCard(
                icon = Icons.Default.PersonAdd,
                title = "Create Invitation",
                subtitle = "Invite someone to join your organization",
                onClick = onNavigateToCreateInvitation
            )
        }

        // Sent Invitations (Admin/Owner only)
        if (isAdminOrOwner) {
            SettingsNavigationCard(
                icon = Icons.AutoMirrored.Filled.Send,
                title = "Sent Invitations",
                subtitle = "View and manage invitations you have sent",
                onClick = onNavigateToSentInvitations
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsNavigationCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
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
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = subtitle,
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
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "AI Chat",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.tertiary
                    ) {
                        Text(
                            text = "Coming Soon",
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onTertiary
                        )
                    }
                }
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

