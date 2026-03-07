//! App Groups service for sharing data with the File Provider extension (macOS only)

use std::path::PathBuf;
use serde::{Deserialize, Serialize};
use tracing::{debug, error, info, warn};

#[cfg(target_os = "macos")]
use objc2::runtime::AnyClass;

/// App Group identifier for sharing data between the main app and File Provider extension
const APP_GROUP_ID: &str = "group.my.ssdid.drive.desktop";

/// Keychain service name for shared credentials
const KEYCHAIN_SERVICE: &str = "my.ssdid.drive.desktop";

/// Notification name for crypto requests
const CRYPTO_REQUEST_NOTIFICATION: &str = "my.ssdid.drive.cryptoRequest";

/// Crypto request from the File Provider extension
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CryptoRequest {
    pub id: String,
    #[serde(rename = "type")]
    pub request_type: CryptoRequestType,
    pub input_path: String,
    pub file_id: Option<String>,
}

/// Type of crypto operation
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CryptoRequestType {
    Encrypt,
    Decrypt,
}

/// Response to a crypto request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CryptoResponse {
    pub request_id: String,
    pub output_path: Option<String>,
    pub error: Option<String>,
}

/// File metadata for sharing with the extension
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedFileMetadata {
    pub id: String,
    pub name: String,
    pub parent_id: String,
    pub is_folder: bool,
    pub size: i64,
    pub created_at: String,
    pub updated_at: String,
}

/// Service for managing App Groups data sharing with the File Provider extension
pub struct AppGroupService {
    container_path: Option<PathBuf>,
}

impl AppGroupService {
    /// Create a new App Groups service
    pub fn new() -> Self {
        let container_path = Self::get_container_path();

        if let Some(ref path) = container_path {
            info!("App Group container path: {:?}", path);
        } else {
            warn!("App Group container path not available (non-macOS or not configured)");
        }

        Self { container_path }
    }

    /// Get the shared container path for App Groups
    #[cfg(target_os = "macos")]
    fn get_container_path() -> Option<PathBuf> {
        use objc2::runtime::AnyObject;
        use objc2::msg_send;
        use objc2::sel;
        use std::ffi::CStr;

        unsafe {
            // Get NSFileManager class
            let nsfilemanager_class = AnyClass::get("NSFileManager")?;

            // Get default manager
            let default_manager_sel = sel!(defaultManager);
            let manager: *mut AnyObject = msg_send![nsfilemanager_class, defaultManager];

            if manager.is_null() {
                return None;
            }

            // Create NSString for group ID
            let nsstring_class = AnyClass::get("NSString")?;
            let group_id_cstr = std::ffi::CString::new(APP_GROUP_ID).ok()?;
            let group_id_nsstring: *mut AnyObject = msg_send![
                nsstring_class,
                stringWithUTF8String: group_id_cstr.as_ptr()
            ];

            if group_id_nsstring.is_null() {
                return None;
            }

            // Get container URL
            let container_url_sel = sel!(containerURLForSecurityApplicationGroupIdentifier:);
            let container_url: *mut AnyObject = msg_send![
                manager,
                containerURLForSecurityApplicationGroupIdentifier: group_id_nsstring
            ];

            if container_url.is_null() {
                debug!("No container URL for App Group: {}", APP_GROUP_ID);
                return None;
            }

            // Get path from URL
            let path_sel = sel!(path);
            let path_nsstring: *mut AnyObject = msg_send![container_url, path];

            if path_nsstring.is_null() {
                return None;
            }

            // Convert to Rust string
            let utf8_sel = sel!(UTF8String);
            let path_cstr: *const i8 = msg_send![path_nsstring, UTF8String];

            if path_cstr.is_null() {
                return None;
            }

            let path_str = CStr::from_ptr(path_cstr).to_str().ok()?;
            Some(PathBuf::from(path_str))
        }
    }

    #[cfg(not(target_os = "macos"))]
    fn get_container_path() -> Option<PathBuf> {
        None
    }

    /// Check if App Groups is available
    pub fn is_available(&self) -> bool {
        self.container_path.is_some()
    }

    /// Get the container path
    pub fn container_path(&self) -> Option<&PathBuf> {
        self.container_path.as_ref()
    }

    /// Get the path for a file in the shared container
    pub fn shared_file_path(&self, filename: &str) -> Option<PathBuf> {
        self.container_path.as_ref().map(|p| p.join(filename))
    }

    /// Write file metadata to shared storage for the extension
    pub fn sync_file_metadata(&self, files: &[SharedFileMetadata]) -> Result<(), AppGroupError> {
        let path = self.shared_file_path("file_metadata.json")
            .ok_or(AppGroupError::NotAvailable)?;

        let json = serde_json::to_string_pretty(files)
            .map_err(|e| AppGroupError::SerializationError(e.to_string()))?;

        std::fs::write(&path, json)
            .map_err(|e| AppGroupError::IoError(e.to_string()))?;

        debug!("Synced {} files to shared metadata", files.len());
        Ok(())
    }

    /// Read pending crypto requests from the extension
    pub fn read_pending_crypto_requests(&self) -> Result<Vec<CryptoRequest>, AppGroupError> {
        let path = self.shared_file_path("crypto_requests.json")
            .ok_or(AppGroupError::NotAvailable)?;

        if !path.exists() {
            return Ok(vec![]);
        }

        let json = std::fs::read_to_string(&path)
            .map_err(|e| AppGroupError::IoError(e.to_string()))?;

        let requests: std::collections::HashMap<String, CryptoRequest> = serde_json::from_str(&json)
            .map_err(|e| AppGroupError::SerializationError(e.to_string()))?;

        Ok(requests.into_values().collect())
    }

