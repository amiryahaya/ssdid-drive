//! PII Service commands for conversation-based PII detection and token management

use crate::error::AppResult;
use crate::services::{Conversation, CreateConversationRequest, DecryptedAskResponse, RegisterKemKeysResponse};
use crate::state::AppState;
use serde::Serialize;
use tauri::State;

/// Response for conversation creation
#[derive(Debug, Serialize)]
pub struct CreateConversationResponse {
    pub id: String,
    pub title: Option<String>,
    pub status: String,
    pub llm_provider: String,
    pub llm_model: String,
    pub created_at: String,
}

impl From<Conversation> for CreateConversationResponse {
    fn from(c: Conversation) -> Self {
        Self {
            id: c.id,
            title: c.title,
            status: c.status,
            llm_provider: c.llm_provider,
            llm_model: c.llm_model,
            created_at: c.created_at,
        }
    }
}

/// Create a new PII service conversation
#[tauri::command]
pub async fn pii_create_conversation(
    title: Option<String>,
    llm_provider: String,
    llm_model: String,
    state: State<'_, AppState>,
) -> AppResult<CreateConversationResponse> {
    state.require_auth()?;

    tracing::info!(
        "Creating PII conversation: provider={}, model={}",
        llm_provider,
        llm_model
    );

    // Sync auth token to PII service
    if let Ok(token) = state.keyring().get_auth_token() {
        state.pii_service().set_auth_token(Some(token));
    }

    let request = CreateConversationRequest {
        title,
        llm_provider,
        llm_model,
    };

    let conversation = state.pii_service().create_conversation(request).await?;

    Ok(conversation.into())
}

/// Get a PII service conversation
#[tauri::command]
pub async fn pii_get_conversation(
    conversation_id: String,
    state: State<'_, AppState>,
) -> AppResult<CreateConversationResponse> {
    state.require_auth()?;

    // Sync auth token
    if let Ok(token) = state.keyring().get_auth_token() {
        state.pii_service().set_auth_token(Some(token));
    }

    let conversation = state.pii_service().get_conversation(&conversation_id).await?;

    Ok(conversation.into())
}

/// List PII service conversations
#[tauri::command]
pub async fn pii_list_conversations(
    state: State<'_, AppState>,
) -> AppResult<Vec<CreateConversationResponse>> {
    state.require_auth()?;

    // Sync auth token
    if let Ok(token) = state.keyring().get_auth_token() {
        state.pii_service().set_auth_token(Some(token));
    }

    let conversations = state.pii_service().list_conversations().await?;

    Ok(conversations.into_iter().map(|c| c.into()).collect())
}

/// Register KEM keys for a conversation
///
/// This generates new ML-KEM (and optionally KAZ-KEM) keypairs,
/// registers the public keys with the PII service, and stores
/// the secret keys locally for DEK unwrapping.
#[tauri::command]
pub async fn pii_register_kem_keys(
    conversation_id: String,
    include_kaz_kem: bool,
    state: State<'_, AppState>,
) -> AppResult<RegisterKemKeysResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!(
        "Registering KEM keys for conversation: {} (KAZ-KEM: {})",
        conversation_id,
        include_kaz_kem
    );

    // Sync auth token
    if let Ok(token) = state.keyring().get_auth_token() {
        state.pii_service().set_auth_token(Some(token));
    }

    let response = state
        .pii_service()
        .register_kem_keys(&conversation_id, &state.crypto_service(), include_kaz_kem)
        .await?;

    Ok(response)
}

/// Send a message to the PII service and get a response
///
/// This automatically handles:
/// - Sending the message to the LLM via the PII service
/// - Unwrapping the KEM-encrypted DEK (if KEM keys were registered)
/// - Decrypting the token map
/// - Restoring original PII values in the response
#[tauri::command]
pub async fn pii_ask(
    conversation_id: String,
    message: String,
    context_files: Option<Vec<String>>,
    state: State<'_, AppState>,
) -> AppResult<DecryptedAskResponse> {
    state.require_auth()?;
    state.require_unlocked()?;

    tracing::info!(
        "Sending message to PII conversation: {}",
        conversation_id
    );

    // Sync auth token
    if let Ok(token) = state.keyring().get_auth_token() {
        state.pii_service().set_auth_token(Some(token));
    }

    let response = state
        .pii_service()
        .ask(&conversation_id, &message, context_files)
        .await?;

    Ok(response)
}

/// Clear KEM secret keys from memory
///
/// Call this when switching conversations or logging out
#[tauri::command]
pub async fn pii_clear_kem_keys(state: State<'_, AppState>) -> AppResult<()> {
    state.pii_service().clear_kem_secret_keys();
    tracing::info!("PII KEM keys cleared from memory");
    Ok(())
}
