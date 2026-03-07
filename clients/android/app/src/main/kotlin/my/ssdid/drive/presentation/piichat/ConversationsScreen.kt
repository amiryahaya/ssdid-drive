package my.ssdid.drive.presentation.piichat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import my.ssdid.drive.domain.model.Conversation
import my.ssdid.drive.domain.model.LlmProvider
import my.ssdid.drive.presentation.piichat.components.NewConversationDialog
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationsScreen(
    onNavigateBack: () -> Unit,
    onNavigateToChat: (String) -> Unit,
    viewModel: ConversationsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    // Handle navigation events
    LaunchedEffect(uiState.navigateToChat) {
        uiState.navigateToChat?.let { conversationId ->
            onNavigateToChat(conversationId)
            viewModel.clearNavigationEvent()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("AI Chat") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.showNewConversationDialog() }) {
                        Icon(Icons.Default.Add, "New Chat")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { viewModel.showNewConversationDialog() }
            ) {
                Icon(Icons.Default.Edit, "New Chat")
            }
        }
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
                uiState.conversations.isEmpty() -> {
                    EmptyConversationsState(
                        onNewChat = { viewModel.showNewConversationDialog() }
                    )
                }
                else -> {
                    ConversationList(
                        conversations = uiState.conversations,
                        onConversationClick = { onNavigateToChat(it.id) },
                        onDeleteConversation = { viewModel.deleteConversation(it.id) }
                    )
                }
            }

            // Error snackbar
            uiState.error?.let { error ->
                Snackbar(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(16.dp),
                    action = {
                        TextButton(onClick = { viewModel.clearError() }) {
                            Text("Dismiss")
                        }
                    }
                ) {
                    Text(error)
                }
            }
        }
    }

    // New conversation dialog
    if (uiState.showNewConversationDialog) {
        NewConversationDialog(
            title = uiState.newConversationTitle,
            onTitleChange = { viewModel.setNewConversationTitle(it) },
            selectedProviderId = uiState.selectedProviderId,
            onProviderChange = { viewModel.selectProvider(it) },
            selectedModel = uiState.selectedModel,
            onModelChange = { viewModel.selectModel(it) },
            isCreating = uiState.isCreating,
            onDismiss = { viewModel.hideNewConversationDialog() },
            onCreate = { viewModel.createConversation() }
        )
    }
}

@Composable
private fun EmptyConversationsState(onNewChat: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.ChatBubbleOutline,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No conversations yet",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Start a secure AI conversation with\npost-quantum encryption.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
        )
        Spacer(modifier = Modifier.height(24.dp))
        Button(onClick = onNewChat) {
            Icon(Icons.Default.Add, null)
            Spacer(modifier = Modifier.width(8.dp))
            Text("New Chat")
        }
    }
}

@Composable
private fun ConversationList(
    conversations: List<Conversation>,
    onConversationClick: (Conversation) -> Unit,
    onDeleteConversation: (Conversation) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = 8.dp)
    ) {
        items(conversations, key = { it.id }) { conversation ->
            ConversationItem(
                conversation = conversation,
                onClick = { onConversationClick(conversation) },
                onDelete = { onDeleteConversation(conversation) }
            )
        }
    }
}

@Composable
private fun ConversationItem(
    conversation: Conversation,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    ListItem(
        modifier = Modifier.clickable(onClick = onClick),
        headlineContent = {
            Text(
                text = conversation.title ?: "Untitled Chat",
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        },
        supportingContent = {
            Column {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Provider badge
                    val providerName = LlmProvider.findById(conversation.llmProvider)?.name
                        ?: conversation.llmProvider
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant
                    ) {
                        Text(
                            text = providerName,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                    Text(
                        text = conversation.llmModel,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = formatDate(conversation.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        leadingContent = {
            // KEM status indicator
            Icon(
                imageVector = if (conversation.hasKemKeysRegistered) {
                    Icons.Default.VerifiedUser
                } else {
                    Icons.Default.Shield
                },
                contentDescription = if (conversation.hasKemKeysRegistered) {
                    "Encrypted"
                } else {
                    "Not encrypted yet"
                },
                tint = if (conversation.hasKemKeysRegistered) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        },
        trailingContent = {
            IconButton(onClick = onDelete) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.error
                )
            }
        }
    )
}

private fun formatDate(instant: Instant): String {
    val formatter = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT)
        .withZone(ZoneId.systemDefault())
    return formatter.format(instant)
}
