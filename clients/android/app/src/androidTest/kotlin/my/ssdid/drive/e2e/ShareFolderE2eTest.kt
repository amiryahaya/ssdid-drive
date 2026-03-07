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
class ShareFolderE2eTest {

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
    fun shareFolderFlow_succeeds() = runBlocking {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val userAPassword = "E2ePassword!123".toCharArray()
        val userBPassword = "E2ePassword!456".toCharArray()

        try {
            val userA = E2eTestUtils.registerUser(
                authRepository,
                E2eTestConfig.uniqueEmail("e2e_folder_a"),
                userAPassword,
                tenantSlug
            )

            authRepository.logout()

            val userB = E2eTestUtils.registerUser(
                authRepository,
                E2eTestConfig.uniqueEmail("e2e_folder_b"),
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

            val sharedFolderResult = folderRepository.createFolder(rootFolder.id, "e2e_shared_folder")
            val sharedFolder = when (sharedFolderResult) {
                is Result.Success -> sharedFolderResult.data
                is Result.Error -> throw AssertionError("Folder creation failed: ${sharedFolderResult.exception.message}")
            }

            val localFile = E2eTestConfig.createTempFile(
                context,
                "e2e_folder_share.txt",
                "folder share payload".toByteArray()
            )

            val uploadResult = fileRepository.uploadFile(
                localPath = localFile.absolutePath,
                folderId = sharedFolder.id,
                fileName = "folder_share.txt",
                mimeType = "text/plain"
            )

            val uploadedFile = when (uploadResult) {
                is Result.Success -> uploadResult.data
                is Result.Error -> throw AssertionError("Upload failed: ${uploadResult.exception.message}")
            }

            val grantee = attachPublicKeysToUser(userB)

            val shareResult = shareRepository.shareFolder(
                sharedFolder.id,
                grantee,
                SharePermission.READ,
                recursive = true
            )

            val share = when (shareResult) {
                is Result.Success -> shareResult.data
                is Result.Error -> throw AssertionError("Share folder failed: ${shareResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userB.email, userBPassword, tenantSlug)

            val receivedShares = shareRepository.getReceivedShares()
            if (receivedShares !is Result.Success || receivedShares.data.none { it.id == share.id }) {
                throw AssertionError("Folder share not visible to recipient")
            }

            val sharedFolderAccess = folderRepository.getFolder(sharedFolder.id)
            if (sharedFolderAccess !is Result.Success) {
                throw AssertionError("Recipient cannot access shared folder: ${sharedFolderAccess.exceptionOrNull()?.message}")
            }

            val filesInFolder = fileRepository.getFiles(sharedFolder.id)
            if (filesInFolder !is Result.Success || filesInFolder.data.none { it.id == uploadedFile.id }) {
                throw AssertionError("Shared file missing for recipient")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userA.email, userAPassword, tenantSlug)
            val revokeResult = shareRepository.revokeShare(share.id)
            if (revokeResult is Result.Error) {
                throw AssertionError("Revoke failed: ${revokeResult.exception.message}")
            }

            authRepository.logout()

            E2eTestUtils.loginAndUnlock(authRepository, userB.email, userBPassword, tenantSlug)

            val rootAfterRevoke = folderRepository.getFolder(sharedFolder.id)
            if (rootAfterRevoke is Result.Success) {
                throw AssertionError("Recipient still accesses folder after revoke")
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
