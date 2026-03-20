package my.ssdid.drive.presentation.recovery

import android.util.Base64
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.GsonBuilder
import my.ssdid.drive.crypto.RecoveryFile
import my.ssdid.drive.crypto.ShamirSecretSharing
import my.ssdid.drive.data.remote.dto.ApproveRequestResponse
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.MyRecoveryRequestData
import my.ssdid.drive.data.remote.dto.PendingRecoveryRequestDto
import my.ssdid.drive.data.remote.dto.RecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.RejectRequestResponse
import my.ssdid.drive.data.remote.dto.ReleasedShareDto
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.SetupTrusteesRequest
import my.ssdid.drive.data.remote.dto.TrusteeDto
import my.ssdid.drive.data.remote.dto.TrusteeShareEntry
import my.ssdid.drive.domain.repository.RecoveryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.security.MessageDigest
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

// ==================== Wizard ViewModel (Setup Flow with Shamir Shares) ====================

@HiltViewModel
class RecoveryWizardViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    enum class WizardStep { EXPLANATION, GENERATING, DOWNLOAD, UPLOADING, SUCCESS, ERROR }

    data class WizardUiState(
        val step: WizardStep = WizardStep.EXPLANATION,
        val selfFile: String? = null,
        val trustedFile: String? = null,
        val serverShare: String? = null,
        val keyProof: String? = null,
        val selfSaved: Boolean = false,
        val trustedSaved: Boolean = false,
        val error: String? = null
    )

    private val _wizardState = MutableStateFlow(WizardUiState())
    val wizardState: StateFlow<WizardUiState> = _wizardState.asStateFlow()

    fun beginSetup(masterKey: ByteArray, userDid: String, kemPublicKey: ByteArray) {
        _wizardState.update { it.copy(step = WizardStep.GENERATING) }
        viewModelScope.launch {
            try {
                val shares = ShamirSecretSharing.split(masterKey, 2, 3)
                val file1 = RecoveryFile.create(shares[0].first, shares[0].second, userDid)
                val file2 = RecoveryFile.create(shares[1].first, shares[1].second, userDid)
                val serverShareB64 = Base64.encodeToString(shares[2].second, Base64.NO_WRAP)
                val proof = MessageDigest.getInstance("SHA3-256")
                    .digest(kemPublicKey)
                    .joinToString("") { "%02x".format(it) }

                val gson = GsonBuilder().setPrettyPrinting().create()
                _wizardState.update {
                    it.copy(
                        step = WizardStep.DOWNLOAD,
                        selfFile = gson.toJson(file1),
                        trustedFile = gson.toJson(file2),
                        serverShare = serverShareB64,
                        keyProof = proof
                    )
                }
            } catch (e: Exception) {
                _wizardState.update { it.copy(step = WizardStep.ERROR, error = e.message) }
            }
        }
    }

    fun markSelfSaved() { _wizardState.update { it.copy(selfSaved = true) } }
    fun markTrustedSaved() { _wizardState.update { it.copy(trustedSaved = true) } }

    fun uploadServerShare() {
        val s = _wizardState.value
        _wizardState.update { it.copy(step = WizardStep.UPLOADING) }
        viewModelScope.launch {
            recoveryRepository.setupRecovery(s.serverShare!!, s.keyProof!!)
                .onSuccess { _wizardState.update { it.copy(step = WizardStep.SUCCESS) } }
                .onFailure { e -> _wizardState.update { it.copy(step = WizardStep.ERROR, error = e.message) } }
        }
    }

    fun retryFromError() {
        _wizardState.update { WizardUiState() }
    }
}

// ==================== Recovery Flow ViewModel (Login Page) ====================

