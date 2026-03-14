//! OIDC authentication commands
//!
//! Desktop OIDC flow:
//! 1. Client calls `oidc_login` -> opens system browser to provider auth URL
//! 2. Provider redirects to `ssdid-drive://auth/callback?provider=X&id_token=Y`
//! 3. Deep link handler captures the redirect, calls `verify_oidc_token`
//! 4. Backend verifies the ID token, returns session token

use crate::error::{AppError, AppResult};
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize, Deserialize)]
pub struct OidcLoginResponse {
    pub token: String,
    pub mfa_required: Option<bool>,
    pub totp_setup_required: Option<bool>,
}

/// Open system browser for OIDC provider authentication
#[tauri::command]
pub async fn oidc_login(provider: String, state: State<'_, AppState>) -> AppResult<()> {
    let base_url = state.api_client().base_url().to_string();
    let server_url = base_url
        .trim_end_matches("/api")
        .trim_end_matches("/api/");

    // The server-side authorize endpoint generates PKCE state and redirects
    // the browser to the identity provider (Google/Microsoft).
    let authorize_url = format!(
        "{}/api/auth/oidc/{}/authorize?redirect_uri={}",
        server_url,
        provider,
        urlencoding::encode("ssdid-drive://auth/callback")
    );

    tracing::info!("Opening OIDC authorize URL for provider: {}", provider);

    open::that(&authorize_url)
        .map_err(|e| AppError::Auth(format!("Failed to open browser: {}", e)))?;

    Ok(())
}

/// Verify an OIDC ID token received from the provider callback
#[tauri::command]
pub async fn verify_oidc_token(
    provider: String,
    id_token: String,
    invitation_token: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<OidcLoginResponse> {
    #[derive(Serialize)]
    struct Body {
        provider: String,
        id_token: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        invitation_token: Option<String>,
    }

    let response: OidcLoginResponse = state
        .api_client()
        .post_unauth(
            "/auth/oidc/verify",
            &Body {
                provider,
                id_token,
                invitation_token,
            },
        )
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
