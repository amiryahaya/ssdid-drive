package my.ssdid.drive.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
 * Dialog showing the privacy policy.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyPolicyDialog(
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
                    title = { Text("Privacy Policy") },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = "Close")
                        }
                    }
                )

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    PolicySection(
                        title = "Data Collection",
                        content = """
                            SSDID Drive collects only the minimum data necessary to provide our secure file sharing service:

                            • Account information (email address)
                            • Files you upload (encrypted end-to-end)
                            • Sharing preferences and settings
                            • Device information for security purposes
                        """.trimIndent()
                    )

                    PolicySection(
                        title = "End-to-End Encryption",
                        content = """
                            All files are encrypted on your device before being uploaded. We use:

                            • AES-256-GCM for file encryption
                            • Post-quantum cryptography (KAZ-KEM) for key exchange
                            • Digital signatures (KAZ-Sign) for authenticity

                            Your encryption keys are derived from your password and never leave your device in plaintext.
                        """.trimIndent()
                    )

                    PolicySection(
                        title = "Data Storage",
                        content = """
                            • Encrypted files are stored on secure cloud infrastructure
                            • We cannot access the contents of your files
                            • Metadata (file names, sizes) may be visible to administrators
                            • Data is stored in compliance with applicable regulations
                        """.trimIndent()
                    )

                    PolicySection(
                        title = "Data Sharing",
                        content = """
                            We do not sell or share your personal data with third parties except:

                            • When required by law
                            • To protect our rights and safety
                            • With your explicit consent

                            Files are only shared with users you explicitly authorize.
                        """.trimIndent()
                    )

                    PolicySection(
                        title = "Your Rights",
                        content = """
                            You have the right to:

                            • Access your personal data
                            • Delete your account and data
                            • Export your data
                            • Revoke file sharing access at any time

                            Contact your administrator for data requests.
                        """.trimIndent()
                    )

                    PolicySection(
                        title = "Security",
                        content = """
                            We implement industry-standard security measures:

                            • TLS 1.3 for all network communications
                            • Certificate pinning to prevent MITM attacks
                            • Biometric authentication support
                            • Automatic session timeouts
                            • Device enrollment verification
                        """.trimIndent()
                    )

                    PolicySection(
                        title = "Contact",
                        content = """
                            For privacy-related inquiries, please contact your organization's administrator or our privacy team.

                            Last updated: January 2026
                        """.trimIndent()
                    )
                }
            }
        }
    }
}

@Composable
private fun PolicySection(
    title: String,
    content: String
) {
    Column {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = content,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}
