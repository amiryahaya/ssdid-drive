package com.securesharing.presentation.recovery

import androidx.compose.foundation.layout.*
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
import com.securesharing.domain.model.RecoveryConfigStatus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoverySetupScreen(
    onNavigateBack: () -> Unit,
    onNavigateToTrusteeSelection: (Int) -> Unit,
    viewModel: RecoverySetupViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(uiState.isSetupComplete) {
        if (uiState.isSetupComplete && uiState.config != null) {
            onNavigateToTrusteeSelection(uiState.config!!.totalShares)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Recovery Setup") },
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
                uiState.isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }

                uiState.config?.status == RecoveryConfigStatus.ACTIVE -> {
                    // Recovery already configured
                    RecoveryConfiguredContent(
                        config = uiState.config!!,
                        onDisable = { viewModel.disableRecovery() },
                        onViewShares = { onNavigateToTrusteeSelection(uiState.config!!.totalShares) }
                    )
                }

                else -> {
                    // Setup new recovery
                    RecoverySetupContent(
                        threshold = uiState.threshold,
                        totalShares = uiState.totalShares,
                        onThresholdChange = { viewModel.setThreshold(it) },
                        onTotalSharesChange = { viewModel.setTotalShares(it) },
                        onSetup = { viewModel.setupRecovery() },
                        error = uiState.error,
                        onDismissError = { viewModel.clearError() }
                    )
                }
            }
        }
    }
}

@Composable
private fun RecoverySetupContent(
    threshold: Int,
    totalShares: Int,
    onThresholdChange: (Int) -> Unit,
    onTotalSharesChange: (Int) -> Unit,
    onSetup: () -> Unit,
    error: String?,
    onDismissError: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.Security,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Account Recovery",
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Set up recovery by distributing encrypted shares of your master key to trusted colleagues. You'll need a minimum number of shares to recover your account.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Total shares slider
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
                        text = "Total Shares",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = "$totalShares",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.primary
                    )
                }

                Slider(
                    value = totalShares.toFloat(),
                    onValueChange = { onTotalSharesChange(it.toInt()) },
                    valueRange = 2f..10f,
                    steps = 7,
                    modifier = Modifier.fillMaxWidth()
                )

                Text(
                    text = "Number of trusted people who will hold shares",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Threshold slider
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
                        text = "Required Shares",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = "$threshold",
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.primary
                    )
                }

                Slider(
                    value = threshold.toFloat(),
                    onValueChange = { onThresholdChange(it.toInt()) },
                    valueRange = 2f..totalShares.toFloat(),
                    steps = (totalShares - 3).coerceAtLeast(0),
                    modifier = Modifier.fillMaxWidth()
                )

                Text(
                    text = "Minimum shares needed for recovery",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Summary
        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Default.Info,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "You'll need $threshold out of $totalShares trustees to approve your recovery request.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Button(
            onClick = onSetup,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.Key, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Setup Recovery")
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
}

@Composable
private fun RecoveryConfiguredContent(
    config: com.securesharing.domain.model.RecoveryConfig,
    onDisable: () -> Unit,
    onViewShares: () -> Unit
) {
    var showDisableDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.VerifiedUser,
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Recovery Enabled",
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Your account recovery is configured and active.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        Card(
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                modifier = Modifier.padding(16.dp)
            ) {
                ListItem(
                    headlineContent = { Text("Total Shares") },
                    trailingContent = {
                        Text(
                            "${config.totalShares}",
                            style = MaterialTheme.typography.titleMedium
                        )
                    },
                    leadingContent = {
                        Icon(Icons.Default.People, contentDescription = null)
                    }
                )

                Divider()

                ListItem(
                    headlineContent = { Text("Required for Recovery") },
                    trailingContent = {
                        Text(
                            "${config.threshold}",
                            style = MaterialTheme.typography.titleMedium
                        )
                    },
                    leadingContent = {
                        Icon(Icons.Default.Key, contentDescription = null)
                    }
                )

                Divider()

                ListItem(
                    headlineContent = { Text("Status") },
                    trailingContent = {
                        AssistChip(
                            onClick = {},
                            label = { Text(config.status.name) },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = MaterialTheme.colorScheme.primaryContainer
                            )
                        )
                    },
                    leadingContent = {
                        Icon(Icons.Default.CheckCircle, contentDescription = null)
                    }
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        OutlinedButton(
            onClick = onViewShares,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.Visibility, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("View Shares")
        }

        Spacer(modifier = Modifier.height(8.dp))

        TextButton(
            onClick = { showDisableDialog = true },
            colors = ButtonDefaults.textButtonColors(
                contentColor = MaterialTheme.colorScheme.error
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.RemoveCircle, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Disable Recovery")
        }
    }

    if (showDisableDialog) {
        AlertDialog(
            onDismissRequest = { showDisableDialog = false },
            title = { Text("Disable Recovery?") },
            text = {
                Text("This will revoke all recovery shares. You won't be able to recover your account if you lose access. This action cannot be undone.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDisableDialog = false
                        onDisable()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Disable")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDisableDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}
