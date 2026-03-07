package my.ssdid.drive.presentation.piichat.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import my.ssdid.drive.domain.model.LlmProvider

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewConversationDialog(
    title: String,
    onTitleChange: (String) -> Unit,
    selectedProviderId: String,
    onProviderChange: (String) -> Unit,
    selectedModel: String,
    onModelChange: (String) -> Unit,
    isCreating: Boolean,
    onDismiss: () -> Unit,
    onCreate: () -> Unit
) {
    val selectedProvider = LlmProvider.findById(selectedProviderId)

    AlertDialog(
        onDismissRequest = { if (!isCreating) onDismiss() },
        title = { Text("New Conversation") },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Title input
                OutlinedTextField(
                    value = title,
                    onValueChange = onTitleChange,
                    label = { Text("Title (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isCreating,
                    singleLine = true
                )

                // Provider selection
                Text(
                    text = "AI Provider",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    LlmProvider.providers.forEach { provider ->
                        FilterChip(
                            selected = selectedProviderId == provider.id,
                            onClick = { onProviderChange(provider.id) },
                            label = { Text(provider.name) },
                            enabled = !isCreating
                        )
                    }
                }

                // Model selection
                Text(
                    text = "Model",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Column(
                    modifier = Modifier.selectableGroup()
                ) {
                    selectedProvider?.models?.forEach { model ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(48.dp)
                                .selectable(
                                    selected = selectedModel == model,
                                    onClick = { onModelChange(model) },
                                    role = Role.RadioButton,
                                    enabled = !isCreating
                                )
                                .padding(horizontal = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            RadioButton(
                                selected = selectedModel == model,
                                onClick = null,
                                enabled = !isCreating
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = model,
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }

                // Security info banner
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        Icon(
                            imageVector = Icons.Default.VerifiedUser,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(
                                text = "Post-quantum encryption enabled",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = "Your personal information will be automatically detected, tokenized, and protected using ML-KEM and KAZ-KEM encryption.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onCreate,
                enabled = !isCreating
            ) {
                if (isCreating) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text("Create")
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                enabled = !isCreating
            ) {
                Text("Cancel")
            }
        }
    )
}
