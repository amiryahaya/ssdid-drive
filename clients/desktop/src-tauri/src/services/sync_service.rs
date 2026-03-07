//! Background sync service for offline mode
//!
//! Handles:
//! - Network connectivity monitoring
//! - Queuing operations when offline
//! - Syncing pending changes when back online
//! - File cache management

use crate::error::{AppError, AppResult};
use crate::storage::{Database, CachedFileRow};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// Sync status for UI display
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(tag = "status", content = "data")]
pub enum SyncStatus {
    #[default]
    Idle,
    Syncing {
        progress: u8,
        message: String,
    },
    Offline,
    Error {
        message: String,
    },
}

/// Offline operation types that can be queued
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "action", content = "payload")]
pub enum OfflineOperation {
    UploadFile {
        local_path: String,
        folder_id: Option<String>,
        file_name: String,
    },
    DeleteItem {
        item_id: String,
    },
    RenameItem {
        item_id: String,
        new_name: String,
    },
    MoveItem {
        item_id: String,
        new_folder_id: Option<String>,
    },
    CreateFolder {
        name: String,
        parent_id: Option<String>,
    },
}

/// Re-export CachedFileRow as CachedFile for API consistency
pub type CachedFile = CachedFileRow;

/// Sync state
#[derive(Debug)]
struct SyncState {
    status: SyncStatus,
    is_online: bool,
    last_sync: Option<Instant>,
    pending_count: usize,
}

impl Default for SyncState {
    fn default() -> Self {
        Self {
            status: SyncStatus::Idle,
            is_online: true,
            last_sync: None,
            pending_count: 0,
        }
    }
}

/// Background sync service
pub struct SyncService {
    database: Arc<Database>,
    state: Arc<RwLock<SyncState>>,
}

impl SyncService {
    /// Create a new sync service
    pub fn new(database: Arc<Database>) -> Self {
        Self {
            database,
            state: Arc::new(RwLock::new(SyncState::default())),
        }
    }

    /// Get current sync status
    pub fn get_status(&self) -> SyncStatus {
        self.state.read().status.clone()
    }

    /// Check if currently online
    pub fn is_online(&self) -> bool {
        self.state.read().is_online
    }

    /// Set online/offline status
    pub fn set_online(&self, online: bool) {
        let mut state = self.state.write();
        state.is_online = online;
        state.status = if online {
            SyncStatus::Idle
        } else {
            SyncStatus::Offline
        };
    }

    /// Get pending operation count
    pub fn get_pending_count(&self) -> AppResult<usize> {
        self.database.get_pending_operation_count()
    }

    /// Queue an operation for later sync
    pub fn queue_operation(&self, operation: OfflineOperation) -> AppResult<()> {
        let payload = serde_json::to_string(&operation)
            .map_err(|e| AppError::Internal(format!("Serialization error: {}", e)))?;

        let action = match &operation {
            OfflineOperation::UploadFile { .. } => "upload_file",
            OfflineOperation::DeleteItem { .. } => "delete_item",
            OfflineOperation::RenameItem { .. } => "rename_item",
            OfflineOperation::MoveItem { .. } => "move_item",
            OfflineOperation::CreateFolder { .. } => "create_folder",
        };

        self.database.queue_offline_operation(action, &payload)?;

        let mut state = self.state.write();
        state.pending_count += 1;

        tracing::info!("Queued offline operation: {}", action);
        Ok(())
    }

    /// Get all pending operations
    pub fn get_pending_operations(&self) -> AppResult<Vec<(i64, OfflineOperation)>> {
        let rows = self.database.get_pending_operations()?;
        let mut operations = Vec::new();

        for (id, _action, payload) in rows {
            match serde_json::from_str(&payload) {
                Ok(op) => operations.push((id, op)),
                Err(e) => {
                    tracing::warn!("Failed to parse offline operation {}: {}", id, e);
                }
            }
        }

        Ok(operations)
    }

    /// Remove a completed operation from the queue
    pub fn complete_operation(&self, id: i64) -> AppResult<()> {
        self.database.remove_offline_operation(id)?;

        let mut state = self.state.write();
        if state.pending_count > 0 {
            state.pending_count -= 1;
        }

        Ok(())
    }

    /// Increment retry count for a failed operation
    pub fn retry_operation(&self, id: i64) -> AppResult<()> {
        self.database.increment_operation_retry(id)
    }

    /// Cache file metadata
    pub fn cache_files(&self, files: &[CachedFile]) -> AppResult<()> {
        self.database.cache_files(files)
    }

    /// Get cached files for a folder
    pub fn get_cached_files(&self, folder_id: Option<&str>) -> AppResult<Vec<CachedFile>> {
        self.database.get_cached_files(folder_id)
    }

    /// Clear file cache for a folder
    pub fn clear_folder_cache(&self, folder_id: Option<&str>) -> AppResult<()> {
        self.database.clear_folder_cache(folder_id)
    }

    /// Update sync status
    pub fn set_status(&self, status: SyncStatus) {
        let mut state = self.state.write();
        state.status = status;
    }

    /// Mark sync as completed
    pub fn mark_synced(&self) {
        let mut state = self.state.write();
        state.last_sync = Some(Instant::now());
        state.status = SyncStatus::Idle;
    }

    /// Get time since last sync
    pub fn time_since_sync(&self) -> Option<Duration> {
        self.state.read().last_sync.map(|t| t.elapsed())
    }
}
