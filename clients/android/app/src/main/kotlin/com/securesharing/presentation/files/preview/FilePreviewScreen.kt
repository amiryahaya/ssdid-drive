package com.securesharing.presentation.files.preview

import android.app.Activity
import android.net.Uri
import android.view.WindowManager
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rizzi.bouquet.ResourceType
import com.rizzi.bouquet.VerticalPDFReader
import com.rizzi.bouquet.rememberVerticalPdfReaderState
import com.securesharing.presentation.common.ErrorState
import com.securesharing.presentation.common.ListLoadingSkeleton

/**
 * File preview screen that displays different content based on file type.
 * Supports: images (with zoom), PDFs, text files, and other file types.
 *
 * SECURITY: Screenshot and screen recording are disabled while viewing documents
 * to protect sensitive content from unauthorized capture.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilePreviewScreen(
    fileId: String,
    onNavigateBack: () -> Unit,
    onShare: (String) -> Unit,
    onDownload: (String) -> Unit,
    viewModel: FilePreviewViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    // SECURITY: Enable screenshot prevention when viewing documents
    // This blocks screenshots, screen recordings, and display on non-secure screens
    DisposableEffect(Unit) {
        val activity = context as? Activity
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        onDispose {
            // Restore screenshot capability when leaving the preview screen
            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    LaunchedEffect(fileId) {
        viewModel.loadFile(fileId)
    }

    // Show snackbar for messages
    LaunchedEffect(uiState.message) {
        uiState.message?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearMessage()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = uiState.file?.name ?: "File Preview",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                },
                navigationIcon = {
                    IconButton(
                        onClick = onNavigateBack,
                        modifier = Modifier.semantics { contentDescription = "Navigate back" }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    uiState.file?.let { file ->
                        IconButton(
                            onClick = { onShare(file.id) },
                            modifier = Modifier.semantics { contentDescription = "Share file" }
                        ) {
                            Icon(Icons.Default.Share, contentDescription = "Share")
                        }
                        IconButton(
                            onClick = { onDownload(file.id) },
                            modifier = Modifier.semantics { contentDescription = "Download file" }
                        ) {
                            Icon(Icons.Default.Download, contentDescription = "Download")
                        }
                        IconButton(
                            onClick = { viewModel.toggleFavorite() },
                            modifier = Modifier.semantics {
                                contentDescription = if (uiState.isFavorite) "Remove from favorites" else "Add to favorites"
                            }
                        ) {
                            Icon(
                                if (uiState.isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                                contentDescription = if (uiState.isFavorite) "Unfavorite" else "Favorite",
                                tint = if (uiState.isFavorite) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
                            )
                        }
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
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        CircularProgressIndicator()
                        Spacer(modifier = Modifier.height(16.dp))
                        Text(
                            text = uiState.loadingMessage ?: "Loading file...",
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
                uiState.error != null -> {
                    ErrorState(
                        message = uiState.error!!,
                        onRetry = { viewModel.loadFile(fileId) },
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
                uiState.file != null -> {
                    val file = uiState.file!!
                    when {
                        file.isImage() -> ImagePreview(
                            uri = uiState.decryptedUri,
                            contentDescription = file.name
                        )
                        file.isPdf() -> PdfPreview(
                            uri = uiState.decryptedUri,
                            fileName = file.name
                        )
                        file.isText() -> TextPreview(
                            content = uiState.textContent,
                            fileName = file.name
                        )
                        else -> UnsupportedPreview(
                            file = file,
                            onDownload = { onDownload(file.id) }
                        )
                    }
                }
            }
        }
    }
}

/**
 * Image preview with pinch-to-zoom and pan support.
 */
