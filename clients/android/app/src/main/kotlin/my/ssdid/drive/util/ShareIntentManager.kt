package my.ssdid.drive.util

import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manager for handling files received via share intent from other apps.
 *
 * This is a singleton that holds pending URIs until they are processed.
 * The URIs are cleared after successful upload or when the user cancels.
 */
@Singleton
class ShareIntentManager @Inject constructor() {

    private val _pendingUris = MutableStateFlow<List<Uri>>(emptyList())
    val pendingUris: StateFlow<List<Uri>> = _pendingUris.asStateFlow()

    private val _pendingMimeType = MutableStateFlow<String?>(null)
    val pendingMimeType: StateFlow<String?> = _pendingMimeType.asStateFlow()

    /**
     * Set the pending URIs from a share intent.
     */
    fun setPendingFiles(uris: List<Uri>, mimeType: String) {
        _pendingUris.value = uris
        _pendingMimeType.value = mimeType
    }

    /**
     * Check if there are pending files to upload.
     */
    fun hasPendingFiles(): Boolean = _pendingUris.value.isNotEmpty()

    /**
     * Clear the pending files after processing.
     */
    fun clearPendingFiles() {
        _pendingUris.value = emptyList()
        _pendingMimeType.value = null
    }

    /**
     * Get the count of pending files.
     */
    fun getPendingCount(): Int = _pendingUris.value.size
}
