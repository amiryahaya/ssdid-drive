package my.ssdid.drive.data.remote.dto

import com.google.gson.annotations.SerializedName

/** Auth provider from GET /auth/providers */
data class AuthProviderDto(
    val id: String,
    val name: String,
    @SerializedName("provider_type") val providerType: String,
    @SerializedName("tenant_id") val tenantId: String,
    @SerializedName("client_id") val clientId: String?,
    val issuer: String?,
    val enabled: Boolean
)

data class AuthProvidersResponse(
    val providers: List<AuthProviderDto>
)

/** OIDC authorize request/response */
data class OidcAuthorizeRequest(
    @SerializedName("provider_id") val providerId: String,
    @SerializedName("redirect_uri") val redirectUri: String
)

data class OidcAuthorizeResponse(
    @SerializedName("authorization_url") val authorizationUrl: String,
    val state: String
)

/** OIDC callback request/response */
data class OidcCallbackRequest(
    val code: String,
    val state: String
)

data class OidcCallbackResponse(
    val status: String,
    val user: UserDto? = null,
    @SerializedName("access_token") val accessToken: String? = null,
    @SerializedName("refresh_token") val refreshToken: String? = null,
    @SerializedName("device_id") val deviceId: String? = null,
    @SerializedName("key_bundle") val keyBundle: VaultKeyBundleDto? = null,
    @SerializedName("key_material") val keyMaterial: String? = null,
    @SerializedName("key_salt") val keySalt: String? = null
)

/** Vault-based key bundle (OIDC / non-PRF WebAuthn) */
data class VaultKeyBundleDto(
    val source: String,
    @SerializedName("vault_encrypted_master_key") val vaultEncryptedMasterKey: String,
    @SerializedName("vault_mk_nonce") val vaultMkNonce: String,
    @SerializedName("vault_salt") val vaultSalt: String,
    @SerializedName("key_material") val keyMaterial: String? = null,
    @SerializedName("key_salt") val keySalt: String? = null,
    @SerializedName("encrypted_private_keys") val encryptedPrivateKeys: EncryptedPrivateKeysDto,
    @SerializedName("public_keys") val publicKeys: KeyBundlePublicKeysDto
)

/** WebAuthn key bundle (may be PRF or vault-based) */
data class WebAuthnKeyBundleDto(
    val source: String,
    @SerializedName("encrypted_master_key") val encryptedMasterKey: String? = null,
    @SerializedName("mk_nonce") val mkNonce: String? = null,
    @SerializedName("vault_encrypted_master_key") val vaultEncryptedMasterKey: String? = null,
    @SerializedName("vault_mk_nonce") val vaultMkNonce: String? = null,
    @SerializedName("vault_salt") val vaultSalt: String? = null,
    @SerializedName("key_material") val keyMaterial: String? = null,
    @SerializedName("key_salt") val keySalt: String? = null,
    @SerializedName("encrypted_private_keys") val encryptedPrivateKeys: EncryptedPrivateKeysDto,
    @SerializedName("public_keys") val publicKeys: KeyBundlePublicKeysDto
)

data class EncryptedPrivateKeysDto(
    @SerializedName("encrypted_ml_kem_sk") val encryptedMlKemSk: String,
    @SerializedName("encrypted_ml_dsa_sk") val encryptedMlDsaSk: String,
    @SerializedName("encrypted_kaz_kem_sk") val encryptedKazKemSk: String,
    @SerializedName("encrypted_kaz_sign_sk") val encryptedKazSignSk: String
)

data class KeyBundlePublicKeysDto(
    @SerializedName("ml_kem_pk") val mlKemPk: String,
    @SerializedName("ml_dsa_pk") val mlDsaPk: String,
    @SerializedName("kaz_kem_pk") val kazKemPk: String,
    @SerializedName("kaz_sign_pk") val kazSignPk: String
)

/** OIDC registration for new users */
data class OidcRegisterRequest(
    @SerializedName("provider_id") val providerId: String,
    @SerializedName("oidc_sub") val oidcSub: String,
    val email: String,
    val name: String,
    @SerializedName("vault_encrypted_master_key") val vaultEncryptedMasterKey: String,
    @SerializedName("vault_mk_nonce") val vaultMkNonce: String,
    @SerializedName("vault_salt") val vaultSalt: String,
    @SerializedName("encrypted_ml_kem_sk") val encryptedMlKemSk: String,
    @SerializedName("encrypted_ml_dsa_sk") val encryptedMlDsaSk: String,
    @SerializedName("encrypted_kaz_kem_sk") val encryptedKazKemSk: String,
    @SerializedName("encrypted_kaz_sign_sk") val encryptedKazSignSk: String,
    @SerializedName("ml_kem_pk") val mlKemPk: String,
    @SerializedName("ml_dsa_pk") val mlDsaPk: String,
    @SerializedName("kaz_kem_pk") val kazKemPk: String,
    @SerializedName("kaz_sign_pk") val kazSignPk: String
)

/** WebAuthn begin login request/response */
data class WebAuthnLoginBeginRequest(
    val email: String? = null
)

data class WebAuthnBeginResponse(
    val options: com.google.gson.JsonObject,
    @SerializedName("challenge_id") val challengeId: String
)

/** WebAuthn login complete request/response */
data class WebAuthnLoginCompleteRequest(
    @SerializedName("challenge_id") val challengeId: String,
    val assertion: com.google.gson.JsonObject,
    @SerializedName("prf_output") val prfOutput: String? = null
)

data class WebAuthnLoginResponse(
    val user: UserDto,
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("refresh_token") val refreshToken: String,
    @SerializedName("device_id") val deviceId: String,
    @SerializedName("key_bundle") val keyBundle: WebAuthnKeyBundleDto
)

/** User credential management */
data class CredentialDto(
    val id: String,
    @SerializedName("credential_type") val credentialType: String,
    val name: String?,
    @SerializedName("provider_name") val providerName: String?,
    @SerializedName("created_at") val createdAt: String,
    @SerializedName("last_used_at") val lastUsedAt: String?
)

data class CredentialsResponse(
    val credentials: List<CredentialDto>
)

data class RenameCredentialRequest(
    val name: String
)

/** OIDC registration response (new user) */
data class OidcRegisterResponse(
    val user: UserDto,
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("refresh_token") val refreshToken: String,
    @SerializedName("device_id") val deviceId: String? = null
)
