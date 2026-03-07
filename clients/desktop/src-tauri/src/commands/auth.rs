//! Authentication commands (SSDID session model)
//!
//! The SSDID Wallet handles identity and signing. These commands
//! manage the session token and user state on the desktop side.

use crate::error::AppResult;
use crate::models::{AuthStatus, User};
use crate::state::AppState;
use tauri::State;

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
