package my.ssdid.drive.presentation.tenant

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * Screen for requesting a new organization/tenant.
 *
 * Displays a form with organization name (required) and reason (optional).
 * On success, shows a confirmation message.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TenantRequestScreen(
    onNavigateBack: () -> Unit,
    viewModel: TenantRequestViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Request Organization") },
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
            if (uiState.isSubmitted) {
                // Success state
                SuccessContent(onDone = onNavigateBack)
            } else {
                // Form state
                FormContent(
                    uiState = uiState,
                    onOrganizationNameChange = { viewModel.updateOrganizationName(it) },
                    onReasonChange = { viewModel.updateReason(it) },
                    onSubmit = { viewModel.submitRequest() }
                )
            }
        }
    }
}

@Composable
private fun FormContent(
    uiState: TenantRequestUiState,
    onOrganizationNameChange: (String) -> Unit,
    onReasonChange: (String) -> Unit,
    onSubmit: () -> Unit
) {
    Spacer(modifier = Modifier.height(16.dp))

    // Header icon
    Icon(
        imageVector = Icons.Default.Business,
        contentDescription = "Organization",
        modifier = Modifier.size(64.dp),
        tint = MaterialTheme.colorScheme.primary
    )

    Spacer(modifier = Modifier.height(16.dp))

    Text(
        text = "Create Your Organization",
        style = MaterialTheme.typography.headlineSmall,
        fontWeight = FontWeight.SemiBold
    )

    Spacer(modifier = Modifier.height(8.dp))

    Text(
        text = "Submit a request to create a new organization for your team. An administrator will review your request.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(32.dp))

    // Organization Name field (required)
    OutlinedTextField(
        value = uiState.organizationName,
        onValueChange = onOrganizationNameChange,
        label = { Text("Organization Name") },
        placeholder = { Text("e.g. Acme Corp") },
        singleLine = true,
        enabled = !uiState.isLoading,
        modifier = Modifier.fillMaxWidth(),
        isError = uiState.error != null
    )

    Spacer(modifier = Modifier.height(16.dp))

    // Reason field (optional, multiline)
    OutlinedTextField(
        value = uiState.reason,
        onValueChange = { if (it.length <= 500) onReasonChange(it) },
        label = { Text("Reason (optional)") },
        placeholder = { Text("Why do you need this organization?") },
        minLines = 3,
        maxLines = 5,
        enabled = !uiState.isLoading,
        modifier = Modifier.fillMaxWidth(),
        supportingText = {
            Text(
                text = "${uiState.reason.length}/500",
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.End
            )
        }
    )

    // Error message
    if (uiState.error != null) {
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = uiState.error,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error
        )
    }

    Spacer(modifier = Modifier.height(24.dp))

    // Submit button
    Button(
        onClick = onSubmit,
        modifier = Modifier.fillMaxWidth(),
        enabled = uiState.organizationName.isNotBlank() && !uiState.isLoading
    ) {
        if (uiState.isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                color = MaterialTheme.colorScheme.onPrimary
            )
        } else {
            Text("Submit Request")
        }
    }

    Spacer(modifier = Modifier.height(32.dp))
}

@Composable
private fun SuccessContent(onDone: () -> Unit) {
    Spacer(modifier = Modifier.height(48.dp))

    Icon(
        imageVector = Icons.Default.CheckCircle,
        contentDescription = "Success",
        modifier = Modifier.size(80.dp),
        tint = MaterialTheme.colorScheme.primary
    )

    Spacer(modifier = Modifier.height(24.dp))

    Text(
        text = "Request Submitted!",
        style = MaterialTheme.typography.headlineSmall,
        fontWeight = FontWeight.SemiBold
    )

    Spacer(modifier = Modifier.height(12.dp))

    Text(
        text = "Your organization request has been submitted for review. You will be notified once it is approved.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center
    )

    Spacer(modifier = Modifier.height(32.dp))

    Button(
        onClick = onDone,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text("Done")
    }

    Spacer(modifier = Modifier.height(32.dp))
}
