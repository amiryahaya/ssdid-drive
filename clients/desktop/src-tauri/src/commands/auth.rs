//! Authentication commands

use crate::error::AppResult;
use crate::models::{
    AuthStatus, ChangePasswordRequest, Device, LoginCredentials, LoginResponse,
    RegistrationInfo, RegistrationResponse, UpdateProfileRequest, User,
};
use crate::state::AppState;
use tauri::State;

/// Login with email and password
#[tauri::command]
pub async fn login(
    email: String,
    password: String,
    state: State<'_, AppState>,
) -> AppResult<LoginResponse> {
    tracing::info!("Login attempt for: {}", email);

    let credentials = LoginCredentials {
        email,
        password,
        device_id: None,
    };

    let response = state.auth_service().login(credentials).await?;

    // Update app state
    state.set_current_user(Some(response.user.clone()));
    state.unlock();

    tracing::info!("Login successful for user: {}", response.user.id);
    Ok(response)
}

/// Register a new user
#[tauri::command]
pub async fn register(
    email: String,
    password: String,
    name: String,
    invitation_token: String,
    state: State<'_, AppState>,
) -> AppResult<RegistrationResponse> {
    tracing::info!("Registration attempt for: {}", email);

    let info = RegistrationInfo {
        email,
        password,
        name,
        invitation_token,
    };

    let response = state.auth_service().register(info).await?;

    // Update app state
    state.set_current_user(Some(response.user.clone()));
    state.unlock();

    tracing::info!("Registration successful for user: {}", response.user.id);
    Ok(response)
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

/// Get the current authenticated user
#[tauri::command]
pub async fn get_current_user(state: State<'_, AppState>) -> AppResult<Option<User>> {
    Ok(state.current_user())
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

/// Change the user's password
#[tauri::command]
pub async fn change_password(
    current_password: String,
    new_password: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    tracing::info!("Password change requested");

    let request = ChangePasswordRequest {
        current_password,
        new_password,
    };

    state.auth_service().change_password(request).await
}

/// Update user profile
#[tauri::command]
pub async fn update_profile(
    name: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<User> {
    state.require_auth()?;
    tracing::info!("Profile update requested");

    let request = UpdateProfileRequest { name };
    let user = state.auth_service().update_profile(request).await?;

    // Update app state with new user info
    state.set_current_user(Some(user.clone()));

    Ok(user)
}

/// List all devices/sessions for the current user
#[tauri::command]
pub async fn list_devices(state: State<'_, AppState>) -> AppResult<Vec<Device>> {
    state.require_auth()?;
    tracing::debug!("Listing devices");

    state.auth_service().list_devices().await
}

/// Revoke a device/session
#[tauri::command]
pub async fn revoke_device(
    device_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    tracing::info!("Revoking device: {}", device_id);

    state.auth_service().revoke_device(&device_id).await
}