@Composable
private fun ImagePreview(
    uri: Uri?,
    contentDescription: String
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    scale = (scale * zoom).coerceIn(0.5f, 5f)
                    offsetX += pan.x
                    offsetY += pan.y
                }
            },
        contentAlignment = Alignment.Center
    ) {
        if (uri != null) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(uri)
                    .crossfade(true)
                    .build(),
                contentDescription = contentDescription,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer(
                        scaleX = scale,
                        scaleY = scale,
                        translationX = offsetX,
                        translationY = offsetY
                    ),
                contentScale = ContentScale.Fit
            )
        } else {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(16.dp))
                Text("Decrypting image...")
            }
        }
    }

    // Zoom controls
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.BottomEnd
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Zoom buttons with proper 48dp touch targets for accessibility
            SmallFloatingActionButton(
                onClick = { scale = (scale * 0.8f).coerceIn(0.5f, 5f) },
                modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp),
                containerColor = MaterialTheme.colorScheme.secondaryContainer
            ) {
                Icon(Icons.Default.ZoomOut, contentDescription = "Zoom out")
            }
            SmallFloatingActionButton(
                onClick = {
                    scale = 1f
                    offsetX = 0f
                    offsetY = 0f
                },
                modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp),
                containerColor = MaterialTheme.colorScheme.secondaryContainer
            ) {
                Icon(Icons.Default.FitScreen, contentDescription = "Reset zoom")
            }
            SmallFloatingActionButton(
                onClick = { scale = (scale * 1.25f).coerceIn(0.5f, 5f) },
                modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp),
                containerColor = MaterialTheme.colorScheme.secondaryContainer
            ) {
                Icon(Icons.Default.ZoomIn, contentDescription = "Zoom in")
            }
        }
    }
}

/**
 * PDF preview using Bouquet PDF viewer library.
 * Supports pinch-to-zoom and vertical scrolling.
 */
@Composable
private fun PdfPreview(
    uri: Uri?,
    fileName: String
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center
    ) {
        if (uri != null) {
            // Create PDF reader state with the local URI
            val pdfState = rememberVerticalPdfReaderState(
                resource = ResourceType.Local(uri),
                isZoomEnable = true
            )

            // Show loading indicator while PDF is being rendered
            if (!pdfState.isLoaded) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator()
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "Loading PDF...",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            // PDF viewer with vertical scrolling
            VerticalPDFReader(
                state = pdfState,
                modifier = Modifier.fillMaxSize()
            )

            // Page indicator overlay
            if (pdfState.isLoaded && pdfState.pdfPageCount > 1) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(16.dp),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.9f),
                        shape = MaterialTheme.shapes.small
                    ) {
                        Text(
                            text = "Page ${pdfState.currentPage + 1} of ${pdfState.pdfPageCount}",
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                        )
                    }
                }
            }

            // Error handling - show error UI if PDF loaded but file is null
            if (pdfState.file == null && pdfState.isLoaded) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(32.dp)
                ) {
                    Icon(
                        Icons.Default.PictureAsPdf,
                        contentDescription = null,
                        modifier = Modifier.size(80.dp),
                        tint = MaterialTheme.colorScheme.error
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "Unable to load PDF",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "The file may be corrupted or password-protected",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(16.dp))
                Text("Decrypting PDF...")
            }
        }
    }
}

/**
 * Text file preview with syntax highlighting for code files.
 */
@Composable
private fun TextPreview(
    content: String?,
    fileName: String
) {
    val scrollState = rememberScrollState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface)
    ) {
        // File info header
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Default.Description,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = fileName,
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }

        // Text content
        if (content != null) {
            Text(
                text = content,
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(16.dp),
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace
                )
            )
        } else {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator()
                    Spacer(modifier = Modifier.height(16.dp))
                    Text("Decrypting text...")
                }
            }
        }
    }
}

/**
 * Fallback preview for unsupported file types.
 */
@Composable
private fun UnsupportedPreview(
    file: com.securesharing.domain.model.FileItem,
    onDownload: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = when {
                file.isVideo() -> Icons.Default.VideoFile
                file.isAudio() -> Icons.Default.AudioFile
                else -> Icons.Default.InsertDriveFile
            },
            contentDescription = null,
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = file.name,
            style = MaterialTheme.typography.titleMedium
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = file.formattedSize(),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = file.mimeType,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        Text(
            text = "Preview not available for this file type",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        Button(onClick = onDownload) {
            Icon(Icons.Default.Download, contentDescription = null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("Download to view")
        }
    }
}
