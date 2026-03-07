package my.ssdid.drive.presentation.sharing

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.presentation.common.ErrorState

/**
 * Screen for sharing a folder with another user.
 *
 * Flow:
 * 1. Display folder info
 * 2. Search and select recipient
 * 3. Choose permission level
 * 4. Toggle recursive sharing
 * 5. Optionally set expiry
 * 6. Confirm share
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareFolderScreen(
    onNavigateBack: () -> Unit,
    onShareSuccess: () -> Unit,
    viewModel: ShareFolderViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val focusManager = LocalFocusManager.current

    // Handle share success
    LaunchedEffect(uiState.shareSuccess) {
        if (uiState.shareSuccess) {
            onShareSuccess()
        }
    }

    // Show error snackbar
    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Share Folder") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) }
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
                uiState.error != null && uiState.folder == null -> {
                    ErrorState(
                        message = uiState.error!!,
                        onRetry = null,
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                uiState.folder != null -> {
                    ShareFolderContent(
                        uiState = uiState,
                        onSearchQueryChanged = viewModel::onSearchQueryChanged,
                        onUserSelected = viewModel::onUserSelected,
                        onUserCleared = viewModel::onUserCleared,
                        onPermissionSelected = viewModel::onPermissionSelected,
                        onRecursiveChanged = viewModel::onRecursiveChanged,
                        onExpiryChanged = viewModel::onExpiryChanged,
                        onShare = {
                            focusManager.clearFocus()
                            viewModel.shareFolder()
                        }
                    )
                }
            }

            // Sharing progress overlay
            if (uiState.isSharing) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.scrim.copy(alpha = 0.5f)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Card {
                            Column(
                                modifier = Modifier.padding(24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                CircularProgressIndicator()
                                Spacer(modifier = Modifier.height(16.dp))
                                Text("Sharing folder...")
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ShareFolderContent(
    uiState: ShareFolderUiState,
    onSearchQueryChanged: (String) -> Unit,
    onUserSelected: (User) -> Unit,
    onUserCleared: () -> Unit,
    onPermissionSelected: (SharePermission) -> Unit,
    onRecursiveChanged: (Boolean) -> Unit,
    onExpiryChanged: (Int?) -> Unit,
    onShare: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        // Folder info card
        Card(
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Folder,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(16.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = uiState.folder!!.name,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = if (uiState.folder.isRoot) "Root folder" else "Folder",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Recipient section
        Text(
            text = "Share with",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))

        if (uiState.selectedUser != null) {
            // Selected user chip
            Card(
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Person,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = uiState.selectedUser.displayName ?: uiState.selectedUser.email,
                            style = MaterialTheme.typography.bodyLarge
                        )
                        if (uiState.selectedUser.displayName != null) {
                            Text(
                                text = uiState.selectedUser.email,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    IconButton(onClick = onUserCleared) {
                        Icon(Icons.Default.Close, contentDescription = "Remove")
                    }
                }
            }
        } else {
            // Search field
            OutlinedTextField(
                value = uiState.searchQuery,
                onValueChange = onSearchQueryChanged,
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Search by email or name") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                trailingIcon = {
                    if (uiState.isSearching) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp
                        )
                    }
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { })
            )

            // Search results
            if (uiState.searchResults.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Card(
                    modifier = Modifier.fillMaxWidth()
                ) {
                    LazyColumn(
                        modifier = Modifier.heightIn(max = 200.dp)
                    ) {
                        items(uiState.searchResults) { user ->
                            ListItem(
                                headlineContent = {
                                    Text(user.displayName ?: user.email)
                                },
                                supportingContent = if (user.displayName != null) {
                                    { Text(user.email) }
                                } else null,
                                leadingContent = {
                                    Icon(Icons.Default.Person, contentDescription = null)
                                },
                                modifier = Modifier.clickable { onUserSelected(user) }
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Permission section
        Text(
            text = "Permission",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SharePermission.entries.forEach { permission ->
                FilterChip(
                    selected = uiState.selectedPermission == permission,
                    onClick = { onPermissionSelected(permission) },
                    label = { Text(permission.displayName()) },
                    modifier = Modifier.weight(1f)
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = when (uiState.selectedPermission) {
                SharePermission.READ -> "Recipient can view folder contents"
                SharePermission.WRITE -> "Recipient can view, add, and modify files"
                SharePermission.ADMIN -> "Recipient can view, modify, and share the folder"
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Recursive option
        Card(
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Include subfolders",
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(
                        text = "Share all files and subfolders within this folder",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(
                    checked = uiState.recursive,
                    onCheckedChange = onRecursiveChanged
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Expiry section
        Text(
            text = "Expiry (optional)",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            listOf(null to "Never", 7 to "7 days", 30 to "30 days", 90 to "90 days").forEach { (days, label) ->
                FilterChip(
                    selected = uiState.expiryDays == days,
                    onClick = { onExpiryChanged(days) },
                    label = { Text(label) }
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        // Share button
        Button(
            onClick = onShare,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            enabled = uiState.selectedUser != null && !uiState.isSharing
        ) {
            Icon(Icons.Default.FolderShared, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Share Folder")
        }
    }
}
