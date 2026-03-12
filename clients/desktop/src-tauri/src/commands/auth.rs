//! Authentication commands (SSDID session model)
//!
//! The SSDID Wallet handles identity and signing. These commands
//! manage the session token and user state on the desktop side.

use crate::error::{AppError, AppResult};
use crate::models::{AuthStatus, User};
use crate::state::AppState;
use serde::{Deserialize, Serialize};
use tauri::State;

#[derive(Debug, Serialize)]
pub struct ChallengeResult {
    pub challenge_id: String,
    pub subscriber_secret: String,
    pub qr_payload: String,
    pub server_did: String,
}

/// Create a login/register challenge by calling the backend API (from Rust, bypassing CORS)
#[tauri::command]
pub async fn create_challenge(
    state: State<'_, AppState>,
) -> AppResult<ChallengeResult> {
    let base_url = state.api_client().base_url().to_string();
    // The API base_url includes /api, and the auth routes are at /api/auth/ssdid/login/initiate
    // So we need to strip /api from base_url and use the full path
    let server_url = base_url.trim_end_matches("/api").trim_end_matches("/api/");
    let url = format!("{}/api/auth/ssdid/login/initiate", server_url);

    tracing::info!("Creating challenge via: {}", url);

    let client = reqwest::Client::new();
    let resp = client
        .post(&url)
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| AppError::Network(format!("Failed to initiate login: {}", e)))?;

    if !resp.status().is_success() {
        return Err(AppError::Network(format!(
            "Login initiate failed: {}",
            resp.status()
        )));
    }

    #[derive(Deserialize)]
    struct QrPayload {
        server_did: String,
    }

    #[derive(Deserialize)]
    struct InitiateResponse {
        challenge_id: String,
        subscriber_secret: String,
        qr_payload: serde_json::Value,
    }

    let data: InitiateResponse = resp
        .json()
        .await
        .map_err(|e| AppError::Network(format!("Invalid response: {}", e)))?;

    let server_did = data.qr_payload
        .get("server_did")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();

    Ok(ChallengeResult {
        challenge_id: data.challenge_id,
        subscriber_secret: data.subscriber_secret,
        qr_payload: data.qr_payload.to_string(),
        server_did,
    })
}

/// Save a session token after successful SSDID wallet authentication
#[tauri::command]
pub async fn save_session(
    token: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    tracing::info!("Saving session token from SSDID wallet auth");
    state.auth_service().save_session(&token)?;
    state.unlock();

    // Fetch and cache the current user
    match state.auth_service().get_current_user().await {
        Ok(user) => {
            tracing::info!("Session saved for user: {}", user.id);
            state.set_current_user(Some(user));
        }
        Err(e) => {
            tracing::warn!("Session saved but failed to fetch user: {}", e);
        }
    }

    Ok(())
}

/// Check the current authentication status
#[tauri::command]
pub async fn check_auth_status(state: State<'_, AppState>) -> AppResult<AuthStatus> {
    let user = state.current_user();
    let is_locked = state.is_locked();

    Ok(AuthStatus {
        is_authenticated: user.is_some(),
        is_locked,
        user,
    })
}

/// Get the current authenticated user
#[tauri::command]
pub async fn get_current_user(state: State<'_, AppState>) -> AppResult<Option<User>> {
    // If we have a cached user, return it
    if let Some(user) = state.current_user() {
        return Ok(Some(user));
    }

    // If we have a session but no cached user, try to fetch
    if state.auth_service().is_authenticated() {
        match state.auth_service().get_current_user().await {
            Ok(user) => {
                state.set_current_user(Some(user.clone()));
                state.unlock();
                Ok(Some(user))
            }
            Err(_) => Ok(None),
        }
    } else {
        Ok(None)
    }
}

/// Logout the current user
#[tauri::command]
pub async fn logout(state: State<'_, AppState>) -> AppResult<()> {
    let user_id = state.current_user().map(|u| u.id.clone());
    tracing::info!("Logout for user: {:?}", user_id);

    state.auth_service().logout().await?;

    // Clear app state
    state.set_current_user(None);
    state.lock();

    Ok(())
}
