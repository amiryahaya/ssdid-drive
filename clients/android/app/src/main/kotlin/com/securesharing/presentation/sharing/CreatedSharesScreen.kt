package com.securesharing.presentation.sharing

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
import com.securesharing.presentation.common.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreatedSharesScreen(
    onNavigateBack: () -> Unit,
    viewModel: SharesViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedShare by remember { mutableStateOf<com.securesharing.domain.model.Share?>(null) }

    LaunchedEffect(Unit) {
        viewModel.loadCreatedShares()
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
                viewModel.loadCreatedShares()
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("My Shares") },
                navigationIcon = {
                    IconButton(
                        onClick = onNavigateBack,
                        modifier = Modifier.semantics { contentDescription = "Navigate back" }
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.loadCreatedShares() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
                uiState.isLoading && uiState.createdShares.isEmpty() -> {
                    ListLoadingSkeleton(
                        itemCount = 5,
                        modifier = Modifier.fillMaxSize()
                    )
                }
                // Show empty state
                !uiState.isLoading && uiState.createdShares.isEmpty() && uiState.error == null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        EmptySharesState(isReceived = false)
                    }
                }
                // Show content
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(vertical = 8.dp)
                    ) {
                        itemsIndexed(
                            items = uiState.createdShares,
                            key = { _, share -> share.id }
                        ) { index, share ->
                            AnimatedListItem(index = index) {
                                ShareItem(
                                    share = share,
                                    isReceived = false,
                                    onClick = { selectedShare = share },
                                    onRevoke = { viewModel.revokeShare(share.id) }
                                )
                            }
                        }
                    }
                }
            }

            // Share Details Dialog
            selectedShare?.let { share ->
                ShareDetailsDialog(
                    share = share,
                    onDismiss = { selectedShare = null },
                    onRevoke = {
                        viewModel.revokeShare(share.id)
                        selectedShare = null
                    }
                )
            }
        }
    }
}