@HiltViewModel
class RecoveryFlowViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    enum class FlowStep { SELECT_PATH, UPLOAD_FILES, RECONSTRUCTING, RE_ENROLLING, SUCCESS, ERROR }

    data class FlowUiState(
        val step: FlowStep = FlowStep.SELECT_PATH,
        val file1Content: String? = null,
        val file2Content: String? = null,
        val serverShareFetched: Boolean = false,
        val serverShare: String? = null,
        val oldDid: String = "",
        val newDid: String = "",
        val kemPublicKey: String = "",
        val error: String? = null
    )

    private val _flowState = MutableStateFlow(FlowUiState())
    val flowState: StateFlow<FlowUiState> = _flowState.asStateFlow()

    fun setFile1Content(content: String) {
        _flowState.update { it.copy(file1Content = content) }
    }

    fun setFile2Content(content: String) {
        _flowState.update { it.copy(file2Content = content) }
    }

    fun setOldDid(did: String) {
        _flowState.update { it.copy(oldDid = did) }
    }

    fun setNewDid(did: String) {
        _flowState.update { it.copy(newDid = did) }
    }

    fun setKemPublicKey(key: String) {
        _flowState.update { it.copy(kemPublicKey = key) }
    }

    fun fetchServerShare() {
        val s = _flowState.value
        if (s.oldDid.isBlank()) {
            _flowState.update { it.copy(step = FlowStep.ERROR, error = "DID is required to fetch server share") }
            return
        }
        viewModelScope.launch {
            recoveryRepository.getServerShare(s.oldDid)
                .onSuccess { share ->
                    _flowState.update {
                        it.copy(
                            serverShare = share.serverShare,
                            serverShareFetched = true
                        )
                    }
                }
                .onFailure { e ->
                    _flowState.update { it.copy(step = FlowStep.ERROR, error = e.message) }
                }
        }
    }

    fun recoverWithTwoFiles() {
        val s = _flowState.value
        if (s.file1Content == null || s.file2Content == null) {
            _flowState.update { it.copy(step = FlowStep.ERROR, error = "Both recovery files are required") }
            return
        }
        _flowState.update { it.copy(step = FlowStep.RECONSTRUCTING) }
        viewModelScope.launch {
            try {
                val gson = GsonBuilder().create()
                val rf1 = gson.fromJson(s.file1Content, RecoveryFile::class.java)
                val rf2 = gson.fromJson(s.file2Content, RecoveryFile::class.java)

                val bytes1 = rf1.validate().getOrElse { e ->
                    _flowState.update { it.copy(step = FlowStep.ERROR, error = "File 1: ${e.message}") }
                    return@launch
                }
                val bytes2 = rf2.validate().getOrElse { e ->
                    _flowState.update { it.copy(step = FlowStep.ERROR, error = "File 2: ${e.message}") }
                    return@launch
                }

                // Reconstruct the secret from 2 of 3 shares (path A: two user files)
                ShamirSecretSharing.reconstruct(listOf(Pair(rf1.shareIndex, bytes1), Pair(rf2.shareIndex, bytes2)))

                _flowState.update { it.copy(step = FlowStep.RE_ENROLLING) }
            } catch (e: Exception) {
                _flowState.update { it.copy(step = FlowStep.ERROR, error = "Reconstruction failed: ${e.message}") }
            }
        }
    }

    fun recoverWithFileAndServer() {
        val s = _flowState.value
        if (s.file1Content == null) {
            _flowState.update { it.copy(step = FlowStep.ERROR, error = "Recovery file is required") }
            return
        }
        if (!s.serverShareFetched || s.serverShare == null) {
            _flowState.update { it.copy(step = FlowStep.ERROR, error = "Server share not yet fetched") }
            return
        }
        _flowState.update { it.copy(step = FlowStep.RECONSTRUCTING) }
        viewModelScope.launch {
            try {
                val gson = GsonBuilder().create()
                val rf1 = gson.fromJson(s.file1Content, RecoveryFile::class.java)

                val bytes1 = rf1.validate().getOrElse { e ->
                    _flowState.update { it.copy(step = FlowStep.ERROR, error = "Recovery file: ${e.message}") }
                    return@launch
                }
                val serverBytes = Base64.decode(s.serverShare, Base64.NO_WRAP)

                // Reconstruct using file share + server share
                ShamirSecretSharing.reconstruct(listOf(Pair(rf1.shareIndex, bytes1), Pair(3, serverBytes)))

                _flowState.update { it.copy(step = FlowStep.RE_ENROLLING) }
            } catch (e: Exception) {
                _flowState.update { it.copy(step = FlowStep.ERROR, error = "Reconstruction failed: ${e.message}") }
            }
        }
    }

    fun completeRecovery() {
        val s = _flowState.value
        val oldDid = s.oldDid.ifBlank {
            _flowState.update { it.copy(step = FlowStep.ERROR, error = "Original DID required") }
            return
        }
        viewModelScope.launch {
            recoveryRepository.completeRecovery(
                oldDid = oldDid,
                newDid = s.newDid.ifBlank { oldDid },
                keyProof = "",
                kemPublicKey = s.kemPublicKey
            )
                .onSuccess { _flowState.update { it.copy(step = FlowStep.SUCCESS) } }
                .onFailure { e -> _flowState.update { it.copy(step = FlowStep.ERROR, error = e.message) } }
        }
    }

    fun clearError() {
        _flowState.update { it.copy(step = FlowStep.SELECT_PATH, error = null) }
    }
}

// ==================== Trustee Setup ViewModel ====================

