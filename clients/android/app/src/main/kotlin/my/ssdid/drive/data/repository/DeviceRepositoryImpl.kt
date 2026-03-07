package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.DeviceDto
import my.ssdid.drive.data.remote.dto.DeviceEnrollmentDto
import my.ssdid.drive.data.remote.dto.DeviceInfoDto
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
 * Device key enrollment and request signing are now handled by the
 * SSDID Wallet.  This implementation retains read-only server queries
 * and push notification management.
 */
@Singleton
class DeviceRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val pushNotificationManager: PushNotificationManager
) : DeviceRepository {

    override suspend fun enrollDevice(deviceName: String?): Result<DeviceEnrollment> {
        // Device enrollment (key generation, fingerprinting) is now handled by the SSDID Wallet
        return Result.error(AppException.Unknown("Device enrollment is managed by the SSDID Wallet"))
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
        // Request signing is now handled by the SSDID Wallet
        return Result.error(AppException.CryptoError("Request signing is managed by the SSDID Wallet"))
    }

    override suspend fun getEnrollmentId(): String? {
        return secureStorage.getDeviceEnrollmentId()
    }

    override suspend fun clearEnrollment() {
        secureStorage.clearDeviceEnrollment()
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
