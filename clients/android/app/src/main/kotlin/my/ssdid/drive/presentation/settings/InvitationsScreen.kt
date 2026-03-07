package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.Invitation
import my.ssdid.drive.domain.model.UserRole

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvitationsScreen(
    onNavigateBack: () -> Unit,
    viewModel: InvitationsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Show success message
    LaunchedEffect(uiState.successMessage) {
        uiState.successMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearSuccessMessage()
        }
    }

    // Show error message
    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Pending Invitations") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when {
                uiState.isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                uiState.invitations.isEmpty() -> {
                    EmptyInvitationsContent(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        items(uiState.invitations) { invitation ->
                            InvitationCard(
                                invitation = invitation,
                                isProcessing = uiState.isProcessing,
                                onAccept = { viewModel.acceptInvitation(invitation.id) },
                                onDecline = { viewModel.declineInvitation(invitation.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyInvitationsContent(
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.Mail,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No Pending Invitations",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "When someone invites you to join their organization, it will appear here.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}

@Composable
private fun InvitationCard(
    invitation: Invitation,
    isProcessing: Boolean,
    onAccept: () -> Unit,
    onDecline: () -> Unit
) {
    var showDeclineDialog by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            // Organization name
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Business,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(8.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = invitation.tenantName ?: "Unknown Organization",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (invitation.tenantSlug != null) {
                        Text(
                            text = invitation.tenantSlug,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                RoleBadge(role = invitation.role)
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Invited by
            if (invitation.invitedBy != null) {
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Person,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Invited by ${invitation.invitedBy.getDisplayText()}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
            }

            // Invited at
            if (invitation.invitedAt != null) {
                Text(
                    text = "Received: ${formatDate(invitation.invitedAt)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Action buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                OutlinedButton(
                    onClick = { showDeclineDialog = true },
                    enabled = !isProcessing,
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Icon(Icons.Default.Close, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Decline")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(
                    onClick = onAccept,
                    enabled = !isProcessing
                ) {
                    if (isProcessing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = MaterialTheme.colorScheme.onPrimary,
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Accept")
                }
            }
        }
    }

    // Decline confirmation dialog
    if (showDeclineDialog) {
        AlertDialog(
            onDismissRequest = { showDeclineDialog = false },
            title = { Text("Decline Invitation") },
            text = {
                Text("Are you sure you want to decline this invitation to join ${invitation.tenantName ?: "this organization"}?")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeclineDialog = false
                        onDecline()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Decline")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeclineDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun RoleBadge(role: UserRole) {
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

private fun formatDate(dateString: String): String {
    // Simple date formatting - in production, use a proper date parser
    return try {
        dateString.substringBefore("T")
    } catch (e: Exception) {
        dateString
    }
}
