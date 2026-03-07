package com.securesharing.util

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Security utilities for device integrity checks.
 *
 * SECURITY: Provides detection for rooted devices and emulators.
 * These checks help protect sensitive cryptographic operations
 * from potentially compromised environments.
 *
 * Note: These checks are not foolproof and can be bypassed by
 * sophisticated attackers. They provide defense-in-depth.
 */
@Singleton
class SecurityUtils @Inject constructor(
    @ApplicationContext private val context: Context
) {
    /**
     * Comprehensive device security check.
     * Returns a SecurityStatus with details about detected issues.
     */
    fun checkDeviceSecurity(): SecurityStatus {
        val issues = mutableListOf<SecurityIssue>()

        // Check for root
        val rootCheck = checkForRoot()
        if (rootCheck.isRooted) {
            issues.add(SecurityIssue.ROOT_DETECTED)
        }

        // Check for emulator (only flag in release builds)
        if (!com.securesharing.BuildConfig.DEBUG) {
            val emulatorCheck = checkForEmulator()
            if (emulatorCheck.isEmulator) {
                issues.add(SecurityIssue.EMULATOR_DETECTED)
            }
        }

        // Check for hooking frameworks (Frida, Xposed, etc.)
        val hookingCheck = checkForHookingFrameworks()
        if (hookingCheck.isHooked) {
            issues.add(SecurityIssue.HOOKING_FRAMEWORK_DETECTED)
        }

        // Check for debugging
        if (isDebuggingEnabled()) {
            issues.add(SecurityIssue.DEBUGGING_ENABLED)
        }

        // Check for test keys (non-production ROM)
        if (isTestKeysBuild()) {
            issues.add(SecurityIssue.TEST_KEYS_BUILD)
        }

        // Check for dangerous apps
        val dangerousApps = checkForDangerousApps()
        if (dangerousApps.isNotEmpty()) {
            issues.add(SecurityIssue.DANGEROUS_APPS_INSTALLED)
        }

        return SecurityStatus(
            isSecure = issues.isEmpty(),
            issues = issues,
            rootDetails = rootCheck,
            emulatorDetails = checkForEmulator(),
            hookingDetails = hookingCheck,
            dangerousApps = dangerousApps
        )
    }

    /**
     * Quick check if device appears to be rooted.
     */
    fun isDeviceRooted(): Boolean = checkForRoot().isRooted

    /**
     * Quick check if running on emulator.
     */
    fun isEmulator(): Boolean = checkForEmulator().isEmulator

    // ==================== Root Detection ====================

    /**
     * Comprehensive root detection.
     */
    fun checkForRoot(): RootCheckResult {
        val detectionMethods = mutableListOf<String>()

        // Check for su binary in common locations
        if (checkForSuBinary()) {
            detectionMethods.add("su binary found")
        }

        // Check for root management apps
        if (checkForRootManagementApps()) {
            detectionMethods.add("Root management app installed")
        }

        // Check for potentially dangerous props
        if (checkForDangerousProps()) {
            detectionMethods.add("Dangerous build props detected")
        }

        // Check for RW system partition
        if (checkForRWSystem()) {
            detectionMethods.add("System partition is read-write")
        }

        // Check for Magisk
        if (checkForMagisk()) {
            detectionMethods.add("Magisk detected")
        }

        // Check for busybox
        if (checkForBusybox()) {
            detectionMethods.add("Busybox installed")
        }

        return RootCheckResult(
            isRooted = detectionMethods.isNotEmpty(),
            detectionMethods = detectionMethods
        )
    }

    private fun checkForSuBinary(): Boolean {
        val paths = listOf(
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/system/su",
            "/system/bin/.ext/.su",
            "/system/usr/we-need-root/su-backup",
            "/system/xbin/mu",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/data/local/su",
            "/su/bin/su",
            "/su/bin",
            "/magisk/.core/bin/su"
        )
        return paths.any { File(it).exists() }
    }

    private fun checkForRootManagementApps(): Boolean {
        val rootApps = listOf(
            "com.noshufou.android.su",
            "com.noshufou.android.su.elite",
            "eu.chainfire.supersu",
            "com.koushikdutta.superuser",
            "com.thirdparty.superuser",
            "com.yellowes.su",
            "com.topjohnwu.magisk",
            "me.phh.superuser",
            "com.kingouser.com",
            "com.kingroot.kinguser",
            "com.smedialink.oneclickroot",
            "com.zhiqupk.root.global"
        )

        val pm = context.packageManager
        return rootApps.any { packageName ->
            try {
                pm.getPackageInfo(packageName, 0)
                true
            } catch (e: PackageManager.NameNotFoundException) {
                false
            }
        }
    }

    private fun checkForDangerousProps(): Boolean {
        val dangerousProps = mapOf(
            "ro.debuggable" to "1",
            "ro.secure" to "0"
        )

        return dangerousProps.any { (prop, dangerousValue) ->
            try {
                val value = Runtime.getRuntime()
                    .exec("getprop $prop")
                    .inputStream
                    .bufferedReader()
                    .readLine()
                    ?.trim()
                value == dangerousValue
            } catch (e: Exception) {
                false
            }
        }
    }

    private fun checkForRWSystem(): Boolean {
        return try {
            val mounts = File("/proc/mounts").readText()
            mounts.contains("/system") && mounts.contains("rw,")
        } catch (e: Exception) {
            false
        }
    }

    private fun checkForMagisk(): Boolean {
        val magiskPaths = listOf(
            "/sbin/.magisk",
            "/sbin/.core",
            "/data/adb/magisk",
            "/data/adb/modules"
        )
        return magiskPaths.any { File(it).exists() }
    }

    private fun checkForBusybox(): Boolean {
        val paths = listOf(
            "/system/xbin/busybox",
            "/system/bin/busybox",
            "/sbin/busybox",
            "/data/local/bin/busybox"
        )
        return paths.any { File(it).exists() }
    }

    // ==================== Emulator Detection ====================

    /**
     * Comprehensive emulator detection.
     */
    fun checkForEmulator(): EmulatorCheckResult {
        val indicators = mutableListOf<String>()

        // Check Build properties
        if (checkBuildProperties()) {
            indicators.add("Suspicious build properties")
        }

        // Check for emulator-specific files
        if (checkEmulatorFiles()) {
            indicators.add("Emulator files detected")
        }

        // Check hardware properties
        if (checkHardwareProperties()) {
            indicators.add("Emulator hardware detected")
        }

        // Check for QEMU
        if (checkForQemu()) {
            indicators.add("QEMU detected")
        }

        // Check telephony
        if (checkTelephonyProperties()) {
            indicators.add("Emulator telephony properties")
        }

        return EmulatorCheckResult(
            isEmulator = indicators.isNotEmpty(),
            indicators = indicators
        )
    }

    private fun checkBuildProperties(): Boolean {
        val suspiciousProps = listOf(
            Build.FINGERPRINT.startsWith("generic"),
            Build.FINGERPRINT.startsWith("unknown"),
            Build.MODEL.contains("google_sdk"),
            Build.MODEL.contains("Emulator"),
            Build.MODEL.contains("Android SDK built for x86"),
            Build.MODEL.lowercase().contains("sdk"),
            Build.MANUFACTURER.contains("Genymotion"),
            Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"),
            Build.PRODUCT.contains("sdk"),
            Build.PRODUCT.contains("google_sdk"),
            Build.PRODUCT.contains("sdk_x86"),
            Build.PRODUCT.contains("vbox86p"),
            Build.PRODUCT.contains("emulator"),
            Build.PRODUCT.contains("simulator"),
            Build.HARDWARE.contains("goldfish"),
            Build.HARDWARE.contains("ranchu"),
            Build.BOARD.lowercase().contains("nox"),
            Build.BOOTLOADER.lowercase().contains("nox"),
            Build.HARDWARE.lowercase().contains("nox"),
            Build.SERIAL == "unknown" || Build.SERIAL == "android"
        )

        return suspiciousProps.any { it }
    }

    private fun checkEmulatorFiles(): Boolean {
        val emulatorFiles = listOf(
            "/dev/socket/qemud",
            "/dev/qemu_pipe",
            "/system/lib/libc_malloc_debug_qemu.so",
            "/sys/qemu_trace",
            "/system/bin/qemu-props",
            "/dev/socket/genyd",
            "/dev/socket/baseband_genyd"
        )
        return emulatorFiles.any { File(it).exists() }
    }

    private fun checkHardwareProperties(): Boolean {
        val hardware = Build.HARDWARE.lowercase()
        val emulatorHardware = listOf(
            "goldfish",
            "ranchu",
            "vbox86",
            "nox"
        )
        return emulatorHardware.any { hardware.contains(it) }
    }

    private fun checkForQemu(): Boolean {
        return try {
            val cpuInfo = File("/proc/cpuinfo").readText()
            cpuInfo.contains("QEMU") || cpuInfo.contains("Goldfish")
        } catch (e: Exception) {
            false
        }
    }

    private fun checkTelephonyProperties(): Boolean {
        return try {
            val phoneNumber = "15555215554" // Default emulator phone number
            // Would need TelephonyManager permission to fully check
            Build.DEVICE?.contains("generic") == true
        } catch (e: Exception) {
            false
        }
    }

    // ==================== Runtime Hooking Detection ====================

    /**
     * Comprehensive runtime hooking framework detection.
     * Detects Frida, Xposed, and other instrumentation tools.
     */
    fun checkForHookingFrameworks(): HookingCheckResult {
        val detectedFrameworks = mutableListOf<String>()

        // Check for Frida
        if (detectFridaServer()) {
            detectedFrameworks.add("Frida server detected (port scan)")
        }
        if (detectFridaGadget()) {
            detectedFrameworks.add("Frida gadget detected (memory)")
        }
        if (detectFridaLibraries()) {
            detectedFrameworks.add("Frida libraries detected")
        }

        // Check for Xposed at runtime
        if (detectXposedRuntime()) {
            detectedFrameworks.add("Xposed runtime hooks detected")
        }

        // Check for suspicious native libraries
        if (detectSuspiciousNativeLibraries()) {
            detectedFrameworks.add("Suspicious native libraries detected")
        }

        // Check for debugger attached
        if (detectDebuggerAttached()) {
            detectedFrameworks.add("Debugger attached")
        }

        return HookingCheckResult(
            isHooked = detectedFrameworks.isNotEmpty(),
            detectedFrameworks = detectedFrameworks
        )
    }

    /**
     * Detect Frida server by checking default ports.
     * Frida typically listens on port 27042.
     */
    private fun detectFridaServer(): Boolean {
        val fridaPorts = listOf(27042, 27043, 27044, 27045)

        return fridaPorts.any { port ->
            try {
                java.net.Socket().use { socket ->
                    socket.connect(java.net.InetSocketAddress("127.0.0.1", port), 100)
                    true
                }
            } catch (e: Exception) {
                false
            }
        }
    }

    /**
     * Detect Frida gadget by scanning /proc/self/maps for suspicious libraries.
     */
    private fun detectFridaGadget(): Boolean {
        return try {
            val mapsFile = File("/proc/self/maps")
            if (!mapsFile.exists()) return false

            val suspiciousPatterns = listOf(
                "frida",
                "gadget",
                "agent",
                "linjector"
            )

            mapsFile.readLines().any { line ->
                val lowerLine = line.lowercase()
                suspiciousPatterns.any { pattern -> lowerLine.contains(pattern) }
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Detect Frida-related libraries in common locations.
     */
    private fun detectFridaLibraries(): Boolean {
        val fridaLibraries = listOf(
            "/data/local/tmp/frida-server",
            "/data/local/tmp/re.frida.server",
            "/data/local/tmp/frida-agent.so",
            "/data/local/tmp/frida-gadget.so"
        )

        // Also check in app's private directory
        val appDataDir = context.applicationInfo.dataDir
        val appFridaFiles = listOf(
            "$appDataDir/frida",
            "$appDataDir/libfrida-gadget.so"
        )

        return (fridaLibraries + appFridaFiles).any { File(it).exists() }
    }

    /**
     * Detect Xposed framework at runtime by checking for hooks.
     */
    private fun detectXposedRuntime(): Boolean {
        // Check for Xposed-related stack trace elements
        val stackTrace = Thread.currentThread().stackTrace
        val xposedClasses = listOf(
            "de.robv.android.xposed",
            "com.android.internal.os.ZygoteInit",
            "com.saurik.substrate",
            "EdXposed",
            "LSPosed"
        )

        val hasXposedInStack = stackTrace.any { element ->
            xposedClasses.any { xposedClass ->
                element.className.contains(xposedClass, ignoreCase = true)
            }
        }

        if (hasXposedInStack) return true

        // Check for Xposed native methods
        return try {
            val xposedBridge = Class.forName("de.robv.android.xposed.XposedBridge")
            true
        } catch (e: ClassNotFoundException) {
            // Also check for EdXposed and LSPosed
            try {
                Class.forName("org.lsposed.lspd.core.Main")
                true
            } catch (e2: ClassNotFoundException) {
                false
            }
        }
    }

    /**
     * Detect suspicious native libraries loaded in process memory.
     */
    private fun detectSuspiciousNativeLibraries(): Boolean {
        return try {
            val mapsFile = File("/proc/self/maps")
            if (!mapsFile.exists()) return false

            val suspiciousLibs = listOf(
                "substrate",
                "xposed",
                "edxposed",
                "lsposed",
                "riru",
                "zygisk",
                "magisk",
                "inject"
            )

            mapsFile.readLines().any { line ->
                val lowerLine = line.lowercase()
                suspiciousLibs.any { lib ->
                    lowerLine.contains(lib) && lowerLine.contains(".so")
                }
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Detect if a debugger is currently attached.
     */
    private fun detectDebuggerAttached(): Boolean {
        // Check Android's Debug class
        if (android.os.Debug.isDebuggerConnected()) {
            return true
        }

        // Check TracerPid in /proc/self/status
        return try {
            val statusFile = File("/proc/self/status")
            if (!statusFile.exists()) return false

            statusFile.readLines().any { line ->
                if (line.startsWith("TracerPid:")) {
                    val tracerPid = line.substringAfter(":").trim()
                    tracerPid != "0"
                } else {
                    false
                }
            }
        } catch (e: Exception) {
            false
        }
    }

    // ==================== Other Security Checks ====================

    private fun isDebuggingEnabled(): Boolean {
        return Settings.Global.getInt(
            context.contentResolver,
            Settings.Global.ADB_ENABLED,
            0
        ) == 1
    }

    private fun isTestKeysBuild(): Boolean {
        return Build.TAGS?.contains("test-keys") == true
    }

    private fun checkForDangerousApps(): List<String> {
        val dangerousApps = listOf(
            "com.saurik.substrate" to "Cydia Substrate",
            "de.robv.android.xposed.installer" to "Xposed Framework",
            "de.robv.android.xposed" to "Xposed Framework",
            "org.meowcat.edxposed.manager" to "EdXposed Manager",
            "org.lsposed.manager" to "LSPosed Manager",
            "com.android.vending.billing.InAppBillingService.LUCK" to "Lucky Patcher",
            "com.chelpus.lackypatch" to "Lucky Patcher",
            "com.ramdroid.appquarantine" to "App Quarantine",
            "com.formyhm.hideroot" to "Hide Root",
            "com.devadvance.rootcloak" to "RootCloak",
            "com.devadvance.rootcloakplus" to "RootCloak Plus",
            "com.topjohnwu.magisk" to "Magisk Manager",
            "io.github.vvb2060.magisk" to "Magisk Alpha"
        )

        val pm = context.packageManager
        return dangerousApps.mapNotNull { (packageName, appName) ->
            try {
                pm.getPackageInfo(packageName, 0)
                appName
            } catch (e: PackageManager.NameNotFoundException) {
                null
            }
        }
    }
}

/**
 * Overall security status of the device.
 */
data class SecurityStatus(
    val isSecure: Boolean,
    val issues: List<SecurityIssue>,
    val rootDetails: RootCheckResult,
    val emulatorDetails: EmulatorCheckResult,
    val hookingDetails: HookingCheckResult,
    val dangerousApps: List<String>
) {
    val hasHighRiskIssues: Boolean
        get() = issues.any { it.riskLevel == RiskLevel.HIGH }

    val hasMediumRiskIssues: Boolean
        get() = issues.any { it.riskLevel == RiskLevel.MEDIUM }
}

/**
 * Result of root detection check.
 */
data class RootCheckResult(
    val isRooted: Boolean,
    val detectionMethods: List<String>
)

/**
 * Result of emulator detection check.
 */
data class EmulatorCheckResult(
    val isEmulator: Boolean,
    val indicators: List<String>
)

/**
 * Result of hooking framework detection check.
 */
data class HookingCheckResult(
    val isHooked: Boolean,
    val detectedFrameworks: List<String>
)

/**
 * Security issues that can be detected.
 */
enum class SecurityIssue(val riskLevel: RiskLevel, val description: String) {
    ROOT_DETECTED(RiskLevel.HIGH, "Device appears to be rooted"),
    EMULATOR_DETECTED(RiskLevel.MEDIUM, "Running on an emulator"),
    HOOKING_FRAMEWORK_DETECTED(RiskLevel.HIGH, "Runtime hooking framework detected (Frida/Xposed)"),
    DEBUGGING_ENABLED(RiskLevel.LOW, "USB debugging is enabled"),
    TEST_KEYS_BUILD(RiskLevel.MEDIUM, "Non-production ROM detected"),
    DANGEROUS_APPS_INSTALLED(RiskLevel.HIGH, "Potentially dangerous apps installed")
}

/**
 * Risk level for security issues.
 */
enum class RiskLevel {
    LOW,
    MEDIUM,
    HIGH
}
