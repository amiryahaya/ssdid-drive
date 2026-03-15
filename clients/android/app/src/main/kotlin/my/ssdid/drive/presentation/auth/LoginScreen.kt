package my.ssdid.drive.presentation.auth

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import my.ssdid.drive.R

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    onNavigateToRegister: () -> Unit = {},
    onNavigateToRecovery: () -> Unit = {},
    onNavigateToJoinTenant: () -> Unit = {},
    onNavigateToTenantRequest: () -> Unit = {},
    onNavigateToTotp: (email: String) -> Unit = {},
    onOidcLogin: (provider: String) -> Unit = {},
    viewModel: LoginViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(uiState.isAuthenticated) {
        if (uiState.isAuthenticated) {
            onLoginSuccess()
        }
    }

    LaunchedEffect(uiState.navigateToTotp) {
        uiState.navigateToTotp?.let { email ->
            onNavigateToTotp(email)
            viewModel.onTotpNavigated()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painter = painterResource(id = R.mipmap.ic_launcher_foreground),
            contentDescription = "SSDID Drive",
            modifier = Modifier.size(120.dp)
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "SSDID Drive",
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

        // Invite code entry point
        OutlinedCard(
            onClick = onNavigateToJoinTenant,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Have an invite code?",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Enter your code to join an organization",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Icon(
                    Icons.Default.GroupAdd,
                    contentDescription = "Enter invite code",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Divider with "or sign in" text
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HorizontalDivider(modifier = Modifier.weight(1f))
            Text(
                text = "  or sign in  ",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            HorizontalDivider(modifier = Modifier.weight(1f))
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Email input
        OutlinedTextField(
            value = uiState.email,
            onValueChange = viewModel::updateEmail,
            label = { Text("Email") },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Done
            ),
            keyboardActions = KeyboardActions(onDone = { viewModel.submitEmail() }),
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("email_input"),
            enabled = !uiState.isLoading
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Continue button
        Button(
            onClick = { viewModel.submitEmail() },
            enabled = !uiState.isLoading && uiState.email.isNotBlank(),
            modifier = Modifier
                .fillMaxWidth()
                .testTag("login_button")
        ) {
            if (uiState.isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 2.dp
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text("Continue with Email")
        }

        // Error display
        uiState.error?.let { error ->
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = error,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // OIDC divider
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HorizontalDivider(modifier = Modifier.weight(1f))
            Text(
                text = "  or  ",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            HorizontalDivider(modifier = Modifier.weight(1f))
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Google sign-in button
        OutlinedButton(
            onClick = { onOidcLogin("google") },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("google_button"),
            enabled = !uiState.isLoading
        ) {
            Text("Sign in with Google")
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Microsoft sign-in button
        OutlinedButton(
            onClick = { onOidcLogin("microsoft") },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("microsoft_button"),
            enabled = !uiState.isLoading
        ) {
            Text("Sign in with Microsoft")
        }

        Spacer(modifier = Modifier.height(24.dp))

        TextButton(onClick = onNavigateToRecovery) {
            Text("Lost your authenticator? Recover access")
        }

        Spacer(modifier = Modifier.height(16.dp))

        TextButton(onClick = onNavigateToTenantRequest) {
            Text("Need an organization? Request one")
        }
    }
}
