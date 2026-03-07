//! WebAuthn (passkey) authentication commands

use crate::error::{AppError, AppResult};
use crate::models::{
    WebAuthnLoginBeginResponse, WebAuthnLoginCompleteRequest, WebAuthnLoginResponse,
    WebAuthnRegisterBeginResponse, WebAuthnRegisterCompleteRequest,
};
use crate::state::AppState;
use tauri::State;

/// Begin WebAuthn login - returns options for navigator.credentials.get()
#[tauri::command]
pub async fn webauthn_login_begin(
    email: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<WebAuthnLoginBeginResponse> {
    tracing::info!("Starting WebAuthn login");
    state
        .webauthn_service()
        .login_begin(email.as_deref())
        .await
}

/// Complete WebAuthn login with assertion from browser
#[tauri::command]
pub async fn webauthn_login_complete(
    challenge_id: String,
    assertion: serde_json::Value,
    prf_output: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<WebAuthnLoginResponse> {
    tracing::info!("Completing WebAuthn login");

    let request = WebAuthnLoginCompleteRequest {
        challenge_id,
        assertion,
        prf_output: prf_output.clone(),
    };

    let response = state.webauthn_service().login_complete(request).await?;

    let key_bundle = &response.key_bundle;

    // Determine key unlock method based on bundle source
    if key_bundle.source == "credential" {
        // PRF-based: use prf_output to derive wrapping key
        let prf = prf_output
            .ok_or_else(|| AppError::Auth("PRF output required for credential-based key bundle".to_string()))?;
        let prf_bytes = base64::engine::general_purpose::STANDARD
            .decode(&prf)
            .map_err(|e| AppError::Crypto(format!("Invalid PRF output: {}", e)))?;

        use base64::Engine;
        let wrapping_key = state.webauthn_service().derive_prf_wrapping_key(&prf_bytes)?;

        let encrypted_mk = key_bundle.encrypted_master_key.as_ref()
            .ok_or_else(|| AppError::Auth("Missing encrypted_master_key".to_string()))?;
        let mk_nonce = key_bundle.mk_nonce.as_ref()
            .ok_or_else(|| AppError::Auth("Missing mk_nonce".to_string()))?;

        state.auth_service().login_with_vault_key_bundle(
            &response.access_token,
            &response.refresh_token,
            &response.device_id,
            encrypted_mk,
            mk_nonce,
            &wrapping_key,
            &key_bundle.encrypted_private_keys,
        ).await?;
    } else {
        // Vault-based: derive vault key from server-provided key_material
        let key_material = key_bundle.key_material.as_ref()
            .ok_or_else(|| AppError::Auth("Missing key_material for vault-based unlock".to_string()))?;
        let key_salt = key_bundle.key_salt.as_ref()
            .ok_or_else(|| AppError::Auth("Missing key_salt for vault-based unlock".to_string()))?;

        let vault_key = state.oidc_service().derive_vault_key(key_material, key_salt)?;

        let vault_mk = key_bundle.vault_encrypted_master_key.as_ref()
            .ok_or_else(|| AppError::Auth("Missing vault_encrypted_master_key".to_string()))?;
        let vault_nonce = key_bundle.vault_mk_nonce.as_ref()
            .ok_or_else(|| AppError::Auth("Missing vault_mk_nonce".to_string()))?;

        state.auth_service().login_with_vault_key_bundle(
            &response.access_token,
            &response.refresh_token,
            &response.device_id,
            vault_mk,
            vault_nonce,
            &vault_key,
            &key_bundle.encrypted_private_keys,
        ).await?;
    }

    // Update app state
    state.set_current_user(Some(response.user.clone()));
    state.unlock();
    state.api_client().set_auth_token(Some(response.access_token.clone()));

    Ok(response)
}

/// Begin WebAuthn registration
#[tauri::command]
pub async fn webauthn_register_begin(
    email: String,
    tenant_slug: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<WebAuthnRegisterBeginResponse> {
    tracing::info!("Starting WebAuthn registration");
    state
        .webauthn_service()
        .register_begin(&email, tenant_slug.as_deref())
        .await
}

/// Complete WebAuthn registration
#[tauri::command]
pub async fn webauthn_register_complete(
    request: WebAuthnRegisterCompleteRequest,
    state: State<'_, AppState>,
) -> AppResult<WebAuthnLoginResponse> {
    tracing::info!("Completing WebAuthn registration");
    let response = state.webauthn_service().register_complete(request).await?;

    // Update app state
    state.set_current_user(Some(response.user.clone()));
    state.unlock();
    state.api_client().set_auth_token(Some(response.access_token.clone()));

    Ok(response)
}

/// Begin adding a new passkey credential (authenticated)
#[tauri::command]
pub async fn webauthn_add_credential_begin(
    state: State<'_, AppState>,
) -> AppResult<WebAuthnRegisterBeginResponse> {
    state.require_auth()?;
    tracing::info!("Starting add credential flow");
    state.webauthn_service().credential_begin().await
}

/// Complete adding a new passkey credential (authenticated)
#[tauri::command]
pub async fn webauthn_add_credential_complete(
    request: WebAuthnRegisterCompleteRequest,
    state: State<'_, AppState>,
) -> AppResult<serde_json::Value> {
    state.require_auth()?;
    tracing::info!("Completing add credential flow");
    state.webauthn_service().credential_complete(request).await
}
