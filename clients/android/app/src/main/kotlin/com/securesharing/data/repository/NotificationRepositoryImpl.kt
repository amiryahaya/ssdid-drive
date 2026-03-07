package com.securesharing.data.repository

import com.securesharing.data.local.SecureStorage
import com.securesharing.data.local.dao.NotificationDao
import com.securesharing.data.local.entity.NotificationActionType
import com.securesharing.data.local.entity.NotificationEntity
import com.securesharing.domain.model.Notification
import com.securesharing.domain.model.NotificationAction
import com.securesharing.domain.model.NotificationActionType as DomainActionType
import com.securesharing.domain.model.NotificationType
import com.securesharing.domain.repository.NotificationRepository
import com.securesharing.service.NotificationHandler
import com.securesharing.util.AppException
import com.securesharing.util.Result
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NotificationRepositoryImpl @Inject constructor(
    private val notificationDao: NotificationDao,
    private val secureStorage: SecureStorage,
    private val notificationHandler: NotificationHandler
) : NotificationRepository {

    private val userId: String
        get() = secureStorage.getUserIdSync() ?: ""

    override suspend fun getNotifications(): Result<List<Notification>> {
        return try {
            val notifications = notificationDao.getAll(userId).map { it.toDomain() }
            Result.success(notifications)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to get notifications", e))
        }
    }

    override fun observeNotifications(): Flow<List<Notification>> {
        return notificationDao.observeAll(userId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override fun observeRecentNotifications(limit: Int): Flow<List<Notification>> {
        return notificationDao.observeRecent(userId, limit).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun getUnreadNotifications(): Result<List<Notification>> {
        return try {
            val notifications = notificationDao.getUnread(userId).map { it.toDomain() }
            Result.success(notifications)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to get unread notifications", e))
        }
    }

    override fun observeUnreadNotifications(): Flow<List<Notification>> {
        return notificationDao.observeUnread(userId).map { entities ->
            entities.map { it.toDomain() }
        }
    }

    override suspend fun getUnreadCount(): Int {
        return try {
            notificationDao.getUnreadCount(userId)
        } catch (e: Exception) {
            0
        }
    }

    override fun observeUnreadCount(): Flow<Int> {
        return notificationDao.observeUnreadCount(userId)
    }

    override suspend fun getNotificationsByType(type: NotificationType): Result<List<Notification>> {
        return try {
            val entityType = com.securesharing.data.local.entity.NotificationType.fromString(type.name)
            val notifications = notificationDao.getByType(userId, entityType).map { it.toDomain() }
            Result.success(notifications)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to get notifications by type", e))
        }
    }

    override suspend fun markAsRead(notificationId: String): Result<Unit> {
        return try {
            notificationDao.markAsRead(notificationId)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to mark notification as read", e))
        }
    }

    override suspend fun markAllAsRead(): Result<Unit> {
        return try {
            notificationDao.markAllAsRead(userId)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to mark all notifications as read", e))
        }
    }

    override suspend fun deleteNotification(notificationId: String): Result<Unit> {
        return try {
            notificationDao.deleteById(notificationId)
            notificationHandler.cancelNotification(notificationId)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to delete notification", e))
        }
    }

    override suspend fun deleteAllNotifications(): Result<Unit> {
        return try {
            notificationDao.deleteAll(userId)
            notificationHandler.cancelAllNotifications()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to delete all notifications", e))
        }
    }

    override suspend fun cleanupOldNotifications(daysOld: Int): Result<Unit> {
        return try {
            val cutoff = Instant.now().minusSeconds((daysOld * 24 * 60 * 60).toLong())
            notificationDao.deleteOldReadNotifications(userId, cutoff)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to cleanup notifications", e))
        }
    }

    override suspend fun createLocalNotification(
        type: NotificationType,
        title: String,
        message: String,
        actionType: String?,
        actionId: String?
    ): Result<Notification> {
        return try {
            val entityType = com.securesharing.data.local.entity.NotificationType.fromString(type.name)
            val entityActionType = actionType?.let { NotificationActionType.fromString(it) }

            val entity = NotificationEntity(
                userId = userId,
                type = entityType,
                title = title,
                message = message,
                actionType = entityActionType,
                actionId = actionId
            )

            notificationDao.insert(entity)
            notificationHandler.showNotification(entity)

            Result.success(entity.toDomain())
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Failed to create notification", e))
        }
    }

    // Note: Push notification registration is handled by PushNotificationManager using OneSignal

    // ==================== Helper Methods ====================

    private fun NotificationEntity.toDomain(): Notification {
        return Notification(
            id = id,
            type = NotificationType.fromString(type.name),
            title = title,
            message = message,
            isRead = isRead,
            action = actionType?.let {
                NotificationAction(
                    type = DomainActionType.fromString(it.name),
                    resourceId = actionId
                )
            },
            createdAt = createdAt
        )
    }
}
