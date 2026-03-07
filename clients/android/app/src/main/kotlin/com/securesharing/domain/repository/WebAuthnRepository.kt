package com.securesharing.domain.repository

import com.securesharing.domain.model.User
import com.securesharing.domain.model.UserCredential
import com.securesharing.util.Result

interface WebAuthnRepository {
    suspend fun loginBegin(email: String?): Result<WebAuthnBeginResult>
    suspend fun loginComplete(
        challengeId: String,
        assertionJson: String,
        prfOutput: String?
    ): Result<User>
    suspend fun getCredentials(): Result<List<UserCredential>>
    suspend fun renameCredential(credentialId: String, name: String): Result<UserCredential>
    suspend fun deleteCredential(credentialId: String): Result<Unit>
}

data class WebAuthnBeginResult(
    val optionsJson: String,
    val challengeId: String
)
