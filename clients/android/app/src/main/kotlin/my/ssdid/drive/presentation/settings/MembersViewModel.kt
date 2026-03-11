package my.ssdid.drive.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.TenantMember
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class MembersUiState(
    val members: List<TenantMember> = emptyList(),
    val isLoading: Boolean = false,
    val isUpdating: Boolean = false,
    val error: String? = null,
    val successMessage: String? = null,
    val currentUserId: String? = null,
    val currentUserRole: UserRole = UserRole.USER,
    val currentTenantId: String? = null,
    val memberToChangeRole: TenantMember? = null,
    val memberToRemove: TenantMember? = null
)

@HiltViewModel
class MembersViewModel @Inject constructor(
    private val tenantRepository: TenantRepository,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(MembersUiState())
    val uiState: StateFlow<MembersUiState> = _uiState.asStateFlow()

    init {
        loadCurrentUserContext()
    }

    private fun loadCurrentUserContext() {
        viewModelScope.launch {
            // Get current user
            when (val userResult = authRepository.getCurrentUser()) {
                is Result.Success -> {
                    _uiState.update { it.copy(currentUserId = userResult.data.id) }
                }
                is Result.Error -> { /* continue without user id */ }
            }

            // Get tenant context
            val context = tenantRepository.getCurrentTenantContext()
            context?.let { ctx ->
                _uiState.update {
                    it.copy(
                        currentUserRole = ctx.currentRole,
                        currentTenantId = ctx.currentTenantId
                    )
                }
                loadMembers(ctx.currentTenantId)
            }
        }
    }

    fun loadMembers(tenantId: String? = _uiState.value.currentTenantId) {
        if (tenantId == null) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = tenantRepository.getTenantMembers(tenantId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            members = result.data,
                            isLoading = false
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message ?: "Failed to load members"
                        )
                    }
                }
            }
        }
    }

    fun showChangeRoleDialog(member: TenantMember) {
        _uiState.update { it.copy(memberToChangeRole = member) }
    }

    fun dismissChangeRoleDialog() {
        _uiState.update { it.copy(memberToChangeRole = null) }
    }

    fun changeRole(member: TenantMember, newRole: UserRole) {
        val tenantId = _uiState.value.currentTenantId ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isUpdating = true, memberToChangeRole = null) }

            when (val result = tenantRepository.updateMemberRole(tenantId, member.userId, newRole)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isUpdating = false,
                            successMessage = "Role updated to ${newRole.name.lowercase()}"
                        )
                    }
                    loadMembers(tenantId)
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isUpdating = false,
                            error = result.exception.message ?: "Failed to update role"
                        )
                    }
                }
            }
        }
    }

    fun showRemoveMemberDialog(member: TenantMember) {
        _uiState.update { it.copy(memberToRemove = member) }
    }

    fun dismissRemoveMemberDialog() {
        _uiState.update { it.copy(memberToRemove = null) }
    }

    fun removeMember(member: TenantMember) {
        val tenantId = _uiState.value.currentTenantId ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isUpdating = true, memberToRemove = null) }

            when (val result = tenantRepository.removeMember(tenantId, member.userId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isUpdating = false,
                            successMessage = "${member.displayName ?: member.email ?: "Member"} removed"
                        )
                    }
                    loadMembers(tenantId)
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isUpdating = false,
                            error = result.exception.message ?: "Failed to remove member"
                        )
                    }
                }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun clearSuccessMessage() {
        _uiState.update { it.copy(successMessage = null) }
    }
}
