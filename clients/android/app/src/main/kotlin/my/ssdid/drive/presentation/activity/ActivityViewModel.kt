package my.ssdid.drive.presentation.activity

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.FileActivity
import my.ssdid.drive.domain.repository.ActivityRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ActivityUiState(
    val items: List<FileActivity> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val selectedFilter: String = "All"
)

@HiltViewModel
class ActivityViewModel @Inject constructor(
    private val activityRepository: ActivityRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(ActivityUiState())
    val uiState: StateFlow<ActivityUiState> = _uiState.asStateFlow()

    init {
        loadActivity()
    }

    fun loadActivity() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            val filter = _uiState.value.selectedFilter
            val eventType = mapFilterToEventType(filter)
            val resourceType = mapFilterToResourceType(filter)

            when (val result = activityRepository.getActivity(
                eventType = eventType,
                resourceType = resourceType
            )) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            items = result.data
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

    fun setFilter(filter: String) {
        _uiState.update { it.copy(selectedFilter = filter) }
        loadActivity()
    }

    private fun mapFilterToEventType(filter: String): String? {
        return when (filter) {
            "Uploads" -> "file_uploaded"
            "Downloads" -> "file_downloaded"
            "Shares" -> "file_shared"
            "Renames" -> "file_renamed"
            "Deletes" -> "file_deleted"
            else -> null
        }
    }

    private fun mapFilterToResourceType(filter: String): String? {
        return when (filter) {
            "Folders" -> "folder"
            else -> null
        }
    }
}
