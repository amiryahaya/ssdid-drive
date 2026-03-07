//! Tenant management commands

use crate::error::AppResult;
use crate::models::{
    Tenant, TenantConfig, TenantInvitation, TenantListResponse, TenantMember, TenantRole,
    TenantSwitchResponse,
};
use crate::state::AppState;
use tauri::State;

/// List all tenants the current user belongs to
#[tauri::command]
pub async fn list_tenants(state: State<'_, AppState>) -> AppResult<TenantListResponse> {
    state.require_auth()?;
    tracing::debug!("Listing user tenants");

    state.tenant_service().list_tenants().await
}

/// Switch to a different tenant
#[tauri::command]
pub async fn switch_tenant(
    tenant_id: String,
    state: State<'_, AppState>,
) -> AppResult<TenantSwitchResponse> {
    state.require_auth()?;
    tracing::info!("Switching to tenant: {}", tenant_id);

    let response = state.tenant_service().switch_tenant(&tenant_id).await?;

    // Update user's tenant_id in state
    if let Some(mut user) = state.current_user() {
        user.tenant_id = tenant_id;
        state.set_current_user(Some(user));
    }

    Ok(response)
}

/// Get configuration for the current tenant
#[tauri::command]
pub async fn get_tenant_config(state: State<'_, AppState>) -> AppResult<TenantConfig> {
    state.require_auth()?;
    tracing::debug!("Getting tenant config");

    state.tenant_service().get_tenant_config().await
}

/// Leave a tenant
#[tauri::command]
pub async fn leave_tenant(tenant_id: String, state: State<'_, AppState>) -> AppResult<()> {
    state.require_auth()?;
    tracing::info!("Leaving tenant: {}", tenant_id);

    state.tenant_service().leave_tenant(&tenant_id).await
}

/// Get members of a tenant (requires admin/owner role)
#[tauri::command]
pub async fn get_tenant_members(
    tenant_id: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<TenantMember>> {
    state.require_auth()?;
    tracing::debug!("Getting members for tenant: {}", tenant_id);

    state.tenant_service().get_tenant_members(&tenant_id).await
}

/// Invite a user to a tenant (requires admin/owner role)
#[tauri::command]
pub async fn invite_tenant_member(
    tenant_id: String,
    email: String,
    role: TenantRole,
    state: State<'_, AppState>,
) -> AppResult<TenantMember> {
    state.require_auth()?;
    tracing::info!("Inviting {} to tenant {} as {:?}", email, tenant_id, role);

    state
        .tenant_service()
        .invite_member(&tenant_id, &email, role)
        .await
}

/// Update a member's role (requires owner role)
#[tauri::command]
pub async fn update_tenant_member_role(
    tenant_id: String,
    user_id: String,
    role: TenantRole,
    state: State<'_, AppState>,
) -> AppResult<TenantMember> {
    state.require_auth()?;
    tracing::info!(
        "Updating role for user {} in tenant {} to {:?}",
        user_id,
        tenant_id,
        role
    );

    state
        .tenant_service()
        .update_member_role(&tenant_id, &user_id, role)
        .await
}

/// Remove a member from a tenant (requires admin/owner role)
#[tauri::command]
pub async fn remove_tenant_member(
    tenant_id: String,
    user_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    tracing::info!("Removing user {} from tenant {}", user_id, tenant_id);

    state
        .tenant_service()
        .remove_member(&tenant_id, &user_id)
        .await
}

/// Get pending tenant invitations for the current user
#[tauri::command]
pub async fn get_tenant_invitations(
    state: State<'_, AppState>,
) -> AppResult<Vec<TenantInvitation>> {
    state.require_auth()?;
    tracing::debug!("Getting pending tenant invitations");

    state.tenant_service().get_pending_invitations().await
}

/// Accept a tenant invitation
#[tauri::command]
pub async fn accept_tenant_invitation(
    invitation_id: String,
    state: State<'_, AppState>,
) -> AppResult<Tenant> {
    state.require_auth()?;
    tracing::info!("Accepting tenant invitation: {}", invitation_id);

    state
        .tenant_service()
        .accept_invitation(&invitation_id)
        .await
}

/// Decline a tenant invitation
#[tauri::command]
pub async fn decline_tenant_invitation(
    invitation_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    state.require_auth()?;
    tracing::info!("Declining tenant invitation: {}", invitation_id);

    state
        .tenant_service()
        .decline_invitation(&invitation_id)
        .await
}
