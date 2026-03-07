package my.ssdid.drive.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.AuthProvider
import my.ssdid.drive.domain.repository.OidcCallbackResult
import my.ssdid.drive.domain.repository.OidcRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OidcUiState(
    val providers: List<AuthProvider> = emptyList(),
    val isLoadingProviders: Boolean = false,
    val isLoading: Boolean = false,
    val authorizationUrl: String? = null,
    val pendingState: String? = null,
    val isLoggedIn: Boolean = false,
    val isNewUser: Boolean = false,
    val newUserKeyMaterial: String? = null,
    val newUserKeySalt: String? = null,
    val error: String? = null
)

@HiltViewModel
class OidcLoginViewModel @Inject constructor(
    private val oidcRepository: OidcRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(OidcUiState())
    val uiState: StateFlow<OidcUiState> = _uiState.asStateFlow()

    fun loadProviders(tenantSlug: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingProviders = true) }
            when (val result = oidcRepository.getProviders(tenantSlug)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            providers = result.data.filter { p -> p.enabled },
                            isLoadingProviders = false
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoadingProviders = false, error = result.exception.message)
                    }
                }
            }
        }
    }

    fun beginLogin(providerId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = oidcRepository.beginAuthorize(providerId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            authorizationUrl = result.data.authorizationUrl,
                            pendingState = result.data.state
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, error = result.exception.message)
                    }
                }
            }
        }
    }

    fun handleCallback(code: String, state: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = oidcRepository.handleCallback(code, state)) {
                is Result.Success -> {
                    when (val callbackResult = result.data) {
                        is OidcCallbackResult.Authenticated -> {
                            _uiState.update {
                                it.copy(isLoading = false, isLoggedIn = true)
                            }
                        }
                        is OidcCallbackResult.NewUser -> {
                            _uiState.update {
                                it.copy(
                                    isLoading = false,
                                    isNewUser = true,
                                    newUserKeyMaterial = callbackResult.keyMaterial,
                                    newUserKeySalt = callbackResult.keySalt
                                )
                            }
                        }
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, error = result.exception.message)
                    }
                }
            }
        }
    }

    fun clearAuthorizationUrl() {
        _uiState.update { it.copy(authorizationUrl = null) }
    }
}
