package my.ssdid.drive.presentation.recovery

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

/**
 * Recovery screen accessed from the login page.
 * Supports two recovery paths:
 *   - Path A: User provides 2 recovery files (self + trusted contact share)
 *   - Path B: User provides 1 recovery file + server fetches its share
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoveryScreen(
    onNavigateBack: () -> Unit,
    onRecoveryComplete: () -> Unit,
    viewModel: RecoveryFlowViewModel = hiltViewModel()
) {
    val state by viewModel.flowState.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(state.step) {
        if (state.step == RecoveryFlowViewModel.FlowStep.SUCCESS) {
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
            when (state.step) {
                RecoveryFlowViewModel.FlowStep.SELECT_PATH -> {
                    RecoveryPathSelection(
                        onSelectPathA = { viewModel.setFile1Content(""); viewModel.setFile2Content("") },
                        onSelectPathB = { viewModel.setFile1Content("") }
                    )
                }

                RecoveryFlowViewModel.FlowStep.UPLOAD_FILES -> {
                    if (state.file2Content != null) {
                        // Path A: two files
                        PathAUploadContent(
                            file1Content = state.file1Content,
                            file2Content = state.file2Content,
                            onFile1Loaded = { viewModel.setFile1Content(it) },
                            onFile2Loaded = { viewModel.setFile2Content(it) },
                            onRecover = { viewModel.recoverWithTwoFiles() }
                        )
                    } else {
                        // Path B: one file + server
                        PathBUploadContent(
                            file1Content = state.file1Content,
                            oldDid = state.oldDid,
                            serverShareFetched = state.serverShareFetched,
                            onFile1Loaded = { viewModel.setFile1Content(it) },
                            onDidChanged = { viewModel.setOldDid(it) },
                            onFetchServerShare = { viewModel.fetchServerShare() },
                            onRecover = { viewModel.recoverWithFileAndServer() }
                        )
                    }
                }

                RecoveryFlowViewModel.FlowStep.RECONSTRUCTING -> {
                    RecoveryProgressContent(message = "Reconstructing secret key...")
                }

                RecoveryFlowViewModel.FlowStep.RE_ENROLLING -> {
                    ReEnrollmentContent(
                        newDid = state.newDid,
                        kemPublicKey = state.kemPublicKey,
                        onNewDidChanged = { viewModel.setNewDid(it) },
                        onKemKeyChanged = { viewModel.setKemPublicKey(it) },
                        onComplete = { viewModel.completeRecovery() }
                    )
                }

                RecoveryFlowViewModel.FlowStep.SUCCESS -> {
                    RecoverySuccessContent()
                }

                RecoveryFlowViewModel.FlowStep.ERROR -> {
                    RecoveryErrorContent(
                        error = state.error,
                        onRetry = { viewModel.clearError() }
                    )
                }
            }
        }
    }
}

// ==================== Path Selection ====================

@Composable
private fun RecoveryPathSelection(
    onSelectPathA: () -> Unit,
    onSelectPathB: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.LockReset,
            contentDescription = null,
            modifier = Modifier.size(72.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Recover Your Account",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Choose how you want to recover your account. You need any 2 of the 3 shares to restore access.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Path A card
        Card(
            modifier = Modifier.fillMaxWidth(),
            onClick = onSelectPathA
        ) {
            Column(modifier = Modifier.padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.FolderOpen,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "Use Two Recovery Files",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Use your personal recovery file and your trusted contact's recovery file. No internet connection required.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Works offline",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Path B card
        Card(
            modifier = Modifier.fillMaxWidth(),
            onClick = onSelectPathB
        ) {
            Column(modifier = Modifier.padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.CloudDownload,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.secondary
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "Use One File + Server",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Use one recovery file and retrieve the server-stored share using your DID. Requires internet connection.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row {
                    Icon(
                        Icons.Default.Wifi,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.secondary
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Requires internet",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary
                    )
                }
            }
        }
    }
}

// ==================== Path A: Two Files ====================

@Composable
private fun PathAUploadContent(
    file1Content: String?,
    file2Content: String?,
    onFile1Loaded: (String) -> Unit,
    onFile2Loaded: (String) -> Unit,
    onRecover: () -> Unit
) {
    val context = LocalContext.current

    val file1Launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let {
            val content = readFileContent(context, it)
            if (content != null) onFile1Loaded(content)
        }
    }

    val file2Launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let {
            val content = readFileContent(context, it)
            if (content != null) onFile2Loaded(content)
        }
    }

    val file1Loaded = file1Content?.isNotBlank() == true
    val file2Loaded = file2Content?.isNotBlank() == true

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Load Recovery Files",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Open your personal recovery file and your trusted contact's recovery file.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(24.dp))

        RecoveryFilePickerCard(
            label = "Personal Recovery File",
            isLoaded = file1Loaded,
            onPick = { file1Launcher.launch(arrayOf("application/json", "*/*")) }
        )

        Spacer(modifier = Modifier.height(12.dp))

        RecoveryFilePickerCard(
            label = "Trusted Contact's Recovery File",
            isLoaded = file2Loaded,
            onPick = { file2Launcher.launch(arrayOf("application/json", "*/*")) }
        )

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = onRecover,
            enabled = file1Loaded && file2Loaded,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.LockOpen, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Recover Account")
        }
    }
}

