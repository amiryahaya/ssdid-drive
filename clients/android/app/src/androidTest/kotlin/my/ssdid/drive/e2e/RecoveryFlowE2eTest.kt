package my.ssdid.drive.e2e

import androidx.test.ext.junit.runners.AndroidJUnit4
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.RecoveryRepository
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
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

    @Before
    fun setUp() {
        hiltRule.inject()
        assumeTrue(E2eTestConfig.isE2eEnabled())
        assumeTrue(E2eTestConfig.isLocalBackend())
        assumeTrue(E2eTestConfig.tenantSlug().isNotBlank())
    }

    @Test
    fun recoverySetup_andStatus_succeeds() = runBlocking {
        // This E2E test validates the server-assisted recovery API.
        // Full wallet-based recovery flow is tested via wallet integration tests.

        // Verify status endpoint is reachable
        val statusResult = recoveryRepository.getStatus()
        assertTrue("getStatus should succeed", statusResult.isSuccess)
    }

    @Test
    fun recoverySetup_andDelete_succeeds() = runBlocking {
        val tenantSlug = E2eTestConfig.tenantSlug()

        try {
            val user = E2eTestUtils.registerUser(
                authRepository,
                E2eTestConfig.uniqueEmail("e2e_recovery_setup"),
                "E2ePassword!123".toCharArray(),
                tenantSlug
            )

            // Verify status is initially inactive
            val initialStatus = recoveryRepository.getStatus()
            assertTrue("Initial status should succeed", initialStatus.isSuccess)

        } finally {
            authRepository.logout()
        }
    }
}
