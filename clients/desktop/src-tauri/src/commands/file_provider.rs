//! File Provider extension commands for macOS Finder integration

use tauri::State;
use tracing::{debug, error, info, warn};

use crate::state::AppState;
use crate::services::{AppGroupService, CryptoResponse};

/// Register the File Provider domain with the system
#[tauri::command]
pub async fn register_file_provider_domain(
    state: State<'_, AppState>,
) -> Result<(), String> {
    state.require_auth().map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    {
        info!("Registering File Provider domain");

        // On macOS, the File Provider domain is automatically registered
        // when the extension is first accessed. We just need to ensure
        // the shared data is set up.
        let app_group = AppGroupService::new();

        if !app_group.is_available() {
            warn!("App Groups not available - File Provider may not work correctly");
            return Ok(());
        }

        // Sync current auth token to shared keychain
        let keyring = state.keyring();
        if let Ok(token) = keyring.get_auth_token() {
            if let Err(e) = app_group.store_auth_token(&token) {
                error!("Failed to store auth token in shared keychain: {}", e);
            }
        }

        info!("File Provider domain registration complete");
        Ok(())
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = state;
        Err("File Provider is only available on macOS".to_string())
    }
}

/// Unregister the File Provider domain (e.g., on logout)
#[tauri::command]
pub async fn unregister_file_provider_domain() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        info!("Unregistering File Provider domain");

        let app_group = AppGroupService::new();

        // Clear shared auth token
        if let Err(e) = app_group.clear_auth_token() {
            warn!("Failed to clear shared auth token: {}", e);
        }

        info!("File Provider domain unregistration complete");
        Ok(())
    }

    #[cfg(not(target_os = "macos"))]
    {
        Err("File Provider is only available on macOS".to_string())
    }
}

/// Signal the File Provider extension that a file has changed
#[tauri::command]
pub async fn signal_file_changed(file_id: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        debug!("Signaling file change to File Provider: {}", file_id);

        let app_group = AppGroupService::new();

        app_group.signal_extension(Some(&file_id))
            .map_err(|e| format!("Failed to signal extension: {}", e))?;

        Ok(())
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = file_id;
        Err("File Provider is only available on macOS".to_string())
    }
}

/// Process pending crypto requests from the File Provider extension
#[tauri::command]
pub async fn process_crypto_requests(
    state: State<'_, AppState>,
) -> Result<u32, String> {
    state.require_auth().map_err(|e| e.to_string())?;
    state.require_unlocked().map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    {
        let app_group = AppGroupService::new();

        if !app_group.is_available() {
            return Ok(0);
        }

        let requests = app_group.read_pending_crypto_requests()
            .map_err(|e| format!("Failed to read crypto requests: {}", e))?;

        if requests.is_empty() {
            return Ok(0);
        }

        info!("Processing {} crypto requests from File Provider", requests.len());

        let crypto_service = state.crypto_service();
        let mut processed = 0u32;

        for request in requests {
            let response = match process_single_crypto_request(crypto_service, &request) {
                Ok(output_path) => CryptoResponse {
                    request_id: request.id.clone(),
                    output_path: Some(output_path),
                    error: None,
                },
                Err(e) => {
                    error!("Crypto request {} failed: {}", request.id, e);
                    CryptoResponse {
                        request_id: request.id.clone(),
                        output_path: None,
                        error: Some(e),
                    }
                }
            };

            // Write response
            if let Err(e) = app_group.write_crypto_response(response) {
                error!("Failed to write crypto response: {}", e);
            }

            // Clear the request
            if let Err(e) = app_group.clear_crypto_request(&request.id) {
                warn!("Failed to clear crypto request: {}", e);
            }

            processed += 1;
        }

        // Signal extension that responses are ready
        let _ = app_group.signal_extension(None);

        Ok(processed)
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = state;
        Ok(0)
    }
}

/// Check if File Provider is available on this system
#[tauri::command]
pub fn is_file_provider_available() -> bool {
    #[cfg(target_os = "macos")]
    {
        let app_group = AppGroupService::new();
        app_group.is_available()
    }

    #[cfg(not(target_os = "macos"))]
    {
        false
    }
}

