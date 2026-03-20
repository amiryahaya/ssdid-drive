//! Recovery commands
//!
//! Handles key recovery using Shamir secret sharing with server-held share,
//! and trustee-based recovery via the backend trustee endpoints.

use crate::error::{AppError, AppResult};
use crate::services::{
    RecoveryFile, RecoveryService, RecoveryStatus, RecoveryShareEntry, SetupTrusteesRequest,
    TrusteeRecoverySetup, PendingRecoveryRequest,
};
use crate::state::AppState;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use tauri::State;
use zeroize::Zeroize;

/// Upload the server's Shamir share and key proof (low-level key-split recovery setup).
///
/// Called after the user has split their master key via `split_master_key_command` and
/// chosen which share to store server-side.
#[tauri::command]
pub async fn upload_recovery_server_share(
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

// ============================================================
// Trustee-based recovery commands
// These correspond to the recoveryStore.ts actions that call
// the /api/recovery/trustees/* and /api/recovery/requests/* endpoints.
// ============================================================

/// Fetch the current trustee recovery setup.
///
/// Returns the setup (threshold + trustees) or null if none exists.
/// Corresponds to `get_recovery_setup` invoke in recoveryStore.ts.
#[tauri::command]
pub async fn get_recovery_setup(
    state: State<'_, AppState>,
) -> AppResult<Option<TrusteeRecoverySetup>> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Fetching trustee recovery setup");

    state.recovery_service().get_trustee_setup().await
}

/// Configure trustees for recovery.
///
/// For each email:
///   1. Search for the user by email to get their user ID and KEM public keys.
///   2. Split the master key into N Shamir shares (one per trustee).
///   3. Encrypt each share with the corresponding trustee's KEM public keys.
///   4. POST to /api/recovery/trustees/setup.
///
/// Corresponds to `setup_recovery` invoke (with `trusteeEmails`) in recoveryStore.ts.
#[tauri::command]
pub async fn setup_recovery(
    threshold: i32,
    trustee_emails: Vec<String>,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!(
        "Setting up trustee recovery: threshold={}, trustees={}",
        threshold,
        trustee_emails.len()
    );

    setup_trustees_internal(threshold, &trustee_emails, &state).await
}

/// Update an existing trustee recovery configuration.
///
/// Re-runs the full setup (replaces existing trustees).
/// Corresponds to `update_recovery` invoke in recoveryStore.ts.
#[tauri::command]
pub async fn update_recovery(
    threshold: i32,
    trustee_emails: Vec<String>,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!(
        "Updating trustee recovery: threshold={}, trustees={}",
        threshold,
        trustee_emails.len()
    );

    setup_trustees_internal(threshold, &trustee_emails, &state).await
}

/// Remove the server-side recovery setup (delete_recovery_setup for trustee setup).
///
/// Corresponds to `remove_recovery` invoke in recoveryStore.ts.
#[tauri::command]
pub async fn remove_recovery(state: State<'_, AppState>) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Removing recovery setup");

    state.recovery_service().delete_setup().await
}

/// Fetch pending recovery requests for which the current user is a trustee.
///
/// Corresponds to `get_pending_recovery_requests` invoke in recoveryStore.ts.
#[tauri::command]
pub async fn get_pending_recovery_requests(
    state: State<'_, AppState>,
) -> AppResult<Vec<PendingRecoveryRequest>> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::debug!("Fetching pending recovery requests (trustee view)");

    state.recovery_service().get_pending_requests().await
}

/// Approve a recovery request as a trustee.
///
/// Corresponds to `approve_recovery_request` invoke in recoveryStore.ts.
#[tauri::command]
pub async fn approve_recovery_request(
    request_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Approving recovery request: {}", request_id);

    state
        .recovery_service()
        .approve_request(&request_id)
        .await
}

/// Deny a recovery request as a trustee.
///
/// Corresponds to `deny_recovery_request` invoke in recoveryStore.ts.
#[tauri::command]
pub async fn deny_recovery_request(
    request_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!("Denying recovery request: {}", request_id);

    state
        .recovery_service()
        .reject_request(&request_id)
        .await
}

// ============================================================
// Internal helpers
// ============================================================

