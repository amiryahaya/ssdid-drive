package my.ssdid.drive.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.TotpSetupInfo
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TotpSetupUiState(
    val step: TotpSetupStep = TotpSetupStep.Loading,
    val setupInfo: TotpSetupInfo? = null,
    val code: String = "",
    val backupCodes: List<String>? = null,
    val isLoading: Boolean = false,
    val isComplete: Boolean = false,
    val error: String? = null
)

enum class TotpSetupStep {
    Loading,
    ScanQr,
    ConfirmCode,
    BackupCodes
}

@HiltViewModel
class TotpSetupViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(TotpSetupUiState())
    val uiState: StateFlow<TotpSetupUiState> = _uiState.asStateFlow()

    init {
        initSetup()
    }

    private fun initSetup() {
        viewModelScope.launch {
            when (val result = authRepository.totpSetup()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            step = TotpSetupStep.ScanQr,
                            setupInfo = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(step = TotpSetupStep.ScanQr, error = result.exception.message)
                    }
                }
            }
        }
    }

    fun proceedToConfirm() {
        _uiState.update { it.copy(step = TotpSetupStep.ConfirmCode) }
    }

    fun updateCode(code: String) {
        if (code.length <= 6 && code.all { it.isDigit() }) {
            _uiState.update { it.copy(code = code, error = null) }
        }
    }

    fun confirmSetup() {
        val code = _uiState.value.code
        if (code.length != 6) {
            _uiState.update { it.copy(error = "Enter a 6-digit code") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = authRepository.totpSetupConfirm(code)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            step = TotpSetupStep.BackupCodes,
                            backupCodes = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, code = "", error = result.exception.message)
                    }
                }
            }
        }
    }

    fun completeSetup() {
        _uiState.update { it.copy(isComplete = true) }
    }
}
