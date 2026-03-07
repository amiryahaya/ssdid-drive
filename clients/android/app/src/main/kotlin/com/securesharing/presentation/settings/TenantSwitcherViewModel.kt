package com.securesharing.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.Tenant
import com.securesharing.domain.model.TenantContext
import com.securesharing.domain.repository.TenantRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for tenant switcher component.
 */
data class TenantSwitcherUiState(
    val currentTenant: Tenant? = null,
    val availableTenants: List<Tenant> = emptyList(),
    val isLoading: Boolean = false,
    val isSwitching: Boolean = false,
    val error: String? = null,
    val switchSuccess: Boolean = false
)

/**
 * ViewModel for managing tenant switching.
 *
 * This ViewModel provides functionality to:
 * - Display the current tenant
 * - List all available tenants for the user
 * - Switch between tenants
 * - Handle tenant context state
 */
@HiltViewModel
class TenantSwitcherViewModel @Inject constructor(
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(TenantSwitcherUiState())
    val uiState: StateFlow<TenantSwitcherUiState> = _uiState.asStateFlow()

    init {
        loadTenantContext()
        observeTenantContext()
    }

    /**
     * Load the initial tenant context.
     */
    private fun loadTenantContext() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            val context = tenantRepository.getCurrentTenantContext()
            if (context != null) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        currentTenant = context.getCurrentTenant(),
                        availableTenants = context.availableTenants
                    )
                }
            } else {
                // Try to fetch from server
                refreshTenants()
            }
        }
    }

    /**
     * Observe tenant context changes.
     */
    private fun observeTenantContext() {
        viewModelScope.launch {
            tenantRepository.observeTenantContext().collect { context ->
                context?.let { ctx ->
                    _uiState.update {
                        it.copy(
                            currentTenant = ctx.getCurrentTenant(),
                            availableTenants = ctx.availableTenants
                        )
                    }
                }
            }
        }
    }

    /**
     * Refresh the list of tenants from the server.
     */
    fun refreshTenants() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = tenantRepository.refreshTenants()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            availableTenants = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    /**
     * Switch to a different tenant.
     *
     * This will:
     * 1. Call the server to switch tenants
     * 2. Update tokens with new tenant context
     * 3. Clear cached data (folder keys, etc.)
     * 4. Update the UI state
     *
     * @param tenantId The ID of the tenant to switch to
     */
    fun switchTenant(tenantId: String) {
        val currentState = _uiState.value

        // Don't switch if already on this tenant
        if (currentState.currentTenant?.id == tenantId) {
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isSwitching = true, error = null, switchSuccess = false) }

            when (val result = tenantRepository.switchTenant(tenantId)) {
                is Result.Success -> {
                    val newContext = result.data
                    _uiState.update {
                        it.copy(
                            isSwitching = false,
                            currentTenant = newContext.getCurrentTenant(),
                            availableTenants = newContext.availableTenants,
                            switchSuccess = true
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isSwitching = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    /**
     * Leave a tenant.
     *
     * @param tenantId The ID of the tenant to leave
     */
    fun leaveTenant(tenantId: String) {
        val currentState = _uiState.value

        // Can't leave if it's the only tenant
        if (currentState.availableTenants.size <= 1) {
            _uiState.update { it.copy(error = "Cannot leave your only organization") }
            return
        }

        // Can't leave current tenant without switching first
        if (currentState.currentTenant?.id == tenantId) {
            _uiState.update { it.copy(error = "Switch to another organization before leaving this one") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = tenantRepository.leaveTenant(tenantId)) {
                is Result.Success -> {
                    // Refresh tenant list after leaving
                    refreshTenants()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    /**
     * Clear the switch success flag.
     */
    fun clearSwitchSuccess() {
        _uiState.update { it.copy(switchSuccess = false) }
    }

    /**
     * Clear error state.
     */
    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
