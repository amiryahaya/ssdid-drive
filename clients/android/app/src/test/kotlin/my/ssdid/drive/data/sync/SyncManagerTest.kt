package my.ssdid.drive.data.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import my.ssdid.drive.data.local.entity.OperationStatus
import my.ssdid.drive.data.local.entity.OperationType
import my.ssdid.drive.data.local.entity.PendingOperationEntity
import my.ssdid.drive.data.local.entity.ResourceType
import app.cash.turbine.test
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SyncManagerTest {

    private lateinit var context: Context
    private lateinit var offlineQueue: OfflineQueue
    private lateinit var networkMonitor: NetworkMonitor
    private lateinit var workManager: WorkManager

    private val isConnectedFlow = MutableStateFlow(true)

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        offlineQueue = mockk(relaxed = true)
        networkMonitor = mockk(relaxed = true)
        workManager = mockk(relaxed = true)

        // Mock the static WorkManager.getInstance
        mockkStatic(WorkManager::class)
        every { WorkManager.getInstance(any()) } returns workManager

        // Mock Constraints.Builder to avoid NPE on Android SDK fluent builder chain.
        // With unitTests.isReturnDefaultValues = true, fluent builder methods return null,
        // breaking the chained calls.
        val mockConstraints = mockk<Constraints>(relaxed = true)
        mockkConstructor(Constraints.Builder::class)
        every { anyConstructed<Constraints.Builder>().setRequiredNetworkType(any()) } answers { self as Constraints.Builder }
        every { anyConstructed<Constraints.Builder>().build() } returns mockConstraints

        // Mock OneTimeWorkRequest.Builder to avoid NPE on fluent builder chain
        val mockOneTimeWorkRequest = mockk<OneTimeWorkRequest>(relaxed = true)
        mockkConstructor(OneTimeWorkRequest.Builder::class)
        every { anyConstructed<OneTimeWorkRequest.Builder>().setConstraints(any()) } answers { self as OneTimeWorkRequest.Builder }
        every { anyConstructed<OneTimeWorkRequest.Builder>().setExpedited(any()) } answers { self as OneTimeWorkRequest.Builder }
        every { anyConstructed<OneTimeWorkRequest.Builder>().addTag(any()) } answers { self as OneTimeWorkRequest.Builder }
        every { anyConstructed<OneTimeWorkRequest.Builder>().build() } returns mockOneTimeWorkRequest

        // Mock PeriodicWorkRequest.Builder to avoid NPE on fluent builder chain
        val mockPeriodicWorkRequest = mockk<PeriodicWorkRequest>(relaxed = true)
        mockkConstructor(PeriodicWorkRequest.Builder::class)
        every { anyConstructed<PeriodicWorkRequest.Builder>().setConstraints(any()) } answers { self as PeriodicWorkRequest.Builder }
        every { anyConstructed<PeriodicWorkRequest.Builder>().setBackoffCriteria(any(), any<Long>(), any()) } answers { self as PeriodicWorkRequest.Builder }
        every { anyConstructed<PeriodicWorkRequest.Builder>().addTag(any()) } answers { self as PeriodicWorkRequest.Builder }
        every { anyConstructed<PeriodicWorkRequest.Builder>().build() } returns mockPeriodicWorkRequest

        // Default network state
        every { networkMonitor.isConnected } returns isConnectedFlow
        every { networkMonitor.isNetworkAvailable() } returns true

        // Default queue flows
        every { offlineQueue.observePendingCount() } returns flowOf(0)
        every { offlineQueue.observeActiveOperations() } returns flowOf(emptyList())
        every { offlineQueue.observePendingUploads() } returns flowOf(emptyList())
        every { offlineQueue.observeFailedOperations() } returns flowOf(emptyList())
    }

    @After
    fun tearDown() {
        unmockkStatic(WorkManager::class)
        unmockkConstructor(Constraints.Builder::class)
        unmockkConstructor(OneTimeWorkRequest.Builder::class)
        unmockkConstructor(PeriodicWorkRequest.Builder::class)
        unmockkAll()
    }

    private fun createSyncManager(): SyncManager {
        return SyncManager(context, offlineQueue, networkMonitor)
    }

    // ==================== Sync Triggering Tests ====================

    @Test
    fun `triggerSync enqueues work when network is available`() {
        val syncManager = createSyncManager()

        syncManager.triggerSync()

        verify { workManager.enqueueUniqueWork(eq(SyncManager.SYNC_WORK_NAME), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>()) }
        assertEquals(SyncState.SYNCING, syncManager.syncState.value)
    }

    @Test
    fun `triggerSync sets WAITING_FOR_NETWORK when offline`() {
        every { networkMonitor.isNetworkAvailable() } returns false
        val syncManager = createSyncManager()

        syncManager.triggerSync()

        assertEquals(SyncState.WAITING_FOR_NETWORK, syncManager.syncState.value)
    }

    @Test
    fun `schedulePeriodicSync enqueues periodic work`() {
        val syncManager = createSyncManager()

        syncManager.schedulePeriodicSync()

        verify { workManager.enqueueUniquePeriodicWork(eq(SyncManager.PERIODIC_SYNC_WORK_NAME), any(), any()) }
    }

    @Test
    fun `cancelPeriodicSync cancels periodic work by name`() {
        val syncManager = createSyncManager()

        syncManager.cancelPeriodicSync()

        verify { workManager.cancelUniqueWork(SyncManager.PERIODIC_SYNC_WORK_NAME) }
    }

    @Test
    fun `cancelAllSync cancels by tag and resets state to IDLE`() {
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false
        val syncManager = createSyncManager()
        syncManager.triggerSync() // set to SYNCING

        syncManager.cancelAllSync()

        verify { workManager.cancelAllWorkByTag(SyncManager.SYNC_TAG) }
        assertEquals(SyncState.IDLE, syncManager.syncState.value)
    }

    // ==================== Sync Status Reporting Tests ====================

    @Test
    fun `reportSyncStarted sets state to SYNCING`() {
        val syncManager = createSyncManager()

        syncManager.reportSyncStarted()

        assertEquals(SyncState.SYNCING, syncManager.syncState.value)
    }

    @Test
    fun `reportSyncCompleted sets state to IDLE and updates last sync time`() {
        val syncManager = createSyncManager()
        syncManager.reportSyncStarted()

        syncManager.reportSyncCompleted()

        assertEquals(SyncState.IDLE, syncManager.syncState.value)
        assertNotNull(syncManager.lastSyncTime.value)
    }

    @Test
    fun `reportSyncFailed sets state to ERROR`() {
        val syncManager = createSyncManager()
        syncManager.reportSyncStarted()

        syncManager.reportSyncFailed("something broke")

        assertEquals(SyncState.ERROR, syncManager.syncState.value)
    }

    // ==================== Sync State Flow Tests ====================

    @Test
    fun `syncState initial value is IDLE`() {
        // Start disconnected so the init block does not auto-trigger sync
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false

        val syncManager = createSyncManager()

        assertEquals(SyncState.IDLE, syncManager.syncState.value)
    }

    @Test
    fun `lastSyncTime is initially null`() {
        val syncManager = createSyncManager()

        assertNull(syncManager.lastSyncTime.value)
    }

    // ==================== Observation Delegation Tests ====================

    @Test
    fun `observePendingCount delegates to offlineQueue`() {
        val countFlow = flowOf(3)
        every { offlineQueue.observePendingCount() } returns countFlow

        val syncManager = createSyncManager()

        assertEquals(countFlow, syncManager.observePendingCount())
    }

    @Test
    fun `observeActiveOperations delegates to offlineQueue`() {
        val ops = listOf(createTestOperation())
        val opsFlow = flowOf(ops)
        every { offlineQueue.observeActiveOperations() } returns opsFlow

        val syncManager = createSyncManager()

        assertEquals(opsFlow, syncManager.observeActiveOperations())
    }

    @Test
    fun `observePendingUploads delegates to offlineQueue`() {
        val uploadsFlow = flowOf(listOf(createTestOperation(type = OperationType.UPLOAD_FILE)))
        every { offlineQueue.observePendingUploads() } returns uploadsFlow

        val syncManager = createSyncManager()

        assertEquals(uploadsFlow, syncManager.observePendingUploads())
    }

    @Test
    fun `observeFailedOperations delegates to offlineQueue`() {
        val failedFlow = flowOf(listOf(createTestOperation(status = OperationStatus.FAILED)))
        every { offlineQueue.observeFailedOperations() } returns failedFlow

        val syncManager = createSyncManager()

        assertEquals(failedFlow, syncManager.observeFailedOperations())
    }

    // ==================== Combined Sync Status Tests ====================

    @Test
    fun `observeSyncStatus combines state, pending count, and connectivity`() = runBlocking {
        every { offlineQueue.observePendingCount() } returns flowOf(3)
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false
        val syncManager = createSyncManager()
        isConnectedFlow.value = true

        syncManager.observeSyncStatus().test {
            val status = awaitItem()
            assertEquals(3, status.pendingCount)
            assertTrue(status.isOnline)
            assertTrue(status.hasPendingOperations)
            cancelAndConsumeRemainingEvents()
        }
    }

    @Test
    fun `SyncStatus needsSync is true when has pending ops and online and not syncing`() {
        val status = SyncStatus(
            state = SyncState.IDLE,
            pendingCount = 2,
            isOnline = true
        )

        assertTrue(status.needsSync)
        assertTrue(status.hasPendingOperations)
        assertFalse(status.isSyncing)
    }

    @Test
    fun `SyncStatus needsSync is false when already syncing`() {
        val status = SyncStatus(
            state = SyncState.SYNCING,
            pendingCount = 2,
            isOnline = true
        )

        assertFalse(status.needsSync)
        assertTrue(status.isSyncing)
    }

    @Test
    fun `SyncStatus needsSync is false when offline`() {
        val status = SyncStatus(
            state = SyncState.IDLE,
            pendingCount = 2,
            isOnline = false
        )

        assertFalse(status.needsSync)
    }

    @Test
    fun `SyncStatus needsSync is false when no pending operations`() {
        val status = SyncStatus(
            state = SyncState.IDLE,
            pendingCount = 0,
            isOnline = true
        )

        assertFalse(status.needsSync)
        assertFalse(status.hasPendingOperations)
    }

    // ==================== Operation Management Tests ====================

    @Test
    fun `retryOperation resets operation and triggers sync`() = runBlocking {
        // Start disconnected to prevent init block from auto-triggering sync
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false
        val syncManager = createSyncManager()

        // Re-enable network for the retryOperation call
        every { networkMonitor.isNetworkAvailable() } returns true

        syncManager.retryOperation("op-1")

        coVerify { offlineQueue.retryOperation("op-1") }
        verify { workManager.enqueueUniqueWork(eq(SyncManager.SYNC_WORK_NAME), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>()) }
    }

    @Test
    fun `retryAllFailed retries each failed operation and triggers sync`() = runBlocking {
        // Start disconnected to prevent init block from auto-triggering sync
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false

        val failedOps = listOf(
            createTestOperation(id = "op-1", status = OperationStatus.FAILED),
            createTestOperation(id = "op-2", status = OperationStatus.FAILED)
        )
        coEvery { offlineQueue.getRetryableOperations() } returns failedOps

        val syncManager = createSyncManager()

        // Re-enable network for retryAllFailed
        every { networkMonitor.isNetworkAvailable() } returns true
        syncManager.retryAllFailed()

        coVerify { offlineQueue.retryOperation("op-1") }
        coVerify { offlineQueue.retryOperation("op-2") }
        verify { workManager.enqueueUniqueWork(eq(SyncManager.SYNC_WORK_NAME), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>()) }
    }

    @Test
    fun `retryAllFailed triggers sync even when no failed operations`() = runBlocking {
        // Start disconnected to prevent init block from auto-triggering sync
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false

        coEvery { offlineQueue.getRetryableOperations() } returns emptyList()

        val syncManager = createSyncManager()

        // Re-enable network for retryAllFailed
        every { networkMonitor.isNetworkAvailable() } returns true
        syncManager.retryAllFailed()

        coVerify(exactly = 0) { offlineQueue.retryOperation(any()) }
        // triggerSync is still called
        verify { workManager.enqueueUniqueWork(eq(SyncManager.SYNC_WORK_NAME), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>()) }
    }

    @Test
    fun `cancelOperation delegates to offlineQueue`() = runBlocking {
        // Start disconnected to prevent init block from auto-triggering sync
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false
        val syncManager = createSyncManager()

        syncManager.cancelOperation("op-1")

        coVerify { offlineQueue.cancelOperation("op-1") }
    }

    @Test
    fun `cleanup calls cleanupCompleted and cleanupCancelled`() = runBlocking {
        // Start disconnected to prevent init block from auto-triggering sync
        isConnectedFlow.value = false
        every { networkMonitor.isNetworkAvailable() } returns false
        val syncManager = createSyncManager()

        syncManager.cleanup()

        coVerify { offlineQueue.cleanupCompleted(any()) }
        coVerify { offlineQueue.cleanupCancelled() }
    }

    // ==================== Init Behavior Tests ====================

    @Test
    fun `init resets interrupted operations`() {
        createSyncManager()

        coVerify(timeout = 1000) { offlineQueue.resetInterruptedOperations() }
    }

    // ==================== Companion Object Tests ====================

    @Test
    fun `companion constants have expected values`() {
        assertEquals("ssdid_drive_sync", SyncManager.SYNC_WORK_NAME)
        assertEquals("ssdid_drive_periodic_sync", SyncManager.PERIODIC_SYNC_WORK_NAME)
        assertEquals("sync", SyncManager.SYNC_TAG)
    }

    // ==================== Helpers ====================

    private fun createTestOperation(
        id: String = "op-test",
        type: OperationType = OperationType.DELETE_FILE,
        status: OperationStatus = OperationStatus.PENDING
    ) = PendingOperationEntity(
        id = id,
        operationType = type,
        resourceType = ResourceType.FILE,
        resourceId = "file-1",
        parentId = null,
        payload = """{"fileId":"file-1"}""",
        status = status,
        priority = 5
    )
}
