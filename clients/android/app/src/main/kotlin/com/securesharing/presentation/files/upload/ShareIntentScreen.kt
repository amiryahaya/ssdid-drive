package com.securesharing.presentation.files.upload

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.securesharing.domain.model.Folder

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareIntentScreen(
    onNavigateBack: () -> Unit,
    onUploadComplete: () -> Unit,
    viewModel: ShareIntentViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate when upload is complete
    LaunchedEffect(uiState.uploadComplete) {
        if (uiState.uploadComplete) {
            if (uiState.failCount == 0) {
                snackbarHostState.showSnackbar(
                    message = "${uiState.successCount} file(s) uploaded successfully",
                    duration = SnackbarDuration.Short
                )
            }
            onUploadComplete()
        }
    }

    // Show error
    LaunchedEffect(uiState.error) {
        uiState.error?.let { error ->
            snackbarHostState.showSnackbar(
                message = error,
                duration = SnackbarDuration.Short
            )
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Upload Files") },
                navigationIcon = {
                    IconButton(
                        onClick = {
                            viewModel.cancel()
                            onNavigateBack()
                        }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            Surface(
                tonalElevation = 3.dp
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            viewModel.cancel()
                            onNavigateBack()
                        },
                        modifier = Modifier.weight(1f),
                        enabled = !uiState.isUploading
                    ) {
                        Text("Cancel")
                    }
                    Button(
                        onClick = { viewModel.uploadFiles() },
                        modifier = Modifier.weight(1f),
                        enabled = !uiState.isUploading &&
                                uiState.pendingFiles.isNotEmpty() &&
                                uiState.selectedFolderId != null
                    ) {
                        if (uiState.isUploading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                        }
                        Text(if (uiState.isUploading) "Uploading..." else "Upload")
                    }
                }
            }
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Destination folder selector
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .clickable(enabled = !uiState.isUploading) {
                        viewModel.showFolderPicker()
                    },
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Folder,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "Upload to",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            uiState.selectedFolderName,
                            style = MaterialTheme.typography.bodyLarge
                        )
                    }
                    Icon(
                        Icons.Default.ChevronRight,
                        contentDescription = "Select folder",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Upload progress
            if (uiState.isUploading) {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp)
                    ) {
                        Text(
                            "Uploading ${uiState.uploadProgress} of ${uiState.uploadTotal}",
                            style = MaterialTheme.typography.bodyMedium
                        )
                        if (uiState.currentFileName != null) {
                            Text(
                                uiState.currentFileName!!,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        LinearProgressIndicator(
                            progress = uiState.uploadProgress.toFloat() / uiState.uploadTotal.coerceAtLeast(1),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
            }

            // Files header
            Text(
                "${uiState.pendingFiles.size} file(s) to upload",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )

            // File list
            if (uiState.pendingFiles.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.AutoMirrored.Filled.InsertDriveFile,
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            "No files to upload",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 16.dp)
                ) {
                    items(
                        items = uiState.pendingFiles,
                        key = { it.uri.toString() }
                    ) { file ->
                        PendingFileItem(
                            file = file,
                            formattedSize = viewModel.formatFileSize(file.size),
                            onRemove = { viewModel.removeFile(file.uri) },
                            enabled = !uiState.isUploading
                        )
                    }
                }
            }
        }
    }

    // Folder picker dialog
    if (uiState.showFolderPicker) {
        FolderPickerDialog(
            folders = uiState.folders,
            isLoading = uiState.isLoadingFolders,
            onDismiss = { viewModel.hideFolderPicker() },
            onSelectFolder = { viewModel.selectFolder(it) }
        )
    }
}

@Composable
private fun PendingFileItem(
    file: PendingFile,
    formattedSize: String,
    onRemove: () -> Unit,
    enabled: Boolean
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // File icon based on mime type
            Icon(
                imageVector = getFileIcon(file.mimeType),
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(40.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    file.name,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    formattedSize,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(
                onClick = onRemove,
                enabled = enabled
            ) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "Remove file",
                    tint = if (enabled)
                        MaterialTheme.colorScheme.onSurfaceVariant
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f)
                )
            }
        }
    }
}

@Composable
private fun FolderPickerDialog(
    folders: List<Folder>,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onSelectFolder: (Folder) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Select Destination") },
        text = {
            if (isLoading) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(200.dp),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else if (folders.isEmpty()) {
                Text("No folders available")
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
                                    if (folder.isRoot) Icons.Default.Home else Icons.Default.Folder,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            },
                            modifier = Modifier.clickable {
                                onSelectFolder(folder)
                            }
                        )
                        Divider()
                    }
                }
            }
        },
        confirmButton = { },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

private fun getFileIcon(mimeType: String): androidx.compose.ui.graphics.vector.ImageVector {
    return when {
        mimeType.startsWith("image/") -> Icons.Default.Image
        mimeType.startsWith("video/") -> Icons.Default.VideoFile
        mimeType.startsWith("audio/") -> Icons.Default.AudioFile
        mimeType == "application/pdf" -> Icons.Default.PictureAsPdf
        mimeType.contains("document") || mimeType.contains("text") -> Icons.Default.Description
        mimeType.contains("spreadsheet") || mimeType.contains("excel") -> Icons.Default.TableChart
        mimeType.contains("presentation") || mimeType.contains("powerpoint") -> Icons.Default.Slideshow
        mimeType.contains("zip") || mimeType.contains("archive") -> Icons.Default.FolderZip
        else -> Icons.AutoMirrored.Filled.InsertDriveFile
    }
}
