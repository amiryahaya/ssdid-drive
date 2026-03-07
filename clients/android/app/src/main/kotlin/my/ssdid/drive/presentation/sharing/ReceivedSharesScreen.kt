package my.ssdid.drive.presentation.sharing

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.ResourceType
import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.presentation.common.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceivedSharesScreen(
    onNavigateBack: () -> Unit,
    onNavigateToFile: (String) -> Unit,
    onNavigateToFolder: (String) -> Unit,
    onNavigateToCreated: () -> Unit,
    viewModel: SharesViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {
        viewModel.loadReceivedShares()
    }

    // Show snackbar for errors
    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            val result = snackbarHostState.showSnackbar(
                message = error,
                actionLabel = "Retry",
                duration = SnackbarDuration.Long
            )
            if (result == SnackbarResult.ActionPerformed) {
                viewModel.loadReceivedShares()
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Shared with Me") },
                navigationIcon = {
                    IconButton(
                        onClick = onNavigateBack,
                        modifier = Modifier.semantics { contentDescription = "Navigate back" }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.loadReceivedShares() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    TextButton(onClick = onNavigateToCreated) {
                        Text("My Shares")
                    }
                }
            )
        },
        snackbarHost = {
            SnackbarHost(hostState = snackbarHostState) { data ->
                Snackbar(
                    snackbarData = data,
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                    actionColor = MaterialTheme.colorScheme.primary
                )
            }
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when {
                // Show skeleton loading on initial load
                uiState.isLoading && uiState.receivedShares.isEmpty() -> {
                    ListLoadingSkeleton(
                        itemCount = 5,
                        modifier = Modifier.fillMaxSize()
                    )
                }
                // Show empty state
                !uiState.isLoading && uiState.receivedShares.isEmpty() && uiState.error == null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        EmptySharesState(isReceived = true)
                    }
                }
                // Show content
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(vertical = 8.dp)
                    ) {
                        itemsIndexed(
                            items = uiState.receivedShares,
                            key = { _, share -> share.id }
                        ) { index, share ->
                            AnimatedListItem(index = index) {
                                ShareItem(
                                    share = share,
                                    isReceived = true,
                                    onClick = {
                                        when (share.resourceType) {
                                            ResourceType.FILE -> onNavigateToFile(share.resourceId)
                                            ResourceType.FOLDER -> onNavigateToFolder(share.resourceId)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ShareItem(
    share: Share,
    isReceived: Boolean,
    onClick: () -> Unit,
    onRevoke: (() -> Unit)? = null
) {
    val description = if (isReceived) {
        "Shared by ${share.grantor?.email ?: "Unknown"}, ${share.resourceType.name.lowercase()} with ${share.permission.displayName()} access"
    } else {
        "Shared with ${share.grantee?.email ?: "Unknown"}, ${share.resourceType.name.lowercase()} with ${share.permission.displayName()} access"
    }

    ListItem(
        headlineContent = {
            Text(
                if (isReceived) {
                    "From: ${share.grantor?.email ?: "Unknown"}"
                } else {
                    "To: ${share.grantee?.email ?: "Unknown"}"
                }
            )
        },
        supportingContent = {
            Column {
                Text("${share.resourceType.name.lowercase().replaceFirstChar { it.uppercase() }} - ${share.permission.displayName()}")
                share.expiresAt?.let {
                    Text(
                        "Expires: $it",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        },
        leadingContent = {
            Icon(
                imageVector = when (share.resourceType) {
                    ResourceType.FILE -> Icons.Default.InsertDriveFile
                    ResourceType.FOLDER -> Icons.Default.Folder
                },
                contentDescription = when (share.resourceType) {
                    ResourceType.FILE -> "File"
                    ResourceType.FOLDER -> "Folder"
                },
                tint = MaterialTheme.colorScheme.primary
            )
        },
        trailingContent = {
            if (onRevoke != null) {
                IconButton(
                    onClick = onRevoke,
                    modifier = Modifier.semantics { contentDescription = "Revoke share" }
                ) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Revoke",
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            } else {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            }
        },
        modifier = Modifier
            .clickable(onClick = onClick)
            .semantics { contentDescription = description }
    )
}
