package my.ssdid.drive.data.repository

import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.ActivityItemDto
import my.ssdid.drive.domain.model.FileActivity
import my.ssdid.drive.domain.repository.ActivityRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ActivityRepositoryImpl @Inject constructor(
    private val apiService: ApiService
) : ActivityRepository {

    override suspend fun getActivity(
        page: Int?,
        pageSize: Int?,
        eventType: String?,
        resourceType: String?
    ): Result<List<FileActivity>> {
        return try {
            val response = apiService.getActivity(
                page = page,
                pageSize = pageSize,
                eventType = eventType,
                resourceType = resourceType
            )

            if (response.isSuccessful) {
                val items = response.body()!!.items.map { it.toDomain() }
                Result.success(items)
            } else {
                Result.error(AppException.Unknown("Failed to get activity logs"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get activity logs", e))
        }
    }

    override suspend fun getResourceActivity(
        resourceId: String,
        page: Int?,
        pageSize: Int?
    ): Result<List<FileActivity>> {
        return try {
            val response = apiService.getResourceActivity(
                resourceId = resourceId,
                page = page,
                pageSize = pageSize
            )

            if (response.isSuccessful) {
                val items = response.body()!!.items.map { it.toDomain() }
                Result.success(items)
            } else {
                Result.error(AppException.Unknown("Failed to get resource activity"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get resource activity", e))
        }
    }

    private fun ActivityItemDto.toDomain(): FileActivity {
        return FileActivity(
            id = id,
            actorId = actorId,
            actorName = actorName,
            eventType = eventType,
            resourceType = resourceType,
            resourceId = resourceId,
            resourceName = resourceName,
            details = details,
            createdAt = try {
                Instant.parse(createdAt)
            } catch (e: Exception) {
                Instant.now()
            }
        )
    }
}
