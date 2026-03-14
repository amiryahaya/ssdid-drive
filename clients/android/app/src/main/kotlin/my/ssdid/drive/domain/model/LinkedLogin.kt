package my.ssdid.drive.domain.model

/**
 * Domain model representing a linked login method on an account.
 */
data class LinkedLogin(
    val id: String,
    val provider: String,
    val providerSubject: String,
    val email: String? = null,
    val linkedAt: String? = null
)

/**
 * Domain model for TOTP setup information.
 */
data class TotpSetupInfo(
    val secret: String,
    val otpauthUri: String,
    val qrCode: String? = null
)
