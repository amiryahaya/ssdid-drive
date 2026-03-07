package com.securesharing.presentation.recovery

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.securesharing.domain.model.User

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrusteeSelectionScreen(
    totalShares: Int,
    onNavigateBack: () -> Unit,
    onComplete: () -> Unit,
    viewModel: TrusteeSelectionViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(totalShares) {
        viewModel.initialize(totalShares)
    }

    LaunchedEffect(uiState.isDistributionComplete) {
        if (uiState.isDistributionComplete) {
            onComplete()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Select Trustees") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            when {
                uiState.isLoading && uiState.availableUsers.isEmpty() -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center)
                    )
                }

                uiState.availableUsers.isEmpty() -> {
                    EmptyTrusteesContent()
                }

                else -> {
                    TrusteeSelectionContent(
                        availableUsers = uiState.availableUsers,
                        selectedTrustees = uiState.selectedTrustees,
                        distributedShares = uiState.distributedShares.size,
                        currentShareIndex = uiState.currentShareIndex,
                        totalShares = uiState.totalShares,
                        isLoading = uiState.isLoading,
                        onSelectTrustee = { viewModel.selectTrustee(it) },
                        onDeselectTrustee = { viewModel.deselectTrustee(it) },
                        onDistribute = { viewModel.distributeShare(it) },
                        error = uiState.error,
                        onDismissError = { viewModel.clearError() }
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyTrusteesContent() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Default.PersonOff,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "No Users Available",
            style = MaterialTheme.typography.titleLarge
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "There are no other users in your organization to serve as trustees.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TrusteeSelectionContent(
    availableUsers: List<User>,
    selectedTrustees: List<User>,
    distributedShares: Int,
    currentShareIndex: Int,
    totalShares: Int,
    isLoading: Boolean,
    onSelectTrustee: (User) -> Unit,
    onDeselectTrustee: (User) -> Unit,
    onDistribute: (User) -> Unit,
    error: String?,
    onDismissError: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Progress header
        LinearProgressIndicator(
            progress = distributedShares.toFloat() / totalShares,
            modifier = Modifier.fillMaxWidth()
        )

        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            )
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Distribution Progress",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = "Share $currentShareIndex of $totalShares",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = "$distributedShares / $totalShares",
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }

        // Selected trustees chips
        if (selectedTrustees.isNotEmpty()) {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp)
            ) {
                Text(
                    text = "Selected Trustees",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Spacer(modifier = Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    selectedTrustees.forEach { trustee ->
                        FilterChip(
                            selected = true,
                            onClick = { onDeselectTrustee(trustee) },
                            label = { Text(trustee.email) },
                            trailingIcon = {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = "Remove",
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }

        // Available users list
        Text(
            text = "Available Users",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp)
        )

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            val usersToShow = availableUsers.filter { user ->
                !selectedTrustees.any { it.id == user.id }
            }

            items(usersToShow) { user ->
                TrusteeUserItem(
                    user = user,
                    isSelected = false,
                    canSelect = selectedTrustees.size < totalShares - distributedShares,
                    isLoading = isLoading,
                    onSelect = { onSelectTrustee(user) },
                    onDistribute = { onDistribute(user) }
                )
            }

            // Show selected trustees pending distribution
            items(selectedTrustees) { user ->
                TrusteeUserItem(
                    user = user,
                    isSelected = true,
                    canSelect = true,
                    isLoading = isLoading,
                    onSelect = { onDeselectTrustee(user) },
                    onDistribute = { onDistribute(user) }
                )
            }
        }

        // Error snackbar
        if (error != null) {
            Snackbar(
                action = {
                    TextButton(onClick = onDismissError) {
                        Text("Dismiss")
                    }
                },
                modifier = Modifier.padding(16.dp)
            ) {
                Text(error)
            }
        }
    }
}

@Composable
private fun TrusteeUserItem(
    user: User,
    isSelected: Boolean,
    canSelect: Boolean,
    isLoading: Boolean,
    onSelect: () -> Unit,
    onDistribute: () -> Unit
) {
    ListItem(
        headlineContent = {
            Text(user.email)
        },
        supportingContent = {
            Text(
                (user.role?.name ?: "User").lowercase().replaceFirstChar { it.uppercase() },
                style = MaterialTheme.typography.bodySmall
            )
        },
        leadingContent = {
            Icon(
                if (isSelected) Icons.Default.CheckCircle else Icons.Default.Person,
                contentDescription = null,
                tint = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        trailingContent = {
            if (isSelected) {
                Button(
                    onClick = onDistribute,
                    enabled = !isLoading,
                    modifier = Modifier.height(36.dp)
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(
                            Icons.AutoMirrored.Filled.Send,
                            contentDescription = "Send",
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Send", style = MaterialTheme.typography.labelMedium)
                    }
                }
            } else if (canSelect) {
                IconButton(onClick = onSelect) {
                    Icon(Icons.Default.Add, contentDescription = "Select")
                }
            }
        },
        modifier = Modifier.clickable(enabled = !isSelected && canSelect) { onSelect() }
    )
}
