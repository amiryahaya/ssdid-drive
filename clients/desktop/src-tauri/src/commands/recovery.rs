//! Recovery commands
//!
//! Handles key recovery using Shamir secret sharing with trustees.

use crate::error::{AppError, AppResult};
use crate::models::{
    InitiateRecoveryRequest, RecoveryRequest, RecoverySetup, SetupRecoveryRequest,
};
use crate::state::AppState;
use tauri::State;

/// Setup recovery with trustees
///
/// Splits the master key using Shamir's secret sharing scheme and distributes
/// encrypted shares to the specified trustees.
#[tauri::command]
pub async fn setup_recovery(
    threshold: u32,
    trustee_emails: Vec<String>,
    state: State<'_, AppState>,
) -> AppResult<RecoverySetup> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!(
        "Setting up recovery with {} trustees, threshold: {}",
        trustee_emails.len(),
        threshold
    );

    let request = SetupRecoveryRequest {
        threshold,
        trustee_emails,
    };

    // Get the actual master key from crypto service
    let master_key = state.crypto_service().get_master_key()?;

    state
        .recovery_service()
        .setup_recovery(request, &master_key)
        .await
}

/// Get the current recovery configuration status
#[tauri::command]
pub async fn get_recovery_status(state: State<'_, AppState>) -> AppResult<RecoverySetup> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Getting recovery status");

    state.recovery_service().get_recovery_status().await
}

/// Initiate account recovery
///
/// Starts the recovery process for a user who has lost their password.
/// Trustees will be notified to approve the request.
#[tauri::command]
pub async fn initiate_recovery(
    email: String,
    new_password: String,
    state: State<'_, AppState>,
) -> AppResult<RecoveryRequest> {
    tracing::info!("Initiating recovery for: {}", email);

    let request = InitiateRecoveryRequest {
        email,
        new_password,
    };

    state.recovery_service().initiate_recovery(request).await
}

/// Approve a recovery request (as a trustee)
///
/// Called by a trustee to submit their decrypted share for recovery.
#[tauri::command]
pub async fn approve_recovery_request(
    recovery_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Approving recovery request: {}", recovery_id);

    // Get the trustee's KEM private keys from the session
    let (ml_kem_sk, kaz_kem_sk) = state.auth_service().get_kem_keys()?;

    state
        .recovery_service()
        .approve_recovery_request(&recovery_id, &ml_kem_sk, &kaz_kem_sk)
        .await
}

/// Complete the recovery process (after sufficient approvals)
///
/// Reconstructs the master key from submitted shares and re-encrypts
/// with the new password.
#[tauri::command]
pub async fn complete_recovery(
    recovery_id: String,
    new_password: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    tracing::info!("Completing recovery: {}", recovery_id);

    state
        .recovery_service()
        .complete_recovery(&recovery_id, &new_password)
        .await
}

/// Get pending recovery requests where the current user is a trustee
#[tauri::command]
pub async fn get_pending_recovery_requests(
    state: State<'_, AppState>,
) -> AppResult<Vec<RecoveryRequest>> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Getting pending recovery requests");

    state.recovery_service().get_pending_requests().await
}
