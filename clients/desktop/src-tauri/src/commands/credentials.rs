//! Credential management commands

use crate::error::AppResult;
use crate::models::{CredentialListResponse, RenameCredentialRequest, UserCredential};
use crate::state::AppState;
use tauri::State;

/// List all credentials for the current user
#[tauri::command]
pub async fn list_credentials(
    state: State<'_, AppState>,
) -> AppResult<Vec<UserCredential>> {
    state.require_auth()?;
    tracing::debug!("Listing credentials");

    let response: CredentialListResponse = state
        .api_client()
        .get("/auth/credentials")
        .await?;

    Ok(response.credentials)
}

/// Rename a credential
#[tauri::command]
pub async fn rename_credential(
    credential_id: String,
    name: String,
    state: State<'_, AppState>,
) -> AppResult<UserCredential> {
    state.require_auth()?;
    tracing::info!("Renaming credential: {}", credential_id);

    let request = RenameCredentialRequest { name };
    let credential: UserCredential = state
        .api_client()
        .put(&format!("/auth/credentials/{}", credential_id), &request)
        .await?;

    Ok(credential)
}

/// Delete a credential
#[tauri::command]
pub async fn delete_credential(
    credential_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    tracing::info!("Deleting credential: {}", credential_id);

    state
        .api_client()
        .delete_no_content(&format!("/auth/credentials/{}", credential_id))
        .await
}
