package com.securesharing.domain.model

/**
 * Domain model representing a tenant (organization) that a user belongs to.
 */
data class Tenant(
    val id: String,
    val name: String,
    val slug: String,
    val role: UserRole,
    val joinedAt: String? = null
)

/**
 * Represents the current tenant context for the authenticated user.
 */
data class TenantContext(
    val currentTenantId: String,
    val currentRole: UserRole,
    val availableTenants: List<Tenant>
) {
    /**
     * Get the current tenant from the list of available tenants.
     */
    fun getCurrentTenant(): Tenant? = availableTenants.find { it.id == currentTenantId }

    /**
     * Check if the user has access to a specific tenant.
     */
    fun hasAccessTo(tenantId: String): Boolean = availableTenants.any { it.id == tenantId }

    /**
     * Check if the user is an admin or owner in the current tenant.
     */
    fun isAdminOrOwner(): Boolean = currentRole == UserRole.ADMIN || currentRole == UserRole.OWNER

    /**
     * Check if the user can manage users in the current tenant (admin/owner only).
     */
    fun canManageUsers(): Boolean = isAdminOrOwner()
}
