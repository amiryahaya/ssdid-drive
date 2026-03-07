package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/**
 * Dialog showing open source licenses.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LicensesDialog(
    onDismiss: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            shape = MaterialTheme.shapes.large
        ) {
            Column {
                TopAppBar(
                    title = { Text("Open Source Licenses") },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = "Close")
                        }
                    }
                )

                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    items(openSourceLicenses) { license ->
                        LicenseItem(license = license)
                    }
                }
            }
        }
    }
}

@Composable
private fun LicenseItem(license: License) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Text(
                text = license.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = license.version,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = license.licenseType,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary
            )
            if (license.description != null) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = license.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private data class License(
    val name: String,
    val version: String,
    val licenseType: String,
    val description: String? = null
)

private val openSourceLicenses = listOf(
    License(
        name = "Jetpack Compose",
        version = "1.6.0",
        licenseType = "Apache License 2.0",
        description = "Android's modern toolkit for building native UI"
    ),
    License(
        name = "Hilt",
        version = "2.50",
        licenseType = "Apache License 2.0",
        description = "Dependency injection library for Android"
    ),
    License(
        name = "Retrofit",
        version = "2.9.0",
        licenseType = "Apache License 2.0",
        description = "Type-safe HTTP client for Android"
    ),
    License(
        name = "OkHttp",
        version = "4.12.0",
        licenseType = "Apache License 2.0",
        description = "HTTP client for Android"
    ),
    License(
        name = "Room",
        version = "2.6.1",
        licenseType = "Apache License 2.0",
        description = "SQLite abstraction library"
    ),
    License(
        name = "Coil",
        version = "2.5.0",
        licenseType = "Apache License 2.0",
        description = "Image loading library for Android"
    ),
    License(
        name = "Bouquet",
        version = "1.1.2",
        licenseType = "Apache License 2.0",
        description = "PDF viewer library for Compose"
    ),
    License(
        name = "KAZ-KEM",
        version = "1.0.0",
        licenseType = "Proprietary",
        description = "Post-quantum key encapsulation mechanism"
    ),
    License(
        name = "KAZ-Sign",
        version = "1.0.0",
        licenseType = "Proprietary",
        description = "Post-quantum digital signature algorithm"
    ),
    License(
        name = "OneSignal",
        version = "5.1.6",
        licenseType = "Apache License 2.0",
        description = "Push notification service"
    ),
    License(
        name = "DataStore",
        version = "1.0.0",
        licenseType = "Apache License 2.0",
        description = "Data storage solution for key-value pairs"
    )
)
