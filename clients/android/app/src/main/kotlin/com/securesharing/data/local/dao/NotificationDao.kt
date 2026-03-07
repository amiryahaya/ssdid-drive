package com.securesharing.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.securesharing.data.local.entity.NotificationEntity
import com.securesharing.data.local.entity.NotificationType
import kotlinx.coroutines.flow.Flow
import java.time.Instant

/**
 * Data Access Object for notifications.
 */
@Dao
interface NotificationDao {

    // ==================== Insert Operations ====================

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(notification: NotificationEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(notifications: List<NotificationEntity>)

    // ==================== Query Operations ====================

    /**
     * Get all notifications for a user, ordered by creation date.
     */
    @Query("SELECT * FROM notifications WHERE userId = :userId ORDER BY createdAt DESC")
    suspend fun getAll(userId: String): List<NotificationEntity>

    /**
     * Observe all notifications for a user.
     */
    @Query("SELECT * FROM notifications WHERE userId = :userId ORDER BY createdAt DESC")
    fun observeAll(userId: String): Flow<List<NotificationEntity>>

    /**
     * Observe all notifications with limit.
     */
    @Query("SELECT * FROM notifications WHERE userId = :userId ORDER BY createdAt DESC LIMIT :limit")
    fun observeRecent(userId: String, limit: Int = 50): Flow<List<NotificationEntity>>

    /**
     * Get unread notifications for a user.
     */
    @Query("SELECT * FROM notifications WHERE userId = :userId AND isRead = 0 ORDER BY createdAt DESC")
    suspend fun getUnread(userId: String): List<NotificationEntity>

    /**
     * Observe unread notifications.
     */
    @Query("SELECT * FROM notifications WHERE userId = :userId AND isRead = 0 ORDER BY createdAt DESC")
    fun observeUnread(userId: String): Flow<List<NotificationEntity>>

    /**
     * Get unread notification count.
     */
    @Query("SELECT COUNT(*) FROM notifications WHERE userId = :userId AND isRead = 0")
    suspend fun getUnreadCount(userId: String): Int

    /**
     * Observe unread notification count.
     */
    @Query("SELECT COUNT(*) FROM notifications WHERE userId = :userId AND isRead = 0")
    fun observeUnreadCount(userId: String): Flow<Int>

    /**
     * Get notifications by type.
     */
    @Query("SELECT * FROM notifications WHERE userId = :userId AND type = :type ORDER BY createdAt DESC")
    suspend fun getByType(userId: String, type: NotificationType): List<NotificationEntity>

    /**
     * Observe notifications by type.
     */
    @Query("SELECT * FROM notifications WHERE userId = :userId AND type = :type ORDER BY createdAt DESC")
    fun observeByType(userId: String, type: NotificationType): Flow<List<NotificationEntity>>

    /**
     * Get a notification by ID.
     */
    @Query("SELECT * FROM notifications WHERE id = :id")
    suspend fun getById(id: String): NotificationEntity?

    /**
     * Check if a notification exists.
     */
    @Query("SELECT EXISTS(SELECT 1 FROM notifications WHERE id = :id)")
    suspend fun exists(id: String): Boolean

    // ==================== Update Operations ====================

    @Update
    suspend fun update(notification: NotificationEntity)

    /**
     * Mark a notification as read.
     */
    @Query("UPDATE notifications SET isRead = 1 WHERE id = :id")
    suspend fun markAsRead(id: String)

    /**
     * Mark all notifications as read for a user.
     */
    @Query("UPDATE notifications SET isRead = 1 WHERE userId = :userId")
    suspend fun markAllAsRead(userId: String)

    /**
     * Mark notifications of a specific type as read.
     */
    @Query("UPDATE notifications SET isRead = 1 WHERE userId = :userId AND type = :type")
    suspend fun markTypeAsRead(userId: String, type: NotificationType)

    // ==================== Delete Operations ====================

    /**
     * Delete a notification by ID.
     */
    @Query("DELETE FROM notifications WHERE id = :id")
    suspend fun deleteById(id: String)

    /**
     * Delete all notifications for a user.
     */
    @Query("DELETE FROM notifications WHERE userId = :userId")
    suspend fun deleteAll(userId: String)

    /**
     * Delete read notifications older than a certain date.
     */
    @Query("DELETE FROM notifications WHERE userId = :userId AND isRead = 1 AND createdAt < :before")
    suspend fun deleteOldReadNotifications(userId: String, before: Instant)

    /**
     * Delete all notifications older than a certain date.
     */
    @Query("DELETE FROM notifications WHERE userId = :userId AND createdAt < :before")
    suspend fun deleteOlderThan(userId: String, before: Instant)

    /**
     * Delete notifications by type.
     */
    @Query("DELETE FROM notifications WHERE userId = :userId AND type = :type")
    suspend fun deleteByType(userId: String, type: NotificationType)
}
