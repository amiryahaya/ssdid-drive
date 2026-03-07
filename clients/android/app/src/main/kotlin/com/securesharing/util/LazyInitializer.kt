package com.securesharing.util

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.properties.ReadOnlyProperty
import kotlin.reflect.KProperty

/**
 * Thread-safe lazy initializer with background preloading support.
 *
 * Use this for heavy components that should be initialized:
 * - Lazily on first access, OR
 * - In the background during app startup
 *
 * Example:
 * ```
 * val heavyComponent by lazyInit { ExpensiveComponent() }
 *
 * // Optionally preload in background
 * scope.launch { heavyComponent.preload() }
 * ```
 */
class LazyInitializer<T>(
    private val initializer: () -> T
) : ReadOnlyProperty<Any?, T> {

    @Volatile
    private var _value: T? = null
    private val mutex = Mutex()
    private val initialized = AtomicBoolean(false)

    val isInitialized: Boolean get() = initialized.get()

    override fun getValue(thisRef: Any?, property: KProperty<*>): T {
        // Fast path - already initialized
        _value?.let { return it }

        // Slow path - need to initialize
        return kotlinx.coroutines.runBlocking {
            mutex.withLock {
                // Double-check
                _value?.let { return@runBlocking it }

                val newValue = initializer()
                _value = newValue
                initialized.set(true)
                newValue
            }
        }
    }

    /**
     * Get the value without blocking, returns null if not yet initialized.
     */
    fun getOrNull(): T? = _value

    /**
     * Preload the value in the current coroutine context.
     * Safe to call multiple times.
     */
    suspend fun preload(): T {
        _value?.let { return it }

        return mutex.withLock {
            _value?.let { return@withLock it }

            val newValue = initializer()
            _value = newValue
            initialized.set(true)
            newValue
        }
    }
}

/**
 * Create a lazy initializer for a heavy component.
 */
fun <T> lazyInit(initializer: () -> T): LazyInitializer<T> {
    return LazyInitializer(initializer)
}

/**
 * Background preloader for lazy components.
 *
 * Use this to preload heavy components during app startup or screen transitions.
 */
object BackgroundPreloader {

    private val scope = CoroutineScope(Dispatchers.Default)
    private val preloadTasks = mutableListOf<suspend () -> Unit>()

    /**
     * Register a lazy initializer for background preloading.
     */
    fun <T> register(initializer: LazyInitializer<T>) {
        preloadTasks.add { initializer.preload() }
    }

    /**
     * Start preloading all registered components in the background.
     * Call this after the app's critical path is complete.
     */
    fun preloadAll() {
        scope.launch {
            preloadTasks.forEach { task ->
                try {
                    task()
                } catch (e: Exception) {
                    // Log but don't fail - preloading is best-effort
                    android.util.Log.w("BackgroundPreloader", "Preload failed", e)
                }
            }
        }
    }

    /**
     * Clear all registered preload tasks.
     */
    fun clear() {
        preloadTasks.clear()
    }
}

/**
 * Lazy singleton with optional background preloading.
 *
 * Example:
 * ```
 * object ExpensiveService : LazySingleton<ExpensiveServiceImpl>({ ExpensiveServiceImpl() }) {
 *     init { registerForPreload() }
 * }
 *
 * // Usage
 * val service = ExpensiveService.instance
 * ```
 */
abstract class LazySingleton<T>(initializer: () -> T) {

    private val lazyInitializer = LazyInitializer(initializer)

    val instance: T by lazyInitializer

    val isInitialized: Boolean get() = lazyInitializer.isInitialized

    fun getOrNull(): T? = lazyInitializer.getOrNull()

    suspend fun preload(): T = lazyInitializer.preload()

    protected fun registerForPreload() {
        BackgroundPreloader.register(lazyInitializer)
    }
}
