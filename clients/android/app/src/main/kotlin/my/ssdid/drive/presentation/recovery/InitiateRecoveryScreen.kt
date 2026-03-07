package my.ssdid.drive.presentation.recovery

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.RecoveryRequest
import my.ssdid.drive.domain.model.RecoveryRequestStatus
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InitiateRecoveryScreen(
    onNavigateBack: () -> Unit,
    onRecoveryComplete: () -> Unit,
    viewModel: RecoveryRequestViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(uiState.isRecoveryComplete) {
        if (uiState.isRecoveryComplete) {
            onRecoveryComplete()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Account Recovery") },
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
            when {
                uiState.isLoading && uiState.currentRequest == null -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }

                uiState.currentRequest != null -> {
                    // Show recovery progress
                    RecoveryProgressContent(
                        request = uiState.currentRequest!!,
                        isLoading = uiState.isLoading,
                        onRefresh = { viewModel.checkRequestStatus(uiState.currentRequest!!.id) },
                        onComplete = { password ->
                            viewModel.completeRecovery(uiState.currentRequest!!.id, password)
                        },
                        onCancel = { viewModel.cancelRequest(uiState.currentRequest!!.id) },
                        error = uiState.error,
                        onDismissError = { viewModel.clearError() }
                    )
                }

                uiState.myRequests.isNotEmpty() -> {
                    // Show past requests
                    PastRequestsContent(
                        requests = uiState.myRequests,
                        onInitiateNew = {
                            // Show initiate form
                        }
                    )
                }

                else -> {
                    // Show initiate form
                    InitiateRecoveryContent(
                        isLoading = uiState.isLoading,
                        onInitiate = { password, reason ->
                            viewModel.initiateRecovery(password, reason)
                        },
                        error = uiState.error,
                        onDismissError = { viewModel.clearError() }
                    )
                }
            }
        }
    }
}

