package my.ssdid.drive.data.repository

import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.local.dao.NotificationDao
import my.ssdid.drive.data.local.entity.NotificationActionType
import my.ssdid.drive.data.local.entity.NotificationEntity
import my.ssdid.drive.domain.model.Notification
import my.ssdid.drive.domain.model.NotificationAction
import my.ssdid.drive.domain.model.NotificationActionType as DomainActionType
import my.ssdid.drive.domain.model.NotificationType
import my.ssdid.drive.domain.repository.NotificationRepository
import my.ssdid.drive.service.NotificationHandler
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
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
            val entityType = my.ssdid.drive.data.local.entity.NotificationType.fromString(type.name)
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
            val entityType = my.ssdid.drive.data.local.entity.NotificationType.fromString(type.name)
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
