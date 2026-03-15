package my.ssdid.drive.domain.repository

import my.ssdid.drive.crypto.PqcAlgorithm
import my.ssdid.drive.domain.model.CreatedInvitation
import my.ssdid.drive.domain.model.Invitation
import my.ssdid.drive.domain.model.InvitationAccepted
import my.ssdid.drive.domain.model.InviteCodeInfo
import my.ssdid.drive.domain.model.SentInvitation
import my.ssdid.drive.domain.model.Tenant
import my.ssdid.drive.domain.model.TenantConfig
import my.ssdid.drive.domain.model.TenantContext
import my.ssdid.drive.domain.model.TenantRequestResult
import my.ssdid.drive.domain.model.TenantMember
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for tenant configuration and multi-tenant operations.
 */
interface TenantRepository {

    // ==================== Multi-Tenant Operations ====================

    /**
     * Observe the current tenant context as a Flow.
     * Emits updates whenever the tenant context changes.
     */
    fun observeTenantContext(): Flow<TenantContext?>

    /**
     * Get the current tenant context.
     */
    suspend fun getCurrentTenantContext(): TenantContext?

    /**
     * Get list of all tenants the user belongs to.
     */
    suspend fun getUserTenants(): Result<List<Tenant>>

    /**
     * Switch to a different tenant.
     * This will update tokens and tenant context.
     *
     * @param tenantId The ID of the tenant to switch to
     * @return Result containing the new TenantContext or an error
     */
    suspend fun switchTenant(tenantId: String): Result<TenantContext>

    /**
     * Leave a tenant (remove self from tenant).
     * Cannot leave if user is the only owner.
     *
     * @param tenantId The ID of the tenant to leave
     * @return Result indicating success or failure
     */
    suspend fun leaveTenant(tenantId: String): Result<Unit>

    /**
     * Refresh the tenant list from the server.
     */
    suspend fun refreshTenants(): Result<List<Tenant>>

    /**
     * Save the tenant context locally.
     */
    suspend fun saveTenantContext(context: TenantContext)

    /**
     * Clear all tenant data (on logout).
     */
    suspend fun clearTenantData()

    // ==================== Tenant Configuration ====================

    /**
     * Fetch the current tenant's configuration from the server.
     * This includes the PQC algorithm setting.
     */
    suspend fun getTenantConfig(): Result<TenantConfig>

    /**
     * Get the cached PQC algorithm setting.
     * Returns the default (KAZ) if not fetched yet.
     */
    fun getPqcAlgorithm(): PqcAlgorithm

    /**
     * Refresh the tenant configuration from the server
     * and update the local crypto config.
     */
    suspend fun refreshConfig(): Result<TenantConfig>

    /**
     * Get all users in the tenant.
     * Used for sharing and recovery trustee selection.
     */
    suspend fun getTenantUsers(): Result<List<User>>

    // ==================== Tenant Requests ====================

    /**
     * Submit a request to create a new tenant/organization.
     *
     * @param organizationName The desired organization name
     * @param reason Optional reason for the request
     * @return Result containing the tenant request details or an error
     */
    suspend fun submitTenantRequest(organizationName: String, reason: String? = null): Result<TenantRequestResult>

    // ==================== Member Management ====================

    /**
     * Get list of members in the specified tenant.
     * Requires admin or owner role.
     *
     * @param tenantId The ID of the tenant
     * @return Result containing list of members or an error
     */
    suspend fun getTenantMembers(tenantId: String): Result<List<TenantMember>>

    /**
     * Invite a user to a tenant by email.
     * Requires admin or owner role.
     *
     * @param tenantId The ID of the tenant
     * @param email The email of the user to invite
     * @param role The role to assign (defaults to member)
     * @return Result indicating success or failure
     */
    suspend fun inviteMember(tenantId: String, email: String, role: UserRole = UserRole.USER): Result<Unit>

    /**
     * Update a member's role in a tenant.
     * Requires owner role.
     *
     * @param tenantId The ID of the tenant
     * @param userId The ID of the user whose role to update
     * @param role The new role to assign
     * @return Result containing updated member or an error
     */
    suspend fun updateMemberRole(tenantId: String, userId: String, role: UserRole): Result<TenantMember>

    /**
     * Remove a member from a tenant.
     * Requires admin or owner role. Cannot remove owners.
     *
     * @param tenantId The ID of the tenant
     * @param userId The ID of the user to remove
     * @return Result indicating success or failure
     */
    suspend fun removeMember(tenantId: String, userId: String): Result<Unit>

    // ==================== Invitations ====================

    /**
     * Get pending invitations for the current user.
     *
     * @return Result containing list of pending invitations
     */
    suspend fun getPendingInvitations(): Result<List<Invitation>>

    /**
     * Accept a tenant invitation.
     *
     * @param invitationId The ID of the invitation to accept
     * @return Result containing the accepted invitation details
     */
    suspend fun acceptInvitation(invitationId: String): Result<InvitationAccepted>

    /**
     * Decline a tenant invitation.
     *
     * @param invitationId The ID of the invitation to decline
     * @return Result indicating success or failure
     */
    suspend fun declineInvitation(invitationId: String): Result<Unit>

    // ==================== Create & Sent Invitations ====================

    /**
     * Create a new invitation.
     * Requires admin or owner role.
     *
     * @param email Optional email of the person to invite
     * @param role The role to assign (defaults to member)
     * @param message Optional message to include with the invitation
     * @return Result containing the created invitation with short code
     */
    suspend fun createInvitation(
        email: String? = null,
        role: UserRole = UserRole.USER,
        message: String? = null
    ): Result<CreatedInvitation>

    /**
     * Get invitations sent by the current user.
     *
     * @param page Page number for pagination
     * @param perPage Items per page
     * @return Result containing list of sent invitations
     */
    suspend fun getSentInvitations(page: Int = 1, perPage: Int = 20): Result<List<SentInvitation>>

    /**
     * Revoke a pending invitation.
     *
     * @param invitationId The ID of the invitation to revoke
     * @return Result indicating success or failure
     */
    suspend fun revokeInvitation(invitationId: String): Result<Unit>

    // ==================== Invite Code ====================

    /**
     * Look up an invitation by short code (e.g. "ACME-7K9X").
     * Public endpoint -- no auth required.
     *
     * @param code The short invite code
     * @return Result containing the invite code info for preview
     */
    suspend fun lookupInviteCode(code: String): Result<InviteCodeInfo>

    /**
     * Accept an invitation by its ID (after looking up by short code).
     * Requires auth -- used for existing logged-in users.
     *
     * @param invitationId The ID from the invite code lookup
     * @return Result containing the accepted invitation details
     */
    suspend fun acceptInvitationById(invitationId: String): Result<InvitationAccepted>
}