    /// Write a crypto response for the extension
    pub fn write_crypto_response(&self, response: CryptoResponse) -> Result<(), AppGroupError> {
        let path = self.shared_file_path("crypto_responses.json")
            .ok_or(AppGroupError::NotAvailable)?;

        // Read existing responses
        let mut responses: std::collections::HashMap<String, CryptoResponse> = if path.exists() {
            let json = std::fs::read_to_string(&path)
                .map_err(|e| AppGroupError::IoError(e.to_string()))?;
            serde_json::from_str(&json).unwrap_or_default()
        } else {
            std::collections::HashMap::new()
        };

        // Add new response
        responses.insert(response.request_id.clone(), response);

        // Write back
        let json = serde_json::to_string_pretty(&responses)
            .map_err(|e| AppGroupError::SerializationError(e.to_string()))?;

        std::fs::write(&path, json)
            .map_err(|e| AppGroupError::IoError(e.to_string()))?;

        Ok(())
    }

    /// Clear a processed crypto request
    pub fn clear_crypto_request(&self, request_id: &str) -> Result<(), AppGroupError> {
        let path = self.shared_file_path("crypto_requests.json")
            .ok_or(AppGroupError::NotAvailable)?;

        if !path.exists() {
            return Ok(());
        }

        let json = std::fs::read_to_string(&path)
            .map_err(|e| AppGroupError::IoError(e.to_string()))?;

        let mut requests: std::collections::HashMap<String, CryptoRequest> = serde_json::from_str(&json)
            .map_err(|e| AppGroupError::SerializationError(e.to_string()))?;

        requests.remove(request_id);

        let json = serde_json::to_string_pretty(&requests)
            .map_err(|e| AppGroupError::SerializationError(e.to_string()))?;

        std::fs::write(&path, json)
            .map_err(|e| AppGroupError::IoError(e.to_string()))?;

        Ok(())
    }

    /// Store auth token in shared keychain
    #[cfg(target_os = "macos")]
    pub fn store_auth_token(&self, token: &str) -> Result<(), AppGroupError> {
        use security_framework::passwords::{set_generic_password, delete_generic_password};

        // First try to delete existing entry
        let _ = delete_generic_password(KEYCHAIN_SERVICE, "auth_token");

        // Then set the new value
        set_generic_password(KEYCHAIN_SERVICE, "auth_token", token.as_bytes())
            .map_err(|e| AppGroupError::KeychainError(e.to_string()))?;

        debug!("Stored auth token in shared keychain");
        Ok(())
    }

    #[cfg(not(target_os = "macos"))]
    pub fn store_auth_token(&self, _token: &str) -> Result<(), AppGroupError> {
        Err(AppGroupError::NotAvailable)
    }

    /// Clear auth token from shared keychain
    #[cfg(target_os = "macos")]
    pub fn clear_auth_token(&self) -> Result<(), AppGroupError> {
        use security_framework::passwords::delete_generic_password;

        let _ = delete_generic_password(KEYCHAIN_SERVICE, "auth_token");
        debug!("Cleared auth token from shared keychain");
        Ok(())
    }

    #[cfg(not(target_os = "macos"))]
    pub fn clear_auth_token(&self) -> Result<(), AppGroupError> {
        Err(AppGroupError::NotAvailable)
    }

    /// Notify the File Provider extension of changes
    #[cfg(target_os = "macos")]
    pub fn signal_extension(&self, file_id: Option<&str>) -> Result<(), AppGroupError> {
        use objc2::runtime::AnyObject;
        use objc2::msg_send;
        use objc2::sel;

        unsafe {
            // Get NSDistributedNotificationCenter
            let center_class = AnyClass::get("NSDistributedNotificationCenter")
                .ok_or(AppGroupError::NotAvailable)?;

            let default_center: *mut AnyObject = msg_send![center_class, defaultCenter];

            if default_center.is_null() {
                return Err(AppGroupError::NotAvailable);
            }

            // Create notification name NSString
            let nsstring_class = AnyClass::get("NSString")
                .ok_or(AppGroupError::NotAvailable)?;

            let notification_name_cstr = std::ffi::CString::new(CRYPTO_REQUEST_NOTIFICATION)
                .map_err(|e| AppGroupError::IoError(e.to_string()))?;

            let notification_name: *mut AnyObject = msg_send![
                nsstring_class,
                stringWithUTF8String: notification_name_cstr.as_ptr()
            ];

            // Post notification
            let _: () = msg_send![
                default_center,
                postNotificationName: notification_name
                object: std::ptr::null::<AnyObject>()
                userInfo: std::ptr::null::<AnyObject>()
                deliverImmediately: true
            ];

            debug!("Signaled File Provider extension");
            Ok(())
        }
    }

    #[cfg(not(target_os = "macos"))]
    pub fn signal_extension(&self, _file_id: Option<&str>) -> Result<(), AppGroupError> {
        Err(AppGroupError::NotAvailable)
    }
}

impl Default for AppGroupService {
    fn default() -> Self {
        Self::new()
    }
}

/// Errors that can occur when working with App Groups
#[derive(Debug, thiserror::Error)]
pub enum AppGroupError {
    #[error("App Groups not available on this platform")]
    NotAvailable,

    #[error("I/O error: {0}")]
    IoError(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Keychain error: {0}")]
    KeychainError(String),
}
