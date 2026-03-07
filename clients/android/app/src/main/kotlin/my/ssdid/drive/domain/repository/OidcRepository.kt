package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.AuthProvider
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.util.Result

interface OidcRepository {
    suspend fun getProviders(tenantSlug: String): Result<List<AuthProvider>>
    suspend fun beginAuthorize(providerId: String): Result<OidcAuthorizeResult>
    suspend fun handleCallback(code: String, state: String): Result<OidcCallbackResult>
    suspend fun completeRegistration(
        providerId: String,
        oidcSub: String,
        email: String,
        name: String,
        keyMaterial: String,
        keySalt: String
    ): Result<User>
}

data class OidcAuthorizeResult(
    val authorizationUrl: String,
    val state: String
)

sealed class OidcCallbackResult {
    data class Authenticated(val user: User) : OidcCallbackResult()
    data class NewUser(val keyMaterial: String, val keySalt: String) : OidcCallbackResult()
}
