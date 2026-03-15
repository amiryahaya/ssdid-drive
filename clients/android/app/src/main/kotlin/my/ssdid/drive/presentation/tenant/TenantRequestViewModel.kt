package my.ssdid.drive.presentation.tenant

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.Result
import javax.inject.Inject

data class TenantRequestUiState(
    val organizationName: String = "",
    val reason: String = "",
    val isLoading: Boolean = false,
    val isSubmitted: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class TenantRequestViewModel @Inject constructor(
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(TenantRequestUiState())
    val uiState = _uiState.asStateFlow()

    fun updateOrganizationName(name: String) {
        _uiState.update { it.copy(organizationName = name, error = null) }
    }

    fun updateReason(reason: String) {
        _uiState.update { it.copy(reason = reason) }
    }

    fun submitRequest() {
        val name = _uiState.value.organizationName.trim()
        if (name.isBlank()) {
            _uiState.update { it.copy(error = "Organization name is required") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            val reason = _uiState.value.reason.trim().ifBlank { null }
            when (val result = tenantRepository.submitTenantRequest(name, reason)) {
                is Result.Success -> {
                    _uiState.update { it.copy(isLoading = false, isSubmitted = true) }
                }
                is Result.Error -> {
                    _uiState.update { it.copy(isLoading = false, error = result.exception.message) }
                }
            }
        }
    }
}
