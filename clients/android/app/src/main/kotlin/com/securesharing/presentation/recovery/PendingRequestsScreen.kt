package com.securesharing.presentation.recovery

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.securesharing.domain.model.RecoveryRequest
import com.securesharing.domain.model.RecoveryRequestStatus
import com.securesharing.domain.model.RecoveryShare
import com.securesharing.domain.model.RecoveryShareStatus
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PendingRequestsScreen(
    onNavigateBack: () -> Unit,
    viewModel: TrusteeSharesViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    var selectedTab by remember { mutableStateOf(0) }

    LaunchedEffect(Unit) {
        viewModel.loadData()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Trustee Dashboard") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Tabs
            TabRow(selectedTabIndex = selectedTab) {
                Tab(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    text = { Text("Pending Shares") },
                    icon = {
                        BadgedBox(
                            badge = {
                                if (uiState.pendingShares.isNotEmpty()) {
                                    Badge { Text("${uiState.pendingShares.size}") }
                                }
                            }
                        ) {
                            Icon(Icons.Default.Key, contentDescription = null)
                        }
                    }
                )
                Tab(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    text = { Text("Recovery Requests") },
                    icon = {
                        BadgedBox(
                            badge = {
                                if (uiState.pendingApprovals.isNotEmpty()) {
                                    Badge { Text("${uiState.pendingApprovals.size}") }
                                }
                            }
                        ) {
                            Icon(Icons.Default.HelpCenter, contentDescription = null)
                        }
                    }
                )
                Tab(
                    selected = selectedTab == 2,
                    onClick = { selectedTab = 2 },
                    text = { Text("My Shares") },
                    icon = { Icon(Icons.Default.Shield, contentDescription = null) }
                )
            }

            Box(
                modifier = Modifier.fillMaxSize()
            ) {
                when {
                    uiState.isLoading -> {
                        CircularProgressIndicator(
                            modifier = Modifier.align(Alignment.Center)
                        )
                    }

                    else -> {
                        when (selectedTab) {
                            0 -> PendingSharesTab(
                                shares = uiState.pendingShares,
                                onAccept = { viewModel.acceptShare(it) },
                                onReject = { viewModel.rejectShare(it) }
                            )
                            1 -> RecoveryRequestsTab(
                                requests = uiState.pendingApprovals,
                                acceptedShares = uiState.acceptedShares,
                                onApprove = { requestId, shareId ->
                                    viewModel.approveRecovery(requestId, shareId)
                                }
                            )
                            2 -> AcceptedSharesTab(
                                shares = uiState.acceptedShares
                            )
                        }
                    }
                }

                // Error snackbar
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
    }
}

@Composable
private fun PendingSharesTab(
    shares: List<RecoveryShare>,
    onAccept: (String) -> Unit,
    onReject: (String) -> Unit
) {
    if (shares.isEmpty()) {
        EmptyStateContent(
            icon = Icons.Default.CheckCircle,
            title = "No Pending Shares",
            message = "You have no pending recovery share invitations."
        )
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(shares) { share ->
                PendingShareItem(
                    share = share,
                    onAccept = { onAccept(share.id) },
                    onReject = { onReject(share.id) }
                )
            }
        }
    }
}

