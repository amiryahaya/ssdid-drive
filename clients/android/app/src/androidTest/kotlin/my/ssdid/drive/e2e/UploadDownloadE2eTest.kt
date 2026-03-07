package my.ssdid.drive.e2e

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.FileRepository
import my.ssdid.drive.domain.repository.FolderRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class UploadDownloadE2eTest {

    @get:Rule
    val hiltRule = HiltAndroidRule(this)

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var folderRepository: FolderRepository

    @Inject
    lateinit var fileRepository: FileRepository

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
    fun uploadAndDownloadFlow_succeeds() = runBlocking {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("e2e_upload")
        val password = "E2ePassword!123".toCharArray()

        try {
            E2eTestUtils.registerUser(authRepository, email, password, tenantSlug)

            val rootFolderResult = folderRepository.getRootFolder()
            val rootFolder = when (rootFolderResult) {
                is Result.Success -> rootFolderResult.data
                is Result.Error -> throw AssertionError("Root folder missing: ${rootFolderResult.exception.message}")
            }

            val localFile = E2eTestConfig.createTempFile(
                context,
                "e2e_upload.txt",
                "e2e upload payload".toByteArray()
            )

            val uploadResult = fileRepository.uploadFile(
                localPath = localFile.absolutePath,
                folderId = rootFolder.id,
                fileName = "e2e_upload.txt",
                mimeType = "text/plain"
            )

            val uploadedFile = when (uploadResult) {
                is Result.Success -> uploadResult.data
                is Result.Error -> throw AssertionError("Upload failed: ${uploadResult.exception.message}")
            }

            val downloadUri = withTimeout(60_000) {
                fileRepository.downloadFile(uploadedFile.id)
                    .filterIsInstance<my.ssdid.drive.domain.repository.DownloadProgress.Completed>()
                    .first()
                    .uri
            }

            val downloadedFile = downloadUri.path?.let { java.io.File(it) }
                ?: throw AssertionError("Download URI has no path")

            if (!downloadedFile.exists() || downloadedFile.length() == 0L) {
                throw AssertionError("Downloaded file missing or empty")
            }
        } finally {
            E2eTestUtils.zeroize(password)
        }
    }
}