@Composable
private fun InitiateRecoveryContent(
    isLoading: Boolean,
    onInitiate: (String, String?) -> Unit,
    error: String?,
    onDismissError: () -> Unit
) {
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }
    var showConfirmDialog by remember { mutableStateOf(false) }

    val passwordsMatch = password == confirmPassword && password.isNotEmpty()
    val canInitiate = passwordsMatch && password.length >= 8

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.LockReset,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Recover Your Account",
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "If you've lost access to your account, you can request recovery from your trustees. You'll need their approval to regain access.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f)
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.Top
            ) {
                Icon(
                    Icons.Default.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Important",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.error
                    )
                    Text(
                        text = "Recovery will generate new encryption keys. Your trustees will re-encrypt your data with your new keys.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // New password
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("New Password") },
            placeholder = { Text("Enter your new password") },
            visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            trailingIcon = {
                IconButton(onClick = { showPassword = !showPassword }) {
                    Icon(
                        if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                        contentDescription = if (showPassword) "Hide password" else "Show password"
                    )
                }
            },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Confirm password
        OutlinedTextField(
            value = confirmPassword,
            onValueChange = { confirmPassword = it },
            label = { Text("Confirm Password") },
            placeholder = { Text("Confirm your new password") },
            visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            isError = confirmPassword.isNotEmpty() && !passwordsMatch,
            supportingText = {
                if (confirmPassword.isNotEmpty() && !passwordsMatch) {
                    Text("Passwords do not match")
                }
            },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Reason (optional)
        OutlinedTextField(
            value = reason,
            onValueChange = { reason = it },
            label = { Text("Reason (Optional)") },
            placeholder = { Text("Why do you need to recover your account?") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 2,
            maxLines = 4
        )

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = { showConfirmDialog = true },
            enabled = canInitiate && !isLoading,
            modifier = Modifier.fillMaxWidth()
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp
                )
            } else {
                Icon(Icons.Default.Send, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Request Recovery")
            }
        }

        // Error snackbar
        if (error != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Snackbar(
                action = {
                    TextButton(onClick = onDismissError) {
                        Text("Dismiss")
                    }
                }
            ) {
                Text(error)
            }
        }
    }

    if (showConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showConfirmDialog = false },
            title = { Text("Start Account Recovery?") },
            text = {
                Text("Your trustees will be notified of this recovery request. Once enough trustees approve, you'll be able to access your account with your new password.")
            },
            confirmButton = {
                Button(onClick = {
                    showConfirmDialog = false
                    onInitiate(password, reason.ifEmpty { null })
                }) {
                    Text("Start Recovery")
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
private fun RecoveryProgressContent(
    request: RecoveryRequest,
    isLoading: Boolean,
    onRefresh: () -> Unit,
    onComplete: (String) -> Unit,
    onCancel: () -> Unit,
    error: String?,
    onDismissError: () -> Unit
) {
    var password by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }
    var showCancelDialog by remember { mutableStateOf(false) }

    val canComplete = request.status == RecoveryRequestStatus.APPROVED && password.length >= 8

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Status indicator
        when (request.status) {
            RecoveryRequestStatus.PENDING -> {
                Icon(
                    Icons.Default.HourglassTop,
                    contentDescription = null,
                    modifier = Modifier.size(80.dp),
                    tint = MaterialTheme.colorScheme.secondary
                )
            }
            RecoveryRequestStatus.APPROVED -> {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(80.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
            else -> {
                Icon(
                    Icons.Default.Error,
                    contentDescription = null,
                    modifier = Modifier.size(80.dp),
                    tint = MaterialTheme.colorScheme.error
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = when (request.status) {
                RecoveryRequestStatus.PENDING -> "Waiting for Approvals"
                RecoveryRequestStatus.APPROVED -> "Recovery Approved"
                RecoveryRequestStatus.COMPLETED -> "Recovery Complete"
                RecoveryRequestStatus.REJECTED -> "Recovery Rejected"
                RecoveryRequestStatus.CANCELLED -> "Recovery Cancelled"
            },
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = when (request.status) {
                RecoveryRequestStatus.PENDING -> "Your trustees are reviewing your request."
                RecoveryRequestStatus.APPROVED -> "Enter your new password to complete recovery."
                RecoveryRequestStatus.COMPLETED -> "Your account has been recovered."
                RecoveryRequestStatus.REJECTED -> "Your recovery request was rejected."
                RecoveryRequestStatus.CANCELLED -> "Your recovery request was cancelled."
            },
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Progress card
        if (request.progress != null) {
            Card(
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Approval Progress",
                            style = MaterialTheme.typography.titleMedium
                        )
                        Text(
                            text = "${request.progress.approvals} / ${request.progress.threshold}",
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    val progress = request.progress!!
                    LinearProgressIndicator(
                        progress = progress.approvals.toFloat() / progress.threshold,
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    Text(
                        text = if (progress.remaining > 0) {
                            "${progress.remaining} more approval(s) needed"
                        } else {
                            "Threshold reached!"
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Details
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                ListItem(
                    headlineContent = { Text("Request ID") },
                    supportingContent = { Text(request.id.take(8) + "...") },
                    leadingContent = { Icon(Icons.Default.Tag, contentDescription = null) }
                )

                ListItem(
                    headlineContent = { Text("Created") },
                    supportingContent = {
                        Text(
                            request.createdAt.atZone(java.time.ZoneId.systemDefault())
                                .format(DateTimeFormatter.ofPattern("MMM dd, yyyy HH:mm"))
                        )
                    },
                    leadingContent = { Icon(Icons.Default.Schedule, contentDescription = null) }
                )

                if (request.reason != null) {
                    ListItem(
                        headlineContent = { Text("Reason") },
                        supportingContent = { Text(request.reason) },
                        leadingContent = { Icon(Icons.Default.Notes, contentDescription = null) }
                    )
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        // Complete recovery (if approved)
        if (request.status == RecoveryRequestStatus.APPROVED) {
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("New Password") },
                visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    IconButton(onClick = { showPassword = !showPassword }) {
                        Icon(
                            if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = null
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = { onComplete(password) },
                enabled = canComplete && !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp
                    )
                } else {
                    Icon(Icons.Default.Lock, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Complete Recovery")
                }
            }
        }

        // Refresh / Cancel buttons
        if (request.status == RecoveryRequestStatus.PENDING) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = { showCancelDialog = true },
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Cancel Request")
                }

                Button(
                    onClick = onRefresh,
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f)
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(Icons.Default.Refresh, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Refresh")
                    }
                }
            }
        }

        // Error snackbar
        if (error != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Snackbar(
                action = {
                    TextButton(onClick = onDismissError) {
                        Text("Dismiss")
                    }
                }
            ) {
                Text(error)
            }
        }
    }

    if (showCancelDialog) {
        AlertDialog(
            onDismissRequest = { showCancelDialog = false },
            title = { Text("Cancel Recovery Request?") },
            text = {
                Text("This will cancel your pending recovery request. You'll need to start a new request if you want to recover your account later.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showCancelDialog = false
                        onCancel()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Cancel Request")
                }
            },
            dismissButton = {
                TextButton(onClick = { showCancelDialog = false }) {
                    Text("Keep Request")
                }
            }
        )
    }
}

@Composable
private fun PastRequestsContent(
    requests: List<RecoveryRequest>,
    onInitiateNew: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(requests) { request ->
                PastRequestItem(request = request)
            }
        }

        Button(
            onClick = onInitiateNew,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Icon(Icons.Default.Add, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("New Recovery Request")
        }
    }
}

@Composable
private fun PastRequestItem(
    request: RecoveryRequest
) {
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        ListItem(
            headlineContent = {
                Text("Recovery Request")
            },
            supportingContent = {
                Text(
                    request.createdAt.atZone(java.time.ZoneId.systemDefault())
                        .format(DateTimeFormatter.ofPattern("MMM dd, yyyy HH:mm"))
                )
            },
            leadingContent = {
                Icon(
                    when (request.status) {
                        RecoveryRequestStatus.COMPLETED -> Icons.Default.CheckCircle
                        RecoveryRequestStatus.REJECTED -> Icons.Default.Cancel
                        RecoveryRequestStatus.CANCELLED -> Icons.Default.Cancel
                        else -> Icons.Default.HourglassEmpty
                    },
                    contentDescription = null,
                    tint = when (request.status) {
                        RecoveryRequestStatus.COMPLETED -> MaterialTheme.colorScheme.primary
                        RecoveryRequestStatus.REJECTED -> MaterialTheme.colorScheme.error
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            },
            trailingContent = {
                AssistChip(
                    onClick = {},
                    label = { Text(request.status.name) },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = when (request.status) {
                            RecoveryRequestStatus.COMPLETED -> MaterialTheme.colorScheme.primaryContainer
                            RecoveryRequestStatus.REJECTED -> MaterialTheme.colorScheme.errorContainer
                            else -> MaterialTheme.colorScheme.surfaceVariant
                        }
                    )
                )
            }
        )
    }
}
