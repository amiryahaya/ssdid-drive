package my.ssdid.drive.e2e

import androidx.test.ext.junit.runners.AndroidJUnit4
import my.ssdid.drive.domain.repository.AuthRepository
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
class RegistrationLoginE2eTest {

    @get:Rule
    val hiltRule = HiltAndroidRule(this)

    @Inject
    lateinit var authRepository: AuthRepository

    @Before
    fun setUp() {
        hiltRule.inject()
        assumeTrue(E2eTestConfig.isE2eEnabled())
        assumeTrue(E2eTestConfig.isLocalBackend())
        assumeTrue(E2eTestConfig.tenantSlug().isNotBlank())
    }

    @Test
    fun registrationAndLoginFlow_succeeds() = runBlocking {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("e2e_reg")
        val password = "E2ePassword!123".toCharArray()

        try {
            E2eTestUtils.registerUser(authRepository, email, password, tenantSlug)
            authRepository.logout()
            E2eTestUtils.loginAndUnlock(authRepository, email, password, tenantSlug)
        } finally {
            E2eTestUtils.zeroize(password)
        }
    }
}
