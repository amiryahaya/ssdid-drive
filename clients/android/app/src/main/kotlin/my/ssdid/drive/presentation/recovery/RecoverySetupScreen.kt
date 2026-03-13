package my.ssdid.drive.presentation.recovery

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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoverySetupScreen(
    onNavigateBack: () -> Unit,
    viewModel: RecoverySetupViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

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

                uiState.isSetupComplete -> {
                    RecoveryActiveContent(
                        createdAt = uiState.status?.createdAt,
                        onDelete = { viewModel.deleteSetup() }
                    )
                }

                else -> {
                    RecoverySetupContent(
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
    error: String?,
    onDismissError: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
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
            text = "Recovery is managed through the SSDID Wallet. Use the wallet app to configure account recovery.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (error != null) {
            Spacer(modifier = Modifier.height(16.dp))
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
private fun RecoveryActiveContent(
    createdAt: String?,
    onDelete: () -> Unit
) {
    var showDisableDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
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
            text = "Your account recovery is active.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        if (createdAt != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Set up: $createdAt",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        TextButton(
            onClick = { showDisableDialog = true },
            colors = ButtonDefaults.textButtonColors(
                contentColor = MaterialTheme.colorScheme.error
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.RemoveCircle, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Remove Recovery Setup")
        }
    }

    if (showDisableDialog) {
        AlertDialog(
            onDismissRequest = { showDisableDialog = false },
            title = { Text("Remove Recovery Setup?") },
            text = {
                Text("This will remove your server-side recovery share. You won't be able to use server-assisted recovery. This action cannot be undone.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDisableDialog = false
                        onDelete()
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Remove")
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