@Composable
private fun PendingShareItem(
    share: RecoveryShare,
    onAccept: () -> Unit,
    onReject: () -> Unit
) {
    var showConfirmDialog by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Default.Key,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Recovery Share Request",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = "From: ${share.grantor?.email ?: "Unknown"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = "By accepting, you agree to hold this encrypted recovery share. You may be asked to approve recovery requests in the future.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onReject) {
                    Text("Decline")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(onClick = { showConfirmDialog = true }) {
                    Text("Accept")
                }
            }
        }
    }

    if (showConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showConfirmDialog = false },
            title = { Text("Accept Recovery Share?") },
            text = {
                Text("You will become a recovery trustee for ${share.grantor?.email ?: "this user"}. This means they may contact you to help recover their account.")
            },
            confirmButton = {
                Button(onClick = {
                    showConfirmDialog = false
                    onAccept()
                }) {
                    Text("Accept")
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun RecoveryRequestsTab(
    requests: List<RecoveryRequest>,
    acceptedShares: List<RecoveryShare>,
    onApprove: (requestId: String, shareId: String) -> Unit
) {
    if (requests.isEmpty()) {
        EmptyStateContent(
            icon = Icons.Default.VerifiedUser,
            title = "No Recovery Requests",
            message = "There are no pending recovery requests that need your approval."
        )
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(requests) { request ->
                // Find the share for this user
                val share = acceptedShares.find { it.grantorId == request.userId }
                RecoveryRequestItem(
                    request = request,
                    share = share,
                    onApprove = { shareId -> onApprove(request.id, shareId) }
                )
            }
        }
    }
}

@Composable
private fun RecoveryRequestItem(
    request: RecoveryRequest,
    share: RecoveryShare?,
    onApprove: (String) -> Unit
) {
    var showConfirmDialog by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f)
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Default.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Recovery Request",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = request.user?.email ?: "Unknown User",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                AssistChip(
                    onClick = {},
                    label = { Text(request.status.name) },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = when (request.status) {
                            RecoveryRequestStatus.PENDING -> MaterialTheme.colorScheme.secondaryContainer
                            RecoveryRequestStatus.APPROVED -> MaterialTheme.colorScheme.primaryContainer
                            else -> MaterialTheme.colorScheme.surfaceVariant
                        }
                    )
                )
            }

            if (request.reason != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Reason: ${request.reason}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (request.progress != null) {
                val progress = request.progress!!
                Spacer(modifier = Modifier.height(12.dp))

                LinearProgressIndicator(
                    progress = progress.approvals.toFloat() / progress.threshold,
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(4.dp))

                Text(
                    text = "${progress.approvals} / ${progress.threshold} approvals (${progress.remaining} more needed)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Requested: ${request.createdAt.atZone(java.time.ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("MMM dd, yyyy HH:mm"))}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (share != null && request.status == RecoveryRequestStatus.PENDING) {
                Spacer(modifier = Modifier.height(16.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    Button(
                        onClick = { showConfirmDialog = true },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary
                        )
                    ) {
                        Icon(Icons.Default.Approval, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Approve Recovery")
                    }
                }
            }
        }
    }

    if (showConfirmDialog && share != null) {
        AlertDialog(
            onDismissRequest = { showConfirmDialog = false },
            title = { Text("Approve Recovery Request?") },
            text = {
                Column {
                    Text("You are about to approve the account recovery for:")
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = request.user?.email ?: "Unknown User",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Your encrypted share will be re-encrypted and sent to help them recover access. Make sure you verify this request through a separate channel.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            },
            confirmButton = {
                Button(onClick = {
                    showConfirmDialog = false
                    onApprove(share.id)
                }) {
                    Text("Approve")
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun AcceptedSharesTab(
    shares: List<RecoveryShare>
) {
    if (shares.isEmpty()) {
        EmptyStateContent(
            icon = Icons.Default.Shield,
            title = "No Accepted Shares",
            message = "You haven't accepted any recovery shares yet."
        )
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(shares) { share ->
                AcceptedShareItem(share = share)
            }
        }
    }
}

@Composable
private fun AcceptedShareItem(
    share: RecoveryShare
) {
    ListItem(
        headlineContent = {
            Text(share.grantor?.email ?: "Unknown User")
        },
        supportingContent = {
            Column {
                Text("Share #${share.shareIndex}")
                Text(
                    "Accepted: ${share.updatedAt.atZone(java.time.ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("MMM dd, yyyy"))}",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        },
        leadingContent = {
            Icon(
                Icons.Default.Shield,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        },
        trailingContent = {
            AssistChip(
                onClick = {},
                label = { Text("Active") },
                colors = AssistChipDefaults.assistChipColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            )
        }
    )
}

@Composable
private fun EmptyStateContent(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    message: String
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
