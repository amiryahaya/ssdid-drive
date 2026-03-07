package my.ssdid.drive.util

/**
 * Temporary holder for OIDC callback data received via deep link.
 * The LoginScreen observes this and passes the data to OidcLoginViewModel.
 */
object OidcCallbackHolder {
    @Volatile
    var pendingCode: String? = null
        private set

    @Volatile
    var pendingState: String? = null
        private set

    fun set(code: String, state: String) {
        pendingCode = code
        pendingState = state
    }

    fun consume(): Pair<String, String>? {
        val code = pendingCode ?: return null
        val state = pendingState ?: return null
        pendingCode = null
        pendingState = null
        return code to state
    }
}
