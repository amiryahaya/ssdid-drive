//! Tenant-related data models

use serde::{Deserialize, Serialize};

/// User's role within a tenant
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TenantRole {
    Owner,
    Admin,
    Member,
}

impl TenantRole {
    /// Check if this role can manage members
    pub fn can_manage_members(&self) -> bool {
        matches!(self, TenantRole::Owner | TenantRole::Admin)
    }

    /// Check if this role can manage the tenant
    pub fn can_manage_tenant(&self) -> bool {
        matches!(self, TenantRole::Owner)
    }
}

/// Tenant information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tenant {
    pub id: String,
    pub name: String,
    pub slug: String,
    pub role: TenantRole,
    pub joined_at: String,
}

/// Tenant configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantConfig {
    pub id: String,
    pub name: String,
    pub slug: String,
    /// Post-quantum cryptography algorithm preference
    pub pqc_algorithm: String,
    pub plan: String,
    pub settings: TenantSettings,
}

/// Tenant-specific settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantSettings {
    #[serde(default)]
    pub max_file_size_bytes: Option<u64>,
    #[serde(default)]
    pub storage_quota_bytes: Option<u64>,
    #[serde(default)]
    pub allow_external_sharing: bool,
}

impl Default for TenantSettings {
    fn default() -> Self {
        Self {
            max_file_size_bytes: None,
            storage_quota_bytes: None,
            allow_external_sharing: true,
        }
    }
}

/// Tenant member information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantMember {
    pub id: String,
    pub user_id: String,
    pub email: String,
    pub name: Option<String>,
    pub role: TenantRole,
    pub status: MemberStatus,
    pub joined_at: String,
}

/// Member status within a tenant
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MemberStatus {
    Active,
    Pending,
    Inactive,
}

/// Tenant context for the current user
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantContext {
    pub current_tenant_id: String,
    pub current_role: TenantRole,
    pub available_tenants: Vec<Tenant>,
}

impl TenantContext {
    /// Check if user has multiple tenants
    pub fn is_multi_tenant(&self) -> bool {
        self.available_tenants.len() > 1
    }

    /// Get current tenant
    pub fn current_tenant(&self) -> Option<&Tenant> {
        self.available_tenants
            .iter()
            .find(|t| t.id == self.current_tenant_id)
    }
}

/// Response from tenant switch API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantSwitchResponse {
    pub tenant: Tenant,
    pub access_token: String,
    pub refresh_token: String,
}

/// Request to switch tenant
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantSwitchRequest {
    pub tenant_id: String,
}

/// Response for tenant list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantListResponse {
    pub tenants: Vec<Tenant>,
    pub current_tenant_id: String,
}

/// Tenant invitation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantInvitation {
    pub id: String,
    pub tenant_id: String,
    pub tenant_name: String,
    pub invited_by: String,
    pub role: TenantRole,
    pub created_at: String,
    pub expires_at: Option<String>,
}

/// Response for invitation list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InvitationListResponse {
    pub invitations: Vec<TenantInvitation>,
}

/// Request to invite a member
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InviteMemberRequest {
    pub email: String,
    pub role: TenantRole,
}

/// Request to update member role
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateMemberRoleRequest {
    pub role: TenantRole,
}

/// Response for tenant members list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantMembersResponse {
    pub members: Vec<TenantMember>,
}
