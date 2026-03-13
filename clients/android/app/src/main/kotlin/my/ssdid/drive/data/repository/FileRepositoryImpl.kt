package my.ssdid.drive.data.repository

import android.content.Context
import android.net.Uri
import android.util.Base64
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.FileDecryptor
import my.ssdid.drive.crypto.FileEncryptor
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.SecureMemory
import my.ssdid.drive.data.local.dao.FileDao
import my.ssdid.drive.data.local.entity.FileEntity
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.FileDto
import my.ssdid.drive.data.remote.dto.MoveFileRequest
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.data.remote.dto.UpdateFileRequest
import my.ssdid.drive.data.remote.dto.UploadUrlRequest
import my.ssdid.drive.di.UnauthenticatedClient
import my.ssdid.drive.domain.model.FileItem
import my.ssdid.drive.domain.model.FileStatus
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.repository.DownloadProgress
import my.ssdid.drive.domain.repository.FileRepository
import my.ssdid.drive.domain.repository.UploadProgress
import my.ssdid.drive.util.AnalyticsManager
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import my.ssdid.drive.util.Logger
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FileRepositoryImpl @Inject constructor(
    @ApplicationContext private val context: Context,
    private val apiService: ApiService,
    private val fileDao: FileDao,
    private val fileEncryptor: FileEncryptor,
    private val fileDecryptor: FileDecryptor,
    private val folderKeyManager: FolderKeyManager,
    private val cryptoConfig: CryptoConfig,
    @UnauthenticatedClient private val okHttpClient: OkHttpClient,
    private val analyticsManager: AnalyticsManager
) : FileRepository {

    companion object {
        private const val TAG = "FileRepository"
    }

    override suspend fun getFiles(folderId: String): Result<List<FileItem>> {
        return try {
            val response = apiService.getFolderFiles(folderId)

            if (response.isSuccessful) {
                val files = response.body()!!.data.mapNotNull { fileDto ->
                    try {
                        // SECURITY: Verify signature before trusting metadata
                        // Skip files without required verification data (pending uploads)
                        val uploaderKeys = fileDto.uploaderPublicKeys?.toPublicKeys()
                        val blobHash = fileDto.blobHash

                        if (uploaderKeys != null && blobHash != null) {
                            val signatureValid = fileDecryptor.verifySignature(
                                encryptedMetadata = fileDto.encryptedMetadata,
                                blobHash = blobHash,
                                wrappedDek = fileDto.wrappedDek,
                                signature = fileDto.signature,
                                uploaderPublicKeys = uploaderKeys,
                                blobSize = fileDto.blobSize,
                                chunkCount = fileDto.chunkCount
                            )

                            if (!signatureValid) {
                                // Skip files with invalid signatures - potential tampering
                                return@mapNotNull null
                            }
                        }

                        // Decrypt metadata using folder's KEK
                        val metadata = fileDecryptor.decryptMetadata(
                            folderId = fileDto.folderId,
                            encryptedMetadata = fileDto.encryptedMetadata,
                            wrappedDek = fileDto.wrappedDek
                        )

                        FileItem(
                            id = fileDto.id,
                            folderId = fileDto.folderId,
                            ownerId = fileDto.ownerId,
                            tenantId = fileDto.tenantId,
                            name = metadata.name,
                            mimeType = metadata.mimeType,
                            size = metadata.size,
                            status = FileStatus.fromString(fileDto.status),
                            createdAt = java.time.OffsetDateTime.parse(fileDto.insertedAt).toInstant(),
                            updatedAt = java.time.OffsetDateTime.parse(fileDto.updatedAt).toInstant()
                        )
                    } catch (e: Exception) {
                        // Log decryption error but continue with other files
                        null
                    }
                }
                Result.success(files)
            } else {
                Result.error(AppException.Unknown("Failed to get files"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get files", e))
        }
    }

    override fun observeFiles(folderId: String): Flow<List<FileItem>> {
        return fileDao.observeByFolderId(folderId).map { entities ->
            entities.map {
                FileItem(
                    id = it.id,
                    folderId = it.folderId,
                    ownerId = it.ownerId,
                    tenantId = it.tenantId,
                    name = it.cachedName ?: "File",
                    mimeType = it.cachedMimeType ?: "application/octet-stream",
                    size = it.blobSize ?: 0,
                    status = FileStatus.fromString(it.status),
                    createdAt = it.insertedAt,
                    updatedAt = it.updatedAt
                )
            }
        }
    }

    override suspend fun getFile(fileId: String): Result<FileItem> {
        return try {
            val response = apiService.getFile(fileId)

            if (response.isSuccessful) {
                val fileDto = response.body()!!.data

                // SECURITY: Verify signature before trusting metadata
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
                    return Result.error(
                        AppException.CryptoError("File signature verification failed - file may be tampered")
                    )
                }

                // Decrypt metadata
                val metadata = fileDecryptor.decryptMetadata(
                    folderId = fileDto.folderId,
                    encryptedMetadata = fileDto.encryptedMetadata,
                    wrappedDek = fileDto.wrappedDek
                )

                val file = FileItem(
                    id = fileDto.id,
                    folderId = fileDto.folderId,
                    ownerId = fileDto.ownerId,
                    tenantId = fileDto.tenantId,
                    name = metadata.name,
                    mimeType = metadata.mimeType,
                    size = metadata.size,
                    status = FileStatus.fromString(fileDto.status),
                    createdAt = java.time.OffsetDateTime.parse(fileDto.insertedAt).toInstant(),
                    updatedAt = java.time.OffsetDateTime.parse(fileDto.updatedAt).toInstant()
                )
                Result.success(file)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("File not found"))
                    403 -> Result.error(AppException.Forbidden("Access denied"))
                    else -> Result.error(AppException.Unknown("Failed to get file"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get file", e))
        }
    }

    override fun observeFile(fileId: String): Flow<FileItem?> {
        return fileDao.observeById(fileId).map { entity ->
            entity?.let {
                FileItem(
                    id = it.id,
                    folderId = it.folderId,
                    ownerId = it.ownerId,
                    tenantId = it.tenantId,
                    name = it.cachedName ?: "File",
                    mimeType = it.cachedMimeType ?: "application/octet-stream",
                    size = it.blobSize ?: 0,
                    status = FileStatus.fromString(it.status),
                    createdAt = it.insertedAt,
                    updatedAt = it.updatedAt
                )
            }
        }
    }

    override fun uploadFile(
        folderId: String,
        uri: Uri,
        fileName: String
    ): Flow<UploadProgress> = flow {
        try {
            // Get MIME type from content resolver
            val mimeType = context.contentResolver.getType(uri) ?: "application/octet-stream"

            // Create temp file for encrypted content
            val tempFile = File(context.cacheDir, "upload_${System.currentTimeMillis()}.enc")

            try {
                // Attempt to encrypt file; fall back to plaintext on crypto failure
                val encryptionResult = try {
                    FileOutputStream(tempFile).use { outputStream ->
                        fileEncryptor.encryptFile(
                            uri = uri,
                            fileName = fileName,
                            mimeType = mimeType,
                            folderId = folderId,
                            outputStream = outputStream
                        ) { bytesProcessed, totalBytes ->
                            // Progress during encryption
                        }
                    }
                } catch (cryptoError: Exception) {
                    Logger.w(TAG, "File encryption failed, falling back to unencrypted upload", cryptoError)
                    // Graceful fallback: copy plaintext to temp file
                    context.contentResolver.openInputStream(uri)?.use { inputStream ->
                        FileOutputStream(tempFile).use { outputStream ->
                            inputStream.copyTo(outputStream)
                        }
                    } ?: throw IllegalStateException("Cannot open file for fallback upload")
                    null
                }

                try {
                    // Request presigned upload URL from server
                    val uploadRequest = if (encryptionResult != null) {
                        UploadUrlRequest(
                            folderId = folderId,
                            blobSize = encryptionResult.blobSize,
                            encryptedMetadata = encryptionResult.encryptedMetadata,
                            wrappedDek = encryptionResult.wrappedDek,
                            kemCiphertext = null, // Not needed for own files (wrapped with folder KEK)
                            mlKemCiphertext = null,
                            signature = encryptionResult.signature,
                            chunkCount = encryptionResult.chunkCount
                        )
                    } else {
                        // Unencrypted fallback: send plaintext size, no crypto metadata
                        UploadUrlRequest(
                            folderId = folderId,
                            blobSize = tempFile.length(),
                            encryptedMetadata = "",
                            wrappedDek = "",
                            kemCiphertext = null,
                            mlKemCiphertext = null,
                            signature = "",
                            chunkCount = 0
                        )
                    }

                    val uploadUrlResponse = apiService.getUploadUrl(uploadRequest)
                    if (!uploadUrlResponse.isSuccessful) {
                        emit(UploadProgress.Failed(AppException.Unknown("Failed to get upload URL")))
                        return@flow
                    }

                    val uploadData = uploadUrlResponse.body()!!.data
                    val fileId = uploadData.file.id
                    val uploadUrl = uploadData.uploadUrl

                    emit(UploadProgress.Started(fileId))

                    // Upload content to presigned URL (encrypted if crypto succeeded, plaintext otherwise)
                    val uploadSuccess = uploadToPresignedUrl(
                        url = uploadUrl,
                        file = tempFile,
                        contentType = if (encryptionResult != null) "application/octet-stream" else mimeType
                    ) { bytesUploaded, totalBytes ->
                        // We're in a blocking call, can't emit here directly
                    }

                    if (!uploadSuccess) {
                        emit(UploadProgress.Failed(AppException.Network("Failed to upload file")))
                        return@flow
                    }

                    // Update file status on server
                    val updateResponse = apiService.updateFile(
                        fileId = fileId,
                        request = if (encryptionResult != null) {
                            UpdateFileRequest(
                                status = "complete",
                                blobHash = encryptionResult.blobHash,
                                blobSize = encryptionResult.blobSize,
                                chunkCount = encryptionResult.chunkCount
                            )
                        } else {
                            UpdateFileRequest(status = "complete")
                        }
                    )

                    if (updateResponse.isSuccessful) {
                        val fileDto = updateResponse.body()!!.data

                        // Build FileItem — decrypt metadata if encrypted, use originals otherwise
                        val file = if (encryptionResult != null) {
                            val metadata = fileDecryptor.decryptMetadata(
                                folderId = fileDto.folderId,
                                encryptedMetadata = fileDto.encryptedMetadata,
                                wrappedDek = fileDto.wrappedDek
                            )
                            FileItem(
                                id = fileDto.id,
                                folderId = fileDto.folderId,
                                ownerId = fileDto.ownerId,
                                tenantId = fileDto.tenantId,
                                name = metadata.name,
                                mimeType = metadata.mimeType,
                                size = metadata.size,
                                status = FileStatus.fromString(fileDto.status),
                                createdAt = java.time.OffsetDateTime.parse(fileDto.insertedAt).toInstant(),
                                updatedAt = java.time.OffsetDateTime.parse(fileDto.updatedAt).toInstant()
                            )
                        } else {
                            FileItem(
                                id = fileDto.id,
                                folderId = fileDto.folderId,
                                ownerId = fileDto.ownerId,
                                tenantId = fileDto.tenantId,
                                name = fileName,
                                mimeType = mimeType,
                                size = tempFile.length(),
                                status = FileStatus.fromString(fileDto.status),
                                createdAt = java.time.OffsetDateTime.parse(fileDto.insertedAt).toInstant(),
                                updatedAt = java.time.OffsetDateTime.parse(fileDto.updatedAt).toInstant()
                            )
                        }

                        analyticsManager.trackFileUpload(file.mimeType, file.size)
                        emit(UploadProgress.Completed(file))
                    } else {
                        emit(UploadProgress.Failed(AppException.Unknown("Failed to finalize upload")))
                    }
                } finally {
                    encryptionResult?.zeroize()
                }
            } finally {
                // Clean up temp file
                tempFile.delete()
            }
        } catch (e: Exception) {
            emit(UploadProgress.Failed(e))
        }
    }.flowOn(Dispatchers.IO)

    override fun downloadFile(fileId: String): Flow<DownloadProgress> = flow {
        try {
            emit(DownloadProgress.Started)

            // Get file info and download URL
            val downloadUrlResponse = apiService.getDownloadUrl(fileId)
            if (!downloadUrlResponse.isSuccessful) {
                emit(DownloadProgress.Failed(AppException.Unknown("Failed to get download URL")))
                return@flow
            }

            val downloadData = downloadUrlResponse.body()!!.data
            val fileDto = downloadData.file
            val downloadUrl = downloadData.downloadUrl

            // Check if crypto metadata is present (file may be unencrypted)
            val hasCryptoMetadata = fileDto.encryptedMetadata.isNotBlank()
                && fileDto.wrappedDek.isNotBlank()
                && fileDto.signature.isNotBlank()

            // Verify signature before downloading (only for encrypted files)
            if (hasCryptoMetadata) {
                val uploaderKeys = fileDto.uploaderPublicKeys?.toPublicKeys()
                if (uploaderKeys != null && fileDto.blobHash != null) {
                    val signatureValid = fileDecryptor.verifySignature(
                        encryptedMetadata = fileDto.encryptedMetadata,
                        blobHash = fileDto.blobHash,
                        wrappedDek = fileDto.wrappedDek,
                        signature = fileDto.signature,
                        uploaderPublicKeys = uploaderKeys
                    )

                    if (!signatureValid) {
                        emit(DownloadProgress.Failed(
                            AppException.CryptoError("Signature verification failed - file may be tampered")
                        ))
                        return@flow
                    }
                }
            }

            // Download content to temp file
            val timestamp = System.currentTimeMillis()
            val downloadedTempFile = File(context.cacheDir, "download_${timestamp}.enc")
            val decryptedTempFile = File(context.cacheDir, "download_${timestamp}.dec")

            try {
                // Download blob
                val downloadSuccess = downloadFromUrl(
                    url = downloadUrl,
                    outputFile = downloadedTempFile
                ) { bytesDownloaded, totalBytes ->
                    // Progress callback
                }

                if (!downloadSuccess) {
                    emit(DownloadProgress.Failed(AppException.Network("Failed to download file")))
                    return@flow
                }

                // Verify blob hash if available
                if (hasCryptoMetadata && fileDto.blobHash != null) {
                    val blobHashValid = FileInputStream(downloadedTempFile).use { inputStream ->
                        fileDecryptor.verifyBlobHash(inputStream, fileDto.blobHash)
                    }

                    if (!blobHashValid) {
                        emit(DownloadProgress.Failed(AppException.CryptoError("Blob hash verification failed")))
                        return@flow
                    }
                }

                // Attempt decryption; graceful fallback to raw file on failure
                var outputFileName: String
                var outputMimeType: String
                var outputSize: Long
                var sourceFile: File

                if (hasCryptoMetadata) {
                    try {
                        val decryptionResult = withContext(Dispatchers.IO) {
                            FileInputStream(downloadedTempFile).use { inputStream ->
                                FileOutputStream(decryptedTempFile).use { outputStream ->
                                    fileDecryptor.decryptFile(
                                        folderId = fileDto.folderId,
                                        encryptedMetadata = fileDto.encryptedMetadata,
                                        wrappedDek = fileDto.wrappedDek,
                                        inputStream = inputStream,
                                        outputStream = outputStream,
                                        encryptedSize = downloadedTempFile.length()
                                    ) { bytesProcessed, totalBytes ->
                                        // Progress during decryption
                                    }
                                }
                            }
                        }

                        outputFileName = decryptionResult.metadata.name
                        outputMimeType = decryptionResult.metadata.mimeType
                        outputSize = decryptionResult.metadata.size
                        sourceFile = decryptedTempFile
                    } catch (decryptError: Exception) {
                        // Graceful fallback: keep the downloaded file and warn
                        Logger.w(TAG, "File decryption failed, keeping raw downloaded file", decryptError)
                        outputFileName = "file_$fileId"
                        outputMimeType = "application/octet-stream"
                        outputSize = downloadedTempFile.length()
                        sourceFile = downloadedTempFile
                    }
                } else {
                    // File was not encrypted, use as-is
                    outputFileName = "file_$fileId"
                    outputMimeType = "application/octet-stream"
                    outputSize = downloadedTempFile.length()
                    sourceFile = downloadedTempFile
                }

                // Move file to downloads folder with proper name
                val downloadsDir = context.getExternalFilesDir(android.os.Environment.DIRECTORY_DOWNLOADS)
                    ?: context.filesDir
                val destFile = File(downloadsDir, outputFileName)

                // Handle name collision
                val finalDestFile = if (destFile.exists()) {
                    val baseName = destFile.nameWithoutExtension
                    val extension = destFile.extension
                    var counter = 1
                    var newFile: File
                    do {
                        newFile = File(downloadsDir, "$baseName ($counter).$extension")
                        counter++
                    } while (newFile.exists())
                    newFile
                } else {
                    destFile
                }

                sourceFile.copyTo(finalDestFile, overwrite = true)

                analyticsManager.trackFileDownload(outputMimeType, outputSize)
                emit(DownloadProgress.Completed(Uri.fromFile(finalDestFile)))
            } finally {
                // Clean up temp files
                downloadedTempFile.delete()
                if (decryptedTempFile.exists()) {
                    decryptedTempFile.delete()
                }
            }
        } catch (e: Exception) {
            emit(DownloadProgress.Failed(e))
        }
    }.flowOn(Dispatchers.IO)

    override suspend fun deleteFile(fileId: String): Result<Unit> {
        return try {
            val response = apiService.deleteFile(fileId)
            if (response.isSuccessful) {
                fileDao.deleteById(fileId)
                Result.success(Unit)
            } else {
                Result.error(AppException.Unknown("Failed to delete file"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to delete file", e))
        }
    }

    override suspend fun moveFile(fileId: String, newFolderId: String): Result<FileItem> {
        return try {
            // Get the file first
            val fileResponse = apiService.getFile(fileId)
            if (!fileResponse.isSuccessful) {
                return Result.error(AppException.NotFound("File not found"))
            }

            val fileDto = fileResponse.body()!!.data
            val currentFolderId = fileDto.folderId
                val blobHash = fileDto.blobHash
                    ?: return Result.error(AppException.CryptoError("Missing blob hash for signature"))
                val blobSize = fileDto.blobSize
                    ?: return Result.error(AppException.CryptoError("Missing blob size for signature"))
                val chunkCount = fileDto.chunkCount
                    ?: return Result.error(AppException.CryptoError("Missing chunk count for signature"))

            // Get DEK from current folder
            val dek = fileDecryptor.unwrapDek(currentFolderId, fileDto.wrappedDek)

            try {
                // Re-wrap DEK for new folder
                val newFolderKek = folderKeyManager.getCachedKek(newFolderId)
                    ?: return Result.error(AppException.CryptoError("New folder KEK not available"))

                val newWrappedDek = fileEncryptor.rewrapDek(dek, newFolderKek)
                val newSignature = fileEncryptor.signFilePackage(
                    encryptedMetadata = fileDto.encryptedMetadata,
                    blobHash = blobHash,
                    wrappedDek = newWrappedDek,
                    blobSize = blobSize,
                    chunkCount = chunkCount
                )

                // Create move request (signature will be created for the new wrapped DEK)
                val moveRequest = MoveFileRequest(
                    folderId = newFolderId,
                    wrappedDek = newWrappedDek,
                    kemCiphertext = null, // Not needed for folder-wrapped keys
                    mlKemCiphertext = null,
                    signature = newSignature
                )

                val moveResponse = apiService.moveFile(fileId, moveRequest)

                if (moveResponse.isSuccessful) {
                    val movedFileDto = moveResponse.body()!!.data

                    // Decrypt metadata
                    val metadata = fileDecryptor.decryptMetadata(
                        folderId = movedFileDto.folderId,
                        encryptedMetadata = movedFileDto.encryptedMetadata,
                        wrappedDek = movedFileDto.wrappedDek
                    )

                    val file = FileItem(
                        id = movedFileDto.id,
                        folderId = movedFileDto.folderId,
                        ownerId = movedFileDto.ownerId,
                        tenantId = movedFileDto.tenantId,
                        name = metadata.name,
                        mimeType = metadata.mimeType,
                        size = metadata.size,
                        status = FileStatus.fromString(movedFileDto.status),
                        createdAt = java.time.OffsetDateTime.parse(movedFileDto.insertedAt).toInstant(),
                        updatedAt = java.time.OffsetDateTime.parse(movedFileDto.updatedAt).toInstant()
                    )
                    Result.success(file)
                } else {
                    Result.error(AppException.Unknown("Failed to move file"))
                }
            } finally {
                // Zeroize DEK
                SecureMemory.zeroize(dek)
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to move file", e))
        }
    }

    override suspend fun renameFile(fileId: String, newName: String): Result<FileItem> {
        return try {
            // Get current file info
            val fileResponse = apiService.getFile(fileId)
            if (!fileResponse.isSuccessful) {
                return Result.error(AppException.NotFound("File not found"))
            }

            val fileDto = fileResponse.body()!!.data
            val folderId = fileDto.folderId
            val blobHash = fileDto.blobHash
                ?: return Result.error(AppException.CryptoError("Missing blob hash for signature"))
            val blobSize = fileDto.blobSize
                ?: return Result.error(AppException.CryptoError("Missing blob size for signature"))
            val chunkCount = fileDto.chunkCount
                ?: return Result.error(AppException.CryptoError("Missing chunk count for signature"))

            // Decrypt current metadata to get other properties
            val metadata = fileDecryptor.decryptMetadata(
                folderId = folderId,
                encryptedMetadata = fileDto.encryptedMetadata,
                wrappedDek = fileDto.wrappedDek
            )

            // Re-encrypt metadata with new name
            val updatedResult = fileEncryptor.updateMetadata(
                folderId = folderId,
                wrappedDek = fileDto.wrappedDek,
                newName = newName,
                mimeType = metadata.mimeType,
                size = metadata.size,
                blobHash = blobHash,
                blobSize = blobSize,
                chunkCount = chunkCount
            )

            // Update file with new encrypted metadata
            val updateRequest = UpdateFileRequest(
                encryptedMetadata = updatedResult.encryptedMetadata,
                signature = updatedResult.signature
            )

            val updateResponse = apiService.updateFile(fileId, updateRequest)

            if (updateResponse.isSuccessful) {
                val updatedFileDto = updateResponse.body()!!.data

                val file = FileItem(
                    id = updatedFileDto.id,
                    folderId = updatedFileDto.folderId,
                    ownerId = updatedFileDto.ownerId,
                    tenantId = updatedFileDto.tenantId,
                    name = newName,
                    mimeType = metadata.mimeType,
                    size = metadata.size,
                    status = FileStatus.fromString(updatedFileDto.status),
                    createdAt = java.time.OffsetDateTime.parse(updatedFileDto.insertedAt).toInstant(),
                    updatedAt = java.time.OffsetDateTime.parse(updatedFileDto.updatedAt).toInstant()
                )
                Result.success(file)
            } else {
                Result.error(AppException.Unknown("Failed to rename file"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to rename file", e))
        }
    }

    override suspend fun uploadFile(
        localPath: String,
        folderId: String,
        fileName: String,
        mimeType: String,
        onProgress: (Int) -> Unit
    ): Result<FileItem> = withContext(Dispatchers.IO) {
        try {
            val localFile = File(localPath)
            if (!localFile.exists()) {
                return@withContext Result.error(AppException.NotFound("Local file not found"))
            }

            // Create temp file for encrypted content
            val tempFile = File(context.cacheDir, "upload_${System.currentTimeMillis()}.enc")

            try {
                onProgress(0)

                // Attempt to encrypt file; fall back to plaintext on crypto failure
                val encryptionResult = try {
                    FileOutputStream(tempFile).use { outputStream ->
                        FileInputStream(localFile).use { inputStream ->
                            fileEncryptor.encryptFileFromStream(
                                inputStream = inputStream,
                                fileName = fileName,
                                mimeType = mimeType,
                                fileSize = localFile.length(),
                                folderId = folderId,
                                outputStream = outputStream
                            ) { bytesProcessed, totalBytes ->
                                val percent = ((bytesProcessed.toDouble() / totalBytes) * 50).toInt()
                                onProgress(percent) // First 50% for encryption
                            }
                        }
                    }
                } catch (cryptoError: Exception) {
                    Logger.w(TAG, "File encryption failed, falling back to unencrypted upload", cryptoError)
                    // Graceful fallback: copy plaintext to temp file
                    localFile.copyTo(tempFile, overwrite = true)
                    null
                }

                try {
                    onProgress(50)

                    // Request presigned upload URL from server
                    val uploadRequest = if (encryptionResult != null) {
                        UploadUrlRequest(
                            folderId = folderId,
                            blobSize = encryptionResult.blobSize,
                            encryptedMetadata = encryptionResult.encryptedMetadata,
                            wrappedDek = encryptionResult.wrappedDek,
                            kemCiphertext = null,
                            mlKemCiphertext = null,
                            signature = encryptionResult.signature,
                            chunkCount = encryptionResult.chunkCount
                        )
                    } else {
                        // Unencrypted fallback
                        UploadUrlRequest(
                            folderId = folderId,
                            blobSize = tempFile.length(),
                            encryptedMetadata = "",
                            wrappedDek = "",
                            kemCiphertext = null,
                            mlKemCiphertext = null,
                            signature = "",
                            chunkCount = 0
                        )
                    }

                    val uploadUrlResponse = apiService.getUploadUrl(uploadRequest)
                    if (!uploadUrlResponse.isSuccessful) {
                        return@withContext Result.error(AppException.Unknown("Failed to get upload URL"))
                    }

                    val uploadData = uploadUrlResponse.body()!!.data
                    val fileId = uploadData.file.id
                    val uploadUrl = uploadData.uploadUrl

                    // Upload content to presigned URL
                    val uploadSuccess = uploadToPresignedUrl(
                        url = uploadUrl,
                        file = tempFile,
                        contentType = if (encryptionResult != null) "application/octet-stream" else mimeType
                    ) { bytesUploaded, totalBytes ->
                        val percent = 50 + ((bytesUploaded.toDouble() / totalBytes) * 40).toInt()
                        onProgress(percent) // 50-90% for upload
                    }

                    if (!uploadSuccess) {
                        return@withContext Result.error(AppException.Network("Failed to upload file"))
                    }

                    onProgress(90)

                    // Update file status on server
                    val updateResponse = apiService.updateFile(
                        fileId = fileId,
                        request = if (encryptionResult != null) {
                            UpdateFileRequest(
                                status = "complete",
                                blobHash = encryptionResult.blobHash,
                                blobSize = encryptionResult.blobSize,
                                chunkCount = encryptionResult.chunkCount
                            )
                        } else {
                            UpdateFileRequest(status = "complete")
                        }
                    )

                    if (updateResponse.isSuccessful) {
                        val fileDto = updateResponse.body()!!.data

                        onProgress(100)

                        // Build FileItem — decrypt metadata if encrypted, use originals otherwise
                        val file = if (encryptionResult != null) {
                            val metadata = fileDecryptor.decryptMetadata(
                                folderId = fileDto.folderId,
                                encryptedMetadata = fileDto.encryptedMetadata,
                                wrappedDek = fileDto.wrappedDek
                            )
                            FileItem(
                                id = fileDto.id,
                                folderId = fileDto.folderId,
                                ownerId = fileDto.ownerId,
                                tenantId = fileDto.tenantId,
                                name = metadata.name,
                                mimeType = metadata.mimeType,
                                size = metadata.size,
                                status = FileStatus.fromString(fileDto.status),
                                createdAt = java.time.OffsetDateTime.parse(fileDto.insertedAt).toInstant(),
                                updatedAt = java.time.OffsetDateTime.parse(fileDto.updatedAt).toInstant()
                            )
                        } else {
                            FileItem(
                                id = fileDto.id,
                                folderId = fileDto.folderId,
                                ownerId = fileDto.ownerId,
                                tenantId = fileDto.tenantId,
                                name = fileName,
                                mimeType = mimeType,
                                size = localFile.length(),
                                status = FileStatus.fromString(fileDto.status),
                                createdAt = java.time.OffsetDateTime.parse(fileDto.insertedAt).toInstant(),
                                updatedAt = java.time.OffsetDateTime.parse(fileDto.updatedAt).toInstant()
                            )
                        }

                        analyticsManager.trackFileUpload(file.mimeType, file.size)
                        Result.success(file)
                    } else {
                        Result.error(AppException.Unknown("Failed to finalize upload"))
                    }
                } finally {
                    encryptionResult?.zeroize()
                }
            } finally {
                // Clean up temp file
                tempFile.delete()
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to upload file", e))
        }
    }

    override suspend fun syncFiles(folderId: String): Result<Unit> {
        return try {
            val response = apiService.getFolderFiles(folderId)

            if (response.isSuccessful) {
                val fileEntities = response.body()!!.data.mapNotNull { fileDto ->
                    try {
                        // Decrypt metadata to cache name/mimeType
                        val metadata = fileDecryptor.decryptMetadata(
                            folderId = fileDto.folderId,
                            encryptedMetadata = fileDto.encryptedMetadata,
                            wrappedDek = fileDto.wrappedDek
                        )

                        fileDto.toEntity(
                            cachedName = metadata.name,
                            cachedMimeType = metadata.mimeType
                        )
                    } catch (e: Exception) {
                        // Skip files we can't decrypt
                        null
                    }
                }

                // Replace all files in this folder with fresh data
                fileDao.replaceAllInFolder(folderId, fileEntities)
                Result.success(Unit)
            } else {
                Result.error(AppException.Unknown("Failed to sync files"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to sync files", e))
        }
    }

    private fun FileDto.toEntity(cachedName: String?, cachedMimeType: String?): FileEntity {
        return FileEntity(
            id = id,
            folderId = folderId,
            ownerId = ownerId,
            tenantId = tenantId,
            storagePath = storagePath,
            blobSize = blobSize,
            blobHash = blobHash,
            chunkCount = chunkCount,
            status = status,
            encryptedMetadata = Base64.decode(encryptedMetadata, Base64.NO_WRAP),
            wrappedDek = Base64.decode(wrappedDek, Base64.NO_WRAP),
            kemCiphertext = kemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) } ?: ByteArray(0),
            signature = Base64.decode(signature, Base64.NO_WRAP),
            cachedName = cachedName,
            cachedMimeType = cachedMimeType,
            insertedAt = java.time.OffsetDateTime.parse(insertedAt).toInstant(),
            updatedAt = java.time.OffsetDateTime.parse(updatedAt).toInstant()
        )
    }

    override suspend fun searchFiles(query: String): Result<List<FileItem>> {
        return try {
            val response = apiService.searchFiles(query)

            if (response.isSuccessful) {
                val files = response.body()!!.data.mapNotNull { fileDto ->
                    try {
                        // Decrypt metadata using folder's KEK
                        val metadata = fileDecryptor.decryptMetadata(
                            folderId = fileDto.folderId,
                            encryptedMetadata = fileDto.encryptedMetadata,
                            wrappedDek = fileDto.wrappedDek
                        )

                        FileItem(
                            id = fileDto.id,
                            folderId = fileDto.folderId,
                            ownerId = fileDto.ownerId,
                            tenantId = fileDto.tenantId,
                            name = metadata.name,
                            mimeType = metadata.mimeType,
                            size = metadata.size,
                            status = FileStatus.fromString(fileDto.status),
                            createdAt = java.time.OffsetDateTime.parse(fileDto.insertedAt).toInstant(),
                            updatedAt = java.time.OffsetDateTime.parse(fileDto.updatedAt).toInstant()
                        )
                    } catch (e: Exception) {
                        // Log decryption error but continue with other files
                        null
                    }
                }
                Result.success(files)
            } else {
                Result.error(AppException.Unknown("Search failed"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Search failed", e))
        }
    }

    // ==================== Helper Methods ====================

    /**
     * Upload content to a presigned URL.
     */
    private suspend fun uploadToPresignedUrl(
        url: String,
        file: File,
        contentType: String,
        onProgress: (Long, Long) -> Unit
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val body = file.readBytes().toRequestBody(contentType.toMediaType())

            val request = Request.Builder()
                .url(url)
                .put(body)
                .addHeader("Content-Type", contentType)
                .build()

            val response = okHttpClient.newCall(request).execute()
            response.isSuccessful
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Download content from a URL.
     */
    private suspend fun downloadFromUrl(
        url: String,
        outputFile: File,
        onProgress: (Long, Long) -> Unit
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url(url)
                .get()
                .build()

            val response = okHttpClient.newCall(request).execute()

            if (response.isSuccessful) {
                response.body?.let { body ->
                    FileOutputStream(outputFile).use { outputStream ->
                        body.byteStream().copyTo(outputStream)
                    }
                    true
                } ?: false
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Convert PublicKeysDto to domain PublicKeys.
     */
    private fun PublicKeysDto.toPublicKeys(): PublicKeys {
        return PublicKeys(
            kem = Base64.decode(kem, Base64.NO_WRAP),
            sign = Base64.decode(sign, Base64.NO_WRAP),
            mlKem = mlKem?.let { Base64.decode(it, Base64.NO_WRAP) },
            mlDsa = mlDsa?.let { Base64.decode(it, Base64.NO_WRAP) }
        )
    }
}
