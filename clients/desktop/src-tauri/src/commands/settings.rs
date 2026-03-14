//! Settings commands

use crate::error::AppResult;
use crate::models::StorageInfo;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

/// Application settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    /// Theme (light, dark, system)
    pub theme: String,
    /// Auto-lock timeout in seconds (0 = disabled)
    pub auto_lock_timeout: u32,
    /// Show notifications for shares
    pub notify_on_share: bool,
    /// Show notifications for uploads
    pub notify_on_upload: bool,
    /// Download location
    pub download_location: String,
    /// Enable biometric unlock
    pub biometric_enabled: bool,
    /// Sync interval in seconds (0 = manual only)
    pub sync_interval: u32,
    /// Cache size limit in MB (0 = unlimited)
    pub cache_size_limit: u32,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            theme: "system".to_string(),
            auto_lock_timeout: 300, // 5 minutes
            notify_on_share: true,
            notify_on_upload: false,
            download_location: "".to_string(), // Will be set to system default
            biometric_enabled: false,
            sync_interval: 300, // 5 minutes
            cache_size_limit: 1024, // 1 GB
        }
    }
}

/// Get current application settings
#[tauri::command]
pub async fn get_settings(state: State<'_, AppState>) -> AppResult<AppSettings> {
    state.require_auth()?;
    tracing::debug!("Getting application settings");

    // Load settings from database or return defaults
    let settings = state
        .database()
        .get_settings()
        .await
        .unwrap_or_else(|_| AppSettings::default());

    Ok(settings)
}

/// Update application settings
#[tauri::command]
pub async fn update_settings(
    settings: AppSettings,
    state: State<'_, AppState>,
) -> AppResult<AppSettings> {
    state.require_auth()?;
    state.require_unlocked()?;
    tracing::info!("Updating application settings");

    // Save settings to database
    state.database().save_settings(&settings).await?;

    Ok(settings)
}

/// Get storage usage information
#[tauri::command]
pub async fn get_storage_info(state: State<'_, AppState>) -> AppResult<StorageInfo> {
    state.require_auth()?;

    tracing::debug!("Getting storage information");

    // Get storage info from API
    let info = state.file_service().get_storage_info().await?;

    Ok(info)
}

/// Clear the local cache
#[tauri::command]
pub async fn clear_cache(state: State<'_, AppState>) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;
    tracing::info!("Clearing local cache");

    state.database().clear_cache().await?;

    Ok(())
}
