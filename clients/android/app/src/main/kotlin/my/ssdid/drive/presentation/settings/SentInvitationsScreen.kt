package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.ui.graphics.Color
import my.ssdid.drive.domain.model.InvitationStatus
import my.ssdid.drive.domain.model.SentInvitation
import my.ssdid.drive.domain.model.UserRole

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SentInvitationsScreen(
    onNavigateBack: () -> Unit,
    viewModel: SentInvitationsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.successMessage) {
        uiState.successMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearSuccessMessage()
        }
    }

    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Sent Invitations") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        PullToRefreshBox(
            isRefreshing = uiState.isLoading,
            onRefresh = { viewModel.loadSentInvitations() },
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when {
                uiState.isLoading && uiState.invitations.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                    }
                }
                uiState.invitations.isEmpty() -> {
                    EmptySentInvitationsContent(
                        modifier = Modifier
                            .fillMaxSize()
                            .wrapContentSize(Alignment.Center)
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        items(uiState.invitations) { invitation ->
                            SentInvitationCard(
                                invitation = invitation,
                                isRevoking = uiState.isRevoking,
                                onRevoke = { viewModel.revokeInvitation(invitation.id) },
                                onCodeCopied = {
                                    viewModel.showCopiedMessage()
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptySentInvitationsContent(
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.Send,
            contentDescription = "No sent invitations",
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No Sent Invitations",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Invitations you send will appear here.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}

@Composable
private fun SentInvitationCard(
    invitation: SentInvitation,
    isRevoking: Boolean,
    onRevoke: () -> Unit,
    onCodeCopied: () -> Unit = {}
) {
    val clipboardManager = LocalClipboardManager.current
    var showRevokeDialog by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            // Top row: email/open invite + status
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = invitation.email ?: "Open Invite",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
                InvitationStatusBadge(status = invitation.status)
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Role and short code
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                InvitationRoleBadge(role = invitation.role)

                if (invitation.shortCode != null) {
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surface
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = invitation.shortCode,
                                style = MaterialTheme.typography.labelMedium.copy(
                                    fontFamily = FontFamily.Monospace
                                ),
                                color = MaterialTheme.colorScheme.primary
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            IconButton(
                                onClick = {
                                    clipboardManager.setText(AnnotatedString(invitation.shortCode))
                                    onCodeCopied()
                                },
                                modifier = Modifier.size(20.dp)
                            ) {
                                Icon(
                                    Icons.Default.ContentCopy,
                                    contentDescription = "Copy code",
                                    modifier = Modifier.size(14.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Created date
            if (invitation.createdAt != null) {
                Text(
                    text = "Created: ${formatInvitationDate(invitation.createdAt)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                )
            }

            // Revoke action for pending invitations
            if (invitation.status == InvitationStatus.PENDING) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    OutlinedButton(
                        onClick = { showRevokeDialog = true },
                        enabled = !isRevoking,
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.error
                        )
                    ) {
                        Icon(
                            Icons.Default.Block,
                            contentDescription = "Revoke invitation",
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Revoke")
                    }
                }
            }
        }
    }

    // Revoke confirmation dialog
    if (showRevokeDialog) {
        AlertDialog(
            onDismissRequest = { showRevokeDialog = false },
            title = { Text("Revoke Invitation") },
            text = {
                Text(
                    "Are you sure you want to revoke this invitation" +
                        if (invitation.email != null) " to ${invitation.email}?" else "?"
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showRevokeDialog = false
                        onRevoke()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Revoke")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRevokeDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun InvitationStatusBadge(status: InvitationStatus) {
    val pendingColor = Color(0xFFB8860B) // Dark goldenrod for pending (yellow-ish)
    val acceptedColor = Color(0xFF2E7D32) // Green for accepted
    val (text, containerColor) = when (status) {
        InvitationStatus.PENDING -> "Pending" to pendingColor
        InvitationStatus.ACCEPTED -> "Accepted" to acceptedColor
        InvitationStatus.DECLINED -> "Declined" to MaterialTheme.colorScheme.error
        InvitationStatus.EXPIRED -> "Expired" to MaterialTheme.colorScheme.outline
        InvitationStatus.REVOKED -> "Revoked" to MaterialTheme.colorScheme.outline
    }

    Surface(
        shape = MaterialTheme.shapes.small,
        color = containerColor.copy(alpha = 0.2f)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            color = containerColor
        )
    }
}

@Composable
private fun InvitationRoleBadge(role: UserRole) {
    val (text, containerColor) = when (role) {
        UserRole.OWNER -> "Owner" to MaterialTheme.colorScheme.primary
        UserRole.ADMIN -> "Admin" to MaterialTheme.colorScheme.tertiary
        else -> "Member" to MaterialTheme.colorScheme.secondary
    }

    Surface(
        shape = MaterialTheme.shapes.small,
        color = containerColor.copy(alpha = 0.2f)
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            color = containerColor
        )
    }
}

private fun formatInvitationDate(dateString: String): String {
    return try {
        dateString.substringBefore("T")
    } catch (e: Exception) {
        dateString
    }
}
