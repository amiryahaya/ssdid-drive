package my.ssdid.drive.presentation.auth

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TotpSetupScreen(
    onSetupComplete: () -> Unit,
    onNavigateBack: () -> Unit = {},
    viewModel: TotpSetupViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(uiState.isComplete) {
        if (uiState.isComplete) {
            onSetupComplete()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Set Up Two-Factor Authentication") },
                navigationIcon = {
                    if (uiState.step != TotpSetupStep.BackupCodes) {
                        IconButton(onClick = onNavigateBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            when (uiState.step) {
                TotpSetupStep.Loading -> {
                    CircularProgressIndicator(modifier = Modifier.testTag("loading"))
                }

                TotpSetupStep.ScanQr -> {
                    ScanQrStep(
                        otpauthUri = uiState.setupInfo?.otpauthUri ?: "",
                        secret = uiState.setupInfo?.secret ?: "",
                        error = uiState.error,
                        onContinue = viewModel::proceedToConfirm
                    )
                }

                TotpSetupStep.ConfirmCode -> {
                    ConfirmCodeStep(
                        code = uiState.code,
                        isLoading = uiState.isLoading,
                        error = uiState.error,
                        onCodeChange = viewModel::updateCode,
                        onSubmit = viewModel::confirmSetup
                    )
                }

                TotpSetupStep.BackupCodes -> {
                    BackupCodesStep(
                        codes = uiState.backupCodes ?: emptyList(),
                        onComplete = viewModel::completeSetup
                    )
                }
            }
        }
    }
}

@Composable
private fun ScanQrStep(
    otpauthUri: String,
    secret: String,
    error: String?,
    onContinue: () -> Unit
) {
    Text(
        text = "Step 1: Set Up Authenticator",
        style = MaterialTheme.typography.titleLarge
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Open your authenticator app (Google Authenticator, Microsoft Authenticator, etc.) and add this account manually using the secret key below:",
        style = MaterialTheme.typography.bodyMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(24.dp))

    // Open in authenticator app via otpauth:// URI
    if (otpauthUri.isNotEmpty()) {
        val context = LocalContext.current
        OutlinedButton(
            onClick = {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(otpauthUri))
                try {
                    context.startActivity(intent)
                } catch (_: Exception) {
                    // No authenticator app handles otpauth:// — user must enter manually
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("open_authenticator_button")
        ) {
            Text("Open in Authenticator App")
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Or enter the secret key manually:",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
    }

    // Manual entry secret key
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Secret Key",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = secret,
                style = MaterialTheme.typography.bodyLarge,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier.testTag("totp_secret")
            )
        }
    }

    error?.let {
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = it,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }

    Spacer(modifier = Modifier.height(24.dp))

    Button(
        onClick = onContinue,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("continue_button")
    ) {
        Text("I've added the account")
    }
}

@Composable
private fun ConfirmCodeStep(
    code: String,
    isLoading: Boolean,
    error: String?,
    onCodeChange: (String) -> Unit,
    onSubmit: () -> Unit
) {
    Text(
        text = "Step 2: Verify Code",
        style = MaterialTheme.typography.titleLarge
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Enter the 6-digit code from your authenticator app to confirm setup",
        style = MaterialTheme.typography.bodyMedium,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(24.dp))

    OutlinedTextField(
        value = code,
        onValueChange = onCodeChange,
        label = { Text("Verification code") },
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Number,
            imeAction = ImeAction.Done
        ),
        keyboardActions = KeyboardActions(onDone = { onSubmit() }),
        singleLine = true,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("confirm_code_input"),
        enabled = !isLoading
    )

    error?.let {
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = it,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }

    Spacer(modifier = Modifier.height(16.dp))

    Button(
        onClick = onSubmit,
        enabled = !isLoading && code.length == 6,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("confirm_button")
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = MaterialTheme.colorScheme.onPrimary,
                strokeWidth = 2.dp
            )
            Spacer(modifier = Modifier.width(8.dp))
        }
        Text("Verify & Enable")
    }
}

@Composable
private fun BackupCodesStep(
    codes: List<String>,
    onComplete: () -> Unit
) {
    Text(
        text = "Step 3: Save Backup Codes",
        style = MaterialTheme.typography.titleLarge
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Save these backup codes in a safe place. Each code can only be used once to access your account if you lose your authenticator.",
        style = MaterialTheme.typography.bodyMedium,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.error
    )

    Spacer(modifier = Modifier.height(24.dp))

    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            codes.forEachIndexed { index, code ->
                Text(
                    text = "${index + 1}. $code",
                    style = MaterialTheme.typography.bodyLarge,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.testTag("backup_code_$index")
                )
                if (index < codes.lastIndex) {
                    Spacer(modifier = Modifier.height(4.dp))
                }
            }
        }
    }

    Spacer(modifier = Modifier.height(24.dp))

    Button(
        onClick = onComplete,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("done_button")
    ) {
        Text("I've saved my backup codes")
    }
}