@HiltViewModel
class TrusteeSetupViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    data class UiState(
        val trustees: List<TrusteeDto> = emptyList(),
        val threshold: Int = 0,
        val isLoading: Boolean = false,
        val isSetupComplete: Boolean = false,
        val error: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        loadTrustees()
    }

    fun loadTrustees() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            recoveryRepository.getTrustees()
                .onSuccess { response ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            trustees = response.trustees,
                            threshold = response.threshold
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }

    fun setupTrustees(threshold: Int, shares: List<TrusteeShareEntry>) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            recoveryRepository.setupTrustees(SetupTrusteesRequest(threshold, shares))
                .onSuccess {
                    _uiState.update { it.copy(isLoading = false, isSetupComplete = true) }
                    loadTrustees()
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

// ==================== Initiate Recovery ViewModel ====================

@HiltViewModel
class InitiateRecoveryViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    data class UiState(
        val activeRequest: MyRecoveryRequestData? = null,
        val isLoading: Boolean = false,
        val isInitiated: Boolean = false,
        val error: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        checkRecoveryStatus()
    }

    fun checkRecoveryStatus() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            recoveryRepository.getMyRecoveryRequest()
                .onSuccess { response ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            activeRequest = response.request,
                            isInitiated = response.request != null
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }

    fun initiateRecovery() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            recoveryRepository.initiateRecoveryRequest()
                .onSuccess { response ->
                    _uiState.update { it.copy(isLoading = false, isInitiated = true) }
                    checkRecoveryStatus()
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

// ==================== Pending Requests ViewModel (Trustee View) ====================

@HiltViewModel
class PendingRecoveryRequestsViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    data class UiState(
        val requests: List<PendingRecoveryRequestDto> = emptyList(),
        val isLoading: Boolean = false,
        val processingId: String? = null,
        val error: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        loadPendingRequests()
    }

    fun loadPendingRequests() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            recoveryRepository.getPendingRecoveryRequests()
                .onSuccess { response ->
                    _uiState.update { it.copy(isLoading = false, requests = response.requests) }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isLoading = false, error = e.message) }
                }
        }
    }

    fun approveRequest(requestId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(processingId = requestId, error = null) }
            recoveryRepository.approveRecoveryRequest(requestId)
                .onSuccess {
                    _uiState.update { state ->
                        state.copy(
                            processingId = null,
                            requests = state.requests.filterNot { it.id == requestId }
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(processingId = null, error = e.message) }
                }
        }
    }

    fun rejectRequest(requestId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(processingId = requestId, error = null) }
            recoveryRepository.rejectRecoveryRequest(requestId)
                .onSuccess {
                    _uiState.update { state ->
                        state.copy(
                            processingId = null,
                            requests = state.requests.filterNot { it.id == requestId }
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(processingId = null, error = e.message) }
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

// ==================== Trustee-Based Recovery Flow ViewModel ====================

@HiltViewModel
class TrusteeRecoveryViewModel @Inject constructor(
    private val recoveryRepository: RecoveryRepository
) : ViewModel() {

    enum class FlowStep { IDLE, REQUESTING, WAITING_APPROVAL, FETCHING_SHARES, SUCCESS, ERROR }

    data class UiState(
        val step: FlowStep = FlowStep.IDLE,
        val activeRequest: MyRecoveryRequestData? = null,
        val releasedShares: List<ReleasedShareDto> = emptyList(),
        val did: String = "",
        val error: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    fun setDid(did: String) {
        _uiState.update { it.copy(did = did) }
    }

    /** Unauthenticated path: create recovery request by DID (no session). */
    fun createRecoveryRequest() {
        val did = _uiState.value.did
        if (did.isBlank()) {
            _uiState.update { it.copy(step = FlowStep.ERROR, error = "DID is required") }
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(step = FlowStep.REQUESTING, error = null) }
            recoveryRepository.createRecoveryRequest(did)
                .onSuccess {
                    _uiState.update { it.copy(step = FlowStep.WAITING_APPROVAL) }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(step = FlowStep.ERROR, error = e.message) }
                }
        }
    }

    /** Poll the user's active recovery request status. */
    fun checkRequestStatus() {
        viewModelScope.launch {
            recoveryRepository.getMyRecoveryRequest()
                .onSuccess { response ->
                    val req = response.request
                    if (req != null && req.status == "approved") {
                        _uiState.update { it.copy(activeRequest = req, step = FlowStep.FETCHING_SHARES) }
                    } else {
                        _uiState.update { it.copy(activeRequest = req) }
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(error = e.message) }
                }
        }
    }

    /** Fetch released trustee shares once the request is approved. */
    fun fetchReleasedShares(requestId: String) {
        val did = _uiState.value.did
        viewModelScope.launch {
            recoveryRepository.getReleasedShares(requestId, did)
                .onSuccess { response ->
                    _uiState.update {
                        it.copy(
                            releasedShares = response.shares,
                            step = FlowStep.SUCCESS
                        )
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(step = FlowStep.ERROR, error = e.message) }
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(step = FlowStep.IDLE, error = null) }
    }
}
