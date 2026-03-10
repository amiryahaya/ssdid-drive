package my.ssdid.drive.data.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class NetworkMonitorTest {

    private lateinit var context: Context
    private lateinit var connectivityManager: ConnectivityManager
    private lateinit var network: Network
    private lateinit var networkCapabilities: NetworkCapabilities
    private lateinit var mockNetworkRequestBuilder: NetworkRequest.Builder
    private lateinit var mockNetworkRequest: NetworkRequest

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        connectivityManager = mockk(relaxed = true)
        network = mockk(relaxed = true)
        networkCapabilities = mockk(relaxed = true)
        mockNetworkRequest = mockk(relaxed = true)

        every { context.getSystemService(Context.CONNECTIVITY_SERVICE) } returns connectivityManager

        // Mock NetworkRequest.Builder to avoid NPE in unit tests.
        // Android SDK methods return null by default (isReturnDefaultValues = true),
        // which breaks the fluent builder chain.
        mockNetworkRequestBuilder = mockk(relaxed = true)
        every { mockNetworkRequestBuilder.addCapability(any()) } returns mockNetworkRequestBuilder
        every { mockNetworkRequestBuilder.addTransportType(any()) } returns mockNetworkRequestBuilder
        every { mockNetworkRequestBuilder.build() } returns mockNetworkRequest
        mockkConstructor(NetworkRequest.Builder::class)
        every { anyConstructed<NetworkRequest.Builder>().addCapability(any()) } returns mockNetworkRequestBuilder
        every { anyConstructed<NetworkRequest.Builder>().addTransportType(any()) } returns mockNetworkRequestBuilder
        every { anyConstructed<NetworkRequest.Builder>().build() } returns mockNetworkRequest
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ==================== Initial State Tests ====================

    @Test
    fun `initial isConnected is true when network is available and validated`() {
        setupConnected()

        val monitor = createNetworkMonitor()

        assertTrue(monitor.isConnected.value)
    }

    @Test
    fun `initial isConnected is false when no active network`() {
        every { connectivityManager.activeNetwork } returns null

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isConnected.value)
    }

    @Test
    fun `initial isConnected is false when no capabilities`() {
        every { connectivityManager.activeNetwork } returns network
        every { connectivityManager.getNetworkCapabilities(network) } returns null

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isConnected.value)
    }

    @Test
    fun `initial isConnected is false when not validated`() {
        every { connectivityManager.activeNetwork } returns network
        every { connectivityManager.getNetworkCapabilities(network) } returns networkCapabilities
        every { networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns false

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isConnected.value)
    }

    // ==================== Network Type Tests ====================

    @Test
    fun `initial networkType is WIFI when connected via WiFi`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns true
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns false
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) } returns false

        val monitor = createNetworkMonitor()

        assertEquals(NetworkType.WIFI, monitor.networkType.value)
    }

    @Test
    fun `initial networkType is CELLULAR when connected via cellular`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns false
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns true
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) } returns false

        val monitor = createNetworkMonitor()

        assertEquals(NetworkType.CELLULAR, monitor.networkType.value)
    }

    @Test
    fun `initial networkType is ETHERNET when connected via ethernet`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns false
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns false
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) } returns true

        val monitor = createNetworkMonitor()

        assertEquals(NetworkType.ETHERNET, monitor.networkType.value)
    }

    @Test
    fun `initial networkType is NONE when no active network`() {
        every { connectivityManager.activeNetwork } returns null

        val monitor = createNetworkMonitor()

        assertEquals(NetworkType.NONE, monitor.networkType.value)
    }

    @Test
    fun `initial networkType is OTHER when unknown transport`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns false
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns false
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) } returns false

        val monitor = createNetworkMonitor()

        assertEquals(NetworkType.OTHER, monitor.networkType.value)
    }

    // ==================== isNetworkAvailable Tests ====================

    @Test
    fun `isNetworkAvailable returns true when connected`() {
        setupConnected()

        val monitor = createNetworkMonitor()

        assertTrue(monitor.isNetworkAvailable())
    }

    @Test
    fun `isNetworkAvailable returns false when no network`() {
        every { connectivityManager.activeNetwork } returns null

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isNetworkAvailable())
    }

    // ==================== WiFi and Cellular Check Tests ====================

    @Test
    fun `isWifiConnected returns true when on WiFi`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns true

        val monitor = createNetworkMonitor()

        assertTrue(monitor.isWifiConnected())
    }

    @Test
    fun `isWifiConnected returns false when not on WiFi`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns false

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isWifiConnected())
    }

    @Test
    fun `isWifiConnected returns false when no active network`() {
        every { connectivityManager.activeNetwork } returns null

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isWifiConnected())
    }

    @Test
    fun `isCellularConnected returns true when on cellular`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns true

        val monitor = createNetworkMonitor()

        assertTrue(monitor.isCellularConnected())
    }

    @Test
    fun `isCellularConnected returns false when not on cellular`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns false

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isCellularConnected())
    }

    @Test
    fun `isCellularConnected returns false when no active network`() {
        every { connectivityManager.activeNetwork } returns null

        val monitor = createNetworkMonitor()

        assertFalse(monitor.isCellularConnected())
    }

    // ==================== Monitoring Lifecycle Tests ====================

    @Test
    fun `startMonitoring registers network callback`() {
        setupConnected()

        createNetworkMonitor()

        verify { connectivityManager.registerNetworkCallback(any<NetworkRequest>(), any<ConnectivityManager.NetworkCallback>()) }
    }

    @Test
    fun `startMonitoring is idempotent - does not register twice`() {
        setupConnected()
        val monitor = createNetworkMonitor()

        monitor.startMonitoring() // called again

        // init already called startMonitoring once, second call should be a no-op
        verify(exactly = 1) { connectivityManager.registerNetworkCallback(any<NetworkRequest>(), any<ConnectivityManager.NetworkCallback>()) }
    }

    @Test
    fun `stopMonitoring unregisters network callback`() {
        setupConnected()
        val monitor = createNetworkMonitor()

        monitor.stopMonitoring()

        verify { connectivityManager.unregisterNetworkCallback(any<ConnectivityManager.NetworkCallback>()) }
    }

    @Test
    fun `stopMonitoring is safe to call when not monitoring`() {
        setupConnected()
        val monitor = createNetworkMonitor()
        monitor.stopMonitoring()

        // Second call should not throw
        monitor.stopMonitoring()

        // Only one unregister call
        verify(exactly = 1) { connectivityManager.unregisterNetworkCallback(any<ConnectivityManager.NetworkCallback>()) }
    }

    @Test
    fun `startMonitoring works after stopMonitoring`() {
        setupConnected()
        val monitor = createNetworkMonitor()
        monitor.stopMonitoring()

        monitor.startMonitoring()

        verify(exactly = 2) { connectivityManager.registerNetworkCallback(any<NetworkRequest>(), any<ConnectivityManager.NetworkCallback>()) }
    }

    // ==================== Callback Behavior Tests ====================

    @Test
    fun `onAvailable callback sets isConnected to true`() {
        every { connectivityManager.activeNetwork } returns null
        val callbackSlot = slot<ConnectivityManager.NetworkCallback>()
        every { connectivityManager.registerNetworkCallback(any<NetworkRequest>(), capture(callbackSlot)) } just Runs

        val monitor = createNetworkMonitor()
        assertFalse(monitor.isConnected.value)

        // Simulate network becoming available
        callbackSlot.captured.onAvailable(network)

        assertTrue(monitor.isConnected.value)
    }

    @Test
    fun `onLost callback rechecks current connectivity`() {
        setupConnected()
        val callbackSlot = slot<ConnectivityManager.NetworkCallback>()
        every { connectivityManager.registerNetworkCallback(any<NetworkRequest>(), capture(callbackSlot)) } just Runs

        val monitor = createNetworkMonitor()
        assertTrue(monitor.isConnected.value)

        // Simulate losing network - and no other network available
        every { connectivityManager.activeNetwork } returns null
        callbackSlot.captured.onLost(network)

        assertFalse(monitor.isConnected.value)
    }

    @Test
    fun `onCapabilitiesChanged updates network type`() {
        setupConnected()
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns true
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns false
        every { networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) } returns false

        val callbackSlot = slot<ConnectivityManager.NetworkCallback>()
        every { connectivityManager.registerNetworkCallback(any<NetworkRequest>(), capture(callbackSlot)) } just Runs

        val monitor = createNetworkMonitor()

        // Simulate capabilities changing to cellular
        val newCapabilities = mockk<NetworkCapabilities>()
        every { newCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } returns false
        every { newCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } returns true
        every { newCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) } returns false

        callbackSlot.captured.onCapabilitiesChanged(network, newCapabilities)

        assertEquals(NetworkType.CELLULAR, monitor.networkType.value)
    }

    // ==================== NetworkType Enum Tests ====================

    @Test
    fun `NetworkType enum contains all expected values`() {
        val values = NetworkType.values()
        assertEquals(5, values.size)
        assertTrue(values.contains(NetworkType.WIFI))
        assertTrue(values.contains(NetworkType.CELLULAR))
        assertTrue(values.contains(NetworkType.ETHERNET))
        assertTrue(values.contains(NetworkType.OTHER))
        assertTrue(values.contains(NetworkType.NONE))
    }

    // ==================== Helpers ====================

    private fun setupConnected() {
        every { connectivityManager.activeNetwork } returns network
        every { connectivityManager.getNetworkCapabilities(network) } returns networkCapabilities
        every { networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns true
        // Default to no specific transport
        every { networkCapabilities.hasTransport(any()) } returns false
    }

    private fun createNetworkMonitor(): NetworkMonitor {
        return NetworkMonitor(context)
    }
}
