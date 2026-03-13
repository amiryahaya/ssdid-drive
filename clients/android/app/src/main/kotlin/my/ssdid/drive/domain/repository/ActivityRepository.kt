package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.FileActivity
import my.ssdid.drive.util.Result

/**
 * Repository interface for activity log operations.
 */
interface ActivityRepository {

    /**
     * Get activity log entries with optional filtering and pagination.
     */
    suspend fun getActivity(
        page: Int? = null,
        pageSize: Int? = null,
        eventType: String? = null,
        resourceType: String? = null
    ): Result<List<FileActivity>>

    /**
     * Get activity log entries for a specific resource.
     */
    suspend fun getResourceActivity(
        resourceId: String,
        page: Int? = null,
        pageSize: Int? = null
    ): Result<List<FileActivity>>
}
