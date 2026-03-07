//! Tenant management service

use crate::error::{AppError, AppResult};
use crate::models::{
    InvitationListResponse, InviteMemberRequest, Tenant, TenantConfig, TenantInvitation,
    TenantListResponse, TenantMember, TenantMembersResponse, TenantRole, TenantSwitchRequest,
    TenantSwitchResponse, UpdateMemberRoleRequest,
};
use crate::services::ApiClient;
use crate::storage::KeyringStore;
use parking_lot::RwLock;
use std::sync::Arc;

/// Service for tenant management operations
pub struct TenantService {
    api_client: Arc<ApiClient>,
    keyring: Arc<KeyringStore>,
    /// Current tenant context
    current_tenant_id: RwLock<Option<String>>,
    /// Cached available tenants
    available_tenants: RwLock<Vec<Tenant>>,
}

impl TenantService {
    /// Create a new tenant service
    pub fn new(api_client: Arc<ApiClient>, keyring: Arc<KeyringStore>) -> Self {
        Self {
            api_client,
            keyring,
            current_tenant_id: RwLock::new(None),
            available_tenants: RwLock::new(Vec::new()),
        }
    }

    /// Get the current tenant ID
    pub fn current_tenant_id(&self) -> Option<String> {
        self.current_tenant_id.read().clone()
    }

    /// Set the current tenant ID (used during login)
    pub fn set_current_tenant_id(&self, tenant_id: Option<String>) {
        *self.current_tenant_id.write() = tenant_id;
    }

    /// Check if user is in multi-tenant mode
    pub fn is_multi_tenant(&self) -> bool {
        self.available_tenants.read().len() > 1
    }

    /// Get cached available tenants
    pub fn get_available_tenants(&self) -> Vec<Tenant> {
        self.available_tenants.read().clone()
    }

    /// List all tenants the current user belongs to
    pub async fn list_tenants(&self) -> AppResult<TenantListResponse> {
        tracing::debug!("Fetching user tenants");

        let response: TenantListResponse = self.api_client.get("/tenants").await?;

        // Cache the tenants
        *self.available_tenants.write() = response.tenants.clone();
        *self.current_tenant_id.write() = Some(response.current_tenant_id.clone());

        tracing::info!(
            "Found {} tenants, current: {}",
            response.tenants.len(),
            response.current_tenant_id
        );

        Ok(response)
    }

    /// Switch to a different tenant
    pub async fn switch_tenant(&self, tenant_id: &str) -> AppResult<TenantSwitchResponse> {
        tracing::info!("Switching to tenant: {}", tenant_id);

        let request = TenantSwitchRequest {
            tenant_id: tenant_id.to_string(),
        };

        let response: TenantSwitchResponse =
            self.api_client.post("/tenant/switch", &request).await?;

        // Update auth tokens
        self.api_client
            .set_auth_token(Some(response.access_token.clone()));
        self.keyring.store_auth_token(&response.access_token)?;
        self.keyring.store_refresh_token(&response.refresh_token)?;

        // Update current tenant
        *self.current_tenant_id.write() = Some(tenant_id.to_string());

        tracing::info!("Switched to tenant: {} ({})", response.tenant.name, tenant_id);

        Ok(response)
    }

    /// Get configuration for the current tenant
    pub async fn get_tenant_config(&self) -> AppResult<TenantConfig> {
        tracing::debug!("Fetching tenant config");

        let config: TenantConfig = self.api_client.get("/tenant/config").await?;

        tracing::debug!("Tenant config loaded: {} (PQC: {})", config.name, config.pqc_algorithm);

        Ok(config)
    }

    /// Leave a tenant (cannot leave if owner)
    pub async fn leave_tenant(&self, tenant_id: &str) -> AppResult<()> {
        tracing::info!("Leaving tenant: {}", tenant_id);

        // Prevent leaving current tenant without switching first
        if self.current_tenant_id() == Some(tenant_id.to_string()) {
            return Err(AppError::Validation(
                "Cannot leave current tenant. Switch to another tenant first.".to_string(),
            ));
        }

        self.api_client
            .delete_no_content(&format!("/tenants/{}/leave", tenant_id))
            .await?;

        // Remove from cached list
        self.available_tenants
            .write()
            .retain(|t| t.id != tenant_id);

        tracing::info!("Left tenant: {}", tenant_id);

        Ok(())
    }

