package com.securesharing.presentation.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.securesharing.util.OidcCallbackHolder

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    onOidcBrowserOpen: (String) -> Unit = {},
    onNavigateToJoinTenant: () -> Unit = {},
    viewModel: LoginViewModel = hiltViewModel(),
    oidcViewModel: OidcLoginViewModel = hiltViewModel(),
    passkeyViewModel: PasskeyLoginViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val oidcState by oidcViewModel.uiState.collectAsState()
    val passkeyState by passkeyViewModel.uiState.collectAsState()
    val focusManager = LocalFocusManager.current

    LaunchedEffect(uiState.isLoggedIn) {
        if (uiState.isLoggedIn) {
            onLoginSuccess()
        }
    }

    LaunchedEffect(oidcState.isLoggedIn) {
        if (oidcState.isLoggedIn) {
            onLoginSuccess()
        }
    }

    LaunchedEffect(passkeyState.isLoggedIn) {
        if (passkeyState.isLoggedIn) {
            onLoginSuccess()
        }
    }

    // Open browser when authorization URL is available
    LaunchedEffect(oidcState.authorizationUrl) {
        oidcState.authorizationUrl?.let { url ->
            onOidcBrowserOpen(url)
            oidcViewModel.clearAuthorizationUrl()
        }
    }

    // Load OIDC providers on mount and check for pending OIDC callback
    LaunchedEffect(Unit) {
        oidcViewModel.loadProviders("default")

        // Check if there's a pending OIDC callback from deep link
        OidcCallbackHolder.consume()?.let { (code, state) ->
            oidcViewModel.handleCallback(code, state)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = "SecureSharing",
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Post-Quantum Secure File Sharing",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(48.dp))

        OutlinedTextField(
            value = uiState.tenantSlug,
            onValueChange = { viewModel.updateTenantSlug(it) },
            label = { Text("Organization (optional)") },
            placeholder = { Text("e.g., acme-corp") },
            supportingText = { Text("Leave empty to select after login") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Text,
                imeAction = ImeAction.Next
            ),
            keyboardActions = KeyboardActions(
                onNext = { focusManager.moveFocus(FocusDirection.Down) }
            )
        )

        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = uiState.email,
            onValueChange = { viewModel.updateEmail(it) },
            label = { Text("Email") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Next
            ),
            keyboardActions = KeyboardActions(
                onNext = { focusManager.moveFocus(FocusDirection.Down) }
            )
        )

        Spacer(modifier = Modifier.height(16.dp))

        var passwordVisible by remember { mutableStateOf(false) }

        OutlinedTextField(
            value = uiState.password,
            onValueChange = { viewModel.updatePassword(it) },
            label = { Text("Password") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(
                onDone = {
                    focusManager.clearFocus()
                    viewModel.login()
                }
            ),
            trailingIcon = {
                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                    Icon(
                        imageVector = if (passwordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                        contentDescription = if (passwordVisible) "Hide password" else "Show password"
                    )
                }
            }
        )

        if (uiState.error != null) {
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = uiState.error!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = { viewModel.login() },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("login_button"),
            enabled = !uiState.isLoading
        ) {
            if (uiState.isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = MaterialTheme.colorScheme.onPrimary
                )
            } else {
                Text("Login")
            }
        }

        // Show combined errors
        if (oidcState.error != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = oidcState.error!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }

        if (passkeyState.error != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = passkeyState.error!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // "OR" divider
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HorizontalDivider(modifier = Modifier.weight(1f))
            Text(
                text = "  OR  ",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            HorizontalDivider(modifier = Modifier.weight(1f))
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Sign in with Passkey
        OutlinedButton(
            onClick = { passkeyViewModel.beginLogin(uiState.email.ifBlank { null }) },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("passkey_button"),
            enabled = !passkeyState.isLoading
        ) {
            if (passkeyState.isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Icon(
                imageVector = Icons.Default.Fingerprint,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Sign in with Passkey")
        }

        // OIDC provider buttons
        if (oidcState.providers.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))

            oidcState.providers.forEach { provider ->
                OutlinedButton(
                    onClick = { oidcViewModel.beginLogin(provider.id) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("oidc_button_${provider.id}"),
                    enabled = !oidcState.isLoading
                ) {
                    if (oidcState.isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Icon(
                        imageVector = Icons.Default.Language,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Sign in with ${provider.name}")
                }
                Spacer(modifier = Modifier.height(8.dp))
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Invitation-only registration notice
        Text(
            text = "Don't have an account?",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "Contact your administrator to receive an invitation.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(12.dp))

        TextButton(onClick = onNavigateToJoinTenant) {
            Text("Have an invite code?")
        }
    }
}
