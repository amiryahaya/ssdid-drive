package my.ssdid.drive.presentation.recovery

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.domain.repository.RecoveryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// ==================== UI State Classes ====================

data class RecoverySetupUiState(
    val status: RecoveryStatusResponse? = null,
    val isLoading: Boolean = false,
    val isSetupComplete: Boolean = false,
    val error: String? = null
)

data class RecoveryShareUiState(
    val serverShare: ServerShareResponse? = null,
    val isLoading: Boolean = false,
    val error: String? = null
)

data class CompleteRecoveryUiState(
    val result: CompleteRecoveryResponse? = null,
    val isLoading: Boolean = false,
    val isComplete: Boolean = false,
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
        loadStatus()
    }

    fun loadStatus() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            recoveryRepository.getStatus()
                .onSuccess { status ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            status = status,
                            isSetupComplete = status.isActive
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(isLoading = false, error = e.message)
                    }
                }
        }
    }

    fun setupRecovery(serverShare: String, keyProof: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            recoveryRepository.setupRecovery(serverShare, keyProof)
                .onSuccess {
                    _uiState.update {
                        it.copy(isLoading = false, isSetupComplete = true)
                    }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(isLoading = false, error = e.message)
                    }
                }
        }
    }

    fun deleteSetup() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            recoveryRepository.deleteSetup()
                .onSuccess {
                    _uiState.update {
                        it.copy(isLoading = false, status = null, isSetupComplete = false)
                    }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(isLoading = false, error = e.message)
                    }
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

@HiltViewModel
class RecoveryShareViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(RecoveryShareUiState())
    val uiState: StateFlow<RecoveryShareUiState> = _uiState.asStateFlow()

    fun fetchServerShare(did: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            recoveryRepository.getServerShare(did)
                .onSuccess { share ->
                    _uiState.update { it.copy(isLoading = false, serverShare = share) }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

@HiltViewModel
class CompleteRecoveryViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(CompleteRecoveryUiState())
    val uiState: StateFlow<CompleteRecoveryUiState> = _uiState.asStateFlow()

    fun completeRecovery(
        oldDid: String,
        newDid: String,
        keyProof: String,
        kemPublicKey: String
    ) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            recoveryRepository.completeRecovery(oldDid, newDid, keyProof, kemPublicKey)
                .onSuccess { response ->
                    _uiState.update {
                        it.copy(isLoading = false, result = response, isComplete = true)
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
