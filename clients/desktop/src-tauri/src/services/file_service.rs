//! File operations service

use crate::error::{AppError, AppResult};
use crate::models::{
    CreateFolderRequest, DownloadProgress, DownloadPhase, FileItem, FileListResponse, FilePreview,
    MoveRequest, RenameRequest, StorageInfo, UploadProgress, UploadPhase, UploadRequest,
};
use crate::services::{ApiClient, CryptoService};
use crate::storage::Database;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use reqwest::multipart::{Form, Part};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use zeroize::Zeroize;

/// HTTP timeout for file upload operations (10 minutes)
const UPLOAD_TIMEOUT: Duration = Duration::from_secs(600);

/// HTTP timeout for file download operations (10 minutes)
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(600);

/// Chunk size for file encryption (4 MB)
const CHUNK_SIZE: usize = 4 * 1024 * 1024;

/// Maximum allowed chunks to prevent DoS from malicious servers
const MAX_CHUNK_COUNT: usize = 10_000;

/// Maximum chunk size (16 MB) to prevent memory exhaustion
const MAX_CHUNK_SIZE: usize = 16 * 1024 * 1024;

/// Maximum file size for upload (5 GB)
const MAX_FILE_SIZE: u64 = 5 * 1024 * 1024 * 1024;

/// Service for file operations
pub struct FileService {
    api_client: Arc<ApiClient>,
    crypto_service: Arc<CryptoService>,
    database: Arc<Database>,
}

impl FileService {
    /// Create a new file service
    pub fn new(
        api_client: Arc<ApiClient>,
        crypto_service: Arc<CryptoService>,
        database: Arc<Database>,
    ) -> Self {
        Self {
            api_client,
            crypto_service,
            database,
        }
    }

    /// Validate that a file path is safe to read from
    /// Prevents path traversal attacks from malicious IPC requests
    fn validate_upload_path(path: &Path) -> AppResult<PathBuf> {
        // Canonicalize to resolve symlinks and get absolute path
        let canonical = path.canonicalize().map_err(|e| {
            AppError::File(format!("Invalid file path: {}", e))
        })?;

        // Ensure path exists and is a file (not directory)
        if !canonical.is_file() {
            return Err(AppError::File("Path is not a file".to_string()));
        }

        // Block system paths that should never be uploaded
        let path_str = canonical.to_string_lossy();
        let blocked_prefixes = [
            "/etc/", "/var/", "/usr/", "/bin/", "/sbin/",
            "/System/", "/Library/", "/private/",
            "C:\\Windows\\", "C:\\Program Files",
        ];

        for prefix in &blocked_prefixes {
            if path_str.starts_with(prefix) {
                return Err(AppError::File(
                    "Access to system files is not allowed".to_string()
                ));
            }
        }

        Ok(canonical)
    }

    /// Sanitize a filename from an untrusted source (API response)
    /// Removes path traversal sequences and dangerous characters
    fn sanitize_filename(filename: &str) -> AppResult<String> {
        // Extract just the filename, removing any path components
        let name = Path::new(filename)
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| AppError::File("Invalid filename".to_string()))?;

        // Check for empty or dot-only names
        if name.is_empty() || name == "." || name == ".." {
            return Err(AppError::File("Invalid filename".to_string()));
        }

        // Remove any remaining path separators (shouldn't exist after file_name())
        let sanitized = name.replace(['/', '\\'], "_");

        // Ensure no null bytes
        if sanitized.contains('\0') {
            return Err(AppError::File("Invalid filename".to_string()));
        }

