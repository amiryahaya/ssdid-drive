//! Sharing commands

use crate::error::AppResult;
use crate::models::{
    CreateShareRequest, CreateShareResponse, RecipientSearchResult, Share, ShareListResponse,
    SharePermission,
};
use crate::state::AppState;
use tauri::State;

/// Search for users to share with
#[tauri::command]
pub async fn search_recipients(
    query: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<RecipientSearchResult>> {
    state.require_auth()?;

    tracing::debug!("Searching recipients: {}", query);

    state.sharing_service().search_recipients(&query).await
}

/// Create a new share for a file or folder
#[tauri::command]
pub async fn create_share(
    item_id: String,
    recipient_email: String,
    permission: SharePermission,
    expires_at: Option<String>,
    message: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<CreateShareResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!(
        "Creating share for item: {} to recipient: {}",
        item_id,
        recipient_email
    );

    let request = CreateShareRequest {
        item_id,
        recipient_email,
        permission,
        expires_at,
        message,
    };

    // Get signing keys from session for share signature
    let signing_keys = state.auth_service().get_signing_keys().ok();
    let signing_keys_ref = signing_keys
        .as_ref()
        .map(|(ml_dsa, kaz_sign)| (ml_dsa.as_str(), kaz_sign.as_str()));

    state.sharing_service().create_share(request, signing_keys_ref).await
}

/// Revoke an existing share
#[tauri::command]
pub async fn revoke_share(share_id: String, state: State<'_, AppState>) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Revoking share: {}", share_id);

    state.sharing_service().revoke_share(&share_id).await
}

/// Update share permissions
#[tauri::command]
pub async fn update_share(
    share_id: String,
    permission: SharePermission,
    expires_at: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<Share> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Updating share: {}", share_id);

    state
        .sharing_service()
        .update_share(&share_id, permission, expires_at)
        .await
}

/// List shares created by the current user
#[tauri::command]
pub async fn list_my_shares(state: State<'_, AppState>) -> AppResult<ShareListResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Listing user's created shares");

    state.sharing_service().list_my_shares().await
}

/// List shares received by the current user
#[tauri::command]
pub async fn list_shared_with_me(state: State<'_, AppState>) -> AppResult<ShareListResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Listing shares received by user");

    state.sharing_service().list_shared_with_me().await
}

/// Get details for a specific share
#[tauri::command]
pub async fn get_share_details(share_id: String, state: State<'_, AppState>) -> AppResult<Share> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Getting share details: {}", share_id);

    state.sharing_service().get_share_details(&share_id).await
}

/// Accept a received share
#[tauri::command]
pub async fn accept_share(share_id: String, state: State<'_, AppState>) -> AppResult<Share> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Accepting share: {}", share_id);

    state.sharing_service().accept_share(&share_id).await
}

/// Decline a received share
#[tauri::command]
pub async fn decline_share(share_id: String, state: State<'_, AppState>) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Declining share: {}", share_id);

    state.sharing_service().decline_share(&share_id).await
}
