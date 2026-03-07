package com.securesharing.presentation.files

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.securesharing.domain.model.FileItem
import com.securesharing.domain.model.Folder
import com.securesharing.presentation.common.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun FileBrowserScreen(
    folderId: String?,
    onNavigateToFolder: (String) -> Unit,
    onNavigateToFile: (String) -> Unit,
    onNavigateBack: (() -> Unit)? = null,
    onNavigateToSettings: () -> Unit,
    onNavigateToShares: () -> Unit,
    onNavigateToShareFile: (String) -> Unit = {},
    onNavigateToShareFolder: (String) -> Unit = {},
    viewModel: FileBrowserViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    val syncStatus by viewModel.syncStatus.collectAsState()
    var showSyncSheet by remember { mutableStateOf(false) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var showSortMenu by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()
    val snackbarHostState = remember { SnackbarHostState() }
    val haptic = LocalHapticFeedback.current
    val coroutineScope = rememberCoroutineScope()

    // For undo delete functionality
    var pendingDeleteItems by remember { mutableStateOf<List<Pair<String, Boolean>>>(emptyList()) }

    // File picker launcher
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let {
            // Get file name from URI
            val fileName = context.contentResolver.query(it, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                cursor.moveToFirst()
                if (nameIndex >= 0) cursor.getString(nameIndex) else null
            } ?: "unknown_file"

            viewModel.uploadFile(it, fileName)
        }
    }

    LaunchedEffect(folderId) {
        viewModel.loadFolder(folderId)
    }

    // Handle back press in selection mode
    BackHandler(enabled = uiState.isSelectionMode) {
        viewModel.exitSelectionMode()
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
                viewModel.loadFolder(folderId)
            }
            viewModel.clearError()
        }
    }

    // Sync status bottom sheet
    if (showSyncSheet) {
        ModalBottomSheet(
            onDismissRequest = { showSyncSheet = false },
            sheetState = sheetState
        ) {
            SyncStatusSheet(
                syncStatus = syncStatus,
                onRetryAll = {
                    viewModel.retryFailedSync()
                    showSyncSheet = false
                },
                onDismiss = { showSyncSheet = false }
            )
        }
    }

    // Delete confirmation dialog with undo support
    if (showDeleteConfirmation) {
        val itemCount = uiState.selectedCount
        val selectedFiles = uiState.selectedFileIds.toList()
        val selectedFolders = uiState.selectedFolderIds.toList()

        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            icon = {
                Icon(
                    Icons.Default.DeleteOutline,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(32.dp)
                )
            },
            title = { Text("Delete ${itemCount} item${if (itemCount > 1) "s" else ""}?") },
            text = {
                Text(
                    "You can undo this action for a few seconds after deletion.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                        showDeleteConfirmation = false

                        // Store items for potential undo
                        pendingDeleteItems = selectedFiles.map { it to false } +
                                selectedFolders.map { it to true }

                        // Perform delete
                        viewModel.deleteSelected()

                        // Show undo snackbar
                        coroutineScope.launch {
                            val result = snackbarHostState.showSnackbar(
                                message = if (itemCount == 1) "Item deleted" else "$itemCount items deleted",
                                actionLabel = "Undo",
                                duration = SnackbarDuration.Long
                            )
                            if (result == SnackbarResult.ActionPerformed) {
                                // TODO: Implement undo restore when backend supports it
                                snackbarHostState.showSnackbar(
                                    message = "Undo not yet available",
                                    duration = SnackbarDuration.Short
                                )
                            }
                            pendingDeleteItems = emptyList()
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError
                    )
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    Scaffold(
        topBar = {
            if (uiState.isSelectionMode) {
                // Selection mode top bar
                TopAppBar(
                    title = { Text("${uiState.selectedCount} selected") },
                    navigationIcon = {
                        IconButton(
                            onClick = { viewModel.exitSelectionMode() },
                            modifier = Modifier.semantics { contentDescription = "Exit selection mode" }
                        ) {
                            Icon(Icons.Default.Close, contentDescription = "Cancel selection")
                        }
                    },
                    actions = {
                        // Select all
                        IconButton(
                            onClick = { viewModel.selectAll() },
                            modifier = Modifier.semantics { contentDescription = "Select all items" }
                        ) {
                            Icon(Icons.Default.SelectAll, contentDescription = "Select All")
                        }
                        // Download (only for files)
                        val hasFilesSelected = uiState.selectedFileIds.isNotEmpty()
                        IconButton(
                            onClick = { viewModel.downloadSelected() },
                            enabled = hasFilesSelected && !uiState.isBulkOperationInProgress,
                            modifier = Modifier.semantics { contentDescription = "Download selected files" }
                        ) {
                            Icon(
                                Icons.Default.Download,
                                contentDescription = "Download",
                                tint = if (hasFilesSelected && !uiState.isBulkOperationInProgress)
                                    MaterialTheme.colorScheme.onSurface
                                else
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                            )
                        }
                        // Move
                        IconButton(
                            onClick = { viewModel.showMoveDialog() },
                            enabled = uiState.hasSelection && !uiState.isBulkOperationInProgress,
                            modifier = Modifier.semantics { contentDescription = "Move selected items" }
                        ) {
                            Icon(
                                Icons.Default.DriveFileMove,
                                contentDescription = "Move",
                                tint = if (uiState.hasSelection && !uiState.isBulkOperationInProgress)
                                    MaterialTheme.colorScheme.onSurface
                                else
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                            )
                        }
                        // Share
                        IconButton(
                            onClick = {
                                // Share first selected item (files take priority)
                                when {
                                    uiState.selectedFileIds.isNotEmpty() -> {
                                        onNavigateToShareFile(uiState.selectedFileIds.first())
                                        viewModel.exitSelectionMode()
                                    }
                                    uiState.selectedFolderIds.isNotEmpty() -> {
                                        onNavigateToShareFolder(uiState.selectedFolderIds.first())
                                        viewModel.exitSelectionMode()
                                    }
                                }
                            },
                            enabled = uiState.hasSelection && !uiState.isBulkOperationInProgress,
                            modifier = Modifier.semantics { contentDescription = "Share selected items" }
                        ) {
                            Icon(
                                Icons.Default.Share,
                                contentDescription = "Share",
                                tint = if (uiState.hasSelection && !uiState.isBulkOperationInProgress)
                                    MaterialTheme.colorScheme.onSurface
                                else
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                            )
                        }
                        // Delete
                        IconButton(
                            onClick = { showDeleteConfirmation = true },
                            enabled = uiState.hasSelection && !uiState.isBulkOperationInProgress,
                            modifier = Modifier.semantics { contentDescription = "Delete selected items" }
                        ) {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = "Delete",
                                tint = if (uiState.hasSelection && !uiState.isBulkOperationInProgress)
                                    MaterialTheme.colorScheme.error
                                else
                                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                )
            } else if (uiState.isSearchMode) {
                // Search mode top bar
                TopAppBar(
                    title = {
                        OutlinedTextField(
                            value = uiState.searchQuery,
                            onValueChange = { viewModel.updateSearchQuery(it) },
                            placeholder = { Text("Search files...") },
                            singleLine = true,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(end = 8.dp),
                            trailingIcon = {
                                if (uiState.searchQuery.isNotEmpty()) {
                                    IconButton(onClick = { viewModel.updateSearchQuery("") }) {
                                        Icon(Icons.Default.Clear, contentDescription = "Clear search")
                                    }
                                }
                            }
                        )
                    },
                    navigationIcon = {
                        IconButton(
                            onClick = { viewModel.exitSearchMode() },
                            modifier = Modifier.semantics { contentDescription = "Exit search" }
                        ) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    },
                    actions = {
                        if (uiState.isSearching) {
                            CircularProgressIndicator(
                                modifier = Modifier
                                    .size(24.dp)
                                    .padding(end = 16.dp),
                                strokeWidth = 2.dp
                            )
                        }
                    }
                )
            } else {
                // Normal top bar
                TopAppBar(
                    title = {
                        Text(
                            text = uiState.currentFolder?.name ?: "My Files",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    },
                    navigationIcon = {
                        if (onNavigateBack != null && folderId != null) {
                            IconButton(
                                onClick = onNavigateBack,
                                modifier = Modifier.semantics { contentDescription = "Navigate back" }
                            ) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                            }
                        }
                    },
                    actions = {
                        // Refresh button
                        IconButton(
                            onClick = { viewModel.loadFolder(folderId) },
                            modifier = Modifier.semantics { contentDescription = "Refresh" }
                        ) {
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                        }
                        // Search button
                        IconButton(
                            onClick = { viewModel.enterSearchMode() },
                            modifier = Modifier.semantics { contentDescription = "Search files" }
                        ) {
                            Icon(Icons.Default.Search, contentDescription = "Search")
                        }
                        // Favorites filter toggle
                        IconButton(
                            onClick = { viewModel.toggleShowFavoritesOnly() },
                            modifier = Modifier.semantics {
                                contentDescription = if (uiState.showFavoritesOnly) "Show all files" else "Show favorites only"
                            }
                        ) {
                            Icon(
                                if (uiState.showFavoritesOnly) Icons.Filled.Star else Icons.Outlined.StarOutline,
                                contentDescription = "Favorites",
                                tint = if (uiState.showFavoritesOnly)
                                    MaterialTheme.colorScheme.primary
                                else
                                    MaterialTheme.colorScheme.onSurface
                            )
                        }
                        // View mode toggle
                        IconButton(
                            onClick = { viewModel.toggleViewMode() },
                            modifier = Modifier.semantics {
                                contentDescription = if (uiState.viewMode == ViewMode.LIST) "Switch to grid view" else "Switch to list view"
                            }
                        ) {
                            Icon(
                                if (uiState.viewMode == ViewMode.LIST) Icons.Default.GridView else Icons.Default.ViewList,
                                contentDescription = "View mode"
                            )
                        }
                        // Sort button
                        Box {
                            IconButton(
                                onClick = { showSortMenu = true },
                                modifier = Modifier.semantics { contentDescription = "Sort files" }
                            ) {
                                Icon(Icons.Default.Sort, contentDescription = "Sort")
                            }
                            DropdownMenu(
                                expanded = showSortMenu,
                                onDismissRequest = { showSortMenu = false }
                            ) {
                                SortOption.entries.forEach { option ->
                                    DropdownMenuItem(
                                        text = { Text(option.displayName) },
                                        onClick = {
                                            viewModel.setSortOption(option)
                                            showSortMenu = false
                                        },
                                        trailingIcon = {
                                            if (uiState.sortOption == option) {
                                                Icon(Icons.Default.Check, contentDescription = null)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        // Sync status badge
                        SyncStatusBadge(
                            syncStatus = syncStatus,
                            onClick = { showSyncSheet = true }
                        )
                        IconButton(
                            onClick = onNavigateToShares,
                            modifier = Modifier.semantics { contentDescription = "View shared files" }
                        ) {
                            Icon(Icons.Default.Share, contentDescription = "Shares")
                        }
                        IconButton(
                            onClick = onNavigateToSettings,
                            modifier = Modifier.semantics { contentDescription = "Open settings" }
                        ) {
                            Icon(Icons.Default.Settings, contentDescription = "Settings")
                        }
                    }
                )
            }
        },
        floatingActionButton = {
            // Speed Dial FAB - consolidates upload and create folder into expandable menu
            if (!uiState.isSelectionMode) {
                SpeedDialFab(
                    items = listOf(
                        SpeedDialItem(
                            icon = Icons.Default.CreateNewFolder,
                            label = "New Folder",
                            onClick = { viewModel.showCreateFolderDialog() },
                            containerColor = MaterialTheme.colorScheme.tertiaryContainer
                        ),
                        SpeedDialItem(
                            icon = Icons.Default.Upload,
                            label = "Upload File",
                            onClick = { filePickerLauncher.launch(arrayOf("*/*")) },
                            containerColor = MaterialTheme.colorScheme.secondaryContainer
                        )
                    ),
                    mainIcon = Icons.Default.Add,
                    expandedIcon = Icons.Default.Close
                )
            }
        },
        snackbarHost = {
            SnackbarHost(hostState = snackbarHostState) { data ->
                Snackbar(
                    snackbarData = data,
                    containerColor = if (uiState.error != null)
                        MaterialTheme.colorScheme.errorContainer
                    else
                        MaterialTheme.colorScheme.inverseSurface,
                    contentColor = if (uiState.error != null)
                        MaterialTheme.colorScheme.onErrorContainer
                    else
                        MaterialTheme.colorScheme.inverseOnSurface,
                    actionColor = MaterialTheme.colorScheme.primary
                )
            }
        }
    ) { paddingValues ->
        // Pull-to-refresh wrapper
        PullToRefreshContainer(
            isRefreshing = uiState.isLoading && uiState.folders.isNotEmpty(),
            onRefresh = { viewModel.loadFolder(folderId) },
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            Box(modifier = Modifier.fillMaxSize()) {
                when {
                    // Show skeleton loading on initial load
                    uiState.isLoading && uiState.folders.isEmpty() && uiState.files.isEmpty() -> {
                        ListLoadingSkeleton(
                            itemCount = 6,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    // Show enhanced empty state
                    !uiState.isLoading && uiState.folders.isEmpty() && uiState.files.isEmpty() && uiState.error == null -> {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center
                        ) {
                            EnhancedEmptyFolderState(
                                isRootFolder = folderId == null,
                                onCreateFolder = { viewModel.showCreateFolderDialog() },
                                onUploadFile = { filePickerLauncher.launch(arrayOf("*/*")) }
                            )
                        }
                    }
                    // Show content
                    else -> {
                        val displayFolders = uiState.displayFolders
                        val displayFiles = uiState.displayFiles

                        if (uiState.isSearchMode && displayFolders.isEmpty() && displayFiles.isEmpty() && uiState.searchQuery.isNotBlank()) {
                            // Enhanced no search results
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center
                            ) {
                                EmptySearchState(
                                    query = uiState.searchQuery,
                                    onClearSearch = { viewModel.updateSearchQuery("") }
                                )
                            }
                        } else if (uiState.viewMode == ViewMode.LIST) {
                        // List View
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(vertical = 8.dp)
                        ) {
                            itemsIndexed(
                                items = displayFolders,
                                key = { _, folder -> "folder_${folder.id}" }
                            ) { index, folder ->
                                AnimatedListItem(index = index) {
                                    FolderListItem(
                                        folder = folder,
                                        isSelectionMode = uiState.isSelectionMode,
                                        isSelected = viewModel.isFolderSelected(folder.id),
                                        isFavorite = uiState.isFolderFavorite(folder.id),
                                        onClick = {
                                            if (uiState.isSelectionMode) {
                                                viewModel.toggleFolderSelection(folder.id)
                                            } else {
                                                onNavigateToFolder(folder.id)
                                            }
                                        },
                                        onLongClick = {
                                            viewModel.toggleFolderSelection(folder.id)
                                        },
                                        onDelete = { viewModel.deleteFolder(folder.id) },
                                        onToggleFavorite = { viewModel.toggleFolderFavorite(folder.id) }
                                    )
                                }
                            }
                            itemsIndexed(
                                items = displayFiles,
                                key = { _, file -> "file_${file.id}" }
                            ) { index, file ->
                                AnimatedListItem(index = displayFolders.size + index) {
                                    FileListItem(
                                        file = file,
                                        isSelectionMode = uiState.isSelectionMode,
                                        isSelected = viewModel.isFileSelected(file.id),
                                        isFavorite = uiState.isFileFavorite(file.id),
                                        onClick = {
                                            if (uiState.isSelectionMode) {
                                                viewModel.toggleFileSelection(file.id)
                                            } else {
                                                onNavigateToFile(file.id)
                                            }
                                        },
                                        onLongClick = {
                                            viewModel.toggleFileSelection(file.id)
                                        },
                                        onDelete = { viewModel.deleteFile(file.id) },
                                        onToggleFavorite = { viewModel.toggleFileFavorite(file.id) }
                                    )
                                }
                            }
                        }
                    } else {
                        // Grid View
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(minSize = 120.dp),
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            itemsIndexed(
                                items = displayFolders,
                                key = { _, folder -> "folder_${folder.id}" }
                            ) { index, folder ->
                                FolderGridItem(
                                    folder = folder,
                                    isSelectionMode = uiState.isSelectionMode,
                                    isSelected = viewModel.isFolderSelected(folder.id),
                                    isFavorite = uiState.isFolderFavorite(folder.id),
                                    onClick = {
                                        if (uiState.isSelectionMode) {
                                            viewModel.toggleFolderSelection(folder.id)
                                        } else {
                                            onNavigateToFolder(folder.id)
                                        }
                                    },
                                    onLongClick = {
                                        viewModel.toggleFolderSelection(folder.id)
                                    },
                                    onToggleFavorite = { viewModel.toggleFolderFavorite(folder.id) }
                                )
                            }
                            itemsIndexed(
                                items = displayFiles,
                                key = { _, file -> "file_${file.id}" }
                            ) { index, file ->
                                FileGridItem(
                                    file = file,
                                    isSelectionMode = uiState.isSelectionMode,
                                    isSelected = viewModel.isFileSelected(file.id),
                                    isFavorite = uiState.isFileFavorite(file.id),
                                    onClick = {
                                        if (uiState.isSelectionMode) {
                                            viewModel.toggleFileSelection(file.id)
                                        } else {
                                            onNavigateToFile(file.id)
                                        }
                                    },
                                    onLongClick = {
                                        viewModel.toggleFileSelection(file.id)
                                    },
                                    onToggleFavorite = { viewModel.toggleFileFavorite(file.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
        }
    }

    // Create folder dialog
    if (uiState.showCreateFolderDialog) {
        CreateFolderDialog(
            onDismiss = { viewModel.hideCreateFolderDialog() },
            onCreate = { name -> viewModel.createFolder(name) }
        )
    }

    // Move dialog
    if (uiState.showMoveDialog) {
        MoveToFolderDialog(
            folders = uiState.availableFoldersForMove,
            onDismiss = { viewModel.hideMoveDialog() },
            onSelectFolder = { folderId -> viewModel.moveSelected(folderId) }
        )
    }

    // Bulk operation progress dialog
    if (uiState.isBulkOperationInProgress) {
        AlertDialog(
            onDismissRequest = { /* Cannot dismiss during operation */ },
            title = { Text(uiState.bulkOperationMessage ?: "Processing...") },
            text = {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    LinearProgressIndicator(
                        progress = uiState.bulkOperationProgress.toFloat() / uiState.bulkOperationTotal.coerceAtLeast(1),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "${uiState.bulkOperationProgress} / ${uiState.bulkOperationTotal}",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            },
            confirmButton = { /* No buttons during operation */ }
        )
    }

    // Upload progress dialog
    if (uiState.isUploading) {
        AlertDialog(
            onDismissRequest = { /* Cannot dismiss during upload */ },
            title = { Text("Uploading...") },
            text = {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = uiState.uploadFileName ?: "File",
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    LinearProgressIndicator(
                        progress = uiState.uploadProgress / 100f,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "${uiState.uploadProgress}%",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            },
            confirmButton = { /* No buttons during upload */ }
        )
    }

    // Success message snackbar
    LaunchedEffect(uiState.bulkOperationMessage) {
        uiState.bulkOperationMessage?.let { message ->
            if (!uiState.isBulkOperationInProgress) {
                snackbarHostState.showSnackbar(
                    message = message,
                    duration = SnackbarDuration.Short
                )
                viewModel.clearBulkOperationMessage()
            }
        }
    }
}

@Composable
private fun CreateFolderDialog(
    onDismiss: () -> Unit,
    onCreate: (String) -> Unit
) {
    var folderName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Create Folder") },
        text = {
            OutlinedTextField(
                value = folderName,
                onValueChange = { folderName = it },
                label = { Text("Folder name") },
                singleLine = true,
                modifier = Modifier.semantics { contentDescription = "Enter folder name" }
            )
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (folderName.isNotBlank()) {
                        onCreate(folderName)
                    }
                },
                enabled = folderName.isNotBlank()
            ) {
                Text("Create")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

@Composable
private fun MoveToFolderDialog(
    folders: List<Folder>,
    onDismiss: () -> Unit,
    onSelectFolder: (String) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Move to") },
        text = {
            if (folders.isEmpty()) {
                Text(
                    "No other folders available",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                LazyColumn(
                    modifier = Modifier.heightIn(max = 300.dp)
                ) {
                    items(
                        items = folders,
                        key = { it.id }
                    ) { folder ->
                        ListItem(
                            headlineContent = { Text(folder.name) },
                            leadingContent = {
                                Icon(
                                    Icons.Default.Folder,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            },
                            modifier = Modifier.clickable {
                                onSelectFolder(folder.id)
                            }
                        )
                        Divider()
                    }
                }
            }
        },
        confirmButton = { /* Selection handles confirmation */ },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FolderListItem(
    folder: Folder,
    isSelectionMode: Boolean,
    isSelected: Boolean,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onDelete: () -> Unit,
    onToggleFavorite: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }

    ListItem(
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(folder.name)
                if (isFavorite) {
                    Spacer(modifier = Modifier.width(4.dp))
                    Icon(
                        Icons.Filled.Star,
                        contentDescription = "Favorite",
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }
        },
        leadingContent = {
            if (isSelectionMode) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onClick() },
                    modifier = Modifier.semantics { contentDescription = if (isSelected) "Deselect ${folder.name}" else "Select ${folder.name}" }
                )
            } else {
                Icon(
                    Icons.Default.Folder,
                    contentDescription = "Folder",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        },
        trailingContent = {
            if (!isSelectionMode) {
                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        modifier = Modifier.semantics { contentDescription = "More options for ${folder.name}" }
                    ) {
                        Icon(Icons.Default.MoreVert, contentDescription = "More options")
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text(if (isFavorite) "Remove from Favorites" else "Add to Favorites") },
                            onClick = {
                                showMenu = false
                                onToggleFavorite()
                            },
                            leadingIcon = {
                                Icon(
                                    if (isFavorite) Icons.Filled.Star else Icons.Outlined.StarOutline,
                                    contentDescription = null
                                )
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Delete") },
                            onClick = {
                                showMenu = false
                                onDelete()
                            },
                            leadingIcon = {
                                Icon(Icons.Default.Delete, contentDescription = null)
                            }
                        )
                    }
                }
            }
        },
        modifier = Modifier
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            )
            .semantics { contentDescription = "Folder: ${folder.name}" },
        colors = if (isSelected) {
            ListItemDefaults.colors(
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            )
        } else {
            ListItemDefaults.colors()
        }
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FileListItem(
    file: FileItem,
    isSelectionMode: Boolean,
    isSelected: Boolean,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onDelete: () -> Unit,
    onToggleFavorite: () -> Unit
) {
    var showMenu by remember { mutableStateOf(false) }

    ListItem(
        headlineContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(file.name)
                if (isFavorite) {
                    Spacer(modifier = Modifier.width(4.dp))
                    Icon(
                        Icons.Filled.Star,
                        contentDescription = "Favorite",
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }
        },
        supportingContent = { Text(file.formattedSize()) },
        leadingContent = {
            if (isSelectionMode) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onClick() },
                    modifier = Modifier.semantics { contentDescription = if (isSelected) "Deselect ${file.name}" else "Select ${file.name}" }
                )
            } else {
                Icon(
                    imageVector = when {
                        file.isImage() -> Icons.Default.Image
                        file.isPdf() -> Icons.Default.PictureAsPdf
                        file.isVideo() -> Icons.Default.VideoFile
                        file.isAudio() -> Icons.Default.AudioFile
                        else -> Icons.Default.InsertDriveFile
                    },
                    contentDescription = when {
                        file.isImage() -> "Image file"
                        file.isPdf() -> "PDF file"
                        file.isVideo() -> "Video file"
                        file.isAudio() -> "Audio file"
                        else -> "File"
                    },
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        trailingContent = {
            if (!isSelectionMode) {
                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        modifier = Modifier.semantics { contentDescription = "More options for ${file.name}" }
                    ) {
                        Icon(Icons.Default.MoreVert, contentDescription = "More options")
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text(if (isFavorite) "Remove from Favorites" else "Add to Favorites") },
                            onClick = {
                                showMenu = false
                                onToggleFavorite()
                            },
                            leadingIcon = {
                                Icon(
                                    if (isFavorite) Icons.Filled.Star else Icons.Outlined.StarOutline,
                                    contentDescription = null
                                )
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Delete") },
                            onClick = {
                                showMenu = false
                                onDelete()
                            },
                            leadingIcon = {
                                Icon(Icons.Default.Delete, contentDescription = null)
                            }
                        )
                    }
                }
            }
        },
        modifier = Modifier
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            )
            .semantics { contentDescription = "File: ${file.name}, Size: ${file.formattedSize()}" },
        colors = if (isSelected) {
            ListItemDefaults.colors(
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            )
        } else {
            ListItemDefaults.colors()
        }
    )
}

// ==================== Grid Item Components ====================

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FolderGridItem(
    folder: Folder,
    isSelectionMode: Boolean,
    isSelected: Boolean,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onToggleFavorite: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            )
            .semantics { contentDescription = "Folder: ${folder.name}" },
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected)
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
            else
                MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    Icons.Default.Folder,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = folder.name,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center
                )
            }

            // Selection checkbox
            if (isSelectionMode) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onClick() },
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(4.dp)
                )
            }

            // Favorite star
            if (isFavorite) {
                Icon(
                    Icons.Filled.Star,
                    contentDescription = "Favorite",
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(8.dp)
                        .size(16.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FileGridItem(
    file: FileItem,
    isSelectionMode: Boolean,
    isSelected: Boolean,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onToggleFavorite: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            )
            .semantics { contentDescription = "File: ${file.name}" },
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected)
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f)
            else
                MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    imageVector = when {
                        file.isImage() -> Icons.Default.Image
                        file.isPdf() -> Icons.Default.PictureAsPdf
                        file.isVideo() -> Icons.Default.VideoFile
                        file.isAudio() -> Icons.Default.AudioFile
                        else -> Icons.Default.InsertDriveFile
                    },
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = file.name,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center
                )
                Text(
                    text = file.formattedSize(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Selection checkbox
            if (isSelectionMode) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onClick() },
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(4.dp)
                )
            }

            // Favorite star
            if (isFavorite) {
                Icon(
                    Icons.Filled.Star,
                    contentDescription = "Favorite",
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(8.dp)
                        .size(16.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}