/// Get the File Provider shared container path (for debugging)
#[tauri::command]
pub fn get_file_provider_container_path() -> Option<String> {
    #[cfg(target_os = "macos")]
    {
        let app_group = AppGroupService::new();
        app_group.container_path().map(|p| p.to_string_lossy().to_string())
    }

    #[cfg(not(target_os = "macos"))]
    {
        None
    }
}

/// Sync file metadata to the File Provider extension
#[tauri::command]
pub async fn sync_file_metadata_to_extension(
    state: State<'_, AppState>,
) -> Result<u32, String> {
    state.require_auth().map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    {
        use crate::services::SharedFileMetadata;

        let app_group = AppGroupService::new();

        if !app_group.is_available() {
            return Err("App Groups not available".to_string());
        }

        // Get cached files from sync service
        let sync_service = state.sync_service();
        let cached_files = sync_service.get_cached_files(None)
            .map_err(|e| format!("Failed to list cached files: {}", e))?;

        // Convert to shared metadata format
        let metadata: Vec<SharedFileMetadata> = cached_files
            .iter()
            .map(|f| SharedFileMetadata {
                id: f.id.clone(),
                name: f.name.clone(),
                parent_id: f.folder_id.clone().unwrap_or_else(|| "root".to_string()),
                is_folder: f.item_type == "folder",
                size: f.size,
                created_at: f.created_at.clone(),
                updated_at: f.updated_at.clone(),
            })
            .collect();

        let count = metadata.len() as u32;

        app_group.sync_file_metadata(&metadata)
            .map_err(|e| format!("Failed to sync metadata: {}", e))?;

        info!("Synced {} files to File Provider extension", count);
        Ok(count)
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = state;
        Err("File Provider is only available on macOS".to_string())
    }
}

// Helper function to process a single crypto request
#[cfg(target_os = "macos")]
fn process_single_crypto_request(
    crypto_service: &std::sync::Arc<crate::services::CryptoService>,
    request: &crate::services::CryptoRequest,
) -> Result<String, String> {
    use crate::services::CryptoRequestType;
    use std::path::Path;

    let input_path = Path::new(&request.input_path);

    if !input_path.exists() {
        return Err("Input file not found".to_string());
    }

    // Generate output path
    let output_filename = format!("{}.processed", uuid::Uuid::new_v4());
    let output_path = std::env::temp_dir().join(&output_filename);

    match request.request_type {
        CryptoRequestType::Encrypt => {
            // Read plaintext
            let plaintext = std::fs::read(input_path)
                .map_err(|e| format!("Failed to read input file: {}", e))?;

            // Generate a random DEK for this file
            let dek = crypto_service.generate_dek()
                .map_err(|e| format!("Failed to generate DEK: {}", e))?;

            // Encrypt using crypto service
            let encrypted = crypto_service.encrypt_file_chunk(&plaintext, &dek)
                .map_err(|e| format!("Encryption failed: {}", e))?;

            // Write encrypted data
            std::fs::write(&output_path, encrypted)
                .map_err(|e| format!("Failed to write output file: {}", e))?;
        }
        CryptoRequestType::Decrypt => {
            // Get file ID for DEK lookup
            let _file_id = request.file_id.as_ref()
                .ok_or_else(|| "File ID required for decryption".to_string())?;

            // Read encrypted data
            let encrypted = std::fs::read(input_path)
                .map_err(|e| format!("Failed to read input file: {}", e))?;

            // For now, we'll need the DEK from somewhere
            // In production, this would come from the file metadata or a key cache
            // This is a placeholder - the actual implementation would need to
            // retrieve the DEK for this file from secure storage
            return Err("Decryption requires DEK retrieval from file metadata - not yet implemented".to_string());

            // When implemented:
            // let plaintext = crypto_service.decrypt_file_chunk(&encrypted, &dek)
            //     .map_err(|e| format!("Decryption failed: {}", e))?;
            // std::fs::write(&output_path, plaintext)
            //     .map_err(|e| format!("Failed to write output file: {}", e))?;
        }
    }

    Ok(output_path.to_string_lossy().to_string())
}
