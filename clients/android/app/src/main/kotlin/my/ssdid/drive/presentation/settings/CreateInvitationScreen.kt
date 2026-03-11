package my.ssdid.drive.presentation.settings

import android.content.Intent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.UserRole

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateInvitationScreen(
    onNavigateBack: () -> Unit,
    viewModel: CreateInvitationViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Create Invitation") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            if (uiState.createdInvitation != null) {
                InvitationCreatedContent(
                    shortCode = uiState.createdInvitation!!.shortCode,
                    email = uiState.createdInvitation!!.email,
                    onCreateAnother = { viewModel.resetForm() },
                    onNavigateBack = onNavigateBack
                )
            } else {
                CreateInvitationForm(
                    email = uiState.email,
                    emailError = uiState.emailError,
                    selectedRole = uiState.selectedRole,
                    message = uiState.message,
                    isCreating = uiState.isCreating,
                    currentUserRole = uiState.currentUserRole,
                    onEmailChange = viewModel::updateEmail,
                    onRoleChange = viewModel::updateRole,
                    onMessageChange = viewModel::updateMessage,
                    onCreateInvitation = viewModel::createInvitation
                )
            }
        }
    }
}

@Composable
private fun CreateInvitationForm(
    email: String,
    emailError: String?,
    selectedRole: UserRole,
    message: String,
    isCreating: Boolean,
    currentUserRole: UserRole,
    onEmailChange: (String) -> Unit,
    onRoleChange: (UserRole) -> Unit,
    onMessageChange: (String) -> Unit,
    onCreateInvitation: () -> Unit
) {
    val scrollState = rememberScrollState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Email field
        Text(
            text = "Email (optional)",
            style = MaterialTheme.typography.labelLarge
        )
        OutlinedTextField(
            value = email,
            onValueChange = onEmailChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("user@example.com") },
            isError = emailError != null,
            supportingText = emailError?.let {
                { Text(it, color = MaterialTheme.colorScheme.error) }
            } ?: {
                Text("Leave blank to create an open invitation")
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            enabled = !isCreating
        )

        // Role picker
        Text(
            text = "Role",
            style = MaterialTheme.typography.labelLarge
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            RoleChip(
                label = "Member",
                selected = selectedRole == UserRole.USER,
                onClick = { onRoleChange(UserRole.USER) },
                enabled = !isCreating,
                modifier = Modifier.weight(1f)
            )
            RoleChip(
                label = "Admin",
                selected = selectedRole == UserRole.ADMIN,
                onClick = { onRoleChange(UserRole.ADMIN) },
                enabled = !isCreating && currentUserRole == UserRole.OWNER,
                modifier = Modifier.weight(1f)
            )
        }
        if (currentUserRole != UserRole.OWNER) {
            Text(
                text = "Only owners can assign the Admin role",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Message field
        Text(
            text = "Message (optional)",
            style = MaterialTheme.typography.labelLarge
        )
        OutlinedTextField(
            value = message,
            onValueChange = onMessageChange,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 100.dp),
            placeholder = { Text("Add a personal message...") },
            maxLines = 5,
            supportingText = {
                Text(
                    text = "${message.length}/500",
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.End
                )
            },
            enabled = !isCreating
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Create button
        Button(
            onClick = onCreateInvitation,
            modifier = Modifier.fillMaxWidth(),
            enabled = !isCreating
        ) {
            if (isCreating) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                    strokeWidth = 2.dp
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text("Create Invitation")
        }
    }
}

@Composable
private fun RoleChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    enabled: Boolean,
    modifier: Modifier = Modifier
) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = {
            Text(
                text = label,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center
            )
        },
        enabled = enabled,
        modifier = modifier
    )
}

@Composable
private fun InvitationCreatedContent(
    shortCode: String,
    email: String?,
    onCreateAnother: () -> Unit,
    onNavigateBack: () -> Unit
) {
    val clipboardManager = LocalClipboardManager.current
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var showCopiedMessage by remember { mutableStateOf(false) }

    LaunchedEffect(showCopiedMessage) {
        if (showCopiedMessage) {
            snackbarHostState.showSnackbar("Code copied to clipboard")
            showCopiedMessage = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Share,
            contentDescription = "Invitation created",
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Invitation Created!",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        if (email != null) {
            Text(
                text = "Sent to $email",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
        }

        Text(
            text = "Share this code:",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Short code in large monospace text
        Surface(
            shape = MaterialTheme.shapes.medium,
            color = MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = shortCode,
                modifier = Modifier.padding(24.dp),
                style = MaterialTheme.typography.headlineLarge.copy(
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 4.sp
                ),
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Copy button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = {
                    clipboardManager.setText(AnnotatedString(shortCode))
                    showCopiedMessage = true
                },
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    Icons.Default.ContentCopy,
                    contentDescription = "Copy code",
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Copy")
            }

            Button(
                onClick = {
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(
                            Intent.EXTRA_TEXT,
                            "Join our organization using this invite code: $shortCode"
                        )
                    }
                    context.startActivity(Intent.createChooser(shareIntent, "Share Invitation"))
                },
                modifier = Modifier.weight(1f)
            ) {
                Icon(
                    Icons.Default.Share,
                    contentDescription = "Share invitation",
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text("Share")
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        TextButton(onClick = onCreateAnother) {
            Text("Create Another")
        }

        TextButton(onClick = onNavigateBack) {
            Text("Done")
        }
    }

    SnackbarHost(
        hostState = snackbarHostState,
        modifier = Modifier.fillMaxSize(),
        snackbar = { data ->
            Snackbar(snackbarData = data)
        }
    )
}
