package my.ssdid.drive.presentation.recovery

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

// Maximum number of times the user can dismiss the banner before it stops showing
private const val MAX_DISMISSALS = 3
private const val PREF_NAME = "recovery_banner_prefs"
private const val KEY_DISMISS_COUNT = "dismiss_count"

/**
 * A prominent warning banner encouraging users to set up account recovery.
 * Shown when recovery is not configured. Tracks dismissals (max 3) using
 * SharedPreferences so it eventually stops nagging.
 */
@Composable
fun RecoveryBanner(
    onSetupClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var visible by remember { mutableStateOf(false) }

    // Read dismiss count on launch and decide whether to show
    LaunchedEffect(Unit) {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val dismissCount = prefs.getInt(KEY_DISMISS_COUNT, 0)
        visible = dismissCount < MAX_DISMISSALS
    }

    AnimatedVisibility(
        visible = visible,
        enter = expandVertically(),
        exit = shrinkVertically(),
        modifier = modifier
    ) {
        RecoveryBannerContent(
            onSetupClick = {
                visible = false
                onSetupClick()
            },
            onDismiss = {
                scope.launch {
                    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                    val current = prefs.getInt(KEY_DISMISS_COUNT, 0)
                    prefs.edit().putInt(KEY_DISMISS_COUNT, current + 1).apply()
                    visible = false
                }
            }
        )
    }
}

@Composable
private fun RecoveryBannerContent(
    onSetupClick: () -> Unit,
    onDismiss: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.Shield,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onErrorContainer
            )

            Spacer(modifier = Modifier.width(12.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Recovery Not Configured",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
                Text(
                    text = "Set up account recovery to avoid losing access to your files if you lose this device.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer
                )
                Spacer(modifier = Modifier.height(8.dp))
                TextButton(
                    onClick = onSetupClick,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    ),
                    contentPadding = PaddingValues(0.dp)
                ) {
                    Text(
                        text = "Set Up Recovery",
                        fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.labelMedium
                    )
                }
            }

            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(32.dp)
            ) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "Dismiss",
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onErrorContainer
                )
            }
        }
    }
}

/**
 * Reset the banner dismiss count — useful for testing or when recovery is deleted.
 */
fun resetRecoveryBannerDismissCount(context: Context) {
    context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        .edit()
        .remove(KEY_DISMISS_COUNT)
        .apply()
}
