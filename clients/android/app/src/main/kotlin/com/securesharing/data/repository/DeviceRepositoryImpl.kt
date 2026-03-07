package com.securesharing.data.repository

import android.util.Base64
import com.securesharing.crypto.DeviceManager
import com.securesharing.data.local.SecureStorage
import com.securesharing.data.remote.ApiService
import com.securesharing.data.remote.dto.DeviceDto
import com.securesharing.data.remote.dto.DeviceEnrollmentDto
import com.securesharing.data.remote.dto.DeviceInfoDto
import com.securesharing.data.remote.dto.EnrollDeviceRequest
import com.securesharing.data.remote.dto.UpdateDeviceRequest
import com.securesharing.domain.model.Device
import com.securesharing.domain.model.DeviceEnrollment
import com.securesharing.domain.model.DeviceEnrollmentStatus
import com.securesharing.domain.model.DeviceInfo
import com.securesharing.domain.model.DeviceKeyAlgorithm
import com.securesharing.domain.model.DevicePlatform
import com.securesharing.domain.model.DeviceStatus
import com.securesharing.domain.model.DeviceTrustLevel
import com.securesharing.domain.repository.DeviceRepository
import com.securesharing.util.AppException
import com.securesharing.util.PushNotificationManager
import com.securesharing.util.Result
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of DeviceRepository.
 *
 * Handles device enrollment, key management, and request signing.
 */
