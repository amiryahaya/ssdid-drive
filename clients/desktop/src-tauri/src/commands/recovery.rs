//! Recovery commands
//!
//! Handles key recovery using Shamir secret sharing with server-held share.

use crate::error::{AppError, AppResult};
use crate::services::{RecoveryFile, RecoveryService, RecoveryStatus};
use crate::state::AppState;
use tauri::State;

/// Setup recovery by uploading the server's share and key proof.
///
/// Splits the master key into 3 Shamir shares (threshold 2), stores shares
/// 1 and 2 as recovery files for the user, and uploads share 3 to the server
/// along with a key proof.
#[tauri::command]
pub async fn setup_recovery(
    server_share: String,
    key_proof: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Setting up recovery: uploading server share");

    state
        .recovery_service()
        .setup(&server_share, &key_proof)
        .await
}

/// Get the current recovery setup status.
#[tauri::command]
pub async fn get_recovery_status(state: State<'_, AppState>) -> AppResult<RecoveryStatus> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Getting recovery status");

    state.recovery_service().get_status().await
}

/// Split the master key into Shamir shares.
///
/// Returns three `(index, share_data_base64)` tuples. The caller is responsible
/// for wrapping each share into a `RecoveryFile` and persisting/distributing them.
#[tauri::command]
pub async fn split_master_key_command(
    master_key_hex: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<(u8, String)>> {
    state.require_auth()?;
    state.require_unlocked()?;

    let raw = hex::decode(&master_key_hex)
        .map_err(|e| AppError::Crypto(format!("Invalid master key hex: {}", e)))?;
    if raw.len() != 32 {
        return Err(AppError::Crypto(format!(
            "Master key must be 32 bytes, got {}",
            raw.len()
        )));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&raw);

    let ((i1, d1), (i2, d2), (i3, d3)) = RecoveryService::split_master_key(&key)?;

    use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
    Ok(vec![
        (i1, BASE64.encode(&d1)),
        (i2, BASE64.encode(&d2)),
        (i3, BASE64.encode(&d3)),
    ])
}

/// Reconstruct the master key from two Shamir shares.
///
/// Returns the reconstructed key as a hex string.
#[tauri::command]
pub async fn reconstruct_master_key_command(
    index1: u8,
    data1_b64: String,
    index2: u8,
    data2_b64: String,
    state: State<'_, AppState>,
) -> AppResult<String> {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

    let _ = &state; // state not required for crypto-only operation

    let d1 = BASE64
        .decode(&data1_b64)
        .map_err(|e| AppError::Crypto(format!("Invalid share 1 base64: {}", e)))?;
    let d2 = BASE64
        .decode(&data2_b64)
        .map_err(|e| AppError::Crypto(format!("Invalid share 2 base64: {}", e)))?;

    let key = RecoveryService::reconstruct_master_key(index1, &d1, index2, &d2)?;
    Ok(hex::encode(key))
}

/// Create a recovery file struct for a given share.
#[tauri::command]
pub async fn create_recovery_file_command(
    share_index: u8,
    share_data_b64: String,
    user_did: String,
    state: State<'_, AppState>,
) -> AppResult<RecoveryFile> {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

    let _ = &state; // state not required

    let raw = BASE64
        .decode(&share_data_b64)
        .map_err(|e| AppError::Crypto(format!("Invalid share base64: {}", e)))?;

    Ok(RecoveryService::create_recovery_file(share_index, &raw, &user_did))
}

/// Parse and validate a recovery file from its JSON string contents.
#[tauri::command]
pub async fn parse_recovery_file_command(
    contents: String,
    state: State<'_, AppState>,
) -> AppResult<RecoveryFile> {
    let _ = &state; // state not required

    RecoveryService::parse_recovery_file(&contents)
}

/// Retrieve the server-held share for recovery (unauthenticated — DID-based).
#[tauri::command]
pub async fn get_server_share(
    did: String,
    state: State<'_, AppState>,
) -> AppResult<crate::services::ServerShareResponse> {
    tracing::info!("Getting server share for DID recovery");

    state.recovery_service().get_server_share(&did).await
}

/// Complete the recovery process with a new DID and key material.
#[tauri::command]
pub async fn complete_recovery(
    old_did: String,
    new_did: String,
    key_proof: String,
    kem_public_key: String,
    state: State<'_, AppState>,
) -> AppResult<crate::services::CompleteRecoveryResponse> {
    tracing::info!("Completing recovery: old_did={}", old_did);

    state
        .recovery_service()
        .complete_recovery(&old_did, &new_did, &key_proof, &kem_public_key)
        .await
}

/// Delete the recovery setup from the server.
#[tauri::command]
pub async fn delete_recovery_setup(state: State<'_, AppState>) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Deleting recovery setup");

    state.recovery_service().delete_setup().await
}

/// Compute a key proof (SHA-256 hex of a KEM public key).
#[tauri::command]
pub async fn compute_key_proof_command(
    kem_public_key_b64: String,
    state: State<'_, AppState>,
) -> AppResult<String> {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

    let _ = &state; // state not required

    let raw = BASE64
        .decode(&kem_public_key_b64)
        .map_err(|e| AppError::Crypto(format!("Invalid KEM public key base64: {}", e)))?;

    Ok(RecoveryService::compute_key_proof(&raw))
}