        Ok(sanitized)
    }

    /// Validate download destination and construct safe output path
    fn validate_download_path(destination: &str, filename: &str) -> AppResult<PathBuf> {
        let dest_dir = Path::new(destination);

        // Canonicalize destination directory
        let canonical_dest = dest_dir.canonicalize().map_err(|e| {
            AppError::File(format!("Invalid destination directory: {}", e))
        })?;

        // Ensure destination is a directory
        if !canonical_dest.is_dir() {
            return Err(AppError::File("Destination is not a directory".to_string()));
        }

        // Sanitize the filename
        let safe_filename = Self::sanitize_filename(filename)?;

        // Construct final path
        let final_path = canonical_dest.join(&safe_filename);

        // Double-check the final path is still within destination
        // (should always be true after sanitization, but defense in depth)
        if !final_path.starts_with(&canonical_dest) {
            return Err(AppError::File("Path traversal detected".to_string()));
        }

        Ok(final_path)
    }

    /// List files in a folder
    pub async fn list_files(&self, folder_id: Option<&str>) -> AppResult<FileListResponse> {
        let endpoint = match folder_id {
            Some(id) => format!("/files?folder_id={}", id),
            None => "/files".to_string(),
        };

        let response: FileListResponse = self.api_client.get(&endpoint).await?;
        Ok(response)
    }

    /// Upload a file with encryption
    pub async fn upload_file<F>(
        &self,
        request: UploadRequest,
        progress_callback: F,
    ) -> AppResult<FileItem>
    where
        F: Fn(UploadProgress) + Send + 'static,
    {
        let path = Path::new(&request.file_path);

        // Validate the path is safe to read from (prevents path traversal)
        let validated_path = Self::validate_upload_path(path)?;

        let file_name = request
            .file_name
            .or_else(|| validated_path.file_name().map(|n| n.to_string_lossy().to_string()))
            .ok_or_else(|| AppError::File("Could not determine file name".to_string()))?;

        // Open file using validated path
        let mut file = File::open(&validated_path)
            .await
            .map_err(|e| AppError::File(format!("Failed to open file: {}", e)))?;

        let metadata = file
            .metadata()
            .await
            .map_err(|e| AppError::File(format!("Failed to read metadata: {}", e)))?;

        let total_size = metadata.len();

        // Check file size limit to prevent resource exhaustion
        if total_size > MAX_FILE_SIZE {
            return Err(AppError::File(format!(
                "File size {} bytes exceeds maximum allowed {} bytes (5 GB)",
                total_size, MAX_FILE_SIZE
            )));
        }

        // Report preparing phase
        progress_callback(UploadProgress {
            file_id: String::new(),
            file_name: file_name.clone(),
            phase: UploadPhase::Preparing,
            bytes_uploaded: 0,
            total_bytes: total_size,
            progress_percent: 0.0,
        });

        // Read file content
        let mut content = Vec::with_capacity(total_size as usize);
        file.read_to_end(&mut content)
            .await
            .map_err(|e| AppError::File(format!("Failed to read file: {}", e)))?;

        // Report encrypting phase
        progress_callback(UploadProgress {
            file_id: String::new(),
            file_name: file_name.clone(),
            phase: UploadPhase::Encrypting,
            bytes_uploaded: 0,
            total_bytes: total_size,
            progress_percent: 0.0,
        });

        // Generate DEK for this file
        let mut dek = self.crypto_service.generate_dek()?;

        // Get or derive folder KEK
        let folder_id_str = request.folder_id.clone().unwrap_or_else(|| "root".to_string());
        let mut kek = self.crypto_service.derive_folder_kek(&folder_id_str)?;

        // Encrypt the DEK
        let encrypted_dek = self.crypto_service.encrypt_dek(&dek, &kek)?;

        // Zeroize KEK immediately after use
        kek.zeroize();

        // Encrypt file content in chunks
        let mut encrypted_chunks = Vec::new();
        let num_chunks = (content.len() + CHUNK_SIZE - 1) / CHUNK_SIZE;

        for (i, chunk) in content.chunks(CHUNK_SIZE).enumerate() {
            let encrypted_chunk = self.crypto_service.encrypt_file_chunk(chunk, &dek)?;
            encrypted_chunks.push(encrypted_chunk);

            // Report encryption progress
            let progress = ((i + 1) as f64 / num_chunks as f64) * 50.0; // 0-50% for encryption
            progress_callback(UploadProgress {
                file_id: String::new(),
                file_name: file_name.clone(),
                phase: UploadPhase::Encrypting,
                bytes_uploaded: ((i + 1) * CHUNK_SIZE).min(content.len()) as u64,
                total_bytes: total_size,
                progress_percent: progress as f32,
            });
        }

        // Zeroize DEK now that encryption is complete
        dek.zeroize();

        // Zeroize plaintext content now that encryption is complete
        content.zeroize();
        drop(content); // Ensure it's dropped after zeroization

        // Combine all encrypted chunks
        let mut encrypted_content = Vec::new();
        // Write chunk count header
        encrypted_content.extend_from_slice(&(encrypted_chunks.len() as u32).to_le_bytes());
        // Write each chunk with its size prefix
        for chunk in &encrypted_chunks {
            encrypted_content.extend_from_slice(&(chunk.len() as u32).to_le_bytes());
            encrypted_content.extend_from_slice(chunk);
        }

        // Report uploading phase
        progress_callback(UploadProgress {
            file_id: String::new(),
            file_name: file_name.clone(),
            phase: UploadPhase::Uploading,
            bytes_uploaded: 0,
            total_bytes: encrypted_content.len() as u64,
            progress_percent: 50.0,
        });

        // Step 1: Request upload URL from API
        #[derive(serde::Serialize)]
        struct InitUploadRequest {
            file_name: String,
            file_size: u64,
            encrypted_size: u64,
            mime_type: String,
            folder_id: Option<String>,
            encrypted_dek: String,
        }

        #[derive(serde::Deserialize)]
        struct InitUploadResponse {
            file_id: String,
            upload_url: String,
            upload_fields: Option<std::collections::HashMap<String, String>>,
        }

        let mime_type = mime_guess::from_path(&file_name)
            .first_or_octet_stream()
            .to_string();

        let init_request = InitUploadRequest {
            file_name: file_name.clone(),
            file_size: total_size,
            encrypted_size: encrypted_content.len() as u64,
            mime_type,
            folder_id: request.folder_id.clone(),
            encrypted_dek,
        };

        let init_response: InitUploadResponse = self
            .api_client
            .post("/files/upload/init", &init_request)
            .await?;

        let file_id = init_response.file_id.clone();

        // Step 2: Upload encrypted content to pre-signed URL
        let client = reqwest::Client::builder()
            .timeout(UPLOAD_TIMEOUT)
            .build()
            .map_err(|e| AppError::Network(format!("Failed to create HTTP client: {}", e)))?;

        // Build multipart form if upload_fields are provided (S3-style)
        let response = if let Some(fields) = init_response.upload_fields {
            let mut form = Form::new();
            for (key, value) in fields {
                form = form.text(key, value);
            }
            form = form.part(
                "file",
                Part::bytes(encrypted_content.clone()).file_name(file_name.clone()),
            );

            client
                .post(&init_response.upload_url)
                .multipart(form)
                .send()
                .await
                .map_err(|e| AppError::Network(format!("Upload failed: {}", e)))?
        } else {
            // Direct PUT upload
            client
                .put(&init_response.upload_url)
                .header("Content-Type", "application/octet-stream")
                .body(encrypted_content)
                .send()
                .await
                .map_err(|e| AppError::Network(format!("Upload failed: {}", e)))?
        };

        if !response.status().is_success() {
            return Err(AppError::Network(format!(
                "Upload failed with status: {}",
                response.status()
            )));
        }

        // Step 3: Confirm upload completion
        #[derive(serde::Serialize)]
        struct ConfirmUploadRequest {
            file_id: String,
        }

        let confirm_request = ConfirmUploadRequest {
            file_id: file_id.clone(),
        };

        let file_item: FileItem = self
            .api_client
            .post("/files/upload/confirm", &confirm_request)
            .await?;

        // Report completion
        progress_callback(UploadProgress {
            file_id: file_id.clone(),
            file_name,
            phase: UploadPhase::Complete,
            bytes_uploaded: total_size,
            total_bytes: total_size,
            progress_percent: 100.0,
        });

        tracing::info!("File uploaded successfully: {}", file_id);
        Ok(file_item)
    }

    /// Download and decrypt a file
    pub async fn download_file<F>(
        &self,
        file_id: &str,
        destination: &str,
        progress_callback: F,
    ) -> AppResult<String>
    where
        F: Fn(DownloadProgress) + Send + 'static,
    {
        // Report preparing phase
        progress_callback(DownloadProgress {
            file_id: file_id.to_string(),
            file_name: String::new(),
            phase: DownloadPhase::Preparing,
            bytes_downloaded: 0,
            total_bytes: 0,
            progress_percent: 0.0,
        });

        // Step 1: Get download info from API
        #[derive(serde::Deserialize)]
        struct DownloadInfo {
            download_url: String,
            file_name: String,
            file_size: u64,
            encrypted_size: u64,
            encrypted_dek: String,
            folder_id: Option<String>,
        }

        let download_info: DownloadInfo = self
            .api_client
            .get(&format!("/files/{}/download", file_id))
            .await?;

        let file_name = download_info.file_name.clone();
        let total_size = download_info.encrypted_size;

        // Report downloading phase
        progress_callback(DownloadProgress {
            file_id: file_id.to_string(),
            file_name: file_name.clone(),
            phase: DownloadPhase::Downloading,
            bytes_downloaded: 0,
            total_bytes: total_size,
            progress_percent: 0.0,
        });

        // Step 2: Download encrypted content
        let client = reqwest::Client::builder()
            .timeout(DOWNLOAD_TIMEOUT)
            .build()
            .map_err(|e| AppError::Network(format!("Failed to create HTTP client: {}", e)))?;
        let response = client
            .get(&download_info.download_url)
            .send()
            .await
            .map_err(|e| AppError::Network(format!("Download failed: {}", e)))?;

        if !response.status().is_success() {
            return Err(AppError::Network(format!(
                "Download failed with status: {}",
                response.status()
            )));
        }

        let encrypted_content = response
            .bytes()
            .await
            .map_err(|e| AppError::Network(format!("Failed to read response: {}", e)))?;

        progress_callback(DownloadProgress {
            file_id: file_id.to_string(),
            file_name: file_name.clone(),
            phase: DownloadPhase::Downloading,
            bytes_downloaded: encrypted_content.len() as u64,
            total_bytes: total_size,
            progress_percent: 50.0,
        });

        // Report decrypting phase
        progress_callback(DownloadProgress {
            file_id: file_id.to_string(),
            file_name: file_name.clone(),
            phase: DownloadPhase::Decrypting,
            bytes_downloaded: encrypted_content.len() as u64,
            total_bytes: total_size,
            progress_percent: 50.0,
        });

        // Step 3: Decrypt DEK using folder KEK
        let folder_id = download_info.folder_id.unwrap_or_else(|| "root".to_string());
        let mut kek = self.crypto_service.derive_folder_kek(&folder_id)?;
        let mut dek = self
            .crypto_service
            .decrypt_dek(&download_info.encrypted_dek, &kek)?;

        // Zeroize KEK immediately after use
        kek.zeroize();

        // Step 4: Parse and decrypt chunks
        let mut cursor = 0;

        // Read chunk count
        if encrypted_content.len() < 4 {
            return Err(AppError::File("Invalid encrypted file format".to_string()));
        }
        let chunk_count = u32::from_le_bytes([
            encrypted_content[0],
            encrypted_content[1],
            encrypted_content[2],
            encrypted_content[3],
        ]) as usize;
        cursor += 4;

        // Validate chunk count to prevent DoS
        if chunk_count > MAX_CHUNK_COUNT {
            return Err(AppError::File(format!(
                "Chunk count {} exceeds maximum allowed {}",
                chunk_count, MAX_CHUNK_COUNT
            )));
        }

        // Sanity check: chunk_count * minimum overhead should not exceed content size
        let min_overhead_per_chunk = 4; // size prefix
        if chunk_count.saturating_mul(min_overhead_per_chunk) > encrypted_content.len() {
            return Err(AppError::File("Invalid chunk count for content size".to_string()));
        }

        let mut decrypted_content = Vec::new();

        for i in 0..chunk_count {
            // Read chunk size
            if cursor + 4 > encrypted_content.len() {
                return Err(AppError::File("Truncated encrypted file".to_string()));
            }
            let chunk_size = u32::from_le_bytes([
                encrypted_content[cursor],
                encrypted_content[cursor + 1],
                encrypted_content[cursor + 2],
                encrypted_content[cursor + 3],
            ]) as usize;
            cursor += 4;

            // Validate chunk size to prevent memory exhaustion
            if chunk_size > MAX_CHUNK_SIZE {
                return Err(AppError::File(format!(
                    "Chunk size {} exceeds maximum allowed {}",
                    chunk_size, MAX_CHUNK_SIZE
                )));
            }

            // Read and decrypt chunk
            if cursor + chunk_size > encrypted_content.len() {
                return Err(AppError::File("Truncated encrypted chunk".to_string()));
            }
            let encrypted_chunk = &encrypted_content[cursor..cursor + chunk_size];
            cursor += chunk_size;

            let decrypted_chunk = self
                .crypto_service
                .decrypt_file_chunk(encrypted_chunk, &dek)?;
            decrypted_content.extend_from_slice(&decrypted_chunk);

            // Report decryption progress
            let progress = 50.0 + ((i + 1) as f64 / chunk_count as f64) * 50.0; // 50-100%
            progress_callback(DownloadProgress {
                file_id: file_id.to_string(),
                file_name: file_name.clone(),
                phase: DownloadPhase::Decrypting,
                bytes_downloaded: decrypted_content.len() as u64,
                total_bytes: download_info.file_size,
                progress_percent: progress as f32,
            });
        }

        // Step 5: Write to destination with path validation
        // Sanitize filename from API to prevent path traversal
        let dest_path = Self::validate_download_path(destination, &file_name)?;
        let mut output_file = File::create(&dest_path)
            .await
            .map_err(|e| AppError::File(format!("Failed to create output file: {}", e)))?;

        output_file
            .write_all(&decrypted_content)
            .await
            .map_err(|e| AppError::File(format!("Failed to write file: {}", e)))?;

        output_file
            .flush()
            .await
            .map_err(|e| AppError::File(format!("Failed to flush file: {}", e)))?;

        // Zeroize sensitive data now that file is written
        dek.zeroize();
        decrypted_content.zeroize();

        // Report completion
        progress_callback(DownloadProgress {
            file_id: file_id.to_string(),
            file_name: file_name.clone(),
            phase: DownloadPhase::Complete,
            bytes_downloaded: download_info.file_size,
            total_bytes: download_info.file_size,
            progress_percent: 100.0,
        });

        let result_path = dest_path.to_string_lossy().to_string();
        tracing::info!("File downloaded successfully to: {}", result_path);
        Ok(result_path)
    }

    /// Create a new folder
    pub async fn create_folder(&self, request: CreateFolderRequest) -> AppResult<FileItem> {
        // Create folder via API
        let folder: FileItem = self.api_client.post("/folders", &request).await?;

        // Note: KEK for the folder is derived on-demand from the master key
        // using HKDF with folder_id as context

        Ok(folder)
    }

    /// Delete a file or folder
    pub async fn delete_item(&self, item_id: &str) -> AppResult<()> {
        self.api_client
            .delete_no_content(&format!("/files/{}", item_id))
            .await
    }

    /// Rename a file or folder
    pub async fn rename_item(&self, request: RenameRequest) -> AppResult<FileItem> {
        let item: FileItem = self
            .api_client
            .put(&format!("/files/{}", request.item_id), &request)
            .await?;
        Ok(item)
    }

    /// Move a file or folder
    pub async fn move_item(&self, request: MoveRequest) -> AppResult<FileItem> {
        let item: FileItem = self
            .api_client
            .put(&format!("/files/{}/move", request.item_id), &request)
            .await?;
        Ok(item)
    }

    /// Get file preview (first chunk decrypted)
    pub async fn get_preview(&self, file_id: &str) -> AppResult<FilePreview> {
        // Get preview info
        #[derive(serde::Deserialize)]
        struct PreviewInfo {
            preview_url: Option<String>,
            encrypted_dek: String,
            folder_id: Option<String>,
            mime_type: String,
            file_name: String,
        }

        let preview_info: PreviewInfo = self
            .api_client
            .get(&format!("/files/{}/preview", file_id))
            .await?;

        // Check if we have a preview URL (for images, etc.)
        if let Some(preview_url) = preview_info.preview_url {
            // Download and decrypt preview (shorter timeout for previews)
            let client = reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .map_err(|e| AppError::Network(format!("Failed to create HTTP client: {}", e)))?;
            let response = client
                .get(&preview_url)
                .send()
                .await
                .map_err(|e| AppError::Network(format!("Preview download failed: {}", e)))?;

            if response.status().is_success() {
                let encrypted_preview = response.bytes().await.map_err(|e| {
                    AppError::Network(format!("Failed to read preview response: {}", e))
                })?;

                // Decrypt preview
                let folder_id = preview_info.folder_id.unwrap_or_else(|| "root".to_string());
                let mut kek = self.crypto_service.derive_folder_kek(&folder_id)?;
                let mut dek = self
                    .crypto_service
                    .decrypt_dek(&preview_info.encrypted_dek, &kek)?;

                // Zeroize KEK immediately after use
                kek.zeroize();

                // Preview is a single chunk
                let decrypted_preview = self
                    .crypto_service
                    .decrypt_file_chunk(&encrypted_preview, &dek)?;

                // Zeroize DEK after use
                dek.zeroize();

                return Ok(FilePreview {
                    file_id: file_id.to_string(),
                    file_name: preview_info.file_name,
                    mime_type: preview_info.mime_type,
                    preview_data: Some(BASE64.encode(&decrypted_preview)),
                    can_preview: true,
                });
            }
        }

        // No preview available
        Ok(FilePreview {
            file_id: file_id.to_string(),
            file_name: preview_info.file_name,
            mime_type: preview_info.mime_type,
            preview_data: None,
            can_preview: false,
        })
    }

    /// Get storage information
    pub async fn get_storage_info(&self) -> AppResult<StorageInfo> {
        let info: StorageInfo = self.api_client.get("/storage/info").await?;
        Ok(info)
    }
}
