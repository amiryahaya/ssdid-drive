package my.ssdid.drive.presentation.tenant

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.InviteCodeInfo

/**
 * Screen for entering an invite code to join a tenant.
 *
 * Two-step flow:
 * 1. Enter short code (e.g. "ACME-7K9X") and tap "Look Up"
 * 2. Preview the tenant info and tap "Join" to confirm
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JoinTenantScreen(
    onNavigateBack: () -> Unit,
    onJoinSuccess: () -> Unit,
    onNavigateToLogin: () -> Unit = {},
    isLoggedIn: Boolean = true,
    viewModel: JoinTenantViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val focusManager = LocalFocusManager.current

    LaunchedEffect(uiState.isJoined) {
        if (uiState.isJoined) {
            onJoinSuccess()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Join Organization") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Navigate back"
                        )
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(16.dp))

            // Header icon
            Icon(
                imageVector = Icons.Default.GroupAdd,
                contentDescription = "Join organization",
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Enter Invite Code",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Enter the code you received to join an organization.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Code input field
            OutlinedTextField(
                value = uiState.code,
                onValueChange = { viewModel.updateCode(it) },
                label = { Text("Invite Code") },
                placeholder = { Text("e.g. ACME-7K9X") },
                singleLine = true,
                enabled = !uiState.isLookingUp && !uiState.isJoining,
                modifier = Modifier.fillMaxWidth(),
                textStyle = LocalTextStyle.current.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Medium
                ),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Characters,
                    keyboardType = KeyboardType.Text,
                    imeAction = ImeAction.Search
                ),
                keyboardActions = KeyboardActions(
                    onSearch = {
                        focusManager.clearFocus()
                        viewModel.lookupCode()
                    }
                ),
                isError = uiState.lookupError != null,
                supportingText = if (uiState.lookupError != null) {
                    { Text(uiState.lookupError!!) }
                } else {
                    null
                }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Show preview card or Look Up button
            if (uiState.inviteInfo != null) {
                InvitePreviewCard(
                    info = uiState.inviteInfo!!,
                    isJoining = uiState.isJoining,
                    joinError = uiState.joinError,
                    isLoggedIn = isLoggedIn,
                    onJoin = { viewModel.joinTenant() },
                    onCancel = { viewModel.clearPreview() },
                    onContinueToLogin = onNavigateToLogin
                )
            } else {
                // Look Up button
                Button(
                    onClick = {
                        focusManager.clearFocus()
                        viewModel.lookupCode()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = uiState.code.isNotBlank() && !uiState.isLookingUp
                ) {
                    if (uiState.isLookingUp) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                    } else {
                        Text("Look Up")
                    }
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/**
 * Card showing the invite preview after code lookup.
 * Displays tenant name, role, and expiry with Join/Cancel actions.
 */
@Composable
private fun InvitePreviewCard(
    info: InviteCodeInfo,
    isJoining: Boolean,
    joinError: String?,
    isLoggedIn: Boolean,
    onJoin: () -> Unit,
    onCancel: () -> Unit,
    onContinueToLogin: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            // Tenant name
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Business,
                    contentDescription = "Organization",
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Organization",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                    )
                    Text(
                        text = info.tenantName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Role
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Shield,
                    contentDescription = "Role",
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Role",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                    )
                    Text(
                        text = info.role.name.lowercase().replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Expiry
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = "Expiry date",
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Expires",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                    )
                    Text(
                        text = info.expiresAt,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }

            // Error message
            if (joinError != null) {
                Spacer(modifier = Modifier.height(16.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.Error,
                        contentDescription = "Error",
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = joinError,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Action buttons
            if (isLoggedIn) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedButton(
                        onClick = onCancel,
                        modifier = Modifier.weight(1f),
                        enabled = !isJoining
                    ) {
                        Text("Cancel")
                    }

                    Button(
                        onClick = onJoin,
                        modifier = Modifier.weight(1f),
                        enabled = !isJoining
                    ) {
                        if (isJoining) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                        } else {
                            Text("Join")
                        }
                    }
                }
            } else {
                // Not logged in -- redirect to login/register
                Button(
                    onClick = onContinueToLogin,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Continue to Sign In")
                }

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = "You need to sign in or create an account to join this organization.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}
