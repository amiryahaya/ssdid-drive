package com.securesharing.presentation.recovery

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.RecoveryConfig
import com.securesharing.domain.model.RecoveryConfigStatus
import com.securesharing.domain.model.RecoveryRequest
import com.securesharing.domain.model.RecoveryRequestStatus
import com.securesharing.domain.model.RecoveryShare
import com.securesharing.domain.model.RecoveryShareStatus
import com.securesharing.domain.model.User
import com.securesharing.domain.repository.RecoveryRepository
import com.securesharing.domain.repository.TenantRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// ==================== UI State Classes ====================

data class RecoverySetupUiState(
    val config: RecoveryConfig? = null,
    val threshold: Int = 2,
    val totalShares: Int = 3,
    val isLoading: Boolean = false,
    val isSetupComplete: Boolean = false,
    val error: String? = null
)

data class TrusteeSelectionUiState(
    val availableUsers: List<User> = emptyList(),
    val selectedTrustees: List<User> = emptyList(),
    val distributedShares: List<RecoveryShare> = emptyList(),
    val currentShareIndex: Int = 1,
    val totalShares: Int = 0,
    val isLoading: Boolean = false,
    val isDistributionComplete: Boolean = false,
    val error: String? = null
)

data class TrusteeSharesUiState(
    val pendingShares: List<RecoveryShare> = emptyList(),
    val acceptedShares: List<RecoveryShare> = emptyList(),
    val pendingApprovals: List<RecoveryRequest> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

data class RecoveryRequestUiState(
    val myRequests: List<RecoveryRequest> = emptyList(),
    val currentRequest: RecoveryRequest? = null,
    val isLoading: Boolean = false,
    val isRequestCreated: Boolean = false,
    val isRecoveryComplete: Boolean = false,
    val error: String? = null
)

// ==================== ViewModels ====================

@HiltViewModel
class RecoverySetupViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(RecoverySetupUiState())
    val uiState: StateFlow<RecoverySetupUiState> = _uiState.asStateFlow()

    init {
        loadConfig()
    }

    fun loadConfig() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.getRecoveryConfig()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            config = result.data,
                            isSetupComplete = result.data?.status == RecoveryConfigStatus.ACTIVE
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

    fun setThreshold(threshold: Int) {
        _uiState.update {
            it.copy(
                threshold = threshold.coerceIn(2, it.totalShares)
            )
        }
    }

    fun setTotalShares(total: Int) {
        _uiState.update {
            it.copy(
                totalShares = total.coerceIn(it.threshold, 10),
                threshold = it.threshold.coerceAtMost(total)
            )
        }
    }

    fun setupRecovery() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            val state = _uiState.value
            when (val result = recoveryRepository.setupRecovery(state.threshold, state.totalShares)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            config = result.data,
                            isSetupComplete = true
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

    fun disableRecovery() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.disableRecovery()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            config = null,
                            isSetupComplete = false
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

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

@HiltViewModel
class TrusteeSelectionViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository,
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(TrusteeSelectionUiState())
    val uiState: StateFlow<TrusteeSelectionUiState> = _uiState.asStateFlow()

    fun initialize(totalShares: Int) {
        _uiState.update { it.copy(totalShares = totalShares) }
        loadAvailableUsers()
    }

    private fun loadAvailableUsers() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = tenantRepository.getTenantUsers()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            availableUsers = result.data
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

    fun selectTrustee(user: User) {
        val state = _uiState.value
        if (state.selectedTrustees.size < state.totalShares &&
            !state.selectedTrustees.any { it.id == user.id }) {
            _uiState.update {
                it.copy(selectedTrustees = it.selectedTrustees + user)
            }
        }
    }

    fun deselectTrustee(user: User) {
        _uiState.update {
            it.copy(selectedTrustees = it.selectedTrustees.filter { t -> t.id != user.id })
        }
    }

    fun distributeShare(trustee: User) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            val state = _uiState.value
            when (val result = recoveryRepository.createShare(trustee, state.currentShareIndex)) {
                is Result.Success -> {
                    val newIndex = state.currentShareIndex + 1
                    val isComplete = newIndex > state.totalShares

                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            distributedShares = it.distributedShares + result.data,
                            currentShareIndex = newIndex,
                            isDistributionComplete = isComplete
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

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

@HiltViewModel
class TrusteeSharesViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(TrusteeSharesUiState())
    val uiState: StateFlow<TrusteeSharesUiState> = _uiState.asStateFlow()

    init {
        loadData()
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            // Load trustee shares and pending approvals in parallel
            val sharesResult = recoveryRepository.getTrusteeShares()
            val pendingResult = recoveryRepository.getPendingApprovalRequests()

            when (sharesResult) {
                is Result.Success -> {
                    val shares = sharesResult.data
                    _uiState.update {
                        it.copy(
                            pendingShares = shares.filter { s -> s.status == RecoveryShareStatus.PENDING },
                            acceptedShares = shares.filter { s -> s.status == RecoveryShareStatus.ACCEPTED }
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(error = sharesResult.exception.message)
                    }
                }
            }

            when (pendingResult) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            pendingApprovals = pendingResult.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = pendingResult.exception.message
                        )
                    }
                }
            }
        }
    }

    fun acceptShare(shareId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.acceptShare(shareId)) {
                is Result.Success -> {
                    // Move from pending to accepted
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            pendingShares = it.pendingShares.filter { s -> s.id != shareId },
                            acceptedShares = it.acceptedShares + result.data
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

    fun rejectShare(shareId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.rejectShare(shareId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            pendingShares = it.pendingShares.filter { s -> s.id != shareId }
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

    fun approveRecovery(requestId: String, shareId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.approveRecoveryRequest(requestId, shareId)) {
                is Result.Success -> {
                    // Reload data to refresh the list
                    loadData()
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

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

@HiltViewModel
class RecoveryRequestViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(RecoveryRequestUiState())
    val uiState: StateFlow<RecoveryRequestUiState> = _uiState.asStateFlow()

    init {
        loadMyRequests()
    }

    fun loadMyRequests() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.getMyRecoveryRequests()) {
                is Result.Success -> {
                    val activeRequest = result.data.find {
                        it.status == RecoveryRequestStatus.PENDING ||
                        it.status == RecoveryRequestStatus.APPROVED
                    }

                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            myRequests = result.data,
                            currentRequest = activeRequest
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

    fun initiateRecovery(password: String, reason: String?) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.initiateRecovery(password, reason)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            currentRequest = result.data,
                            isRequestCreated = true
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

    fun checkRequestStatus(requestId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.getRecoveryRequest(requestId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            currentRequest = result.data
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

    fun completeRecovery(requestId: String, password: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.completeRecovery(requestId, password)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            isRecoveryComplete = true
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

    fun cancelRequest(requestId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = recoveryRepository.cancelRecoveryRequest(requestId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            currentRequest = null,
                            isRequestCreated = false
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

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
