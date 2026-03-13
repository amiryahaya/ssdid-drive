package my.ssdid.drive.crypto

import android.util.Base64
import com.google.gson.annotations.SerializedName
import java.security.MessageDigest

data class RecoveryFile(
    val version: Int,
    val scheme: String,
    val threshold: Int,
    @SerializedName("share_index") val shareIndex: Int,
    @SerializedName("share_data") val shareData: String,
    val checksum: String,
    @SerializedName("user_did") val userDid: String,
    @SerializedName("created_at") val createdAt: String
) {
    fun validate(): Result<ByteArray> {
        if (version != 1) {
            return Result.failure(IllegalArgumentException(
                "This recovery file requires a newer version of SSDID Drive"))
        }

        val rawBytes = try {
            Base64.decode(shareData, Base64.NO_WRAP)
        } catch (e: Exception) {
            return Result.failure(IllegalArgumentException("Invalid share data"))
        }

        val expectedChecksum = MessageDigest.getInstance("SHA-256")
            .digest(rawBytes)
            .joinToString("") { "%02x".format(it) }

        if (checksum != expectedChecksum) {
            return Result.failure(IllegalArgumentException("Recovery file is damaged"))
        }

        return Result.success(rawBytes)
    }

    companion object {
        fun create(shareIndex: Int, shareData: ByteArray, userDid: String): RecoveryFile {
            val checksum = MessageDigest.getInstance("SHA-256")
                .digest(shareData)
                .joinToString("") { "%02x".format(it) }

            return RecoveryFile(
                version = 1,
                scheme = "shamir-gf256",
                threshold = 2,
                shareIndex = shareIndex,
                shareData = Base64.encodeToString(shareData, Base64.NO_WRAP),
                checksum = checksum,
                userDid = userDid,
                createdAt = java.time.Instant.now().toString()
            )
        }
    }
}
