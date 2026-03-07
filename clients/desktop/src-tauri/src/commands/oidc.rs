//! OIDC authentication commands

use crate::error::{AppError, AppResult};
use crate::models::{
    AuthProvider, OidcCallbackResponse, OidcRegisterRequest, OidcRegisterResponse,
};
use crate::state::AppState;
use tauri::State;

/// Get available auth providers for a tenant
#[tauri::command]
pub async fn oidc_get_providers(
    tenant_slug: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<AuthProvider>> {
    tracing::debug!("Fetching auth providers for tenant: {}", tenant_slug);
    state.oidc_service().get_providers(&tenant_slug).await
}

/// Begin OIDC login flow - returns authorization URL to open in browser
#[tauri::command]
pub async fn oidc_begin_login(
    provider_id: String,
    state: State<'_, AppState>,
) -> AppResult<String> {
    tracing::info!("Starting OIDC login for provider: {}", provider_id);

    let response = state
        .oidc_service()
        .begin_authorize(&provider_id)
        .await?;

    Ok(response.authorization_url)
}

/// Handle OIDC callback after browser redirect
#[tauri::command]
pub async fn oidc_handle_callback(
    code: String,
    oidc_state: String,
    state: State<'_, AppState>,
) -> AppResult<OidcCallbackResponse> {
    tracing::info!("Handling OIDC callback");

    let response = state
        .oidc_service()
        .handle_callback(&code, &oidc_state)
        .await?;

    // If this is an existing user, complete the login
    if response.status == "authenticated" {
        let user = response
            .user
            .clone()
            .ok_or_else(|| AppError::Auth("Missing user in OIDC response".to_string()))?;
        let access_token = response
            .access_token
            .clone()
            .ok_or_else(|| AppError::Auth("Missing access_token".to_string()))?;
        let refresh_token = response
            .refresh_token
            .clone()
            .ok_or_else(|| AppError::Auth("Missing refresh_token".to_string()))?;
        let device_id = response
            .device_id
            .clone()
            .ok_or_else(|| AppError::Auth("Missing device_id".to_string()))?;
        let key_bundle = response
            .key_bundle
            .clone()
            .ok_or_else(|| AppError::Auth("Missing key_bundle".to_string()))?;

        // Derive vault key and unlock
        let key_material = key_bundle.key_material.as_ref()
            .ok_or_else(|| AppError::Auth("Missing key_material in vault bundle".to_string()))?;
        let key_salt = key_bundle.key_salt.as_ref()
            .ok_or_else(|| AppError::Auth("Missing key_salt in vault bundle".to_string()))?;

        let vault_key = state
            .oidc_service()
            .derive_vault_key(key_material, key_salt)?;

        state.auth_service().login_with_vault_key_bundle(
            &access_token,
            &refresh_token,
            &device_id,
            &key_bundle.vault_encrypted_master_key,
            &key_bundle.vault_mk_nonce,
            &vault_key,
            &key_bundle.encrypted_private_keys,
        ).await?;

        // Update app state
        state.set_current_user(Some(user));
        state.unlock();

        // Set API auth token
        state.api_client().set_auth_token(Some(access_token));
    }

    Ok(response)
}

/// Complete OIDC registration for a new user
#[tauri::command]
pub async fn oidc_complete_registration(
    provider_id: String,
    oidc_sub: String,
    email: String,
    name: String,
    key_material: String,
    key_salt: String,
    state: State<'_, AppState>,
) -> AppResult<OidcRegisterResponse> {
    tracing::info!("Completing OIDC registration for: {}", email);

    // Derive vault key from OIDC key material
    let vault_key = state
        .oidc_service()
        .derive_vault_key(&key_material, &key_salt)?;

    // Generate new PQC keys
    let crypto = state.crypto_service();
    let (ml_kem_pk, ml_kem_sk) = crypto.generate_ml_kem_keypair()?;
    let (ml_dsa_pk, ml_dsa_sk) = crypto.generate_ml_dsa_keypair()?;
    let (kaz_kem_pk, kaz_kem_sk) = crypto.generate_kaz_kem_keypair()?;
    let (kaz_sign_pk, kaz_sign_sk) = crypto.generate_kaz_sign_keypair()?;

    // Generate and encrypt master key
    let master_key = crypto.generate_master_key()?;
    let (vault_encrypted_mk, vault_mk_nonce) = crypto.encrypt_master_key(&master_key, &vault_key)?;

    use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
    let vault_salt = BASE64.encode(&vault_key[..16]); // Use first 16 bytes as salt identifier

    // Encrypt private keys with master key
    let encrypted_ml_kem_sk = crypto.encrypt_private_key(&ml_kem_sk, &master_key)?;
    let encrypted_ml_dsa_sk = crypto.encrypt_private_key(&ml_dsa_sk, &master_key)?;
    let encrypted_kaz_kem_sk = crypto.encrypt_private_key(&kaz_kem_sk, &master_key)?;
    let encrypted_kaz_sign_sk = crypto.encrypt_private_key(&kaz_sign_sk, &master_key)?;

    let request = OidcRegisterRequest {
        provider_id,
        oidc_sub,
        email,
        name,
        vault_encrypted_master_key: vault_encrypted_mk,
        vault_mk_nonce,
        vault_salt,
        encrypted_ml_kem_sk,
        encrypted_ml_dsa_sk,
        encrypted_kaz_kem_sk,
        encrypted_kaz_sign_sk,
        ml_kem_pk,
        ml_dsa_pk,
        kaz_kem_pk,
        kaz_sign_pk,
    };

    let response = state.oidc_service().complete_registration(request).await?;

    // Store tokens and set up session
    state.api_client().set_auth_token(Some(response.access_token.clone()));
    state.keyring().store_auth_token(&response.access_token)?;
    state.keyring().store_refresh_token(&response.refresh_token)?;
    state.keyring().store_device_id(&response.device_id)?;

    // Store master key and session keys
    crypto.set_master_key(master_key)?;
    state.auth_service().set_session_keys_from_raw(
        &ml_kem_sk, &ml_dsa_sk, &kaz_kem_sk, &kaz_sign_sk,
    )?;

    // Update app state
    state.set_current_user(Some(response.user.clone()));
    state.unlock();

    Ok(response)
}
