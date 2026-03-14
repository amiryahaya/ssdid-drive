//! OIDC authentication commands
//!
//! Desktop OIDC flow:
//! 1. Client calls `oidc_login` -> generates nonce, opens system browser
//! 2. Provider redirects to `ssdid-drive://auth/callback?provider=X&id_token=Y&nonce=Z`
//! 3. Deep link handler captures the redirect, calls `verify_oidc_token`
//! 4. Rust validates nonce, backend verifies the ID token, returns session token

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
    const ALLOWED_PROVIDERS: &[&str] = &["google", "microsoft"];
    if !ALLOWED_PROVIDERS.contains(&provider.as_str()) {
        return Err(AppError::Validation(format!("Unknown OIDC provider: {}", provider)));
    }

    let nonce = state.generate_oidc_nonce();

    let base_url = state.api_client().base_url().to_string();
    let server_url = base_url
        .trim_end_matches("/api")
        .trim_end_matches("/api/");

    let redirect_uri = format!("ssdid-drive://auth/callback?nonce={}", nonce);
    let authorize_url = format!(
        "{}/api/auth/oidc/{}/authorize?redirect_uri={}",
        server_url,
        provider,
        urlencoding::encode(&redirect_uri)
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
    nonce: Option<String>,
    invitation_token: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<OidcLoginResponse> {
    // Validate nonce to prevent deep link spoofing
    if let Some(ref n) = nonce {
        if !state.validate_oidc_nonce(n) {
            return Err(AppError::Auth("Invalid or expired OIDC nonce".into()));
        }
    } else {
        return Err(AppError::Auth("Missing OIDC nonce".into()));
    }

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

    state.complete_login(&response.token).await?;

    Ok(response)
}
