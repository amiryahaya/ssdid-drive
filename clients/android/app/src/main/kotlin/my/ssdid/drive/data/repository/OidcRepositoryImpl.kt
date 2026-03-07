package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.crypto.CryptoManager
import my.ssdid.drive.crypto.KeyBundle
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.AuthProviderDto
import my.ssdid.drive.data.remote.dto.OidcAuthorizeRequest
import my.ssdid.drive.data.remote.dto.OidcCallbackRequest
import my.ssdid.drive.data.remote.dto.OidcRegisterRequest
import my.ssdid.drive.domain.model.AuthProvider
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.OidcAuthorizeResult
import my.ssdid.drive.domain.repository.OidcCallbackResult
import my.ssdid.drive.domain.repository.OidcRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OidcRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager
) : OidcRepository {

    override suspend fun getProviders(tenantSlug: String): Result<List<AuthProvider>> {
        return try {
            val response = apiService.getAuthProviders(tenantSlug)
            if (response.isSuccessful) {
                val providers: List<AuthProvider> = response.body()?.providers?.map { dto: AuthProviderDto ->
                    AuthProvider(
                        id = dto.id,
                        name = dto.name,
                        providerType = dto.providerType,
                        tenantId = dto.tenantId,
                        clientId = dto.clientId,
                        issuer = dto.issuer,
                        enabled = dto.enabled
                    )
                } ?: emptyList()
                Result.success(providers)
            } else {
                Result.Error(AppException.Unknown("Failed to get providers: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun beginAuthorize(providerId: String): Result<OidcAuthorizeResult> {
        return try {
            val request = OidcAuthorizeRequest(
                providerId = providerId,
                redirectUri = "ssdiddrive://oidc/callback"
            )
            val response = apiService.oidcAuthorize(request)
            if (response.isSuccessful) {
                val body = response.body()!!
                Result.Success(OidcAuthorizeResult(body.authorizationUrl, body.state))
            } else {
                Result.Error(AppException.Unknown("Authorization failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun handleCallback(code: String, state: String): Result<OidcCallbackResult> {
        return try {
            val request = OidcCallbackRequest(code = code, state = state)
            val response = apiService.oidcCallback(request)

            if (!response.isSuccessful) {
                return Result.Error(AppException.Unknown("OIDC callback failed: ${response.code()}"))
            }

            val body = response.body()!!

            when (body.status) {
                "authenticated" -> {
                    // Store tokens
                    secureStorage.saveTokens(body.accessToken!!, body.refreshToken!!)

                    // Derive vault key and unlock master key
                    val vaultBundle = body.keyBundle!!
                    val keyMaterialStr: String = vaultBundle.keyMaterial!!
                    val keySaltStr: String = vaultBundle.keySalt!!
                    val keyMaterial = Base64.decode(keyMaterialStr, Base64.NO_WRAP)
                    val keySalt = Base64.decode(keySaltStr, Base64.NO_WRAP)
                    val vaultKey = cryptoManager.hkdfDerive(
                        keyMaterial, keySalt, "ssdiddrive-vault-key".toByteArray()
                    )

                    // Decrypt master key with vault key
                    val encryptedMk = Base64.decode(vaultBundle.vaultEncryptedMasterKey, Base64.NO_WRAP)
                    val mkNonce = Base64.decode(vaultBundle.vaultMkNonce, Base64.NO_WRAP)
                    val masterKey = cryptoManager.decryptAesGcmWithNonce(encryptedMk, vaultKey, mkNonce)

                    // Decrypt individual private keys with master key
                    val epk = vaultBundle.encryptedPrivateKeys
                    val kazKemSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedKazKemSk, Base64.NO_WRAP), masterKey)
                    val kazSignSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedKazSignSk, Base64.NO_WRAP), masterKey)
                    val mlKemSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedMlKemSk, Base64.NO_WRAP), masterKey)
                    val mlDsaSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedMlDsaSk, Base64.NO_WRAP), masterKey)

                    // Get public keys and construct key bundle
                    val pk = vaultBundle.publicKeys
                    val keys = KeyBundle.create(
                        masterKey = masterKey,
                        kazKemPublicKey = Base64.decode(pk.kazKemPk, Base64.NO_WRAP),
                        kazKemPrivateKey = kazKemSk,
                        kazSignPublicKey = Base64.decode(pk.kazSignPk, Base64.NO_WRAP),
                        kazSignPrivateKey = kazSignSk,
                        mlKemPublicKey = Base64.decode(pk.mlKemPk, Base64.NO_WRAP),
                        mlKemPrivateKey = mlKemSk,
                        mlDsaPublicKey = Base64.decode(pk.mlDsaPk, Base64.NO_WRAP),
                        mlDsaPrivateKey = mlDsaSk
                    )
                    keyManager.setUnlockedKeys(keys)

                    val user = User(
                        id = body.user!!.id,
                        email = body.user.email,
                        displayName = body.user.displayName
                    )
                    Result.Success(OidcCallbackResult.Authenticated(user))
                }
                "new_user" -> {
                    Result.Success(
                        OidcCallbackResult.NewUser(
                            keyMaterial = body.keyMaterial!!,
                            keySalt = body.keySalt!!
                        )
                    )
                }
                else -> Result.Error(AppException.Unknown("Unknown OIDC status: ${body.status}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun completeRegistration(
        providerId: String,
        oidcSub: String,
        email: String,
        name: String,
        keyMaterial: String,
        keySalt: String
    ): Result<User> {
        return try {
            // Generate keys
            val keyBundle = keyManager.generateKeyBundle()

            val keyMaterialBytes = Base64.decode(keyMaterial, Base64.NO_WRAP)
            val keySaltBytes = Base64.decode(keySalt, Base64.NO_WRAP)
            val vaultKey = cryptoManager.hkdfDerive(
                keyMaterialBytes, keySaltBytes, "ssdiddrive-vault-key".toByteArray()
            )

            // Encrypt master key with vault key
            // encryptAesGcm returns nonce (12 bytes) || ciphertext || tag
            val encryptedMkBlob = cryptoManager.encryptAesGcm(keyBundle.masterKey, vaultKey)
            val mkNonce = encryptedMkBlob.copyOfRange(0, 12)
            val mkCiphertext = encryptedMkBlob.copyOfRange(12, encryptedMkBlob.size)

            // Encrypt each private key with master key
            val encryptedKazKemSk = cryptoManager.encryptAesGcm(keyBundle.kazKemPrivateKey, keyBundle.masterKey)
            val encryptedKazSignSk = cryptoManager.encryptAesGcm(keyBundle.kazSignPrivateKey, keyBundle.masterKey)
            val encryptedMlKemSk = cryptoManager.encryptAesGcm(keyBundle.mlKemPrivateKey, keyBundle.masterKey)
            val encryptedMlDsaSk = cryptoManager.encryptAesGcm(keyBundle.mlDsaPrivateKey, keyBundle.masterKey)

            val request = OidcRegisterRequest(
                providerId = providerId,
                oidcSub = oidcSub,
                email = email,
                name = name,
                vaultEncryptedMasterKey = Base64.encodeToString(mkCiphertext, Base64.NO_WRAP),
                vaultMkNonce = Base64.encodeToString(mkNonce, Base64.NO_WRAP),
                vaultSalt = keySalt,
                encryptedKazKemSk = Base64.encodeToString(encryptedKazKemSk, Base64.NO_WRAP),
                encryptedKazSignSk = Base64.encodeToString(encryptedKazSignSk, Base64.NO_WRAP),
                encryptedMlKemSk = Base64.encodeToString(encryptedMlKemSk, Base64.NO_WRAP),
                encryptedMlDsaSk = Base64.encodeToString(encryptedMlDsaSk, Base64.NO_WRAP),
                mlKemPk = Base64.encodeToString(keyBundle.mlKemPublicKey, Base64.NO_WRAP),
                mlDsaPk = Base64.encodeToString(keyBundle.mlDsaPublicKey, Base64.NO_WRAP),
                kazKemPk = Base64.encodeToString(keyBundle.kazKemPublicKey, Base64.NO_WRAP),
                kazSignPk = Base64.encodeToString(keyBundle.kazSignPublicKey, Base64.NO_WRAP)
            )

            val response = apiService.oidcRegister(request)

            if (response.isSuccessful) {
                val body = response.body()!!
                secureStorage.saveTokens(body.accessToken, body.refreshToken)
                keyManager.setUnlockedKeys(keyBundle)

                val user = User(
                    id = body.user.id,
                    email = body.user.email,
                    displayName = body.user.displayName
                )
                Result.Success(user)
            } else {
                Result.Error(AppException.Unknown("OIDC registration failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }
}
