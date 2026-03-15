package my.ssdid.drive.data.remote.dto

import com.google.gson.annotations.SerializedName

data class SubmitTenantRequestBody(
    @SerializedName("organization_name") val organizationName: String,
    @SerializedName("reason") val reason: String? = null
)

data class TenantRequestResponseDto(
    @SerializedName("id") val id: String,
    @SerializedName("organization_name") val organizationName: String,
    @SerializedName("reason") val reason: String?,
    @SerializedName("status") val status: String,
    @SerializedName("created_at") val createdAt: String
)
