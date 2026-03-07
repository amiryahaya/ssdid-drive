package my.ssdid.drive.util

/**
 * Temporary holder for SSDID Wallet callback data received via deep link.
 * The LoginScreen checks this on mount and passes the session token to LoginViewModel.
 */
object WalletCallbackHolder {
    @Volatile
    var pendingSessionToken: String? = null
        private set

    fun set(sessionToken: String) {
        pendingSessionToken = sessionToken
    }

    fun consume(): String? {
        val token = pendingSessionToken ?: return null
        pendingSessionToken = null
        return token
    }
}
