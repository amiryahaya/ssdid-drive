package my.ssdid.drive.data.local.converter

import androidx.room.TypeConverter
import my.ssdid.drive.data.local.entity.NotificationActionType
import my.ssdid.drive.data.local.entity.NotificationType
import my.ssdid.drive.data.local.entity.OperationStatus
import my.ssdid.drive.data.local.entity.OperationType
import my.ssdid.drive.data.local.entity.ResourceType
import java.time.Instant

/**
 * Room type converters for complex types.
 */
class Converters {

    // ==================== Instant Converters ====================

    @TypeConverter
    fun fromInstant(instant: Instant?): String? {
        return instant?.toString()
    }

    @TypeConverter
    fun toInstant(value: String?): Instant? {
        return value?.let {
            try { java.time.OffsetDateTime.parse(it).toInstant() }
            catch (_: Exception) { Instant.parse(it) }
        }
    }

    // ==================== ByteArray Converters ====================

    @TypeConverter
    fun fromByteArray(bytes: ByteArray?): String? {
        return bytes?.let { android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP) }
    }

    @TypeConverter
    fun toByteArray(value: String?): ByteArray? {
        return value?.let { android.util.Base64.decode(it, android.util.Base64.NO_WRAP) }
    }

    // ==================== Enum Converters ====================

    @TypeConverter
    fun fromOperationType(type: OperationType): String = type.name

    @TypeConverter
    fun toOperationType(value: String): OperationType = OperationType.valueOf(value)

    @TypeConverter
    fun fromResourceType(type: ResourceType): String = type.name

    @TypeConverter
    fun toResourceType(value: String): ResourceType = ResourceType.valueOf(value)

    @TypeConverter
    fun fromOperationStatus(status: OperationStatus): String = status.name

    @TypeConverter
    fun toOperationStatus(value: String): OperationStatus = OperationStatus.valueOf(value)

    @TypeConverter
    fun fromNotificationType(type: NotificationType): String = type.name

    @TypeConverter
    fun toNotificationType(value: String): NotificationType = NotificationType.valueOf(value)

    @TypeConverter
    fun fromNotificationActionType(type: NotificationActionType?): String? = type?.name

    @TypeConverter
    fun toNotificationActionType(value: String?): NotificationActionType? = value?.let { NotificationActionType.valueOf(it) }
}
