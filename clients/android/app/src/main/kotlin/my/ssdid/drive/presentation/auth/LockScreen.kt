package my.ssdid.drive.presentation.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * Lock screen shown when the app is locked.
 *
 * Allows unlocking via biometric authentication or password.
 */
@Composable
fun LockScreen(
    onUnlocked: () -> Unit,
    viewModel: LockViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val activity = context as? FragmentActivity

    // Navigate when unlocked
    LaunchedEffect(uiState.isUnlocked) {
        if (uiState.isUnlocked) {
            onUnlocked()
        }
    }

    // Auto-trigger biometric on first launch if available and not showing password input
    LaunchedEffect(Unit) {
        if (uiState.biometricAvailable && !uiState.showPasswordInput && activity != null) {
            viewModel.unlockWithBiometric(activity)
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // App Icon/Logo
            Icon(
                imageVector = Icons.Default.Lock,
                contentDescription = null,
                modifier = Modifier.size(80.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Title
            Text(
                text = "SSDID Drive",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onBackground
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Subtitle
            Text(
                text = "Your files are encrypted and protected",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(48.dp))

            if (uiState.isUnlocking) {
                // Loading state
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = "Unlocking...",
                    style = MaterialTheme.typography.bodyMedium
                )
            } else if (uiState.showPasswordInput) {
                // Password input
                PasswordUnlockSection(
                    onUnlock = { viewModel.unlockWithPassword(it) },
                    onUseBiometric = {
                        viewModel.hidePasswordInput()
                        activity?.let { viewModel.unlockWithBiometric(it) }
                    },
                    biometricAvailable = uiState.biometricAvailable,
                    error = uiState.error
                )
            } else {
                // Biometric unlock
                BiometricUnlockSection(
                    onUnlockWithBiometric = {
                        activity?.let { viewModel.unlockWithBiometric(it) }
                    },
                    onUsePassword = { viewModel.showPasswordInput() },
                    error = uiState.error
                )
            }
        }
    }
}

@Composable
private fun BiometricUnlockSection(
    onUnlockWithBiometric: () -> Unit,
    onUsePassword: () -> Unit,
    error: String?
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Error message
        if (error != null) {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = error,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    modifier = Modifier.padding(16.dp),
                    textAlign = TextAlign.Center
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        // Biometric unlock button
        Button(
            onClick = onUnlockWithBiometric,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Fingerprint,
                contentDescription = null,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Unlock with Biometric")
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Use password instead
        TextButton(onClick = onUsePassword) {
            Text("Use password instead")
        }
    }
}

@Composable
private fun PasswordUnlockSection(
    onUnlock: (String) -> Unit,
    onUseBiometric: () -> Unit,
    biometricAvailable: Boolean,
    error: String?
) {
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth()
    ) {
        // Error message
        if (error != null) {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = error,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    modifier = Modifier.padding(16.dp),
                    textAlign = TextAlign.Center
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
        }

        // Password field
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Password") },
            singleLine = true,
            visualTransformation = if (passwordVisible) {
                VisualTransformation.None
            } else {
                PasswordVisualTransformation()
            },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(
                onDone = {
                    if (password.isNotBlank()) {
                        onUnlock(password)
                        password = ""
                    }
                }
            ),
            trailingIcon = {
                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                    Icon(
                        imageVector = if (passwordVisible) {
                            Icons.Default.VisibilityOff
                        } else {
                            Icons.Default.Visibility
                        },
                        contentDescription = if (passwordVisible) "Hide password" else "Show password"
                    )
                }
            },
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Unlock button
        Button(
            onClick = {
                if (password.isNotBlank()) {
                    onUnlock(password)
                    password = ""
                }
            },
            enabled = password.isNotBlank(),
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
        ) {
            Icon(
                imageVector = Icons.Default.LockOpen,
                contentDescription = null,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Unlock")
        }

        if (biometricAvailable) {
            Spacer(modifier = Modifier.height(16.dp))

            // Use biometric instead
            TextButton(onClick = onUseBiometric) {
                Icon(
                    imageVector = Icons.Default.Fingerprint,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Use biometric instead")
            }
        }
    }
}
