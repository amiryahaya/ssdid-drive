//! Authentication provider models for WebAuthn and OIDC

use serde::{Deserialize, Serialize};

/// An authentication provider (OIDC or WebAuthn)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthProvider {
    pub id: String,
    pub name: String,
    pub provider_type: String,
    pub tenant_id: String,
    pub client_id: Option<String>,
    pub issuer: Option<String>,
    pub enabled: bool,
}

/// Response from GET /auth/providers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthProvidersResponse {
    pub providers: Vec<AuthProvider>,
}

/// Request to begin OIDC authorization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OidcAuthorizeRequest {
    pub provider_id: String,
    pub redirect_uri: String,
}

/// Response from POST /auth/oidc/authorize
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OidcAuthorizeResponse {
    pub authorization_url: String,
    pub state: String,
}

/// Request for OIDC callback
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OidcCallbackRequest {
    pub code: String,
    pub state: String,
}

/// Response from POST /auth/oidc/callback (existing user)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OidcCallbackResponse {
    pub status: String,
    /// Present when status == "authenticated"
    pub user: Option<super::User>,
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub device_id: Option<String>,
    pub key_bundle: Option<VaultKeyBundle>,
    /// Present when status == "new_user"
    pub key_material: Option<String>,
    pub key_salt: Option<String>,
}

/// Vault-based key bundle (for OIDC and non-PRF WebAuthn)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultKeyBundle {
    pub source: String,
    pub vault_encrypted_master_key: String,
    pub vault_mk_nonce: String,
    pub vault_salt: String,
    /// Server-provided key material for vault derivation
    pub key_material: Option<String>,
    pub key_salt: Option<String>,
    /// Encrypted private keys
    pub encrypted_private_keys: EncryptedPrivateKeys,
    /// Public keys
    pub public_keys: PublicKeys,
}

/// WebAuthn key bundle with PRF support
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnKeyBundle {
    pub source: String,
    /// Present when PRF was used (source == "credential")
    pub encrypted_master_key: Option<String>,
    pub mk_nonce: Option<String>,
    /// Present when vault-based (source == "vault")
    pub vault_encrypted_master_key: Option<String>,
    pub vault_mk_nonce: Option<String>,
    pub vault_salt: Option<String>,
    pub key_material: Option<String>,
    pub key_salt: Option<String>,
    /// Encrypted private keys
    pub encrypted_private_keys: EncryptedPrivateKeys,
    /// Public keys
    pub public_keys: PublicKeys,
}

/// Encrypted private keys in a key bundle
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EncryptedPrivateKeys {
    pub encrypted_ml_kem_sk: String,
    pub encrypted_ml_dsa_sk: String,
    pub encrypted_kaz_kem_sk: String,
    pub encrypted_kaz_sign_sk: String,
}

/// Public keys in a key bundle
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicKeys {
    pub ml_kem_pk: String,
    pub ml_dsa_pk: String,
    pub kaz_kem_pk: String,
    pub kaz_sign_pk: String,
}

/// OIDC registration request (new user via OIDC)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OidcRegisterRequest {
    pub provider_id: String,
    pub oidc_sub: String,
    pub email: String,
    pub name: String,
    /// Vault-encrypted master key fields
    pub vault_encrypted_master_key: String,
    pub vault_mk_nonce: String,
    pub vault_salt: String,
    /// Key bundle
    pub encrypted_ml_kem_sk: String,
    pub encrypted_ml_dsa_sk: String,
    pub encrypted_kaz_kem_sk: String,
    pub encrypted_kaz_sign_sk: String,
    pub ml_kem_pk: String,
    pub ml_dsa_pk: String,
    pub kaz_kem_pk: String,
    pub kaz_sign_pk: String,
}

/// Registration response from OIDC register
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OidcRegisterResponse {
    pub user: super::User,
    pub access_token: String,
    pub refresh_token: String,
    pub device_id: String,
}

/// WebAuthn credential creation options from server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnCreationOptions {
    #[serde(flatten)]
    pub options: serde_json::Value,
}

/// WebAuthn credential request options from server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnRequestOptions {
    #[serde(flatten)]
    pub options: serde_json::Value,
}

/// WebAuthn registration begin response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnRegisterBeginResponse {
    pub options: serde_json::Value,
    pub challenge_id: String,
}

/// WebAuthn login begin response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnLoginBeginResponse {
    pub options: serde_json::Value,
    pub challenge_id: String,
}

/// WebAuthn registration complete request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnRegisterCompleteRequest {
    pub challenge_id: String,
    pub attestation: serde_json::Value,
    pub credential_name: Option<String>,
    /// If PRF is supported, include encrypted MK
    pub encrypted_master_key: Option<String>,
    pub mk_nonce: Option<String>,
    /// Vault fields for non-PRF
    pub vault_encrypted_master_key: Option<String>,
    pub vault_mk_nonce: Option<String>,
    pub vault_salt: Option<String>,
    /// Key bundle
    pub encrypted_ml_kem_sk: Option<String>,
    pub encrypted_ml_dsa_sk: Option<String>,
    pub encrypted_kaz_kem_sk: Option<String>,
    pub encrypted_kaz_sign_sk: Option<String>,
    pub ml_kem_pk: Option<String>,
    pub ml_dsa_pk: Option<String>,
    pub kaz_kem_pk: Option<String>,
    pub kaz_sign_pk: Option<String>,
}

/// WebAuthn login complete request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnLoginCompleteRequest {
    pub challenge_id: String,
    pub assertion: serde_json::Value,
    pub prf_output: Option<String>,
}

/// WebAuthn login complete response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebAuthnLoginResponse {
    pub user: super::User,
    pub access_token: String,
    pub refresh_token: String,
    pub device_id: String,
    pub key_bundle: WebAuthnKeyBundle,
}

/// A user credential (passkey, OIDC, etc.)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserCredential {
    pub id: String,
    pub credential_type: String,
    pub name: Option<String>,
    pub provider_name: Option<String>,
    pub created_at: String,
    pub last_used_at: Option<String>,
}

/// Response for credential list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CredentialListResponse {
    pub credentials: Vec<UserCredential>,
}

/// Request to rename a credential
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenameCredentialRequest {
    pub name: String,
}