// ==================== Path B: One File + Server ====================

@Composable
private fun PathBUploadContent(
    file1Content: String?,
    oldDid: String,
    serverShareFetched: Boolean,
    onFile1Loaded: (String) -> Unit,
    onDidChanged: (String) -> Unit,
    onFetchServerShare: () -> Unit,
    onRecover: () -> Unit
) {
    val context = LocalContext.current

    val fileLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let {
            val content = readFileContent(context, it)
            if (content != null) onFile1Loaded(content)
        }
    }

    val fileLoaded = file1Content?.isNotBlank() == true

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Server-Assisted Recovery",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Load your recovery file and enter your original DID to retrieve the server share.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(24.dp))

        RecoveryFilePickerCard(
            label = "Recovery File",
            isLoaded = fileLoaded,
            onPick = { fileLauncher.launch(arrayOf("application/json", "*/*")) }
        )

        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = oldDid,
            onValueChange = onDidChanged,
            label = { Text("Your Original DID") },
            placeholder = { Text("did:ssdid:...") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            trailingIcon = {
                if (serverShareFetched) {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = "Share fetched",
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }
        )

        Spacer(modifier = Modifier.height(12.dp))

        OutlinedButton(
            onClick = onFetchServerShare,
            enabled = oldDid.isNotBlank() && !serverShareFetched,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.CloudDownload, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text(if (serverShareFetched) "Server Share Retrieved" else "Fetch Server Share")
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = onRecover,
            enabled = fileLoaded && serverShareFetched,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.LockOpen, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Recover Account")
        }
    }
}

// ==================== Re-enrollment ====================

@Composable
private fun ReEnrollmentContent(
    newDid: String,
    kemPublicKey: String,
    onNewDidChanged: (String) -> Unit,
    onKemKeyChanged: (String) -> Unit,
    onComplete: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.PersonAdd,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Re-enroll Device",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Your secret has been reconstructed. Enter your new device DID to complete recovery.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(24.dp))

        OutlinedTextField(
            value = newDid,
            onValueChange = onNewDidChanged,
            label = { Text("New Device DID (optional)") },
            placeholder = { Text("Leave blank to keep your existing DID") },
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(12.dp))

        OutlinedTextField(
            value = kemPublicKey,
            onValueChange = onKemKeyChanged,
            label = { Text("KEM Public Key (optional)") },
            placeholder = { Text("Base64-encoded KEM public key") },
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = onComplete,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.Done, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Complete Recovery")
        }
    }
}

// ==================== Shared Components ====================

@Composable
private fun RecoveryFilePickerCard(
    label: String,
    isLoaded: Boolean,
    onPick: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = if (isLoaded)
                MaterialTheme.colorScheme.primaryContainer
            else
                MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                if (isLoaded) Icons.Default.CheckCircle else Icons.Default.InsertDriveFile,
                contentDescription = null,
                tint = if (isLoaded) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
                if (isLoaded) {
                    Text(
                        text = "File loaded",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            OutlinedButton(
                onClick = onPick,
                enabled = !isLoaded
            ) {
                Text(if (isLoaded) "Loaded" else "Open")
            }
        }
    }
}

@Composable
private fun RecoveryProgressContent(message: String) {
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
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun RecoverySuccessContent() {
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
            text = "Recovery Complete",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Your account has been recovered successfully. You can now sign in.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun RecoveryErrorContent(
    error: String?,
    onRetry: () -> Unit
) {
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
            text = "Recovery Failed",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.error
        )
        if (error != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = error,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(modifier = Modifier.height(24.dp))
        Button(onClick = onRetry) {
            Text("Try Again")
        }
    }
}

// ==================== Helpers ====================

private fun readFileContent(context: android.content.Context, uri: Uri): String? {
    return try {
        context.contentResolver.openInputStream(uri)?.use { stream ->
            stream.bufferedReader(Charsets.UTF_8).readText()
        }
    } catch (_: Exception) {
        null
    }
}
