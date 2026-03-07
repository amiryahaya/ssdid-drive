package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.crypto.DeviceManager
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.DeviceDto
import my.ssdid.drive.data.remote.dto.DeviceEnrollmentDto
import my.ssdid.drive.data.remote.dto.DeviceInfoDto
import my.ssdid.drive.data.remote.dto.EnrollDeviceRequest
import my.ssdid.drive.data.remote.dto.UpdateDeviceRequest
import my.ssdid.drive.domain.model.Device
import my.ssdid.drive.domain.model.DeviceEnrollment
import my.ssdid.drive.domain.model.DeviceEnrollmentStatus
import my.ssdid.drive.domain.model.DeviceInfo
import my.ssdid.drive.domain.model.DeviceKeyAlgorithm
import my.ssdid.drive.domain.model.DevicePlatform
import my.ssdid.drive.domain.model.DeviceStatus
import my.ssdid.drive.domain.model.DeviceTrustLevel
import my.ssdid.drive.domain.repository.DeviceRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.util.Result
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
