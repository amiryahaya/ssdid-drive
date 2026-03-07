package com.securesharing.data.remote.dto

import com.google.gson.annotations.SerializedName

// ==================== Push Notification DTOs (OneSignal) ====================

/**
 * Request to register push notification player ID.
 */
data class RegisterPushRequest(
    @SerializedName("player_id")
    val playerId: String
)

// ==================== Device Enrollment DTOs ====================

/**
 * Request to enroll a device with cryptographic binding.
 */
data class EnrollDeviceRequest(
    @SerializedName("device_fingerprint") val deviceFingerprint: String,
    @SerializedName("platform") val platform: String = "android",
    @SerializedName("device_info") val deviceInfo: DeviceInfoDto,
    @SerializedName("device_public_key") val devicePublicKey: String,
    @SerializedName("key_algorithm") val keyAlgorithm: String,
    @SerializedName("device_name") val deviceName: String? = null
)

/**
 * Device information for enrollment.
 */
data class DeviceInfoDto(
    @SerializedName("model") val model: String,
    @SerializedName("manufacturer") val manufacturer: String,
    @SerializedName("os_version") val osVersion: String,
    @SerializedName("app_version") val appVersion: String,
    @SerializedName("sdk_version") val sdkVersion: Int
)

/**
 * Request to update device enrollment (e.g., rename).
 */
data class UpdateDeviceRequest(
    @SerializedName("device_name") val deviceName: String
)

// ==================== Device Enrollment Response DTOs ====================

/**
 * Response containing a single device enrollment.
 */
data class DeviceEnrollmentResponse(
    @SerializedName("data") val data: DeviceEnrollmentDto
)

/**
 * Response containing list of device enrollments.
 */
data class DeviceEnrollmentsResponse(
    @SerializedName("data") val data: List<DeviceEnrollmentDto>
)

/**
 * Device enrollment DTO from API.
 */
data class DeviceEnrollmentDto(
    @SerializedName("id") val id: String,
    @SerializedName("device_id") val deviceId: String,
    @SerializedName("device_name") val deviceName: String?,
    @SerializedName("status") val status: String,
    @SerializedName("key_algorithm") val keyAlgorithm: String,
    @SerializedName("enrolled_at") val enrolledAt: String,
    @SerializedName("last_used_at") val lastUsedAt: String?,
    @SerializedName("push_player_id") val pushPlayerId: String?,
    @SerializedName("device") val device: DeviceDto?
)

/**
 * Device DTO from API.
 */
data class DeviceDto(
    @SerializedName("id") val id: String,
    @SerializedName("device_fingerprint") val deviceFingerprint: String,
    @SerializedName("platform") val platform: String,
    @SerializedName("device_info") val deviceInfo: DeviceInfoDto?,
    @SerializedName("status") val status: String,
    @SerializedName("trust_level") val trustLevel: String,
    @SerializedName("created_at") val createdAt: String
)
