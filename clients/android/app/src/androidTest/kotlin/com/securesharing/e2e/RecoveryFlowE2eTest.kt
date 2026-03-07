package com.securesharing.e2e

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.securesharing.data.remote.ApiService
import com.securesharing.domain.model.User
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.domain.repository.RecoveryRepository
import com.securesharing.util.Result
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class RecoveryFlowE2eTest {

    @get:Rule
    val hiltRule = HiltAndroidRule(this)

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var recoveryRepository: RecoveryRepository

    @Inject
    lateinit var apiService: ApiService

    @Before
    fun setUp() {
        hiltRule.inject()
        assumeTrue(E2eTestConfig.isE2eEnabled())
        assumeTrue(E2eTestConfig.isLocalBackend())
        assumeTrue(E2eTestConfig.tenantSlug().isNotBlank())
    }

    @Test
    fun recoveryFlow_completes() = runBlocking {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val userAPassword = "E2ePassword!123".toCharArray()
        val userBPassword = "E2ePassword!456".toCharArray()
        val newPassword = "E2ePassword!789"

        try {
            val userA = E2eTestUtils.registerUser(
                authRepository,
                E2eTestConfig.uniqueEmail("e2e_recovery_a"),
                userAPassword,
                tenantSlug
            )

            authRepository.logout()

            val userB = E2eTestUtils.registerUser(
                authRepository,
                E2eTestConfig.uniqueEmail("e2e_recovery_b"),
                userBPassword,
                tenantSlug
            )

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userA.email, userAPassword, tenantSlug)

            val setupResult = recoveryRepository.setupRecovery(threshold = 1, totalShares = 1)
            if (setupResult is Result.Error) {
                throw AssertionError("Recovery setup failed: ${setupResult.exception.message}")
            }

            val trustee = attachPublicKeysToUser(userB)

            val shareResult = recoveryRepository.createShare(trustee, shareIndex = 1)
            val share = when (shareResult) {
                is Result.Success -> shareResult.data
                is Result.Error -> throw AssertionError("Create share failed: ${shareResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userB.email, userBPassword, tenantSlug)

            val acceptResult = recoveryRepository.acceptShare(share.id)
            if (acceptResult is Result.Error) {
                throw AssertionError("Trustee accept failed: ${acceptResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userA.email, userAPassword, tenantSlug)

            val requestResult = recoveryRepository.initiateRecovery(newPassword, "e2e")
            val request = when (requestResult) {
                is Result.Success -> requestResult.data
                is Result.Error -> throw AssertionError("Initiate recovery failed: ${requestResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userB.email, userBPassword, tenantSlug)

            val approvalResult = recoveryRepository.approveRecoveryRequest(request.id, share.id)
            if (approvalResult is Result.Error) {
                throw AssertionError("Approve recovery failed: ${approvalResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userA.email, userAPassword, tenantSlug)

            val completeResult = recoveryRepository.completeRecovery(request.id, newPassword)
            if (completeResult is Result.Error) {
                throw AssertionError("Complete recovery failed: ${completeResult.exception.message}")
            }
        } finally {
            E2eTestUtils.zeroize(userAPassword)
            E2eTestUtils.zeroize(userBPassword)
        }
    }

    private suspend fun attachPublicKeysToUser(user: User): User {
        val response = apiService.getUserPublicKey(user.id)
        if (!response.isSuccessful) {
            throw AssertionError("Failed to fetch public keys for ${user.id}")
        }

        val data = response.body()!!.data
        val publicKeys = E2eTestUtils.toPublicKeys(data)

        return user.copy(publicKeys = publicKeys)
    }
}
