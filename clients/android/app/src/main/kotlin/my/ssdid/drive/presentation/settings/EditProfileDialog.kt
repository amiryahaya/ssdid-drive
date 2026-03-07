package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Dialog for editing user profile (display name).
 */
@Composable
fun EditProfileDialog(
    currentDisplayName: String?,
    isLoading: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var displayName by remember { mutableStateOf(currentDisplayName ?: "") }

    AlertDialog(
        onDismissRequest = { if (!isLoading) onDismiss() },
        icon = {
            Icon(
                imageVector = Icons.Default.Person,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        },
        title = {
            Text("Edit Profile")
        },
        text = {
            Column {
                OutlinedTextField(
                    value = displayName,
                    onValueChange = { displayName = it },
                    label = { Text("Display Name") },
                    placeholder = { Text("Enter your name") },
                    singleLine = true,
                    enabled = !isLoading,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = {
                        Text("This name will be shown to others when sharing files")
                    }
                )

                if (error != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = error,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall
                    )
                }

                if (isLoading) {
                    Spacer(modifier = Modifier.height(16.dp))
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(displayName) },
                enabled = !isLoading
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                enabled = !isLoading
            ) {
                Text("Cancel")
            }
        }
    )
}