@Singleton
class DeviceRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val deviceManager: DeviceManager,
    private val pushNotificationManager: PushNotificationManager
) : DeviceRepository {

    override suspend fun enrollDevice(deviceName: String?): Result<DeviceEnrollment> {
        return try {
            // 1. Generate device fingerprint
            val fingerprint = deviceManager.generateDeviceFingerprint()

            // 2. Generate device signing key pair
            val algorithm = deviceManager.getPreferredAlgorithm()
            val (publicKey, privateKey) = deviceManager.generateDeviceKeyPair(algorithm)

            // 3. Get device info
            val deviceInfo = deviceManager.getDeviceInfo()

            // 4. Build enrollment request
            val request = EnrollDeviceRequest(
                deviceFingerprint = fingerprint,
                platform = "android",
                deviceInfo = DeviceInfoDto(
                    model = deviceInfo.model,
                    manufacturer = deviceInfo.manufacturer,
                    osVersion = deviceInfo.osVersion,
                    appVersion = deviceInfo.appVersion,
                    sdkVersion = deviceInfo.sdkVersion
                ),
                devicePublicKey = Base64.encodeToString(publicKey, Base64.NO_WRAP),
                keyAlgorithm = algorithm.toApiString(),
                deviceName = deviceName ?: "${deviceInfo.manufacturer} ${deviceInfo.model}"
            )

            // 5. Call API
            val response = apiService.enrollDevice(request)

            if (response.isSuccessful) {
                val enrollmentDto = response.body()!!.data

                // 6. Store device keys securely
                deviceManager.storeDeviceKeys(publicKey, privateKey, algorithm)

                // 7. Store enrollment ID
                secureStorage.saveDeviceEnrollmentId(enrollmentDto.id)
                secureStorage.saveDeviceId(enrollmentDto.deviceId)

                Result.success(enrollmentDto.toDomain())
            } else {
                // Clean up generated keys on failure
                deviceManager.clearDeviceKey()

                when (response.code()) {
                    400 -> Result.error(AppException.ValidationError("Invalid device enrollment data"))
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Device enrollment not allowed"))
                    409 -> Result.error(AppException.Conflict("Device already enrolled"))
                    else -> Result.error(AppException.Unknown("Failed to enroll device: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            deviceManager.clearDeviceKey()
            Result.error(AppException.Network(e.message ?: "Network error during enrollment"))
        }
    }

    override suspend fun getCurrentEnrollment(): Result<DeviceEnrollment?> {
        val enrollmentId = secureStorage.getDeviceEnrollmentId() ?: return Result.success(null)

        return try {
            val response = apiService.getDeviceEnrollment(enrollmentId)

            if (response.isSuccessful) {
                Result.success(response.body()!!.data.toDomain())
            } else {
                when (response.code()) {
                    404 -> {
                        // Enrollment no longer exists, clear local data
                        clearEnrollment()
                        Result.success(null)
                    }
                    401 -> Result.error(AppException.Unauthorized())
                    else -> Result.error(AppException.Unknown("Failed to get enrollment: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network(e.message ?: "Network error"))
        }
    }

    override suspend fun listEnrollments(): Result<List<DeviceEnrollment>> {
        return try {
            val response = apiService.listDeviceEnrollments()

            if (response.isSuccessful) {
                val enrollments = response.body()!!.data.map { it.toDomain() }
                Result.success(enrollments)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    else -> Result.error(AppException.Unknown("Failed to list enrollments: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network(e.message ?: "Network error"))
        }
    }

    override suspend fun updateEnrollment(enrollmentId: String, deviceName: String): Result<DeviceEnrollment> {
        return try {
            val request = UpdateDeviceRequest(deviceName = deviceName)
            val response = apiService.updateDeviceEnrollment(enrollmentId, request)

            if (response.isSuccessful) {
                Result.success(response.body()!!.data.toDomain())
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Cannot update this enrollment"))
                    404 -> Result.error(AppException.NotFound("Enrollment not found"))
                    else -> Result.error(AppException.Unknown("Failed to update enrollment: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network(e.message ?: "Network error"))
        }
    }

    override suspend fun revokeEnrollment(enrollmentId: String): Result<Unit> {
        return try {
            val response = apiService.revokeDeviceEnrollment(enrollmentId)

            if (response.isSuccessful) {
                // If revoking current device, clear local data
                val currentEnrollmentId = secureStorage.getDeviceEnrollmentId()
                if (enrollmentId == currentEnrollmentId) {
                    clearEnrollment()
                }
                Result.success(Unit)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Cannot revoke this enrollment"))
                    404 -> Result.error(AppException.NotFound("Enrollment not found"))
                    else -> Result.error(AppException.Unknown("Failed to revoke enrollment: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network(e.message ?: "Network error"))
        }
    }

    override suspend fun isDeviceEnrolled(): Boolean {
        return secureStorage.isDeviceEnrolled()
    }

    override suspend fun signRequest(payload: String): Result<String> {
        return try {
            val signature = deviceManager.signRequest(payload)
            if (signature != null) {
                Result.success(signature)
            } else {
                Result.error(AppException.CryptoError("Failed to sign request - keys not available"))
            }
        } catch (e: Exception) {
            Result.error(AppException.CryptoError("Signing failed: ${e.message}"))
        }
    }

    override suspend fun getEnrollmentId(): String? {
        return secureStorage.getDeviceEnrollmentId()
    }

    override suspend fun clearEnrollment() {
        deviceManager.clearEnrollment()
    }

    // ==================== DTO to Domain Mapping ====================

    private fun DeviceEnrollmentDto.toDomain(): DeviceEnrollment {
        return DeviceEnrollment(
            id = id,
            deviceId = deviceId,
            deviceName = deviceName,
            status = DeviceEnrollmentStatus.fromString(status),
            keyAlgorithm = DeviceKeyAlgorithm.fromString(keyAlgorithm),
            enrolledAt = enrolledAt,
            lastUsedAt = lastUsedAt,
            device = device?.toDomain()
        )
    }

    private fun DeviceDto.toDomain(): Device {
        return Device(
            id = id,
            deviceFingerprint = deviceFingerprint,
            platform = DevicePlatform.fromString(platform),
            deviceInfo = deviceInfo?.toDomain(),
            status = DeviceStatus.fromString(status),
            trustLevel = DeviceTrustLevel.fromString(trustLevel),
            createdAt = createdAt
        )
    }

    private fun DeviceInfoDto.toDomain(): DeviceInfo {
        return DeviceInfo(
            model = model,
            manufacturer = manufacturer,
            osVersion = osVersion,
            appVersion = appVersion,
            sdkVersion = sdkVersion
        )
    }

    // ==================== Push Notifications ====================

    override fun registerPushNotifications(userId: String) {
        val enrollmentId = secureStorage.getDeviceEnrollmentIdSync()
        if (enrollmentId != null) {
            pushNotificationManager.login(userId, enrollmentId)
        }
    }

    override fun unregisterPushNotifications() {
        val enrollmentId = secureStorage.getDeviceEnrollmentIdSync()
        pushNotificationManager.logout(enrollmentId)
    }
}
