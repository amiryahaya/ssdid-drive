//! File operation commands

use crate::error::AppResult;
use crate::models::{
    CreateFolderRequest, FileItem, FileListResponse, FilePreview, MoveRequest, RenameRequest,
    UploadProgress, UploadRequest,
};
use crate::state::AppState;
use tauri::{Emitter, State, Window};

/// List files and folders in a directory
#[tauri::command]
pub async fn list_files(
    folder_id: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<FileListResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Listing files in folder: {:?}", folder_id);

    let response = state.file_service().list_files(folder_id.as_deref()).await?;

    Ok(response)
}

/// Upload a file from the local filesystem
#[tauri::command]
pub async fn upload_file(
    file_path: String,
    folder_id: Option<String>,
    file_name: Option<String>,
    state: State<'_, AppState>,
    window: Window,
) -> AppResult<FileItem> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Uploading file: {} to folder: {:?}", file_path, folder_id);

    let request = UploadRequest {
        file_path,
        folder_id,
        file_name,
    };

    let file = state
        .file_service()
        .upload_file(request, move |progress| {
            // Emit progress event to frontend
            let _ = window.emit("upload-progress", &progress);
        })
        .await?;

    tracing::info!("File uploaded successfully: {}", file.id);
    Ok(file)
}

/// Download a file to the local filesystem
#[tauri::command]
pub async fn download_file(
    file_id: String,
    destination: String,
    state: State<'_, AppState>,
    window: Window,
) -> AppResult<String> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Downloading file: {} to: {}", file_id, destination);

    let result_path = state
        .file_service()
        .download_file(&file_id, &destination, move |progress| {
            // Emit progress event to frontend
            let _ = window.emit("download-progress", &progress);
        })
        .await?;

    tracing::info!("File downloaded successfully to: {}", result_path);
    Ok(result_path)
}

/// Create a new folder
#[tauri::command]
pub async fn create_folder(
    name: String,
    parent_id: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<FileItem> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Creating folder: {} in parent: {:?}", name, parent_id);

    let request = CreateFolderRequest { name, parent_id };

    let folder = state.file_service().create_folder(request).await?;

    tracing::info!("Folder created successfully: {}", folder.id);
    Ok(folder)
}

/// Delete a file or folder
#[tauri::command]
pub async fn delete_item(item_id: String, state: State<'_, AppState>) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Deleting item: {}", item_id);

    state.file_service().delete_item(&item_id).await?;

    tracing::info!("Item deleted successfully: {}", item_id);
    Ok(())
}

/// Rename a file or folder
#[tauri::command]
pub async fn rename_item(
    item_id: String,
    new_name: String,
    state: State<'_, AppState>,
) -> AppResult<FileItem> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Renaming item: {} to: {}", item_id, new_name);

    let request = RenameRequest { item_id, new_name };

    let item = state.file_service().rename_item(request).await?;

    tracing::info!("Item renamed successfully: {}", item.id);
    Ok(item)
}

/// Move a file or folder to a new parent
#[tauri::command]
pub async fn move_item(
    item_id: String,
    new_folder_id: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<FileItem> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Moving item: {} to folder: {:?}", item_id, new_folder_id);

    let request = MoveRequest {
        item_id,
        new_folder_id,
    };

    let item = state.file_service().move_item(request).await?;

    tracing::info!("Item moved successfully: {}", item.id);
    Ok(item)
}

/// Get preview data for a file
#[tauri::command]
pub async fn get_file_preview(file_id: String, state: State<'_, AppState>) -> AppResult<FilePreview> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Getting preview for file: {}", file_id);

    let preview = state.file_service().get_preview(&file_id).await?;

    Ok(preview)
}
