package com.securesharing.data.remote.dto

import com.google.gson.annotations.SerializedName
import com.securesharing.util.Validation
import com.securesharing.util.ValidationResult

// ==================== Request DTOs ====================

/**
 * Registration request DTO with validation.
 */
data class RegisterRequest(
    @SerializedName("email") val email: String,
    @SerializedName("password") val password: String,
    @SerializedName("tenant_slug") val tenantSlug: String,
    @SerializedName("public_keys") val publicKeys: PublicKeysDto,
    @SerializedName("encrypted_master_key") val encryptedMasterKey: String,
    @SerializedName("encrypted_private_keys") val encryptedPrivateKeys: String,
    @SerializedName("key_derivation_salt") val keyDerivationSalt: String
) {
    /**
     * Validate all fields.
     * @return ValidationResult
     */
    fun validate(): ValidationResult {
        Validation.validateEmail(email).let { if (it.isInvalid) return it }
        Validation.validatePassword(password).let { if (it.isInvalid) return it }
        Validation.validateTenant(tenantSlug).let { if (it.isInvalid) return it }
        Validation.validateEncryptedData(encryptedMasterKey, "Encrypted master key").let { if (it.isInvalid) return it }
        Validation.validateEncryptedData(encryptedPrivateKeys, "Encrypted private keys").let { if (it.isInvalid) return it }
        Validation.validateEncryptedData(keyDerivationSalt, "Key derivation salt").let { if (it.isInvalid) return it }
        publicKeys.validate().let { if (it.isInvalid) return it }
        return ValidationResult.Valid
    }
}

/**
 * Login request DTO with validation.
 *
 * Note: tenant_slug is optional. If not provided, the user will be logged into
 * their first available tenant. The response includes all tenants the user
 * belongs to, allowing tenant switching after login.
 */
data class LoginRequest(
    @SerializedName("email") val email: String,
    @SerializedName("password") val password: String,
    @SerializedName("tenant_slug") val tenantSlug: String? = null
) {
    /**
     * Validate all fields.
     * @return ValidationResult
     */
    fun validate(): ValidationResult {
        Validation.validateEmail(email).let { if (it.isInvalid) return it }
        Validation.validatePassword(password).let { if (it.isInvalid) return it }
        // tenant_slug is optional for multi-tenant login
        tenantSlug?.let {
            Validation.validateTenant(it).let { r -> if (r.isInvalid) return r }
        }
        return ValidationResult.Valid
    }
}

/**
 * Token refresh request DTO with validation.
 */
data class RefreshTokenRequest(
    @SerializedName("refresh_token") val refreshToken: String
) {
    /**
     * Validate the refresh token.
     * @return ValidationResult
     */
    fun validate(): ValidationResult {
        if (refreshToken.isBlank()) {
            return ValidationResult.Invalid("Refresh token is required")
        }
        if (refreshToken.length > 2048) {
            return ValidationResult.Invalid("Refresh token is too long")
        }
        return ValidationResult.Valid
    }
}

// ==================== Response DTOs ====================

/**
 * Authentication response with multi-tenant support.
 * The response includes all tenants the user belongs to.
 */
data class AuthResponse(
    @SerializedName("data") val data: AuthResponseData
)

data class AuthResponseData(
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("refresh_token") val refreshToken: String,
    @SerializedName("expires_in") val expiresIn: Int,
    @SerializedName("token_type") val tokenType: String,
    @SerializedName("user") val user: UserDto
)

data class UserResponse(
    @SerializedName("data") val data: UserDto
)

data class UsersResponse(
    @SerializedName("data") val data: List<UserDto>
)

data class PublicKeyResponse(
    @SerializedName("data") val data: PublicKeysDto
)

// ==================== User DTOs ====================

/**
 * User DTO with multi-tenant support.
 * Includes list of tenants the user belongs to and the currently active tenant.
 */
