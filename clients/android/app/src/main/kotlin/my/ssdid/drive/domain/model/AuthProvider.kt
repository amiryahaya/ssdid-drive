package my.ssdid.drive.domain.model

data class AuthProvider(
    val id: String,
    val name: String,
    val providerType: String,
    val tenantId: String,
    val clientId: String?,
    val issuer: String?,
    val enabled: Boolean
)

data class UserCredential(
    val id: String,
    val credentialType: String,
    val name: String?,
    val providerName: String?,
    val createdAt: String,
    val lastUsedAt: String?
)
