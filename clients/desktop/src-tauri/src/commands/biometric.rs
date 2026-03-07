//! Biometric authentication commands

use crate::error::AppResult;
use crate::services::{BiometricAvailability, BiometricStatus};
use crate::state::AppState;
use tauri::State;

/// Check biometric authentication availability
#[tauri::command]
pub async fn check_biometric_availability(
    state: State<'_, AppState>,
) -> AppResult<BiometricStatus> {
    tracing::debug!("Checking biometric availability");
    state.biometric_service().check_availability().await
}

/// Get the type of biometric available (for UI display)
#[tauri::command]
pub async fn get_biometric_type(
    state: State<'_, AppState>,
) -> AppResult<Option<String>> {
    let status = state.biometric_service().check_availability().await?;
    Ok(status.biometric_type)
}

/// Check if biometric is enabled by user preference
#[tauri::command]
pub fn is_biometric_enabled(state: State<'_, AppState>) -> bool {
    state.biometric_service().is_enabled()
}

/// Enable or disable biometric authentication
#[tauri::command]
pub async fn set_biometric_enabled(
    state: State<'_, AppState>,
    enabled: bool,
) -> AppResult<()> {
    tracing::info!("Setting biometric enabled: {}", enabled);

    // If enabling, verify biometric is actually available
    if enabled {
        let status = state.biometric_service().check_availability().await?;
        if status.availability != BiometricAvailability::Available {
            return Err(crate::error::AppError::Auth(format!(
                "Cannot enable biometric: {}",
                status.message
            )));
        }
    }

    state.biometric_service().set_enabled(enabled);

    Ok(())
}

/// Authenticate using biometric
#[tauri::command]
pub async fn authenticate_biometric(
    state: State<'_, AppState>,
    reason: String,
) -> AppResult<bool> {
    tracing::info!("Authenticating with biometric");
    state.biometric_service().authenticate(&reason).await
}

/// Unlock the application using biometric authentication
#[tauri::command]
pub async fn unlock_with_biometric(
    state: State<'_, AppState>,
) -> AppResult<bool> {
    tracing::info!("Attempting to unlock with biometric");

    // Check if biometric is enabled
    if !state.biometric_service().is_enabled() {
        return Err(crate::error::AppError::Auth(
            "Biometric authentication is not enabled".to_string()
        ));
    }

    // Authenticate
    let authenticated = state
        .biometric_service()
        .authenticate("Unlock SSDID Drive")
        .await?;

    if authenticated {
        state.unlock();
        tracing::info!("Application unlocked via biometric");
    }

    Ok(authenticated)
}
