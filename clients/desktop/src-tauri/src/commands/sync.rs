//! Sync commands for offline mode support

use crate::models::{CreateFolderRequest, MoveRequest, RenameRequest, UploadRequest};
use crate::services::{CachedFile, OfflineOperation, SyncStatus};
use crate::state::AppState;
use serde::Serialize;
use tauri::State;

/// Sync state response
#[derive(Debug, Serialize)]
pub struct SyncStateResponse {
    pub status: SyncStatus,
    pub is_online: bool,
    pub pending_count: usize,
}

/// Get current sync status
#[tauri::command]
pub async fn get_sync_status(state: State<'_, AppState>) -> Result<SyncStateResponse, String> {
    state.require_auth().map_err(|e| e.to_string())?;
    let sync = state.sync_service();

    Ok(SyncStateResponse {
        status: sync.get_status(),
        is_online: sync.is_online(),
        pending_count: sync.get_pending_count().unwrap_or(0),
    })
}

/// Set online/offline status
#[tauri::command]
pub async fn set_online_status(
    state: State<'_, AppState>,
    online: bool,
) -> Result<(), String> {
    state.require_auth().map_err(|e| e.to_string())?;
    state.sync_service().set_online(online);
    Ok(())
}

/// Get cached files for a folder (for offline access)
#[tauri::command]
pub async fn get_cached_files(
    state: State<'_, AppState>,
    folder_id: Option<String>,
) -> Result<Vec<CachedFile>, String> {
    state.require_auth().map_err(|e| e.to_string())?;
    state
        .sync_service()
        .get_cached_files(folder_id.as_deref())
        .map_err(|e| e.to_string())
}

/// Get pending operation count
#[tauri::command]
pub async fn get_pending_sync_count(
    state: State<'_, AppState>,
) -> Result<usize, String> {
    state.require_auth().map_err(|e| e.to_string())?;
    state
        .sync_service()
        .get_pending_count()
        .map_err(|e| e.to_string())
}

/// Trigger manual sync (processes pending operations)
#[tauri::command]
pub async fn trigger_sync(state: State<'_, AppState>) -> Result<(), String> {
    state.require_auth().map_err(|e| e.to_string())?;
    state.require_unlocked().map_err(|e| e.to_string())?;
    let sync = state.sync_service();

    if !sync.is_online() {
        return Err("Cannot sync while offline".to_string());
    }

    sync.set_status(SyncStatus::Syncing {
        progress: 0,
        message: "Starting sync...".to_string(),
    });

    // Get pending operations
    let operations = sync.get_pending_operations().map_err(|e| e.to_string())?;
    let total = operations.len();

    if total == 0 {
        sync.mark_synced();
        return Ok(());
    }

    let file_service = state.file_service();
    let mut failed_count = 0;

    // Process each operation
    for (i, (id, operation)) in operations.into_iter().enumerate() {
        let progress = ((i + 1) * 100 / total) as u8;
        sync.set_status(SyncStatus::Syncing {
            progress,
            message: format!("Syncing {} of {}...", i + 1, total),
        });

        let result = match operation {
            OfflineOperation::UploadFile {
                local_path,
                folder_id,
                file_name,
            } => {
                let request = UploadRequest {
                    file_path: local_path,
                    folder_id,
                    file_name: Some(file_name),
                };
                file_service
                    .upload_file(request, |_progress| {})
                    .await
                    .map(|_| ())
            }
            OfflineOperation::DeleteItem { item_id } => {
                file_service.delete_item(&item_id).await
            }
            OfflineOperation::RenameItem { item_id, new_name } => {
                file_service
                    .rename_item(RenameRequest { item_id, new_name })
                    .await
                    .map(|_| ())
            }
            OfflineOperation::MoveItem {
                item_id,
                new_folder_id,
            } => {
                file_service
                    .move_item(MoveRequest {
                        item_id,
                        new_folder_id,
                    })
                    .await
                    .map(|_| ())
            }
            OfflineOperation::CreateFolder { name, parent_id } => {
                // Fetch user's KEM public keys for folder key encapsulation
                let ml_kem_pk = state
                    .database()
                    .get_setting("ml_kem_pk")
                    .ok()
                    .flatten()
                    .unwrap_or_default();
                let kaz_kem_pk = state
                    .database()
                    .get_setting("kaz_kem_pk")
                    .ok()
                    .flatten()
                    .unwrap_or_default();

                file_service
                    .create_folder(
                        CreateFolderRequest { name, parent_id },
                        &ml_kem_pk,
                        &kaz_kem_pk,
                    )
                    .await
                    .map(|_| ())
            }
        };

        match result {
            Ok(()) => {
                if let Err(e) = sync.complete_operation(id) {
                    tracing::warn!("Failed to mark operation {} as complete: {}", id, e);
                }
            }
            Err(e) => {
                tracing::warn!("Sync operation {} failed: {}", id, e);
                failed_count += 1;

                // Check if error is permanent (4xx) or transient (5xx/network)
                let is_permanent = matches!(
                    &e,
                    crate::error::AppError::NotAuthenticated
                        | crate::error::AppError::Validation(_)
                        | crate::error::AppError::NotFound(_)
                );

                if is_permanent {
                    // Permanent failure: remove from queue
                    tracing::error!("Permanent failure for operation {}, removing: {}", id, e);
                    let _ = sync.complete_operation(id);
                } else {
                    // Transient failure: increment retry, keep in queue if under limit
                    let _ = sync.retry_operation(id);
                }
            }
        }
    }

    if failed_count > 0 {
        sync.set_status(SyncStatus::Error {
            message: format!("{} operation(s) failed during sync", failed_count),
        });
    } else {
        sync.mark_synced();
    }

    Ok(())
}

/// Clear sync queue (discard pending operations)
#[tauri::command]
pub async fn clear_sync_queue(state: State<'_, AppState>) -> Result<(), String> {
    state.require_auth().map_err(|e| e.to_string())?;
    state.require_unlocked().map_err(|e| e.to_string())?;
    let sync = state.sync_service();
    let operations = sync.get_pending_operations().map_err(|e| e.to_string())?;

    for (id, _) in operations {
        sync.complete_operation(id).map_err(|e| e.to_string())?;
    }

    Ok(())
}