    /// Get members of a tenant (requires admin/owner role)
    pub async fn get_tenant_members(&self, tenant_id: &str) -> AppResult<Vec<TenantMember>> {
        tracing::debug!("Fetching members for tenant: {}", tenant_id);

        let response: TenantMembersResponse = self
            .api_client
            .get(&format!("/tenants/{}/members", tenant_id))
            .await?;

        tracing::debug!("Found {} members", response.members.len());

        Ok(response.members)
    }

    /// Invite a user to a tenant (requires admin/owner role)
    pub async fn invite_member(
        &self,
        tenant_id: &str,
        email: &str,
        role: TenantRole,
    ) -> AppResult<TenantMember> {
        tracing::info!("Inviting {} to tenant {} as {:?}", email, tenant_id, role);

        let request = InviteMemberRequest {
            email: email.to_string(),
            role,
        };

        let member: TenantMember = self
            .api_client
            .post(&format!("/tenants/{}/members", tenant_id), &request)
            .await?;

        tracing::info!("Invited {} to tenant", email);

        Ok(member)
    }

    /// Update a member's role (requires owner role)
    pub async fn update_member_role(
        &self,
        tenant_id: &str,
        user_id: &str,
        new_role: TenantRole,
    ) -> AppResult<TenantMember> {
        tracing::info!(
            "Updating role for user {} in tenant {} to {:?}",
            user_id,
            tenant_id,
            new_role
        );

        let request = UpdateMemberRoleRequest { role: new_role };

        let member: TenantMember = self
            .api_client
            .put(
                &format!("/tenants/{}/members/{}/role", tenant_id, user_id),
                &request,
            )
            .await?;

        tracing::info!("Updated role for user {}", user_id);

        Ok(member)
    }

    /// Remove a member from a tenant (requires admin/owner role, cannot remove owners)
    pub async fn remove_member(&self, tenant_id: &str, user_id: &str) -> AppResult<()> {
        tracing::info!("Removing user {} from tenant {}", user_id, tenant_id);

        self.api_client
            .delete_no_content(&format!("/tenants/{}/members/{}", tenant_id, user_id))
            .await?;

        tracing::info!("Removed user {} from tenant", user_id);

        Ok(())
    }

    /// Get pending invitations for the current user
    pub async fn get_pending_invitations(&self) -> AppResult<Vec<TenantInvitation>> {
        tracing::debug!("Fetching pending invitations");

        let response: InvitationListResponse = self.api_client.get("/invitations").await?;

        tracing::debug!("Found {} pending invitations", response.invitations.len());

        Ok(response.invitations)
    }

    /// Accept a tenant invitation
    pub async fn accept_invitation(&self, invitation_id: &str) -> AppResult<Tenant> {
        tracing::info!("Accepting invitation: {}", invitation_id);

        let tenant: Tenant = self
            .api_client
            .post(&format!("/invitations/{}/accept", invitation_id), &())
            .await?;

        // Add to cached tenants
        self.available_tenants.write().push(tenant.clone());

        tracing::info!("Accepted invitation, joined tenant: {}", tenant.name);

        Ok(tenant)
    }

    /// Decline a tenant invitation
    pub async fn decline_invitation(&self, invitation_id: &str) -> AppResult<()> {
        tracing::info!("Declining invitation: {}", invitation_id);

        self.api_client
            .post::<(), ()>(&format!("/invitations/{}/decline", invitation_id), &())
            .await?;

        tracing::info!("Declined invitation: {}", invitation_id);

        Ok(())
    }

    /// Clear cached tenant data (used on logout)
    pub fn clear(&self) {
        *self.current_tenant_id.write() = None;
        *self.available_tenants.write() = Vec::new();
    }
}
