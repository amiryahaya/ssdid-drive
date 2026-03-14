//! TOTP setup and verification commands

use crate::error::AppResult;
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
pub struct TotpSetupResponse {
    pub secret: String,
    pub otpauth_uri: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TotpSetupConfirmResponse {
    pub backup_codes: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TotpVerifyResponse {
    pub token: String,
}

/// Request TOTP setup (requires auth)
#[tauri::command]
pub async fn totp_setup(state: State<'_, AppState>) -> AppResult<TotpSetupResponse> {
    state
        .api_client()
        .post::<(), TotpSetupResponse>("/auth/totp/setup", &())
        .await
}

/// Confirm TOTP setup with first code (requires auth)
#[tauri::command]
pub async fn totp_setup_confirm(
    code: String,
    state: State<'_, AppState>,
) -> AppResult<TotpSetupConfirmResponse> {
    #[derive(Serialize)]
    struct Body {
        code: String,
    }

    state
        .api_client()
        .post::<Body, TotpSetupConfirmResponse>("/auth/totp/setup/confirm", &Body { code })
        .await
}

/// Verify TOTP code for login (public endpoint)
#[tauri::command]
pub async fn totp_verify(
    email: String,
    code: String,
    state: State<'_, AppState>,
) -> AppResult<TotpVerifyResponse> {
    #[derive(Serialize)]
    struct Body {
        email: String,
        code: String,
    }

    let response: TotpVerifyResponse = state
        .api_client()
        .post_unauth("/auth/totp/verify", &Body { email, code })
        .await?;

    // Save session token
    state.auth_service().save_session(&response.token)?;
    state.unlock();

    // Fetch and cache user
    if let Ok(user) = state.auth_service().get_current_user().await {
        state.set_current_user(Some(user));
    }

    Ok(response)
}
