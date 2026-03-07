//! Sharing related data models

use serde::{Deserialize, Serialize};

/// Share grant information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Share {
    pub id: String,
    pub item_id: String,
    pub item_name: String,
    pub item_type: super::ItemType,
    pub owner_id: String,
    pub owner_name: String,
    pub owner_email: String,
    pub recipient_id: String,
    pub recipient_name: String,
    pub recipient_email: String,
    pub permission: SharePermission,
    pub created_at: String,
    pub expires_at: Option<String>,
    pub last_accessed_at: Option<String>,
    /// Encrypted share key (encrypted with recipient's public key)
    pub encrypted_share_key: String,
    /// Signature of the share grant
    pub signature: String,
}

/// Share permission level
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SharePermission {
    /// Can only view/download
    Read,
    /// Can view/download and upload to shared folder
    Write,
    /// Full control including resharing
    Admin,
}

/// Create share request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateShareRequest {
    pub item_id: String,
    pub recipient_email: String,
    pub permission: SharePermission,
    pub expires_at: Option<String>,
    pub message: Option<String>,
}

/// Create share response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateShareResponse {
    pub share: Share,
}

/// Share list response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShareListResponse {
    pub shares: Vec<Share>,
}

/// Recipient search result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecipientSearchResult {
    pub id: String,
    pub email: String,
    pub name: String,
    /// Combined public key (ML-KEM + KAZ-KEM)
    pub public_keys: RecipientPublicKeys,
}

/// Recipient's public keys for encryption
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecipientPublicKeys {
    pub ml_kem_pk: String,
    pub kaz_kem_pk: String,
    pub ml_dsa_pk: String,
    pub kaz_sign_pk: String,
}

/// Recovery setup information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoverySetup {
    pub is_configured: bool,
    pub threshold: u32,
    pub total_trustees: u32,
    pub trustees: Vec<TrusteeInfo>,
}

/// Trustee information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrusteeInfo {
    pub id: String,
    pub email: String,
    pub name: String,
    pub status: TrusteeStatus,
    pub assigned_at: String,
}

/// Trustee status
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrusteeStatus {
    Pending,
    Accepted,
    Declined,
}

/// Setup recovery request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetupRecoveryRequest {
    pub threshold: u32,
    pub trustee_emails: Vec<String>,
}

/// Recovery request from a user
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoveryRequest {
    pub id: String,
    pub requester_id: String,
    pub requester_email: String,
    pub requester_name: String,
    pub status: RecoveryStatus,
    pub approvals_received: u32,
    pub approvals_required: u32,
    pub created_at: String,
    pub expires_at: String,
}

/// Recovery request status
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecoveryStatus {
    Pending,
    InProgress,
    Completed,
    Expired,
    Cancelled,
}

/// Initiate recovery request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InitiateRecoveryRequest {
    pub email: String,
    pub new_password: String,
}

/// Recovery approval request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApproveRecoveryRequest {
    pub recovery_id: String,
    /// Decrypted share from trustee
    pub recovery_share: String,
}