/// Shared logic for setup_recovery and update_recovery.
///
/// Steps:
///   1. Fetch master key from CryptoService.
///   2. Split it into N Shamir shares (one per trustee).
///   3. For each trustee email: search for user → get KEM public keys.
///   4. Encrypt share[i] with trustee[i]'s KEM public keys using encapsulate_folder_key.
///   5. POST to /api/recovery/trustees/setup.
async fn setup_trustees_internal(
    threshold: i32,
    trustee_emails: &[String],
    state: &AppState,
) -> AppResult<()> {
    if trustee_emails.is_empty() {
        return Err(AppError::Validation(
            "At least one trustee email is required".to_string(),
        ));
    }
    if threshold < 2 {
        return Err(AppError::Validation(
            "Threshold must be at least 2".to_string(),
        ));
    }
    if threshold as usize > trustee_emails.len() {
        return Err(AppError::Validation(
            "Threshold cannot exceed the number of trustees".to_string(),
        ));
    }

    // Step 1: get master key
    let master_key = {
        let mk = state.crypto_service().get_master_key()?;
        let mut raw = [0u8; 32];
        raw.copy_from_slice(&mk);
        raw
    };

    // Step 2: split into shares (one per trustee)
    let n = trustee_emails.len();
    let shares = split_n_shares(&master_key, n, threshold as u8)?;

    // Step 3 + 4: for each trustee, search + encrypt share
    let mut share_entries: Vec<RecoveryShareEntry> = Vec::with_capacity(n);

    for (i, email) in trustee_emails.iter().enumerate() {
        // Search for this user by email
        let search_results = state
            .sharing_service()
            .search_recipients(email)
            .await
            .map_err(|e| {
                AppError::Validation(format!(
                    "Failed to find trustee '{}': {}",
                    email, e
                ))
            })?;

        let trustee = search_results
            .iter()
            .find(|u| u.email.eq_ignore_ascii_case(email))
            .ok_or_else(|| {
                AppError::Validation(format!(
                    "User with email '{}' not found",
                    email
                ))
            })?;

        let (share_index, ref share_bytes) = shares[i];

        // Encrypt share using the trustee's KEM public keys.
        // encapsulate_folder_key returns (kem_ciphertext_b64, wrapped_data_b64, algorithm).
        let (kem_ct, wrapped_share, _algorithm) = state
            .crypto_service()
            .encapsulate_folder_key(
                share_bytes,
                &trustee.public_keys.ml_kem_pk,
                &trustee.public_keys.kaz_kem_pk,
            )
            .map_err(|e| {
                AppError::Crypto(format!(
                    "Failed to encrypt share for '{}': {}",
                    email, e
                ))
            })?;

        // Store encrypted share as "kem_ct:wrapped_share" so the trustee can
        // later decapsulate with their private KEM keys.
        let encrypted_share_blob = format!("{}:{}", kem_ct, wrapped_share);

        share_entries.push(RecoveryShareEntry {
            trustee_user_id: trustee.id.clone(),
            encrypted_share: BASE64.encode(encrypted_share_blob.as_bytes()),
            share_index: share_index as i32,
        });
    }

    // Step 5: POST to backend
    let req = SetupTrusteesRequest {
        threshold,
        shares: share_entries,
    };

    state.recovery_service().setup_trustees(&req).await
}

/// Split a 32-byte master key into `n` Shamir shares (threshold = n so all are needed, but
/// the trustee setup independently controls the threshold at the API level).
///
/// For n > 3, we create a (threshold, n) scheme by taking the first `n` shares from
/// a (2-of-n) dealer — this means any `threshold` shares suffice.
/// Uses the same `sharks` crate as the existing split_master_key.
fn split_n_shares(master_key: &[u8; 32], n: usize, threshold: u8) -> AppResult<Vec<(u8, Vec<u8>)>> {
    use sharks::{Share, Sharks};

    if n < 2 {
        return Err(AppError::Crypto(
            "At least 2 trustees required for Shamir splitting".to_string(),
        ));
    }

    let sharks = Sharks(threshold);
    let dealer = sharks.dealer(master_key);
    let shares: Vec<Share> = dealer.take(n).collect();

    if shares.len() != n {
        return Err(AppError::Crypto(format!(
            "Failed to generate {} Shamir shares",
            n
        )));
    }

    let mut result = Vec::with_capacity(n);
    for s in &shares {
        let mut bytes = Vec::from(s);
        let index = bytes[0];
        let data = bytes[1..].to_vec();
        bytes.zeroize();
        result.push((index, data));
    }

    Ok(result)
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
    mut master_key_hex: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<(u8, String)>> {
    state.require_auth()?;
    state.require_unlocked()?;

    let mut raw = hex::decode(&master_key_hex)
        .map_err(|e| AppError::Crypto(format!("Invalid master key hex: {}", e)))?;
    master_key_hex.zeroize();
    if raw.len() != 32 {
        raw.zeroize();
        return Err(AppError::Crypto(format!(
            "Master key must be 32 bytes, got {}",
            raw.len()
        )));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&raw);
    raw.zeroize();

    let ((i1, mut d1), (i2, mut d2), (i3, mut d3)) = RecoveryService::split_master_key(&key)?;
    key.zeroize();

    use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
    let result = vec![
        (i1, BASE64.encode(&d1)),
        (i2, BASE64.encode(&d2)),
        (i3, BASE64.encode(&d3)),
    ];
    d1.zeroize();
    d2.zeroize();
    d3.zeroize();
    Ok(result)
}

/// Reconstruct the master key from two Shamir shares.
///
/// Returns the reconstructed key as a hex string.
#[tauri::command]
pub async fn reconstruct_master_key_command(
    index1: u8,
    mut data1_b64: String,
    index2: u8,
    mut data2_b64: String,
    state: State<'_, AppState>,
) -> AppResult<String> {
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine};

    let _ = &state; // state not required for crypto-only operation

    let mut d1 = BASE64
        .decode(&data1_b64)
        .map_err(|e| AppError::Crypto(format!("Invalid share 1 base64: {}", e)))?;
    data1_b64.zeroize();
    let mut d2 = BASE64
        .decode(&data2_b64)
        .map_err(|e| {
            d1.zeroize();
            AppError::Crypto(format!("Invalid share 2 base64: {}", e))
        })?;
    data2_b64.zeroize();

    let mut key = RecoveryService::reconstruct_master_key(index1, &d1, index2, &d2)?;
    d1.zeroize();
    d2.zeroize();
    let result = hex::encode(key);
    key.zeroize();
    Ok(result)
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

    let mut raw = BASE64
        .decode(&share_data_b64)
        .map_err(|e| AppError::Crypto(format!("Invalid share base64: {}", e)))?;

    let result = RecoveryService::create_recovery_file(share_index, &raw, &user_did);
    raw.zeroize();
    Ok(result)
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

/// Retrieve the server-held share for recovery.
#[tauri::command]
pub async fn get_server_share(
    did: String,
    state: State<'_, AppState>,
) -> AppResult<crate::services::ServerShareResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

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
    state.require_auth()?;
    state.require_unlocked()?;

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

/// Compute a key proof (SHA3-256 hex of a KEM public key).
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
