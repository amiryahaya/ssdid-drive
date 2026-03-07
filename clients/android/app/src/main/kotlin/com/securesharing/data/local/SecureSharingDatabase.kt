package com.securesharing.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.securesharing.data.local.dao.ChatMessageDao
import com.securesharing.data.local.dao.ConversationDao
import com.securesharing.data.local.dao.FileDao
import com.securesharing.data.local.dao.FolderDao
import com.securesharing.data.local.dao.NotificationDao
import com.securesharing.data.local.dao.PendingOperationDao
import com.securesharing.data.local.dao.ShareDao
import com.securesharing.data.local.dao.UserDao
import com.securesharing.data.local.entity.ChatMessageEntity
import com.securesharing.data.local.entity.ConversationEntity
import com.securesharing.data.local.entity.FileEntity
import com.securesharing.data.local.entity.FolderEntity
import com.securesharing.data.local.entity.NotificationEntity
import com.securesharing.data.local.entity.PendingOperationEntity
import com.securesharing.data.local.entity.ShareEntity
import com.securesharing.data.local.entity.UserEntity
import com.securesharing.data.local.converter.Converters

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
abstract class SecureSharingDatabase : RoomDatabase() {
    abstract fun folderDao(): FolderDao
    abstract fun fileDao(): FileDao
    abstract fun shareDao(): ShareDao
    abstract fun userDao(): UserDao
    abstract fun pendingOperationDao(): PendingOperationDao
    abstract fun notificationDao(): NotificationDao
    abstract fun conversationDao(): ConversationDao
    abstract fun chatMessageDao(): ChatMessageDao
}
