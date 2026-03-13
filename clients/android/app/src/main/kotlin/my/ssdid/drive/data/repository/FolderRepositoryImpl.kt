package my.ssdid.drive.data.repository

import my.ssdid.drive.crypto.FolderKeyManager
import android.util.Base64
import my.ssdid.drive.data.local.dao.FolderDao
import my.ssdid.drive.data.local.entity.FolderEntity
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.CreateFolderRequest
import my.ssdid.drive.data.remote.dto.FolderDto
import my.ssdid.drive.data.remote.dto.UpdateFolderRequest
import my.ssdid.drive.domain.model.Folder
import my.ssdid.drive.domain.model.FolderMetadata
import my.ssdid.drive.domain.repository.FolderRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FolderRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val folderDao: FolderDao,
    private val folderKeyManager: FolderKeyManager
) : FolderRepository {

    override suspend fun getRootFolder(): Result<Folder> {
        return try {
            val response = apiService.getRootFolder()

            if (response.isSuccessful) {
                val folderDto = response.body()!!.data
                val folder = try {
                    decryptFolder(folderDto)
                } catch (_: Exception) {
                    // Root folder may not have encryption keys yet (e.g. auto-created for new tenants)
                    if (folderDto.isRoot) {
                        initializeRootFolderEncryption(folderDto)
                    } else {
                        return Result.error(AppException.CryptoError("Failed to decrypt folder"))
                    }
                }
                Result.success(folder)
            } else {
                Result.error(AppException.Unknown("Failed to get root folder"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get root folder", e))
        }
    }

    /**
     * Initialize encryption for a root folder that was auto-created without keys.
     * Generates KEK, wraps with owner keys, updates backend, and caches the KEK.
     */
    private suspend fun initializeRootFolderEncryption(folderDto: FolderDto): Folder {
        val encryptionData = folderKeyManager.createRootFolderEncryption("My Files")

        // Cache the KEK so createFolder() can use it
        folderKeyManager.cacheKek(folderDto.id, encryptionData.kek)

        // Create signature
        val signature = folderKeyManager.createFolderSignature(
            folderId = folderDto.id,
            parentId = null,
            encryptedMetadata = encryptionData.encryptedMetadata,
            metadataNonce = encryptionData.metadataNonce,
            ownerWrappedKek = encryptionData.ownerWrappedKek,
            ownerKemCiphertext = encryptionData.ownerKemCiphertext,
            ownerMlKemCiphertext = encryptionData.ownerMlKemCiphertext,
            wrappedKek = encryptionData.wrappedKek,
            kemCiphertext = encryptionData.kemCiphertext.ifEmpty { null },
            mlKemCiphertext = encryptionData.mlKemCiphertext
        )

        // Update backend with encryption data
        val updateRequest = UpdateFolderRequest(
            encryptedMetadata = encryptionData.encryptedMetadata,
            metadataNonce = encryptionData.metadataNonce,
            wrappedKek = encryptionData.wrappedKek,
            kemCiphertext = encryptionData.kemCiphertext.ifEmpty { null },
            ownerWrappedKek = encryptionData.ownerWrappedKek,
            ownerKemCiphertext = encryptionData.ownerKemCiphertext,
            mlKemCiphertext = encryptionData.mlKemCiphertext,
            ownerMlKemCiphertext = encryptionData.ownerMlKemCiphertext,
            signature = signature
        )
        apiService.updateFolder(folderDto.id, updateRequest)

        return Folder(
            id = folderDto.id,
            parentId = folderDto.parentId,
            ownerId = folderDto.ownerId,
            tenantId = folderDto.tenantId,
            isRoot = true,
            name = "My Files",
            createdAt = java.time.OffsetDateTime.parse(folderDto.createdAt).toInstant(),
            updatedAt = java.time.OffsetDateTime.parse(folderDto.updatedAt).toInstant()
        )
    }

    override fun observeRootFolder(): Flow<Folder?> {
        return folderDao.observeRootFolder().map { entity ->
            entity?.let {
                Folder(
                    id = it.id,
                    parentId = it.parentId,
                    ownerId = it.ownerId,
                    tenantId = it.tenantId,
                    isRoot = it.isRoot,
                    name = it.cachedName ?: "My Files",
                    createdAt = it.insertedAt,
                    updatedAt = it.updatedAt
                )
            }
        }
    }

    override suspend fun getFolder(folderId: String): Result<Folder> {
        return try {
            val response = apiService.getFolder(folderId)

            if (response.isSuccessful) {
                val folderDto = response.body()!!.data
                val folder = decryptFolder(folderDto)
                Result.success(folder)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Folder not found"))
                    403 -> Result.error(AppException.Forbidden("Access denied"))
                    else -> Result.error(AppException.Unknown("Failed to get folder"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get folder", e))
        }
    }

    override fun observeFolder(folderId: String): Flow<Folder?> {
        return folderDao.observeById(folderId).map { entity ->
            entity?.let {
                Folder(
                    id = it.id,
                    parentId = it.parentId,
                    ownerId = it.ownerId,
                    tenantId = it.tenantId,
                    isRoot = it.isRoot,
                    name = it.cachedName ?: "Folder",
                    createdAt = it.insertedAt,
                    updatedAt = it.updatedAt
                )
            }
        }
    }

    override suspend fun getChildFolders(parentId: String): Result<List<Folder>> {
        return try {
            val response = apiService.getFolderChildren(parentId)

            if (response.isSuccessful) {
                val folders = response.body()!!.data.mapNotNull { folderDto ->
                    try {
                        decryptFolder(folderDto)
                    } catch (_: Exception) {
                        null
                    }
                }
                Result.success(folders)
            } else {
                Result.error(AppException.Unknown("Failed to get child folders"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get child folders", e))
        }
    }

    override fun observeChildFolders(parentId: String): Flow<List<Folder>> {
        return folderDao.observeChildren(parentId).map { entities ->
            entities.map {
                Folder(
                    id = it.id,
                    parentId = it.parentId,
                    ownerId = it.ownerId,
                    tenantId = it.tenantId,
                    isRoot = it.isRoot,
                    name = it.cachedName ?: "Folder",
                    createdAt = it.insertedAt,
                    updatedAt = it.updatedAt
                )
            }
        }
    }

    override suspend fun createFolder(parentId: String, name: String): Result<Folder> {
        return try {
            // Get parent folder's KEK
            val parentKek = folderKeyManager.getCachedKek(parentId)
                ?: return Result.error(AppException.CryptoError("Parent folder KEK not available"))

            // Create encryption data for new folder
            val encryptionData = folderKeyManager.createChildFolderEncryption(name, parentKek)

            // Cache the new folder's KEK (we'll need it if user navigates into it)
            // Note: We don't have the folder ID yet, will cache after response

            val request = CreateFolderRequest(
                parentId = parentId,
                encryptedMetadata = encryptionData.encryptedMetadata,
                metadataNonce = encryptionData.metadataNonce,
                wrappedKek = encryptionData.wrappedKek,
                kemCiphertext = encryptionData.kemCiphertext.ifEmpty { null },
                ownerWrappedKek = encryptionData.ownerWrappedKek,
                ownerKemCiphertext = encryptionData.ownerKemCiphertext,
                mlKemCiphertext = encryptionData.mlKemCiphertext,
                ownerMlKemCiphertext = encryptionData.ownerMlKemCiphertext,
                signature = folderKeyManager.createFolderSignature(
                    folderId = null,
                    parentId = parentId,
                    encryptedMetadata = encryptionData.encryptedMetadata,
                    metadataNonce = encryptionData.metadataNonce,
                    ownerWrappedKek = encryptionData.ownerWrappedKek,
                    ownerKemCiphertext = encryptionData.ownerKemCiphertext,
                    ownerMlKemCiphertext = encryptionData.ownerMlKemCiphertext,
                    wrappedKek = encryptionData.wrappedKek,
                    kemCiphertext = encryptionData.kemCiphertext.ifEmpty { null },
                    mlKemCiphertext = encryptionData.mlKemCiphertext
                )
            )

            val response = apiService.createFolder(request)

            if (response.isSuccessful) {
                val folderDto = response.body()!!.data

                // Cache the KEK for the new folder
                folderKeyManager.cacheKek(folderDto.id, encryptionData.kek)

                val folder = Folder(
                    id = folderDto.id,
                    parentId = folderDto.parentId,
                    ownerId = folderDto.ownerId,
                    tenantId = folderDto.tenantId,
                    isRoot = folderDto.isRoot,
                    name = name,
                    createdAt = java.time.OffsetDateTime.parse(folderDto.createdAt).toInstant(),
                    updatedAt = java.time.OffsetDateTime.parse(folderDto.updatedAt).toInstant()
                )
                Result.success(folder)
            } else {
                when (response.code()) {
                    403 -> Result.error(AppException.Forbidden("Cannot create folder here"))
                    404 -> Result.error(AppException.NotFound("Parent folder not found"))
                    else -> Result.error(AppException.Unknown("Failed to create folder: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to create folder", e))
        }
    }

    override suspend fun renameFolder(folderId: String, newName: String): Result<Folder> {
        return try {
            // Get folder's KEK
            val kek = folderKeyManager.getCachedKek(folderId)
                ?: return Result.error(AppException.CryptoError("Folder KEK not available"))

            val currentResponse = apiService.getFolder(folderId)
            if (!currentResponse.isSuccessful) {
                return Result.error(AppException.Unknown("Failed to load folder for update"))
            }
            val currentFolder = currentResponse.body()!!.data

            // Encrypt new metadata
            val metadata = FolderMetadata(name = newName)
            val encryptedMetadata = folderKeyManager.encryptMetadata(metadata, kek)
            val metadataNonce = folderKeyManager.extractMetadataNonce(encryptedMetadata)

            val signature = folderKeyManager.createFolderSignature(
                folderId = currentFolder.id,
                parentId = currentFolder.parentId,
                encryptedMetadata = encryptedMetadata,
                metadataNonce = metadataNonce,
                ownerWrappedKek = currentFolder.ownerWrappedKek,
                ownerKemCiphertext = currentFolder.ownerKemCiphertext,
                ownerMlKemCiphertext = currentFolder.ownerMlKemCiphertext,
                wrappedKek = currentFolder.wrappedKek,
                kemCiphertext = currentFolder.kemCiphertext,
                mlKemCiphertext = currentFolder.mlKemCiphertext
            )

            val request = UpdateFolderRequest(
                encryptedMetadata = encryptedMetadata,
                metadataNonce = metadataNonce,
                signature = signature
            )

            val response = apiService.updateFolder(folderId, request)

            if (response.isSuccessful) {
                val folderDto = response.body()!!.data
                val folder = Folder(
                    id = folderDto.id,
                    parentId = folderDto.parentId,
                    ownerId = folderDto.ownerId,
                    tenantId = folderDto.tenantId,
                    isRoot = folderDto.isRoot,
                    name = newName,
                    createdAt = java.time.OffsetDateTime.parse(folderDto.createdAt).toInstant(),
                    updatedAt = java.time.OffsetDateTime.parse(folderDto.updatedAt).toInstant()
                )
                Result.success(folder)
            } else {
                when (response.code()) {
                    403 -> Result.error(AppException.Forbidden("Cannot rename folder"))
                    404 -> Result.error(AppException.NotFound("Folder not found"))
                    else -> Result.error(AppException.Unknown("Failed to rename folder"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to rename folder", e))
        }
    }

    override suspend fun deleteFolder(folderId: String): Result<Unit> {
        return try {
            val response = apiService.deleteFolder(folderId)
            if (response.isSuccessful) {
                folderDao.deleteById(folderId)
                Result.success(Unit)
            } else {
                Result.error(AppException.Unknown("Failed to delete folder"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to delete folder", e))
        }
    }

    override suspend fun moveFolder(folderId: String, newParentId: String): Result<Folder> {
        return try {
            // Get folder's current KEK
            val kek = folderKeyManager.getCachedKek(folderId)
                ?: return Result.error(AppException.CryptoError("Folder KEK not available"))

            val currentResponse = apiService.getFolder(folderId)
            if (!currentResponse.isSuccessful) {
                return Result.error(AppException.Unknown("Failed to load folder for move"))
            }
            val currentFolder = currentResponse.body()!!.data

            // Get new parent's KEK to re-wrap the folder's KEK
            val newParentKek = folderKeyManager.getCachedKek(newParentId)
                ?: return Result.error(AppException.CryptoError("New parent folder KEK not available"))

            // Re-wrap KEK for new parent
            val rewrapResult = folderKeyManager.rewrapKekForParent(kek, newParentKek)
            val metadataNonce = currentFolder.metadataNonce
                ?: folderKeyManager.extractMetadataNonce(
                    currentFolder.encryptedMetadata
                        ?: return Result.error(AppException.CryptoError("Missing encrypted metadata"))
                )

            // Create move request
            val request = my.ssdid.drive.data.remote.dto.MoveFolderRequest(
                parentId = newParentId,
                wrappedKek = rewrapResult.wrappedKek,
                kemCiphertext = rewrapResult.kemCiphertext,
                signature = folderKeyManager.createFolderSignature(
                    folderId = currentFolder.id,
                    parentId = newParentId,
                    encryptedMetadata = currentFolder.encryptedMetadata
                        ?: return Result.error(AppException.CryptoError("Missing encrypted metadata")),
                    metadataNonce = metadataNonce,
                    ownerWrappedKek = currentFolder.ownerWrappedKek,
                    ownerKemCiphertext = currentFolder.ownerKemCiphertext,
                    ownerMlKemCiphertext = currentFolder.ownerMlKemCiphertext,
                    wrappedKek = rewrapResult.wrappedKek,
                    kemCiphertext = rewrapResult.kemCiphertext,
                    mlKemCiphertext = currentFolder.mlKemCiphertext
                )
            )

            val response = apiService.moveFolder(folderId, request)

            if (response.isSuccessful) {
                val folderDto = response.body()!!.data
                val folder = decryptFolder(folderDto)
                Result.success(folder)
            } else {
                when (response.code()) {
                    403 -> Result.error(AppException.Forbidden("Cannot move folder here"))
                    404 -> Result.error(AppException.NotFound("Folder not found"))
                    409 -> Result.error(AppException.Conflict("Cannot move folder into itself"))
                    else -> Result.error(AppException.Unknown("Failed to move folder"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to move folder", e))
        }
    }

    override suspend fun syncFolders(): Result<Unit> {
        return try {
            val response = apiService.listFolders()

            if (response.isSuccessful) {
                val folderEntities = response.body()!!.data.mapNotNull { folderDto ->
                    try {
                        val folder = decryptFolder(folderDto)
                        folderDto.toEntity(cachedName = folder.name)
                    } catch (e: Exception) {
                        // Skip folders we can't decrypt
                        null
                    }
                }

                // Insert all folders (replace existing)
                folderDao.insertAll(folderEntities)
                Result.success(Unit)
            } else {
                Result.error(AppException.Unknown("Failed to sync folders"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to sync folders", e))
        }
    }

    private fun FolderDto.toEntity(cachedName: String?): FolderEntity {
        return FolderEntity(
            id = id,
            parentId = parentId,
            ownerId = ownerId,
            tenantId = tenantId,
            isRoot = isRoot,
            encryptedMetadata = encryptedMetadata?.let { Base64.decode(it, Base64.NO_WRAP) } ?: ByteArray(0),
            wrappedKek = Base64.decode(wrappedKek, Base64.NO_WRAP),
            kemCiphertext = kemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) } ?: ByteArray(0),
            signature = signature?.let { Base64.decode(it, Base64.NO_WRAP) } ?: ByteArray(0),
            cachedName = cachedName,
            insertedAt = java.time.OffsetDateTime.parse(createdAt).toInstant(),
            updatedAt = java.time.OffsetDateTime.parse(updatedAt).toInstant()
        )
    }

    override suspend fun getAllFolders(): Result<List<Folder>> {
        return try {
            val response = apiService.listFolders()

            if (response.isSuccessful) {
                val folders = response.body()!!.data.mapNotNull { folderDto ->
                    try {
                        decryptFolder(folderDto)
                    } catch (_: Exception) {
                        null
                    }
                }
                Result.success(folders)
            } else {
                Result.error(AppException.Unknown("Failed to get folders"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get folders", e))
        }
    }

    /**
     * Decrypt a folder DTO into a domain Folder.
     *
     * Decrypts the KEK using owner access, then decrypts the metadata.
     */
    private fun decryptFolder(dto: FolderDto): Folder {
        val encryptedMetadata = dto.encryptedMetadata
            ?: throw AppException.CryptoError("Missing encrypted metadata")

        val signature = dto.signature
        if (!signature.isNullOrBlank()) {
            val ownerKeys = dto.owner?.publicKeys?.toPublicKeys()
                ?: throw AppException.CryptoError("Missing owner public keys for folder verification")
            val metadataNonce = dto.metadataNonce ?: folderKeyManager.extractMetadataNonce(encryptedMetadata)
            val signatureValid = folderKeyManager.verifyFolderSignature(
                folderId = dto.id,
                parentId = dto.parentId,
                encryptedMetadata = encryptedMetadata,
                metadataNonce = metadataNonce,
                ownerWrappedKek = dto.ownerWrappedKek,
                ownerKemCiphertext = dto.ownerKemCiphertext,
                ownerMlKemCiphertext = dto.ownerMlKemCiphertext,
                wrappedKek = dto.wrappedKek,
                kemCiphertext = dto.kemCiphertext,
                mlKemCiphertext = dto.mlKemCiphertext,
                signature = signature,
                ownerPublicKeys = ownerKeys
            )
            if (!signatureValid) {
                throw AppException.CryptoError("Folder signature verification failed - folder may be tampered")
            }
        }

        // Decrypt KEK using owner access (always available)
        val kek = folderKeyManager.decryptFolderKek(
            folderId = dto.id,
            ownerKemCiphertext = dto.ownerKemCiphertext,
            ownerWrappedKek = dto.ownerWrappedKek,
            ownerMlKemCiphertext = dto.ownerMlKemCiphertext
        )

        // Decrypt metadata
        val name = if (encryptedMetadata.isNotEmpty()) {
            try {
                val metadata = folderKeyManager.decryptMetadata(encryptedMetadata, kek)
                metadata.name
            } catch (e: Exception) {
                // Fallback for root folder or decryption errors
                if (dto.isRoot) "My Files" else "Folder"
            }
        } else {
            // No encrypted metadata (shouldn't happen, but handle gracefully)
            if (dto.isRoot) "My Files" else "Folder"
        }

        return Folder(
            id = dto.id,
            parentId = dto.parentId,
            ownerId = dto.ownerId,
            tenantId = dto.tenantId,
            isRoot = dto.isRoot,
            name = name,
            createdAt = java.time.OffsetDateTime.parse(dto.createdAt).toInstant(),
            updatedAt = java.time.OffsetDateTime.parse(dto.updatedAt).toInstant()
        )
    }

    private fun my.ssdid.drive.data.remote.dto.PublicKeysDto.toPublicKeys(): my.ssdid.drive.domain.model.PublicKeys {
        return my.ssdid.drive.domain.model.PublicKeys(
            kem = Base64.decode(kem, Base64.NO_WRAP),
            sign = Base64.decode(sign, Base64.NO_WRAP),
            mlKem = mlKem?.let { Base64.decode(it, Base64.NO_WRAP) },
            mlDsa = mlDsa?.let { Base64.decode(it, Base64.NO_WRAP) }
        )
    }
}
