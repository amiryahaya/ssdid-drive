package my.ssdid.drive.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import my.ssdid.drive.data.local.dao.ChatMessageDao
import my.ssdid.drive.data.local.dao.ConversationDao
import my.ssdid.drive.data.local.dao.FileDao
import my.ssdid.drive.data.local.dao.FolderDao
import my.ssdid.drive.data.local.dao.NotificationDao
import my.ssdid.drive.data.local.dao.PendingOperationDao
import my.ssdid.drive.data.local.dao.ShareDao
import my.ssdid.drive.data.local.dao.UserDao
import my.ssdid.drive.data.local.entity.ChatMessageEntity
import my.ssdid.drive.data.local.entity.ConversationEntity
import my.ssdid.drive.data.local.entity.FileEntity
import my.ssdid.drive.data.local.entity.FolderEntity
import my.ssdid.drive.data.local.entity.NotificationEntity
import my.ssdid.drive.data.local.entity.PendingOperationEntity
import my.ssdid.drive.data.local.entity.ShareEntity
import my.ssdid.drive.data.local.entity.UserEntity
import my.ssdid.drive.data.local.converter.Converters

/**
 * Room database for offline caching.
 */
@Database(
    entities = [
        FolderEntity::class,
        FileEntity::class,
        ShareEntity::class,
        UserEntity::class,
        PendingOperationEntity::class,
        NotificationEntity::class,
        ConversationEntity::class,
        ChatMessageEntity::class
    ],
    version = 4,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class SsdidDriveDatabase : RoomDatabase() {
    abstract fun folderDao(): FolderDao
    abstract fun fileDao(): FileDao
    abstract fun shareDao(): ShareDao
    abstract fun userDao(): UserDao
    abstract fun pendingOperationDao(): PendingOperationDao
    abstract fun notificationDao(): NotificationDao
    abstract fun conversationDao(): ConversationDao
    abstract fun chatMessageDao(): ChatMessageDao
}
