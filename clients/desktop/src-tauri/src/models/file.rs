//! File and folder related data models

use serde::{Deserialize, Serialize};

/// File or folder item
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileItem {
    pub id: String,
    pub name: String,
    pub item_type: ItemType,
    pub size: u64,
    pub mime_type: Option<String>,
    pub folder_id: Option<String>,
    pub owner_id: String,
    pub created_at: String,
    pub updated_at: String,
    /// Whether this item is shared with others
    pub is_shared: bool,
    /// Whether this item was shared with the current user
    pub is_received_share: bool,
}

/// Type of file system item
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ItemType {
    File,
    Folder,
}

impl FileItem {
    pub fn is_folder(&self) -> bool {
        self.item_type == ItemType::Folder
    }

    pub fn is_file(&self) -> bool {
        self.item_type == ItemType::File
    }
}

/// Response for file list requests
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileListResponse {
    pub items: Vec<FileItem>,
    pub current_folder: Option<FolderInfo>,
    pub breadcrumbs: Vec<FolderInfo>,
}

/// Basic folder information for navigation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderInfo {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
}

/// File upload request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadRequest {
    pub file_path: String,
    pub folder_id: Option<String>,
    pub file_name: Option<String>,
}

/// Upload progress event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadProgress {
    pub file_id: String,
    pub file_name: String,
    pub phase: UploadPhase,
    pub bytes_uploaded: u64,
    pub total_bytes: u64,
    pub progress_percent: f32,
}

/// Phases of the upload process
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UploadPhase {
    Preparing,
    Encrypting,
    Uploading,
    Confirming,
    Complete,
    Error,
}

/// Download progress event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadProgress {
    pub file_id: String,
    pub file_name: String,
    pub phase: DownloadPhase,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub progress_percent: f32,
}

/// Phases of the download process
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DownloadPhase {
    Preparing,
    Downloading,
    Decrypting,
    Writing,
    Complete,
    Error,
}

/// File preview data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilePreview {
    pub file_id: String,
    pub file_name: String,
    pub mime_type: String,
    /// Base64-encoded preview data
    pub preview_data: Option<String>,
    /// Whether preview is available
    pub can_preview: bool,
}

/// Create folder request (internal, before encryption)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateFolderRequest {
    pub name: String,
    pub parent_id: Option<String>,
}

/// Create folder API request (with encrypted folder key)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateFolderApiRequest {
    pub name: String,
    pub parent_id: Option<String>,
    /// KEM-encapsulated folder key ciphertext (base64)
    pub encrypted_folder_key: String,
    /// The folder key encrypted with the KEM shared secret (base64, nonce || ciphertext)
    pub wrapped_folder_key: String,
    /// KEM algorithm used
    pub kem_algorithm: String,
}

/// Folder key info returned by API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderKeyInfo {
    /// KEM ciphertext for key decapsulation (base64)
    pub encrypted_folder_key: String,
    /// The folder key encrypted with the KEM shared secret (base64, nonce || ciphertext)
    pub wrapped_folder_key: String,
    /// KEM algorithm used
    pub kem_algorithm: String,
    /// Folder ID
    pub folder_id: String,
}

/// Rename item request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenameRequest {
    pub item_id: String,
    pub new_name: String,
}

/// Move item request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoveRequest {
    pub item_id: String,
    pub new_folder_id: Option<String>,
}

/// Storage information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageInfo {
    pub used_bytes: u64,
    pub total_bytes: u64,
    pub file_count: u64,
    pub folder_count: u64,
}
