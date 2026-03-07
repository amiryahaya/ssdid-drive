package my.ssdid.drive.e2e

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.FileRepository
import my.ssdid.drive.domain.repository.FolderRepository
import my.ssdid.drive.domain.repository.ShareRepository
import my.ssdid.drive.util.Result
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
class ShareRevokeE2eTest {

    @get:Rule
    val hiltRule = HiltAndroidRule(this)

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var folderRepository: FolderRepository

    @Inject
    lateinit var fileRepository: FileRepository

    @Inject
    lateinit var shareRepository: ShareRepository

    @Inject
    lateinit var apiService: ApiService

    private lateinit var context: Context

    @Before
    fun setUp() {
        hiltRule.inject()
        context = ApplicationProvider.getApplicationContext()
        assumeTrue(E2eTestConfig.isE2eEnabled())
        assumeTrue(E2eTestConfig.isLocalBackend())
        assumeTrue(E2eTestConfig.tenantSlug().isNotBlank())
    }

    @Test
    fun shareAndRevokeFlow_succeeds() = runBlocking {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val userAPassword = "E2ePassword!123".toCharArray()
        val userBPassword = "E2ePassword!456".toCharArray()

        try {
            val userA = E2eTestUtils.registerUser(
                authRepository,
                E2eTestConfig.uniqueEmail("e2e_share_a"),
                userAPassword,
                tenantSlug
            )

            authRepository.logout()

            val userB = E2eTestUtils.registerUser(
                authRepository,
                E2eTestConfig.uniqueEmail("e2e_share_b"),
                userBPassword,
                tenantSlug
            )

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userA.email, userAPassword, tenantSlug)

            val rootFolderResult = folderRepository.getRootFolder()
            val rootFolder = when (rootFolderResult) {
                is Result.Success -> rootFolderResult.data
                is Result.Error -> throw AssertionError("Root folder missing: ${rootFolderResult.exception.message}")
            }

            val localFile = E2eTestConfig.createTempFile(
                context,
                "e2e_share.txt",
                "e2e share payload".toByteArray()
            )

            val uploadResult = fileRepository.uploadFile(
                localPath = localFile.absolutePath,
                folderId = rootFolder.id,
                fileName = "e2e_share.txt",
                mimeType = "text/plain"
            )

            val uploadedFile = when (uploadResult) {
                is Result.Success -> uploadResult.data
                is Result.Error -> throw AssertionError("Upload failed: ${uploadResult.exception.message}")
            }

            val userBWithKeys = attachPublicKeysToUser(userB)

            val shareResult = shareRepository.shareFile(
                uploadedFile.id,
                userBWithKeys,
                SharePermission.READ
            )

            val share = when (shareResult) {
                is Result.Success -> shareResult.data
                is Result.Error -> throw AssertionError("Share failed: ${shareResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userB.email, userBPassword, tenantSlug)

            val receivedShares = shareRepository.getReceivedShares()
            if (receivedShares !is Result.Success || receivedShares.data.none { it.id == share.id }) {
                throw AssertionError("Share not visible to recipient")
            }

            val fileAccess = fileRepository.getFile(uploadedFile.id)
            if (fileAccess !is Result.Success) {
                throw AssertionError("Recipient cannot access shared file: ${fileAccess.exceptionOrNull()?.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userA.email, userAPassword, tenantSlug)

            val revokeResult = shareRepository.revokeShare(share.id)
            if (revokeResult is Result.Error) {
                throw AssertionError("Revoke failed: ${revokeResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userB.email, userBPassword, tenantSlug)
            val accessAfterRevoke = fileRepository.getFile(uploadedFile.id)
            if (accessAfterRevoke is Result.Success) {
                throw AssertionError("Recipient still has access after revoke")
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
