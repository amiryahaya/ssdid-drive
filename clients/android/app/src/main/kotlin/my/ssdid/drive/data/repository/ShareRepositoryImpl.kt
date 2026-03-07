package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.crypto.FileDecryptor
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.KeyEncapsulation
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.local.dao.ShareDao
import my.ssdid.drive.data.local.dao.UserDao
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.SetExpiryRequest
import my.ssdid.drive.data.remote.dto.ShareDto
import my.ssdid.drive.data.remote.dto.ShareFileRequest
import my.ssdid.drive.data.remote.dto.ShareFolderRequest
import my.ssdid.drive.data.remote.dto.UpdatePermissionRequest
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.ResourceType
import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.ShareRepository
import my.ssdid.drive.data.local.entity.ShareEntity
import my.ssdid.drive.util.AnalyticsManager
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ShareRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val shareDao: ShareDao,
    private val userDao: UserDao,
    private val secureStorage: SecureStorage,
    private val keyEncapsulation: KeyEncapsulation,
    private val fileDecryptor: FileDecryptor,
    private val folderKeyManager: FolderKeyManager,
    private val analyticsManager: AnalyticsManager
) : ShareRepository {

    override suspend fun getReceivedShares(): Result<List<Share>> {
        return try {
            val response = apiService.getReceivedShares()

            if (response.isSuccessful) {
                val shares = response.body()!!.data.map { it.toDomain() }
                Result.success(shares)
            } else {
                Result.error(AppException.Unknown("Failed to get received shares"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get received shares", e))
        }
    }

    override fun observeReceivedShares(): Flow<List<Share>> {
        val userId = secureStorage.getUserIdSync() ?: ""
        return shareDao.observeReceivedShares(userId).map { entities ->
            entities.map { entity ->
                Share(
                    id = entity.id,
                    grantorId = entity.grantorId,
                    granteeId = entity.granteeId,
                    resourceType = ResourceType.fromString(entity.resourceType),
                    resourceId = entity.resourceId,
                    permission = SharePermission.fromString(entity.permission),
                    recursive = entity.recursive ?: false,
                    expiresAt = entity.expiresAt,
                    revokedAt = entity.revokedAt,
                    grantor = null,
                    grantee = null,
                    createdAt = entity.insertedAt,
                    updatedAt = entity.updatedAt
                )
            }
        }
    }

    override suspend fun getCreatedShares(): Result<List<Share>> {
        return try {
            val response = apiService.getCreatedShares()

            if (response.isSuccessful) {
                val shares = response.body()!!.data.map { it.toDomain() }
                Result.success(shares)
            } else {
                Result.error(AppException.Unknown("Failed to get created shares"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get created shares", e))
        }
    }

    override fun observeCreatedShares(): Flow<List<Share>> {
        val userId = secureStorage.getUserIdSync() ?: ""
        return shareDao.observeCreatedShares(userId).map { entities ->
            entities.map { entity ->
                Share(
                    id = entity.id,
                    grantorId = entity.grantorId,
                    granteeId = entity.granteeId,
                    resourceType = ResourceType.fromString(entity.resourceType),
                    resourceId = entity.resourceId,
                    permission = SharePermission.fromString(entity.permission),
                    recursive = entity.recursive ?: false,
                    expiresAt = entity.expiresAt,
                    revokedAt = entity.revokedAt,
                    grantor = null,
                    grantee = null,
                    createdAt = entity.insertedAt,
                    updatedAt = entity.updatedAt
                )
            }
        }
    }

    override suspend fun getShare(shareId: String): Result<Share> {
        return try {
            val response = apiService.getShare(shareId)

            if (response.isSuccessful) {
                val share = response.body()!!.data.toDomain()
                Result.success(share)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Share not found"))
                    403 -> Result.error(AppException.Forbidden("Access denied"))
                    else -> Result.error(AppException.Unknown("Failed to get share"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get share", e))
        }
    }

    override suspend fun shareFile(
        fileId: String,
        grantee: User,
        permission: SharePermission,
        expiresAt: Instant?
    ): Result<Share> {
        return try {
            // Verify grantee has public keys
            val granteePublicKeys = grantee.publicKeys
                ?: return Result.error(AppException.ValidationError("Recipient has no public keys"))

            // Get the file to access its DEK
            val fileResponse = apiService.getFile(fileId)
            if (!fileResponse.isSuccessful) {
                return Result.error(AppException.NotFound("File not found"))
            }

            val fileDto = fileResponse.body()!!.data

            // SECURITY: Verify file signature before trusting wrapped DEK
            val uploaderKeys = fileDto.uploaderPublicKeys?.toPublicKeys()
                ?: return Result.error(AppException.CryptoError("Missing uploader public keys"))
            val blobHash = fileDto.blobHash
                ?: return Result.error(AppException.CryptoError("Missing blob hash for verification"))
            val blobSize = fileDto.blobSize
                ?: return Result.error(AppException.CryptoError("Missing blob size for verification"))
            val chunkCount = fileDto.chunkCount
                ?: return Result.error(AppException.CryptoError("Missing chunk count for verification"))

            val signatureValid = fileDecryptor.verifySignature(
                encryptedMetadata = fileDto.encryptedMetadata,
                blobHash = blobHash,
                wrappedDek = fileDto.wrappedDek,
                signature = fileDto.signature,
                uploaderPublicKeys = uploaderKeys,
                blobSize = blobSize,
                chunkCount = chunkCount
            )

            if (!signatureValid) {
                return Result.error(AppException.CryptoError("File signature verification failed"))
            }

            // Unwrap the file's DEK using folder's KEK
            val dek = fileDecryptor.unwrapDek(fileDto.folderId, fileDto.wrappedDek)

            try {
                // Encapsulate DEK for the recipient
                val encapsulationResult = keyEncapsulation.encapsulateForFileShare(
                    dek = dek,
                    recipientPublicKeys = granteePublicKeys,
                    fileId = fileId,
                    permission = permission.toString()
                )

                // Create share request
                val request = ShareFileRequest(
                    fileId = fileId,
                    granteeId = grantee.id,
                    wrappedKey = encapsulationResult.wrappedKey,
                    kemCiphertext = encapsulationResult.kemCiphertext,
                    mlKemCiphertext = encapsulationResult.mlKemCiphertext,
                    signature = encapsulationResult.signature,
                    permission = permission.toString(),
                    expiresAt = expiresAt?.let { formatInstant(it) }
                )

                val response = apiService.shareFile(request)

                if (response.isSuccessful) {
                    val share = response.body()!!.data.toDomain()
                    analyticsManager.trackShare("file", permission.toString())
                    Result.success(share)
                } else {
                    when (response.code()) {
                        403 -> Result.error(AppException.Forbidden("Cannot share this file"))
                        404 -> Result.error(AppException.NotFound("File or user not found"))
                        409 -> Result.error(AppException.ValidationError("Share already exists"))
                        else -> Result.error(AppException.Unknown("Failed to share file: ${response.code()}"))
                    }
                }
            } finally {
                // Zeroize DEK
                dek.fill(0)
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to share file", e))
        }
    }

    override suspend fun shareFolder(
        folderId: String,
        grantee: User,
        permission: SharePermission,
        recursive: Boolean,
        expiresAt: Instant?
    ): Result<Share> {
        return try {
            // Verify grantee has public keys
            val granteePublicKeys = grantee.publicKeys
                ?: return Result.error(AppException.ValidationError("Recipient has no public keys"))

            // Get folder's KEK from cache
            val kek = folderKeyManager.getCachedKek(folderId)
                ?: return Result.error(AppException.CryptoError("Folder KEK not available"))

            // Encapsulate KEK for the recipient
            val encapsulationResult = keyEncapsulation.encapsulateForFolderShare(
                kek = kek,
                recipientPublicKeys = granteePublicKeys,
                folderId = folderId,
                permission = permission.toString(),
                recursive = recursive
            )

            // Create share request
            val request = ShareFolderRequest(
                folderId = folderId,
                granteeId = grantee.id,
                wrappedKey = encapsulationResult.wrappedKey,
                kemCiphertext = encapsulationResult.kemCiphertext,
                mlKemCiphertext = encapsulationResult.mlKemCiphertext,
                signature = encapsulationResult.signature,
                permission = permission.toString(),
                recursive = recursive,
                expiresAt = expiresAt?.let { formatInstant(it) }
            )

            val response = apiService.shareFolder(request)

            if (response.isSuccessful) {
                val share = response.body()!!.data.toDomain()
                analyticsManager.trackShare("folder", permission.toString())
                Result.success(share)
            } else {
                when (response.code()) {
                    403 -> Result.error(AppException.Forbidden("Cannot share this folder"))
                    404 -> Result.error(AppException.NotFound("Folder or user not found"))
                    409 -> Result.error(AppException.ValidationError("Share already exists"))
                    else -> Result.error(AppException.Unknown("Failed to share folder: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to share folder", e))
        }
    }

    override suspend fun updatePermission(
        shareId: String,
        permission: SharePermission
    ): Result<Share> {
        return try {
            // Create signature for permission update
            val signature = keyEncapsulation.signPermissionUpdate(shareId, permission.toString())

            val request = UpdatePermissionRequest(
                permission = permission.toString(),
                signature = signature
            )

            val response = apiService.updateSharePermission(shareId, request)

            if (response.isSuccessful) {
                val share = response.body()!!.data.toDomain()
                Result.success(share)
            } else {
                when (response.code()) {
                    403 -> Result.error(AppException.Forbidden("Cannot update this share"))
                    404 -> Result.error(AppException.NotFound("Share not found"))
                    else -> Result.error(AppException.Unknown("Failed to update permission"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to update permission", e))
        }
    }

    override suspend fun updatePermission(
        shareId: String,
        permission: String
    ): Result<Share> {
        val permissionEnum = try {
            SharePermission.fromString(permission)
        } catch (e: Exception) {
            return Result.error(AppException.ValidationError("Invalid permission: $permission"))
        }
        return updatePermission(shareId, permissionEnum)
    }

    override suspend fun shareFile(
        fileId: String,
        recipientId: String,
        permission: String
    ): Result<Share> {
        return try {
            // Fetch recipient's public keys
            val userResponse = apiService.getUser(recipientId)
            if (!userResponse.isSuccessful) {
                return Result.error(AppException.NotFound("Recipient not found"))
            }

            val userDto = userResponse.body()!!.data
            val user = userDto.toDomain()

            val permissionEnum = try {
                SharePermission.fromString(permission)
            } catch (e: Exception) {
                return Result.error(AppException.ValidationError("Invalid permission: $permission"))
            }

            shareFile(fileId, user, permissionEnum, null)
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to share file", e))
        }
    }

    override suspend fun shareFolder(
        folderId: String,
        recipientId: String,
        permission: String
    ): Result<Share> {
        return try {
            // Fetch recipient's public keys
            val userResponse = apiService.getUser(recipientId)
            if (!userResponse.isSuccessful) {
                return Result.error(AppException.NotFound("Recipient not found"))
            }

            val userDto = userResponse.body()!!.data
            val user = userDto.toDomain()

            val permissionEnum = try {
                SharePermission.fromString(permission)
            } catch (e: Exception) {
                return Result.error(AppException.ValidationError("Invalid permission: $permission"))
            }

            shareFolder(folderId, user, permissionEnum, true, null)
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to share folder", e))
        }
    }

    override suspend fun setExpiry(
        shareId: String,
        expiresAt: Instant?
    ): Result<Share> {
        return try {
            val request = SetExpiryRequest(
                expiresAt = expiresAt?.let { formatInstant(it) }
            )

            val response = apiService.setShareExpiry(shareId, request)

            if (response.isSuccessful) {
                val share = response.body()!!.data.toDomain()
                Result.success(share)
            } else {
                when (response.code()) {
                    403 -> Result.error(AppException.Forbidden("Cannot update this share"))
                    404 -> Result.error(AppException.NotFound("Share not found"))
                    else -> Result.error(AppException.Unknown("Failed to set expiry"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to set expiry", e))
        }
    }

    override suspend fun revokeShare(shareId: String): Result<Unit> {
        return try {
            val response = apiService.revokeShare(shareId)
            if (response.isSuccessful) {
                shareDao.deleteById(shareId)
                Result.success(Unit)
            } else {
                Result.error(AppException.Unknown("Failed to revoke share"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to revoke share", e))
        }
    }

    override suspend fun searchUsers(query: String): Result<List<User>> {
        return try {
            val response = apiService.searchUsers(query)

            if (response.isSuccessful) {
                val users = response.body()!!.data.map { it.toDomain() }
                Result.success(users)
            } else {
                Result.error(AppException.Unknown("Failed to search users"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to search users", e))
        }
    }

    override suspend fun syncShares(): Result<Unit> {
        return try {
            // Fetch received shares
            val receivedResponse = apiService.getReceivedShares()
            if (receivedResponse.isSuccessful) {
                val receivedEntities = receivedResponse.body()!!.data.map { it.toEntity() }
                shareDao.insertAll(receivedEntities)
            }

            // Fetch created shares
            val createdResponse = apiService.getCreatedShares()
            if (createdResponse.isSuccessful) {
                val createdEntities = createdResponse.body()!!.data.map { it.toEntity() }
                shareDao.insertAll(createdEntities)
            }

            Result.success(Unit)
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to sync shares", e))
        }
    }

    /**
     * Access a shared file - decapsulate the DEK from the share.
     *
     * @param share The share containing the wrapped key
     * @return The decapsulated DEK
     */
    suspend fun accessSharedFile(share: Share, shareDto: ShareDto): ByteArray {
        // Verify signature if grantor public keys are available
        shareDto.grantorPublicKeys?.let { grantorKeys ->
            val publicKeys = grantorKeys.toPublicKeys()
            val valid = keyEncapsulation.verifyShareSignature(
                wrappedKey = shareDto.wrappedKey,
                kemCiphertext = shareDto.kemCiphertext,
                mlKemCiphertext = shareDto.mlKemCiphertext,
                signature = shareDto.signature,
                grantorPublicKeys = publicKeys,
                resourceType = share.resourceType.toString(),
                resourceId = share.resourceId,
                permission = share.permission.toString(),
                recursive = if (share.resourceType == ResourceType.FOLDER) share.recursive else null
            )

            if (!valid) {
                throw AppException.CryptoError("Share signature verification failed")
            }
        }

        // Decapsulate the shared key
        return keyEncapsulation.decapsulateSharedKey(
            wrappedKey = shareDto.wrappedKey,
            kemCiphertext = shareDto.kemCiphertext,
            mlKemCiphertext = shareDto.mlKemCiphertext
        )
    }

    /**
     * Access a shared folder - decapsulate and cache the KEK.
     *
     * @param share The share containing the wrapped key
     * @param shareDto The full share DTO with crypto fields
     */
    suspend fun accessSharedFolder(share: Share, shareDto: ShareDto) {
        // Decapsulate the KEK
        val kek = accessSharedFile(share, shareDto)

        // Cache the KEK for future access
        folderKeyManager.cacheKek(share.resourceId, kek)
    }

    // ==================== Helper Methods ====================

    private fun formatInstant(instant: Instant): String {
        return DateTimeFormatter.ISO_INSTANT.format(instant)
    }

    private fun ShareDto.toDomain(): Share {
        return Share(
            id = id,
            grantorId = grantorId,
            granteeId = granteeId,
            resourceType = ResourceType.fromString(resourceType),
            resourceId = resourceId,
            permission = SharePermission.fromString(permission),
            recursive = recursive ?: false,
            expiresAt = expiresAt?.let { Instant.parse(it) },
            revokedAt = revokedAt?.let { Instant.parse(it) },
            grantor = grantor?.toDomain(),
            grantee = grantee?.toDomain(),
            createdAt = Instant.parse(insertedAt),
            updatedAt = Instant.parse(updatedAt)
        )
    }

    private fun my.ssdid.drive.data.remote.dto.UserDto.toDomain(): User {
        return User(
            id = id,
            email = email,
            tenantId = tenantId,
            role = role?.let { UserRole.fromString(it) },
            publicKeys = publicKeys?.toPublicKeys(),
            storageQuota = storageQuota,
            storageUsed = storageUsed
        )
    }

    private fun my.ssdid.drive.data.remote.dto.PublicKeysDto.toPublicKeys(): PublicKeys {
        return PublicKeys(
            kem = Base64.decode(kem, Base64.NO_WRAP),
            sign = Base64.decode(sign, Base64.NO_WRAP),
            mlKem = mlKem?.let { Base64.decode(it, Base64.NO_WRAP) },
            mlDsa = mlDsa?.let { Base64.decode(it, Base64.NO_WRAP) }
        )
    }

    private fun ShareDto.toEntity(): ShareEntity {
        return ShareEntity(
            id = id,
            grantorId = grantorId,
            granteeId = granteeId,
            resourceType = resourceType,
            resourceId = resourceId,
            permission = permission,
            wrappedKey = Base64.decode(wrappedKey, Base64.NO_WRAP),
            kemCiphertext = Base64.decode(kemCiphertext, Base64.NO_WRAP),
            signature = Base64.decode(signature, Base64.NO_WRAP),
            recursive = recursive,
            expiresAt = expiresAt?.let { Instant.parse(it) },
            revokedAt = revokedAt?.let { Instant.parse(it) },
            grantorEmail = grantor?.email,
            granteeEmail = grantee?.email,
            insertedAt = Instant.parse(insertedAt),
            updatedAt = Instant.parse(updatedAt)
        )
    }
}
