//! Account management commands (linked logins)

use crate::error::{AppError, AppResult};
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinkedLogin {
    pub id: String,
    pub provider: String,
    pub provider_subject: String,
    pub email: Option<String>,
    pub linked_at: String,
}

/// List all linked logins for the current account
#[tauri::command]
pub async fn list_logins(state: State<'_, AppState>) -> AppResult<Vec<LinkedLogin>> {
    state
        .api_client()
        .get::<Vec<LinkedLogin>>("/account/logins")
        .await
}

/// Initiate linking a new email login (sends OTP)
#[tauri::command]
pub async fn link_email_login(
    email: String,
    state: State<'_, AppState>,
) -> AppResult<serde_json::Value> {
    #[derive(Serialize)]
    struct Body {
        email: String,
    }

    state
        .api_client()
        .post::<Body, serde_json::Value>("/account/logins/email", &Body { email })
        .await
}

/// Link an OIDC login to the current account
#[tauri::command]
pub async fn link_oidc_login(
    provider: String,
    id_token: String,
    state: State<'_, AppState>,
) -> AppResult<serde_json::Value> {
    #[derive(Serialize)]
    struct Body {
        provider: String,
        id_token: String,
    }

    state
        .api_client()
        .post::<Body, serde_json::Value>("/account/logins/oidc", &Body { provider, id_token })
        .await
}

/// Unlink a login from the current account
#[tauri::command]
pub async fn unlink_login(
    login_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    let parsed_id = uuid::Uuid::parse_str(&login_id)
        .map_err(|_| AppError::Validation("Invalid login ID".into()))?;
    state
        .api_client()
        .delete_no_content(&format!("/account/logins/{}", parsed_id))
        .await
}
