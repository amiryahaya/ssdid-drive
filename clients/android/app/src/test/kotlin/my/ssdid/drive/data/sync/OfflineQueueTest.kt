package my.ssdid.drive.data.sync

import com.google.gson.Gson
import my.ssdid.drive.data.local.dao.PendingOperationDao
import my.ssdid.drive.data.local.entity.OperationStatus
import my.ssdid.drive.data.local.entity.OperationType
import my.ssdid.drive.data.local.entity.PendingOperationEntity
import my.ssdid.drive.data.local.entity.ResourceType
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class OfflineQueueTest {

    private lateinit var pendingOperationDao: PendingOperationDao
    private lateinit var gson: Gson
    private lateinit var offlineQueue: OfflineQueue

    @Before
    fun setup() {
        pendingOperationDao = mockk(relaxed = true)
        gson = Gson()
        offlineQueue = OfflineQueue(pendingOperationDao, gson)
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ==================== Enqueue Tests ====================

    @Test
    fun `queueFileUpload inserts operation with correct type and payload`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        val operationId = offlineQueue.queueFileUpload(
            localFilePath = "/tmp/test.pdf",
            folderId = "folder-1",
            fileName = "test.pdf",
            mimeType = "application/pdf",
            fileSize = 1024L
        )

        assertTrue(operationId.isNotBlank())
        val captured = slot.captured
        assertEquals(OperationType.UPLOAD_FILE, captured.operationType)
        assertEquals(ResourceType.FILE, captured.resourceType)
        assertEquals("folder-1", captured.parentId)
        assertNull(captured.resourceId)
        assertEquals("/tmp/test.pdf", captured.localFilePath)
        assertEquals(10, captured.priority)

        val payload = gson.fromJson(captured.payload, FileUploadPayload::class.java)
        assertEquals("/tmp/test.pdf", payload.localFilePath)
        assertEquals("folder-1", payload.folderId)
        assertEquals("test.pdf", payload.fileName)
        assertEquals("application/pdf", payload.mimeType)
        assertEquals(1024L, payload.fileSize)
    }

    @Test
    fun `queueFileDelete inserts operation with file id as resource id`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        val operationId = offlineQueue.queueFileDelete("file-42")

        assertTrue(operationId.isNotBlank())
        val captured = slot.captured
        assertEquals(OperationType.DELETE_FILE, captured.operationType)
        assertEquals(ResourceType.FILE, captured.resourceType)
        assertEquals("file-42", captured.resourceId)
        assertNull(captured.parentId)
        assertEquals(5, captured.priority)
    }

    @Test
    fun `queueFileMove inserts operation with target folder as parent`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        offlineQueue.queueFileMove("file-1", "folder-target")

        val captured = slot.captured
        assertEquals(OperationType.MOVE_FILE, captured.operationType)
        assertEquals("file-1", captured.resourceId)
        assertEquals("folder-target", captured.parentId)

        val payload = gson.fromJson(captured.payload, FileMovePayload::class.java)
        assertEquals("file-1", payload.fileId)
        assertEquals("folder-target", payload.targetFolderId)
    }

    @Test
    fun `queueFolderCreate inserts operation with correct priority`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        offlineQueue.queueFolderCreate("Documents", "parent-1")

        val captured = slot.captured
        assertEquals(OperationType.CREATE_FOLDER, captured.operationType)
        assertEquals(ResourceType.FOLDER, captured.resourceType)
        assertEquals("parent-1", captured.parentId)
        assertNull(captured.resourceId)
        assertEquals(8, captured.priority)

        val payload = gson.fromJson(captured.payload, FolderCreatePayload::class.java)
        assertEquals("Documents", payload.name)
        assertEquals("parent-1", payload.parentFolderId)
    }

    @Test
    fun `queueFolderDelete inserts operation with folder id as resource id`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        offlineQueue.queueFolderDelete("folder-99")

        val captured = slot.captured
        assertEquals(OperationType.DELETE_FOLDER, captured.operationType)
        assertEquals(ResourceType.FOLDER, captured.resourceType)
        assertEquals("folder-99", captured.resourceId)
    }

    @Test
    fun `queueShareFile inserts share operation with correct payload`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        offlineQueue.queueShareFile("file-1", "recipient-1", "read")

        val captured = slot.captured
        assertEquals(OperationType.SHARE_FILE, captured.operationType)
        assertEquals(ResourceType.SHARE, captured.resourceType)
        assertEquals("file-1", captured.parentId)
        assertEquals(7, captured.priority)

        val payload = gson.fromJson(captured.payload, ShareFilePayload::class.java)
        assertEquals("file-1", payload.fileId)
        assertEquals("recipient-1", payload.recipientId)
        assertEquals("read", payload.permission)
    }

    @Test
    fun `queueShareFolder inserts share folder operation`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        offlineQueue.queueShareFolder("folder-1", "recipient-2", "write")

        val captured = slot.captured
        assertEquals(OperationType.SHARE_FOLDER, captured.operationType)
        assertEquals(ResourceType.SHARE, captured.resourceType)
        assertEquals("folder-1", captured.parentId)

        val payload = gson.fromJson(captured.payload, ShareFolderPayload::class.java)
        assertEquals("folder-1", payload.folderId)
        assertEquals("recipient-2", payload.recipientId)
        assertEquals("write", payload.permission)
    }

    @Test
    fun `queueRevokeShare inserts revoke operation with share id`() = runTest {
        val slot = slot<PendingOperationEntity>()
        coEvery { pendingOperationDao.insert(capture(slot)) } just Runs

        offlineQueue.queueRevokeShare("share-1")

        val captured = slot.captured
        assertEquals(OperationType.REVOKE_SHARE, captured.operationType)
        assertEquals(ResourceType.SHARE, captured.resourceType)
        assertEquals("share-1", captured.resourceId)
        assertEquals(6, captured.priority)
    }

    @Test
    fun `each queued operation returns a unique id`() = runTest {
        coEvery { pendingOperationDao.insert(any()) } just Runs

        val id1 = offlineQueue.queueFileDelete("file-1")
        val id2 = offlineQueue.queueFileDelete("file-2")

        assertNotEquals(id1, id2)
    }

    // ==================== Query Tests ====================

    @Test
    fun `getPendingOperations delegates to dao`() = runTest {
        val operations = listOf(createTestOperation())
        coEvery { pendingOperationDao.getPendingOperations() } returns operations

        val result = offlineQueue.getPendingOperations()

        assertEquals(operations, result)
        coVerify { pendingOperationDao.getPendingOperations() }
    }

    @Test
    fun `getNextBatch delegates to dao with batch size`() = runTest {
        val operations = listOf(createTestOperation())
        coEvery { pendingOperationDao.getPendingOperationsLimit(5) } returns operations

        val result = offlineQueue.getNextBatch(5)

        assertEquals(operations, result)
        coVerify { pendingOperationDao.getPendingOperationsLimit(5) }
    }

    @Test
    fun `getNextBatch uses default batch size of 10`() = runTest {
        coEvery { pendingOperationDao.getPendingOperationsLimit(10) } returns emptyList()

        offlineQueue.getNextBatch()

        coVerify { pendingOperationDao.getPendingOperationsLimit(10) }
    }

    @Test
    fun `getRetryableOperations delegates to dao`() = runTest {
        val operations = listOf(createTestOperation(status = OperationStatus.FAILED))
        coEvery { pendingOperationDao.getRetryableOperations() } returns operations

        val result = offlineQueue.getRetryableOperations()

        assertEquals(operations, result)
    }

    @Test
    fun `hasPendingOperations checks dao for active operations`() = runTest {
        coEvery { pendingOperationDao.hasActiveOperationForResource(ResourceType.FILE, "file-1") } returns true

        val result = offlineQueue.hasPendingOperations(ResourceType.FILE, "file-1")

        assertTrue(result)
    }

    @Test
    fun `hasPendingOperations returns false when none exist`() = runTest {
        coEvery { pendingOperationDao.hasActiveOperationForResource(ResourceType.FILE, "file-99") } returns false

        val result = offlineQueue.hasPendingOperations(ResourceType.FILE, "file-99")

        assertFalse(result)
    }

    // ==================== Flow Observation Tests ====================

    @Test
    fun `observeActiveOperations delegates to dao`() = runTest {
        val flow = flowOf(listOf(createTestOperation()))
        every { pendingOperationDao.observeActiveOperations() } returns flow

        val result = offlineQueue.observeActiveOperations()

        assertEquals(flow, result)
    }

    @Test
    fun `observePendingCount delegates to dao`() = runTest {
        val flow = flowOf(5)
        every { pendingOperationDao.observePendingCount() } returns flow

        val result = offlineQueue.observePendingCount()

        assertEquals(flow, result)
    }

    @Test
    fun `observePendingUploads delegates to dao`() = runTest {
        val flow = flowOf(listOf(createTestOperation(type = OperationType.UPLOAD_FILE)))
        every { pendingOperationDao.observePendingUploads() } returns flow

        val result = offlineQueue.observePendingUploads()

        assertEquals(flow, result)
    }

    @Test
    fun `observeFailedOperations delegates to dao`() = runTest {
        val flow = flowOf(listOf(createTestOperation(status = OperationStatus.FAILED)))
        every { pendingOperationDao.observeFailedOperations() } returns flow

        val result = offlineQueue.observeFailedOperations()

        assertEquals(flow, result)
    }

    // ==================== Status Update Tests ====================

    @Test
    fun `markInProgress delegates to dao`() = runTest {
        offlineQueue.markInProgress("op-1")

        coVerify { pendingOperationDao.markInProgress("op-1", any()) }
    }

    @Test
    fun `markCompleted delegates to dao`() = runTest {
        offlineQueue.markCompleted("op-1")

        coVerify { pendingOperationDao.markCompleted("op-1", any(), any()) }
    }

    @Test
    fun `markFailed delegates to dao with error message`() = runTest {
        offlineQueue.markFailed("op-1", "Network timeout")

        coVerify { pendingOperationDao.markFailed("op-1", "Network timeout", any()) }
    }

    @Test
    fun `markFailed delegates to dao with null error message`() = runTest {
        offlineQueue.markFailed("op-1", null)

        coVerify { pendingOperationDao.markFailed("op-1", null, any()) }
    }

    @Test
    fun `updateProgress delegates to dao`() = runTest {
        offlineQueue.updateProgress("op-1", 75)

        coVerify { pendingOperationDao.updateProgress("op-1", 75, any()) }
    }

    @Test
    fun `cancelOperation marks operation as cancelled`() = runTest {
        offlineQueue.cancelOperation("op-1")

        coVerify { pendingOperationDao.markCancelled("op-1", any()) }
    }

    @Test
    fun `retryOperation resets for retry via dao`() = runTest {
        offlineQueue.retryOperation("op-1")

        coVerify { pendingOperationDao.resetForRetry("op-1", any()) }
    }

    @Test
    fun `resetInterruptedOperations resets in-progress to pending`() = runTest {
        offlineQueue.resetInterruptedOperations()

        coVerify { pendingOperationDao.resetInProgressToPending() }
    }

    // ==================== Cleanup Tests ====================

    @Test
    fun `cleanupCompleted deletes old completed operations`() = runTest {
        offlineQueue.cleanupCompleted()

        coVerify { pendingOperationDao.deleteCompletedBefore(any()) }
    }

    @Test
    fun `cleanupCompleted accepts custom time threshold`() = runTest {
        val threshold = Instant.parse("2026-01-01T00:00:00Z")

        offlineQueue.cleanupCompleted(threshold)

        coVerify { pendingOperationDao.deleteCompletedBefore(threshold) }
    }

    @Test
    fun `cleanupCancelled deletes cancelled operations`() = runTest {
        offlineQueue.cleanupCancelled()

        coVerify { pendingOperationDao.deleteCancelled() }
    }

    @Test
    fun `deleteOperationsForResource delegates to dao`() = runTest {
        offlineQueue.deleteOperationsForResource(ResourceType.FILE, "file-1")

        coVerify { pendingOperationDao.deleteByResource(ResourceType.FILE, "file-1") }
    }

    // ==================== Payload Parsing Tests ====================

    @Test
    fun `parsePayload parses FileUploadPayload correctly`() {
        val payload = FileUploadPayload("/tmp/f.pdf", "folder-1", "f.pdf", "application/pdf", 2048L)
        val operation = createTestOperation(
            type = OperationType.UPLOAD_FILE,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as FileUploadPayload

        assertEquals("/tmp/f.pdf", parsed.localFilePath)
        assertEquals("folder-1", parsed.folderId)
        assertEquals("f.pdf", parsed.fileName)
        assertEquals("application/pdf", parsed.mimeType)
        assertEquals(2048L, parsed.fileSize)
    }

    @Test
    fun `parsePayload parses FileDeletePayload correctly`() {
        val payload = FileDeletePayload("file-1")
        val operation = createTestOperation(
            type = OperationType.DELETE_FILE,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as FileDeletePayload

        assertEquals("file-1", parsed.fileId)
    }

    @Test
    fun `parsePayload parses FileMovePayload correctly`() {
        val payload = FileMovePayload("file-1", "folder-2")
        val operation = createTestOperation(
            type = OperationType.MOVE_FILE,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as FileMovePayload

        assertEquals("file-1", parsed.fileId)
        assertEquals("folder-2", parsed.targetFolderId)
    }

    @Test
    fun `parsePayload parses FolderCreatePayload correctly`() {
        val payload = FolderCreatePayload("New Folder", "parent-1")
        val operation = createTestOperation(
            type = OperationType.CREATE_FOLDER,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as FolderCreatePayload

        assertEquals("New Folder", parsed.name)
        assertEquals("parent-1", parsed.parentFolderId)
    }

    @Test
    fun `parsePayload parses ShareFilePayload correctly`() {
        val payload = ShareFilePayload("file-1", "user-2", "read")
        val operation = createTestOperation(
            type = OperationType.SHARE_FILE,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as ShareFilePayload

        assertEquals("file-1", parsed.fileId)
        assertEquals("user-2", parsed.recipientId)
        assertEquals("read", parsed.permission)
    }

    @Test
    fun `parsePayload parses RevokeSharePayload correctly`() {
        val payload = RevokeSharePayload("share-1")
        val operation = createTestOperation(
            type = OperationType.REVOKE_SHARE,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as RevokeSharePayload

        assertEquals("share-1", parsed.shareId)
    }

    @Test
    fun `parsePayload parses FolderDeletePayload correctly`() {
        val payload = FolderDeletePayload("folder-1")
        val operation = createTestOperation(
            type = OperationType.DELETE_FOLDER,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as FolderDeletePayload

        assertEquals("folder-1", parsed.folderId)
    }

    @Test
    fun `parsePayload parses ShareFolderPayload correctly`() {
        val payload = ShareFolderPayload("folder-1", "user-3", "admin")
        val operation = createTestOperation(
            type = OperationType.SHARE_FOLDER,
            payload = gson.toJson(payload)
        )

        val parsed = offlineQueue.parsePayload(operation) as ShareFolderPayload

        assertEquals("folder-1", parsed.folderId)
        assertEquals("user-3", parsed.recipientId)
        assertEquals("admin", parsed.permission)
    }

    // ==================== Helpers ====================

    private fun createTestOperation(
        id: String = "op-test",
        type: OperationType = OperationType.DELETE_FILE,
        status: OperationStatus = OperationStatus.PENDING,
        payload: String = """{"fileId":"file-1"}"""
    ) = PendingOperationEntity(
        id = id,
        operationType = type,
        resourceType = ResourceType.FILE,
        resourceId = "file-1",
        parentId = null,
        payload = payload,
        status = status,
        priority = 5
    )
}
