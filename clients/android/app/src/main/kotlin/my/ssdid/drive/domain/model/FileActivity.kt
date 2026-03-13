package my.ssdid.drive.domain.model

import com.google.gson.JsonObject
import java.time.Duration
import java.time.Instant

/**
 * Domain model representing a file activity log entry.
 */
data class FileActivity(
    val id: String,
    val actorId: String,
    val actorName: String?,
    val eventType: String,
    val resourceType: String,
    val resourceId: String,
    val resourceName: String,
    val details: JsonObject?,
    val createdAt: Instant
) {
    /**
     * Human-readable label for the event type.
     */
    val eventLabel: String
        get() = when (eventType) {
            "file_uploaded" -> "Uploaded"
            "file_downloaded" -> "Downloaded"
            "file_deleted" -> "Deleted"
            "file_renamed" -> "Renamed"
            "file_moved" -> "Moved"
            "file_shared" -> "Shared"
            "share_revoked" -> "Share revoked"
            "share_permission_changed" -> "Permission changed"
            "file_previewed" -> "Previewed"
            "folder_created" -> "Folder created"
            "folder_deleted" -> "Folder deleted"
            "folder_renamed" -> "Folder renamed"
            else -> eventType.replace("_", " ").replaceFirstChar { it.uppercase() }
        }

    /**
     * Relative time string (e.g. "2 minutes ago", "1 hour ago").
     */
    val timeAgo: String
        get() {
            val now = Instant.now()
            val duration = Duration.between(createdAt, now)
            val seconds = duration.seconds

            return when {
                seconds < 60 -> "Just now"
                seconds < 3600 -> {
                    val minutes = seconds / 60
                    if (minutes == 1L) "1 minute ago" else "$minutes minutes ago"
                }
                seconds < 86400 -> {
                    val hours = seconds / 3600
                    if (hours == 1L) "1 hour ago" else "$hours hours ago"
                }
                seconds < 604800 -> {
                    val days = seconds / 86400
                    if (days == 1L) "1 day ago" else "$days days ago"
                }
                seconds < 2592000 -> {
                    val weeks = seconds / 604800
                    if (weeks == 1L) "1 week ago" else "$weeks weeks ago"
                }
                else -> {
                    val months = seconds / 2592000
                    if (months == 1L) "1 month ago" else "$months months ago"
                }
            }
        }
}
