package my.ssdid.drive.presentation.piichat.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import my.ssdid.drive.domain.model.ChatMessage
import my.ssdid.drive.domain.model.MessageRole
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun MessageBubble(message: ChatMessage) {
    val isUser = message.role == MessageRole.USER

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        if (!isUser) {
            // Assistant avatar
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.SmartToy,
                    contentDescription = "AI",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(18.dp)
                )
            }
            Spacer(modifier = Modifier.width(8.dp))
        }

        Column(
            horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
            modifier = Modifier.widthIn(max = 280.dp)
        ) {
            // Message bubble
            Surface(
                shape = RoundedCornerShape(
                    topStart = 16.dp,
                    topEnd = 16.dp,
                    bottomStart = if (isUser) 16.dp else 4.dp,
                    bottomEnd = if (isUser) 4.dp else 16.dp
                ),
                color = if (isUser) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.surfaceVariant
                },
                modifier = Modifier.let {
                    if (message.isTemporary) it.then(Modifier) else it
                }
            ) {
                Text(
                    text = message.content,
                    modifier = Modifier
                        .padding(12.dp)
                        .let {
                            if (message.isTemporary) {
                                it.then(Modifier)
                            } else it
                        },
                    color = if (isUser) {
                        MaterialTheme.colorScheme.onPrimary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    style = MaterialTheme.typography.bodyMedium
                )
            }

            // Metadata row
            Row(
                modifier = Modifier.padding(top = 4.dp, start = 4.dp, end = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // PII badge
                if (message.tokensDetected > 0) {
                    PiiBadge(count = message.tokensDetected)
                }

                // Timestamp
                Text(
                    text = formatTime(message),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
                )
            }
        }

        if (isUser) {
            Spacer(modifier = Modifier.width(8.dp))
            // User avatar
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(MaterialTheme.colorScheme.primary),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = "You",
                    tint = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}

@Composable
fun PiiBadge(count: Int) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.tertiaryContainer
    ) {
        Text(
            text = "$count PII",
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onTertiaryContainer
        )
    }
}

private fun formatTime(message: ChatMessage): String {
    val formatter = DateTimeFormatter.ofPattern("HH:mm")
        .withZone(ZoneId.systemDefault())
    return formatter.format(message.createdAt)
}