data class UserDto(
    @SerializedName("id") val id: String,
    @SerializedName("email") val email: String,
    @SerializedName("display_name") val displayName: String? = null,
    @SerializedName("status") val status: String? = null,
    @SerializedName("recovery_setup_complete") val recoverySetupComplete: Boolean? = null,
    @SerializedName("confirmed_at") val confirmedAt: String? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    // Multi-tenant fields
    @SerializedName("tenants") val tenants: List<TenantDto>? = null,
    @SerializedName("current_tenant_id") val currentTenantId: String? = null,
    // Legacy single-tenant fields (for backwards compatibility)
    @SerializedName("tenant_id") val tenantId: String? = null,
    @SerializedName("role") val role: String? = null,
    // Crypto fields
    @SerializedName("public_keys") val publicKeys: PublicKeysDto? = null,
    @SerializedName("encrypted_master_key") val encryptedMasterKey: String? = null,
    @SerializedName("encrypted_private_keys") val encryptedPrivateKeys: String? = null,
    @SerializedName("key_derivation_salt") val keyDerivationSalt: String? = null,
    // Usage fields
    @SerializedName("storage_quota") val storageQuota: Long? = null,
    @SerializedName("storage_used") val storageUsed: Long? = null,
    @SerializedName("inserted_at") val insertedAt: String? = null,
    @SerializedName("updated_at") val updatedAt: String? = null
) {
    /**
     * Get the effective tenant ID (current or legacy).
     */
    fun getEffectiveTenantId(): String? = currentTenantId ?: tenantId

    /**
     * Get the effective role for the current tenant.
     */
    fun getEffectiveRole(): String? {
        return if (currentTenantId != null && tenants != null) {
            tenants.find { it.id == currentTenantId }?.role
        } else {
            role
        }
    }
}

// ==================== Tenant DTOs ====================

/**
 * Tenant information DTO.
 */
data class TenantDto(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
    @SerializedName("slug") val slug: String,
    @SerializedName("role") val role: String,
    @SerializedName("joined_at") val joinedAt: String? = null
)

/**
 * Response for listing user's tenants.
 */
data class TenantsResponse(
    @SerializedName("data") val data: List<TenantDto>
)

/**
 * Request to switch active tenant.
 */
data class TenantSwitchRequest(
    @SerializedName("tenant_id") val tenantId: String
)

/**
 * Response after switching tenant.
 */
data class TenantSwitchResponse(
    @SerializedName("data") val data: TenantSwitchData
)

data class TenantSwitchData(
    @SerializedName("current_tenant_id") val currentTenantId: String,
    @SerializedName("role") val role: String,
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("refresh_token") val refreshToken: String,
    @SerializedName("expires_in") val expiresIn: Int,
    @SerializedName("token_type") val tokenType: String
)

// ==================== Invitation DTOs ====================

/**
 * Request to invite a user to a tenant.
 */
data class InviteMemberRequest(
    @SerializedName("email") val email: String,
    @SerializedName("role") val role: String = "member"
)

/**
 * Request to update a member's role.
 */
data class UpdateMemberRoleRequest(
    @SerializedName("role") val role: String
)

/**
 * Tenant member information.
 */
data class MemberDto(
    @SerializedName("id") val id: String,
    @SerializedName("user_id") val userId: String,
    @SerializedName("email") val email: String?,
    @SerializedName("display_name") val displayName: String?,
    @SerializedName("role") val role: String,
    @SerializedName("status") val status: String,
    @SerializedName("joined_at") val joinedAt: String?
)

/**
 * Response for listing tenant members.
 */
data class MembersResponse(
    @SerializedName("data") val data: List<MemberDto>
)

/**
 * Response for a single member.
 */
data class MemberResponse(
    @SerializedName("data") val data: MemberDto
)

/**
 * Pending invitation for the current user.
 */
data class InvitationDto(
    @SerializedName("id") val id: String,
    @SerializedName("tenant_id") val tenantId: String,
    @SerializedName("tenant_name") val tenantName: String?,
    @SerializedName("tenant_slug") val tenantSlug: String?,
    @SerializedName("role") val role: String,
    @SerializedName("invited_by") val invitedBy: InviterDto?,
    @SerializedName("invited_at") val invitedAt: String?
)

/**
 * Information about who sent the invitation.
 */
data class InviterDto(
    @SerializedName("id") val id: String?,
    @SerializedName("email") val email: String?,
    @SerializedName("display_name") val displayName: String?
)

/**
 * Response for listing pending invitations.
 */
data class InvitationsResponse(
    @SerializedName("data") val data: List<InvitationDto>
)

/**
 * Response for a newly created invitation.
 */
data class InvitationCreatedResponse(
    @SerializedName("data") val data: InvitationCreatedDto
)

data class InvitationCreatedDto(
    @SerializedName("id") val id: String,
    @SerializedName("user_id") val userId: String,
    @SerializedName("email") val email: String,
    @SerializedName("display_name") val displayName: String?,
    @SerializedName("role") val role: String,
    @SerializedName("status") val status: String,
    @SerializedName("invited_at") val invitedAt: String?
)

/**
 * Response after accepting an invitation.
 */
data class InvitationAcceptedResponse(
    @SerializedName("data") val data: InvitationAcceptedDto
)

data class InvitationAcceptedDto(
    @SerializedName("id") val id: String,
    @SerializedName("tenant_id") val tenantId: String,
    @SerializedName("role") val role: String,
    @SerializedName("status") val status: String,
    @SerializedName("joined_at") val joinedAt: String?
)

/**
 * Request to update user profile.
 * Sent to PUT /me
 */
