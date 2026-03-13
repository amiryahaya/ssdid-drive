package my.ssdid.drive.presentation.recovery

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

// ==================== Recovery Setup Screen (Status / Delete) ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoverySetupScreen(
    onNavigateBack: () -> Unit,
    onStartWizard: () -> Unit = {},
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
                        onDismissError = { viewModel.clearError() },
                        onStartWizard = onStartWizard
                    )
                }
            }
        }
    }
}

@Composable
private fun RecoverySetupContent(
    error: String?,
    onDismissError: () -> Unit,
    onStartWizard: () -> Unit
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
            text = "Set up recovery to protect access to your account. Your secret is split using Shamir's Secret Sharing — no single party can reconstruct it alone.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        Button(
            onClick = onStartWizard,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.Shield, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Set Up Recovery")
        }

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

// ==================== Recovery Setup Wizard Screen ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoverySetupWizardScreen(
    masterKey: ByteArray,
    userDid: String,
    kemPublicKey: ByteArray,
    onNavigateBack: () -> Unit,
    onSetupComplete: () -> Unit,
    viewModel: RecoveryWizardViewModel = hiltViewModel()
) {
    val state by viewModel.wizardState.collectAsState()
    val context = LocalContext.current

    // Auto-start generation on first composition
    LaunchedEffect(Unit) {
        if (state.step == RecoveryWizardViewModel.WizardStep.EXPLANATION) {
            viewModel.beginSetup(masterKey, userDid, kemPublicKey)
        }
    }

    // Navigate on success
    LaunchedEffect(state.step) {
        if (state.step == RecoveryWizardViewModel.WizardStep.SUCCESS) {
            onSetupComplete()
        }
    }

    val selfFileLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri: Uri? ->
        uri?.let {
            writeFileContent(context, it, state.selfFile ?: "")
            viewModel.markSelfSaved()
        }
    }

    val trustedFileLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri: Uri? ->
        uri?.let {
            writeFileContent(context, it, state.trustedFile ?: "")
            viewModel.markTrustedSaved()
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
            when (state.step) {
                RecoveryWizardViewModel.WizardStep.EXPLANATION,
                RecoveryWizardViewModel.WizardStep.GENERATING -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        CircularProgressIndicator()
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = "Generating recovery shares...",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                RecoveryWizardViewModel.WizardStep.DOWNLOAD -> {
                    WizardDownloadStep(
                        selfSaved = state.selfSaved,
                        trustedSaved = state.trustedSaved,
                        onSaveSelf = {
                            selfFileLauncher.launch("recovery-self.json")
                        },
                        onSaveTrusted = {
                            trustedFileLauncher.launch("recovery-trusted.json")
                        },
                        onContinue = { viewModel.uploadServerShare() },
                        canContinue = state.selfSaved && state.trustedSaved
                    )
                }

                RecoveryWizardViewModel.WizardStep.UPLOADING -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        CircularProgressIndicator()
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = "Uploading server share...",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                RecoveryWizardViewModel.WizardStep.SUCCESS -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = null,
                            modifier = Modifier.size(80.dp),
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.height(24.dp))
                        Text(
                            text = "Recovery Setup Complete",
                            style = MaterialTheme.typography.headlineMedium
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "Store your recovery files in safe, separate locations.",
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                RecoveryWizardViewModel.WizardStep.ERROR -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        Icon(
                            Icons.Default.Error,
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = MaterialTheme.colorScheme.error
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = "Setup Failed",
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.error
                        )
                        if (state.error != null) {
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = state.error!!,
                                style = MaterialTheme.typography.bodyMedium,
                                textAlign = TextAlign.Center,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Spacer(modifier = Modifier.height(24.dp))
                        Button(onClick = { viewModel.retryFromError() }) {
                            Text("Try Again")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WizardDownloadStep(
    selfSaved: Boolean,
    trustedSaved: Boolean,
    onSaveSelf: () -> Unit,
    onSaveTrusted: () -> Unit,
    onContinue: () -> Unit,
    canContinue: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.Download,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Save Your Recovery Files",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Two recovery files have been generated. Save them in separate secure locations. You need any 2 of the 3 shares to recover your account.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Self share card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = if (selfSaved)
                    MaterialTheme.colorScheme.primaryContainer
                else
                    MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (selfSaved) Icons.Default.CheckCircle else Icons.Default.Person,
                        contentDescription = null,
                        tint = if (selfSaved) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Your Personal Share",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Keep this file in a secure location only you can access (e.g., password manager, encrypted USB).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(12.dp))
                Button(
                    onClick = onSaveSelf,
                    enabled = !selfSaved,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(
                        if (selfSaved) Icons.Default.Check else Icons.Default.Save,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(if (selfSaved) "Saved" else "Save Personal File")
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Trusted contact share card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = if (trustedSaved)
                    MaterialTheme.colorScheme.primaryContainer
                else
                    MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (trustedSaved) Icons.Default.CheckCircle else Icons.Default.People,
                        contentDescription = null,
                        tint = if (trustedSaved) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Trusted Contact Share",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Give this file to a trusted person or store in a separate secure location (e.g., trusted family member, second device).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(12.dp))
                Button(
                    onClick = onSaveTrusted,
                    enabled = !trustedSaved,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(
                        if (trustedSaved) Icons.Default.Check else Icons.Default.Save,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(if (trustedSaved) "Saved" else "Save Trusted File")
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Info card about server share
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.secondaryContainer
            )
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Icon(
                    Icons.Default.Cloud,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "A third share will be securely stored on the SSDID Drive server. Clicking Continue will upload it.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = onContinue,
            enabled = canContinue,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Continue — Upload Server Share")
        }

        if (!canContinue) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Save both files before continuing",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

// ==================== Helpers ====================

private fun writeFileContent(context: Context, uri: Uri, content: String) {
    try {
        context.contentResolver.openOutputStream(uri)?.use { stream ->
            stream.write(content.toByteArray(Charsets.UTF_8))
        }
    } catch (_: Exception) {
        // File write failure — user will notice the save button stays enabled
    }
}
