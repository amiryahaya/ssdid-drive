package my.ssdid.drive.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * Response wrapper for tenant configuration.
 */
data class TenantConfigResponse(
    @SerializedName("data") val data: TenantConfigDto
)

/**
 * Tenant configuration including PQC algorithm selection.
 */
data class TenantConfigDto(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
    @SerializedName("slug") val slug: String,
    @SerializedName("pqc_algorithm") val pqcAlgorithm: String,
    @SerializedName("plan") val plan: String,
    @SerializedName("settings") val settings: Map<String, Any>?
)