data class UpdateProfileRequest(
    @SerializedName("display_name") val displayName: String?
)

/**
 * Request to update key material after password change.
 * Sent to PUT /me/keys
 */
data class UpdateKeyMaterialRequest(
    @SerializedName("encrypted_master_key") val encryptedMasterKey: String,
    @SerializedName("key_derivation_salt") val keyDerivationSalt: String
)

/**
 * Public keys DTO with validation.
 */
data class PublicKeysDto(
    @SerializedName("kem") val kem: String,
    @SerializedName("sign") val sign: String,
    @SerializedName("ml_kem") val mlKem: String? = null,
    @SerializedName("ml_dsa") val mlDsa: String? = null
) {
    /**
     * Validate public key fields.
     * @return ValidationResult
     */
    fun validate(): ValidationResult {
        Validation.validateEncryptedData(kem, "KEM public key").let { if (it.isInvalid) return it }
        Validation.validateEncryptedData(sign, "Sign public key").let { if (it.isInvalid) return it }
        mlKem?.let {
            Validation.validateEncryptedData(it, "ML-KEM public key").let { r -> if (r.isInvalid) return r }
        }
        mlDsa?.let {
            Validation.validateEncryptedData(it, "ML-DSA public key").let { r -> if (r.isInvalid) return r }
        }
        return ValidationResult.Valid
    }
}

// ==================== Invitation Token DTOs (Public Endpoints) ====================

/**
 * Response for getting public invitation info by token.
 * GET /api/invite/:token
 */
data class InviteInfoResponse(
    @SerializedName("data") val data: InviteInfoDto
)

/**
 * Public invitation information.
 * Shown to users before they accept an invitation.
 */
data class InviteInfoDto(
    @SerializedName("id") val id: String,
    @SerializedName("email") val email: String,
    @SerializedName("role") val role: String,
    @SerializedName("tenant_name") val tenantName: String,
    @SerializedName("inviter_name") val inviterName: String?,
    @SerializedName("message") val message: String?,
    @SerializedName("expires_at") val expiresAt: String,
    @SerializedName("valid") val valid: Boolean,
    @SerializedName("error_reason") val errorReason: String? = null
)

/**
 * Request to accept an invitation and register a new account.
 * POST /api/invite/:token/accept
 */
data class AcceptInviteRequest(
    @SerializedName("display_name") val displayName: String,
    @SerializedName("password") val password: String,
    @SerializedName("public_keys") val publicKeys: PublicKeysDto,
    @SerializedName("encrypted_master_key") val encryptedMasterKey: String,
    @SerializedName("encrypted_private_keys") val encryptedPrivateKeys: String,
    @SerializedName("key_derivation_salt") val keyDerivationSalt: String
) {
    /**
     * Validate all fields.
     * @return ValidationResult
     */
    fun validate(): ValidationResult {
        if (displayName.isBlank()) {
            return ValidationResult.Invalid("Display name is required")
        }
        if (displayName.length > 100) {
            return ValidationResult.Invalid("Display name is too long")
        }
        Validation.validatePassword(password).let { if (it.isInvalid) return it }
        Validation.validateEncryptedData(encryptedMasterKey, "Encrypted master key").let { if (it.isInvalid) return it }
        Validation.validateEncryptedData(encryptedPrivateKeys, "Encrypted private keys").let { if (it.isInvalid) return it }
        Validation.validateEncryptedData(keyDerivationSalt, "Key derivation salt").let { if (it.isInvalid) return it }
        publicKeys.validate().let { if (it.isInvalid) return it }
        return ValidationResult.Valid
    }
}

/**
 * Response after accepting an invitation.
 * Returns auth tokens and user info.
 */
data class AcceptInviteResponse(
    @SerializedName("data") val data: AcceptInviteResponseData
)

data class AcceptInviteResponseData(
    @SerializedName("user") val user: UserDto,
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("refresh_token") val refreshToken: String,
    @SerializedName("expires_in") val expiresIn: Int? = null,
    @SerializedName("token_type") val tokenType: String? = null
)

// ==================== Invite Code DTOs (Short Code Lookup) ====================

/**
 * Response for looking up an invitation by short code.
 * GET /api/invitations/code/{code}
 */
data class InviteCodeInfoResponse(
    @SerializedName("data") val data: InviteCodeInfoDto
)

/**
 * Public invitation information retrieved by short code.
 * Shown to users before they join a tenant.
 */
data class InviteCodeInfoDto(
    @SerializedName("id") val id: String,
    @SerializedName("tenant_name") val tenantName: String,
    @SerializedName("role") val role: String,
    @SerializedName("short_code") val shortCode: String,
    @SerializedName("expires_at") val expiresAt: String
)
