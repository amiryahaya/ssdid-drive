package my.ssdid.drive.util

import java.util.concurrent.atomic.AtomicReference

/**
 * Temporary holder for SSDID Wallet callback data received via deep link.
 * Screens check this on resume and consume the pending result.
 *
 * Each callback is tagged with a flow type to prevent cross-contamination
 * between auth and invite flows sharing the same singleton.
 */
object WalletCallbackHolder {

    sealed class Result {
        data class Success(val sessionToken: String, val flow: Flow) : Result()
        data class Error(val message: String, val flow: Flow) : Result()
    }

    enum class Flow { AUTH, INVITE }

    private val pending = AtomicReference<Result?>(null)

    fun set(sessionToken: String, flow: Flow = Flow.AUTH) {
        pending.set(Result.Success(sessionToken, flow))
    }

    fun setError(message: String, flow: Flow = Flow.INVITE) {
        pending.set(Result.Error(message, flow))
    }

    /**
     * Consume the pending result only if it matches the expected flow.
     * Returns null if no pending result or if the flow doesn't match.
     */
    fun consume(flow: Flow): Result? {
        val current = pending.get() ?: return null
        val matches = when (current) {
            is Result.Success -> current.flow == flow
            is Result.Error -> current.flow == flow
        }
        return if (matches && pending.compareAndSet(current, null)) current else null
    }

    /** Legacy consume for backwards compatibility — consumes any Success for the given flow. */
    fun consumeToken(flow: Flow): String? {
        val result = consume(flow) ?: return null
        return (result as? Result.Success)?.sessionToken
    }
}
