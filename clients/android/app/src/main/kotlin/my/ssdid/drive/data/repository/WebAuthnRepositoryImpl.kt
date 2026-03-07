package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.crypto.CryptoManager
import my.ssdid.drive.crypto.KeyBundle
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.CredentialDto
import my.ssdid.drive.data.remote.dto.EncryptedPrivateKeysDto
import my.ssdid.drive.data.remote.dto.KeyBundlePublicKeysDto
import my.ssdid.drive.data.remote.dto.RenameCredentialRequest
import my.ssdid.drive.data.remote.dto.WebAuthnLoginBeginRequest
import my.ssdid.drive.data.remote.dto.WebAuthnLoginCompleteRequest
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.model.UserCredential
import my.ssdid.drive.domain.repository.WebAuthnBeginResult
import my.ssdid.drive.domain.repository.WebAuthnRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import com.google.gson.Gson
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class WebAuthnRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager,
    private val gson: Gson
) : WebAuthnRepository {

    override suspend fun loginBegin(email: String?): Result<WebAuthnBeginResult> {
        return try {
            val request = WebAuthnLoginBeginRequest(email = email)
            val response = apiService.webauthnLoginBegin(request)

            if (response.isSuccessful) {
                val body = response.body()!!
                Result.Success(
                    WebAuthnBeginResult(
                        optionsJson = gson.toJson(body.options),
                        challengeId = body.challengeId
                    )
                )
            } else {
                Result.Error(AppException.Unknown("WebAuthn begin failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun loginComplete(
        challengeId: String,
        assertionJson: String,
        prfOutput: String?
    ): Result<User> {
        return try {
            val assertionObj = gson.fromJson(assertionJson, com.google.gson.JsonObject::class.java)
            val request = WebAuthnLoginCompleteRequest(
                challengeId = challengeId,
                assertion = assertionObj,
                prfOutput = prfOutput
            )

            val response = apiService.webauthnLoginComplete(request)

            if (!response.isSuccessful) {
                return Result.Error(AppException.Unknown("WebAuthn login failed: ${response.code()}"))
            }

            val body = response.body()!!

            // Store tokens
            secureStorage.saveTokens(body.accessToken, body.refreshToken)

            val keyBundle = body.keyBundle

            val masterKey: ByteArray
            if (keyBundle.source == "credential" && prfOutput != null) {
                // PRF-based unlock
                val prfBytes = Base64.decode(prfOutput, Base64.NO_WRAP)
                val wrappingKey = cryptoManager.hkdfDerive(
                    prfBytes,
                    "ssdiddrive-webauthn-mk".toByteArray(),
                    "wrapping-key".toByteArray()
                )

                val encryptedMkStr: String = keyBundle.encryptedMasterKey!!
                val mkNonceStr: String = keyBundle.mkNonce!!
                val encryptedMk = Base64.decode(encryptedMkStr, Base64.NO_WRAP)
                val mkNonce = Base64.decode(mkNonceStr, Base64.NO_WRAP)
                masterKey = cryptoManager.decryptAesGcmWithNonce(encryptedMk, wrappingKey, mkNonce)
            } else {
                // Vault-based unlock
                val keyMaterialStr: String = keyBundle.keyMaterial!!
                val keySaltStr: String = keyBundle.keySalt!!
                val keyMaterial = Base64.decode(keyMaterialStr, Base64.NO_WRAP)
                val keySalt = Base64.decode(keySaltStr, Base64.NO_WRAP)
                val vaultKey = cryptoManager.hkdfDerive(
                    keyMaterial, keySalt, "ssdiddrive-vault-key".toByteArray()
                )

                val vaultMkStr: String = keyBundle.vaultEncryptedMasterKey!!
                val vaultNonceStr: String = keyBundle.vaultMkNonce!!
                val vaultMk = Base64.decode(vaultMkStr, Base64.NO_WRAP)
                val vaultNonce = Base64.decode(vaultNonceStr, Base64.NO_WRAP)
                masterKey = cryptoManager.decryptAesGcmWithNonce(vaultMk, vaultKey, vaultNonce)
            }

            // Decrypt individual private keys with master key
            val keys = decryptKeyBundle(masterKey, keyBundle.encryptedPrivateKeys, keyBundle.publicKeys)
            keyManager.setUnlockedKeys(keys)

            val user = User(
                id = body.user.id,
                email = body.user.email,
                displayName = body.user.displayName
            )
            Result.Success(user)
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun getCredentials(): Result<List<UserCredential>> {
        return try {
            val response = apiService.getCredentials()
            if (response.isSuccessful) {
                val credentials: List<UserCredential> = response.body()?.credentials?.map { dto: CredentialDto ->
                    UserCredential(
                        id = dto.id,
                        credentialType = dto.credentialType,
                        name = dto.name,
                        providerName = dto.providerName,
                        createdAt = dto.createdAt,
                        lastUsedAt = dto.lastUsedAt
                    )
                } ?: emptyList()
                Result.success(credentials)
            } else {
                Result.Error(AppException.Unknown("Failed to get credentials: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun renameCredential(credentialId: String, name: String): Result<UserCredential> {
        return try {
            val request = RenameCredentialRequest(name = name)
            val response = apiService.renameCredential(credentialId, request)
            if (response.isSuccessful) {
                val dto = response.body()!!
                Result.Success(
                    UserCredential(
                        id = dto.id,
                        credentialType = dto.credentialType,
                        name = dto.name,
                        providerName = dto.providerName,
                        createdAt = dto.createdAt,
                        lastUsedAt = dto.lastUsedAt
                    )
                )
            } else {
                Result.Error(AppException.Unknown("Failed to rename credential: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    override suspend fun deleteCredential(credentialId: String): Result<Unit> {
        return try {
            val response = apiService.deleteCredential(credentialId)
            if (response.isSuccessful) {
                Result.Success(Unit)
            } else {
                Result.Error(AppException.Unknown("Failed to delete credential: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.Error(AppException.Unknown(e.message ?: "Unknown error", e))
        }
    }

    private fun decryptKeyBundle(
        masterKey: ByteArray,
        epk: EncryptedPrivateKeysDto,
        pk: KeyBundlePublicKeysDto
    ): KeyBundle {
        val kazKemSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedKazKemSk, Base64.NO_WRAP), masterKey)
        val kazSignSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedKazSignSk, Base64.NO_WRAP), masterKey)
        val mlKemSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedMlKemSk, Base64.NO_WRAP), masterKey)
        val mlDsaSk = cryptoManager.decryptAesGcm(Base64.decode(epk.encryptedMlDsaSk, Base64.NO_WRAP), masterKey)

        return KeyBundle.create(
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
    }
}
