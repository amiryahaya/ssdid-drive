package my.ssdid.drive.data.remote.dto

import com.google.gson.JsonObject
import com.google.gson.annotations.SerializedName

// ==================== Response DTOs ====================

data class ActivityResponseDto(
    @SerializedName("items") val items: List<ActivityItemDto>,
    @SerializedName("total") val total: Int,
    @SerializedName("page") val page: Int,
    @SerializedName("page_size") val pageSize: Int
)

// ==================== Activity DTOs ====================

data class ActivityItemDto(
    @SerializedName("id") val id: String,
    @SerializedName("actor_id") val actorId: String,
    @SerializedName("actor_name") val actorName: String?,
    @SerializedName("event_type") val eventType: String,
    @SerializedName("resource_type") val resourceType: String,
    @SerializedName("resource_id") val resourceId: String,
    @SerializedName("resource_name") val resourceName: String,
    @SerializedName("details") val details: JsonObject?,
    @SerializedName("created_at") val createdAt: String
)
