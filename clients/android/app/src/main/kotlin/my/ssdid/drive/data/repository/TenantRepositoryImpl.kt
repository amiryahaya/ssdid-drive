package my.ssdid.drive.data.repository

import android.util.Base64
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.PqcAlgorithm
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.InviteMemberRequest
import my.ssdid.drive.data.remote.dto.TenantDto
import my.ssdid.drive.data.remote.dto.TenantSwitchRequest
import my.ssdid.drive.data.remote.dto.UpdateMemberRoleRequest
import my.ssdid.drive.domain.model.Invitation
import my.ssdid.drive.domain.model.InvitationAccepted
import my.ssdid.drive.domain.model.Inviter
import my.ssdid.drive.domain.model.MemberStatus
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.Tenant
import my.ssdid.drive.domain.model.TenantConfig
import my.ssdid.drive.domain.model.TenantContext
import my.ssdid.drive.domain.model.TenantMember
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of TenantRepository.
 *
 * Handles multi-tenant operations including tenant switching and tenant context management.
 * Also fetches tenant configuration from the server and updates the local
 * CryptoConfig with the tenant's PQC algorithm preference.
 */
@Singleton
class TenantRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val cryptoConfig: CryptoConfig,
    private val folderKeyManager: FolderKeyManager,
    private val gson: Gson
) : TenantRepository {

    private val _tenantContextFlow = MutableStateFlow<TenantContext?>(null)

    // ==================== Multi-Tenant Operations ====================

    override fun observeTenantContext(): Flow<TenantContext?> = _tenantContextFlow.asStateFlow()

    override suspend fun getCurrentTenantContext(): TenantContext? {
        // Try to get from memory first
        _tenantContextFlow.value?.let { return it }

        // Load from storage
        val tenantId = secureStorage.getTenantId() ?: return null
        val role = secureStorage.getCurrentRole()?.let { UserRole.fromString(it) } ?: UserRole.USER
        val tenantsJson = secureStorage.getUserTenants()

        val tenants = if (tenantsJson != null) {
            try {
                val type = object : TypeToken<List<TenantDto>>() {}.type
                val dtos: List<TenantDto> = gson.fromJson(tenantsJson, type)
                dtos.map { it.toDomain() }
            } catch (e: Exception) {
                emptyList()
            }
        } else {
            emptyList()
        }

        return TenantContext(
            currentTenantId = tenantId,
            currentRole = role,
            availableTenants = tenants
        ).also {
            _tenantContextFlow.value = it
        }
    }

    override suspend fun getUserTenants(): Result<List<Tenant>> {
        return try {
            val response = apiService.getUserTenants()

            if (response.isSuccessful) {
                val tenants = response.body()!!.data.map { it.toDomain() }
                // Save to storage
                val json = gson.toJson(response.body()!!.data)
                secureStorage.saveUserTenants(json)
                Result.success(tenants)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    else -> Result.error(AppException.Unknown("Failed to get tenants: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get tenants", e))
        }
    }

    override suspend fun switchTenant(tenantId: String): Result<TenantContext> {
        return try {
            val response = apiService.switchTenant(TenantSwitchRequest(tenantId))

            if (response.isSuccessful) {
                val data = response.body()!!.data

                // Clear cached folder keys (they're tenant-specific)
                folderKeyManager.clearCache()

                // Save new tokens and tenant context atomically
                secureStorage.saveTokensWithTenantContext(
                    accessToken = data.accessToken,
                    refreshToken = data.refreshToken,
                    tenantId = data.currentTenantId,
                    role = data.role
                )

                // Refresh tenant config for new tenant
                refreshConfig()

                // Update tenant context
                val currentContext = getCurrentTenantContext()
                val newContext = currentContext?.copy(
                    currentTenantId = data.currentTenantId,
                    currentRole = UserRole.fromString(data.role)
                ) ?: TenantContext(
                    currentTenantId = data.currentTenantId,
                    currentRole = UserRole.fromString(data.role),
                    availableTenants = emptyList()
                )

                _tenantContextFlow.value = newContext

                Result.success(newContext)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Not authorized to access this tenant"))
                    404 -> Result.error(AppException.NotFound("Tenant not found"))
                    else -> Result.error(AppException.Unknown("Failed to switch tenant: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to switch tenant", e))
        }
    }

    override suspend fun leaveTenant(tenantId: String): Result<Unit> {
        return try {
            val response = apiService.leaveTenant(tenantId)

            if (response.isSuccessful) {
                // Refresh tenant list after leaving
                refreshTenants()
                Result.success(Unit)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    404 -> Result.error(AppException.NotFound("Tenant not found"))
                    409 -> Result.error(AppException.Conflict("Cannot leave tenant as the only owner"))
                    else -> Result.error(AppException.Unknown("Failed to leave tenant: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to leave tenant", e))
        }
    }

    override suspend fun refreshTenants(): Result<List<Tenant>> {
        val result = getUserTenants()
        if (result is Result.Success) {
            // Update tenant context with refreshed list
            val currentContext = getCurrentTenantContext()
            currentContext?.let { ctx ->
                val newContext = ctx.copy(availableTenants = result.data)
                _tenantContextFlow.value = newContext
            }
        }
        return result
    }

    override suspend fun saveTenantContext(context: TenantContext) {
        secureStorage.saveTenantId(context.currentTenantId)
        secureStorage.saveCurrentRole(context.currentRole.name.lowercase())
        val json = gson.toJson(context.availableTenants.map { it.toDto() })
        secureStorage.saveUserTenants(json)
        _tenantContextFlow.value = context
    }

    override suspend fun clearTenantData() {
        _tenantContextFlow.value = null
    }

    // ==================== Tenant Configuration ====================

    override suspend fun getTenantConfig(): Result<TenantConfig> {
        return try {
            val response = apiService.getTenantConfig()

            if (response.isSuccessful) {
                val dto = response.body()!!.data
                val config = TenantConfig(
                    id = dto.id,
                    name = dto.name,
                    slug = dto.slug,
                    pqcAlgorithm = PqcAlgorithm.fromString(dto.pqcAlgorithm),
                    plan = dto.plan,
                    settings = dto.settings
                )

                // Update the crypto config with tenant's algorithm
                cryptoConfig.setAlgorithm(config.pqcAlgorithm)

                Result.success(config)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    404 -> Result.error(AppException.NotFound("Tenant not found"))
                    else -> Result.error(AppException.Unknown("Failed to get tenant config: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get tenant config", e))
        }
    }

    override fun getPqcAlgorithm(): PqcAlgorithm {
        return cryptoConfig.getAlgorithm()
    }

    override suspend fun refreshConfig(): Result<TenantConfig> {
        return getTenantConfig()
    }

    override suspend fun getTenantUsers(): Result<List<User>> {
        return try {
            val response = apiService.getTenantUsers()

            if (response.isSuccessful) {
                val users = response.body()!!.data.map { dto ->
                    User(
                        id = dto.id,
                        email = dto.email,
                        displayName = dto.displayName,
                        status = dto.status,
                        tenantId = dto.getEffectiveTenantId(),
                        role = dto.getEffectiveRole()?.let { UserRole.fromString(it) },
                        publicKeys = dto.publicKeys?.let {
                            PublicKeys(
                                kem = Base64.decode(it.kem, Base64.NO_WRAP),
                                sign = Base64.decode(it.sign, Base64.NO_WRAP),
                                mlKem = it.mlKem?.let { pk -> Base64.decode(pk, Base64.NO_WRAP) },
                                mlDsa = it.mlDsa?.let { pk -> Base64.decode(pk, Base64.NO_WRAP) }
                            )
                        },
                        storageQuota = dto.storageQuota,
                        storageUsed = dto.storageUsed
                    )
                }
                Result.success(users)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Not authorized to view users"))
                    else -> Result.error(AppException.Unknown("Failed to get tenant users: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get tenant users", e))
        }
    }

    // ==================== Member Management ====================

    override suspend fun getTenantMembers(tenantId: String): Result<List<TenantMember>> {
        return try {
            val response = apiService.getTenantMembers(tenantId)

            if (response.isSuccessful) {
                val members = response.body()!!.data.map { dto ->
                    TenantMember(
                        id = dto.id,
                        userId = dto.userId,
                        email = dto.email,
                        displayName = dto.displayName,
                        role = UserRole.fromString(dto.role),
                        status = MemberStatus.fromString(dto.status),
                        joinedAt = dto.joinedAt
                    )
                }
                Result.success(members)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Not authorized to view members"))
                    404 -> Result.error(AppException.NotFound("Tenant not found"))
                    else -> Result.error(AppException.Unknown("Failed to get members: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get members", e))
        }
    }

    override suspend fun inviteMember(tenantId: String, email: String, role: UserRole): Result<Unit> {
        return try {
            val roleString = when (role) {
                UserRole.OWNER -> "owner"
                UserRole.ADMIN -> "admin"
                else -> "member"
            }
            val response = apiService.inviteMember(tenantId, InviteMemberRequest(email, roleString))

            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Not authorized to invite members"))
                    404 -> Result.error(AppException.NotFound("User not found with that email"))
                    409 -> Result.error(AppException.Conflict("User is already a member or has a pending invitation"))
                    else -> Result.error(AppException.Unknown("Failed to invite member: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to invite member", e))
        }
    }

    override suspend fun updateMemberRole(tenantId: String, userId: String, role: UserRole): Result<TenantMember> {
        return try {
            val roleString = when (role) {
                UserRole.OWNER -> "owner"
                UserRole.ADMIN -> "admin"
                else -> "member"
            }
            val response = apiService.updateMemberRole(tenantId, userId, UpdateMemberRoleRequest(roleString))

            if (response.isSuccessful) {
                val dto = response.body()!!.data
                val member = TenantMember(
                    id = dto.id,
                    userId = dto.userId,
                    email = dto.email,
                    displayName = dto.displayName,
                    role = UserRole.fromString(dto.role),
                    status = MemberStatus.fromString(dto.status),
                    joinedAt = dto.joinedAt
                )
                Result.success(member)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Only owners can change roles"))
                    404 -> Result.error(AppException.NotFound("Member not found"))
                    else -> Result.error(AppException.Unknown("Failed to update role: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to update role", e))
        }
    }

    override suspend fun removeMember(tenantId: String, userId: String): Result<Unit> {
        return try {
            val response = apiService.removeMember(tenantId, userId)

            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    403 -> Result.error(AppException.Forbidden("Not authorized to remove members"))
                    404 -> Result.error(AppException.NotFound("Member not found"))
                    409 -> Result.error(AppException.Conflict("Cannot remove an owner"))
                    else -> Result.error(AppException.Unknown("Failed to remove member: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to remove member", e))
        }
    }

    // ==================== Invitations ====================

    override suspend fun getPendingInvitations(): Result<List<Invitation>> {
        return try {
            val response = apiService.getPendingInvitations()

            if (response.isSuccessful) {
                val invitations = response.body()!!.data.map { dto ->
                    Invitation(
                        id = dto.id,
                        tenantId = dto.tenantId,
                        tenantName = dto.tenantName,
                        tenantSlug = dto.tenantSlug,
                        role = UserRole.fromString(dto.role),
                        invitedBy = dto.invitedBy?.let { inviter ->
                            Inviter(
                                id = inviter.id,
                                email = inviter.email,
                                displayName = inviter.displayName
                            )
                        },
                        invitedAt = dto.invitedAt
                    )
                }
                Result.success(invitations)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    else -> Result.error(AppException.Unknown("Failed to get invitations: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get invitations", e))
        }
    }

    override suspend fun acceptInvitation(invitationId: String): Result<InvitationAccepted> {
        return try {
            val response = apiService.acceptInvitation(invitationId)

            if (response.isSuccessful) {
                val dto = response.body()!!.data
                val accepted = InvitationAccepted(
                    id = dto.id,
                    tenantId = dto.tenantId,
                    role = UserRole.fromString(dto.role),
                    joinedAt = dto.joinedAt
                )

                // Refresh tenant list after accepting
                refreshTenants()

                Result.success(accepted)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    404 -> Result.error(AppException.NotFound("Invitation not found"))
                    409 -> Result.error(AppException.Conflict("Invitation already processed"))
                    else -> Result.error(AppException.Unknown("Failed to accept invitation: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to accept invitation", e))
        }
    }

    override suspend fun declineInvitation(invitationId: String): Result<Unit> {
        return try {
            val response = apiService.declineInvitation(invitationId)

            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    404 -> Result.error(AppException.NotFound("Invitation not found"))
                    409 -> Result.error(AppException.Conflict("Invitation already processed"))
                    else -> Result.error(AppException.Unknown("Failed to decline invitation: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to decline invitation", e))
        }
    }

    // ==================== Extension Functions ====================

    private fun TenantDto.toDomain(): Tenant = Tenant(
        id = id,
        name = name,
        slug = slug,
        role = UserRole.fromString(role),
        joinedAt = joinedAt
    )

    private fun Tenant.toDto(): TenantDto = TenantDto(
        id = id,
        name = name,
        slug = slug,
        role = role.name.lowercase(),
        joinedAt = joinedAt
    )
}
