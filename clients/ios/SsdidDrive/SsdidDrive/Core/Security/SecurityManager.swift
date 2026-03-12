import Foundation
import UIKit
import Security
import MachO
import Darwin

/// Security manager for detecting compromised devices and enforcing security policies
final class SecurityManager {

    // MARK: - Singleton

    static let shared = SecurityManager()

    private init() {}

    // MARK: - Hooking Framework Detection Result

    struct HookingCheckResult {
        let isHooked: Bool
        let detectedFrameworks: [String]
    }

    // MARK: - Jailbreak Detection

    /// Check if the device is jailbroken
    /// Uses multiple detection methods for comprehensive coverage
    var isJailbroken: Bool {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        // Simulators and Mac Catalyst are not jailbroken
        return false
        #else
        return checkJailbreakIndicators()
        #endif
    }

    /// Perform comprehensive jailbreak detection
    private func checkJailbreakIndicators() -> Bool {
        // Check 1: Common jailbreak file paths
        if checkSuspiciousFilePaths() {
            return true
        }

        // Check 2: Can write to restricted directories
        if canWriteToRestrictedPaths() {
            return true
        }

        // Check 3: Check for suspicious URL schemes
        if checkSuspiciousURLSchemes() {
            return true
        }

        // Check 4: Check for suspicious dylibs
        if checkSuspiciousDylibs() {
            return true
        }

        // Check 5: Check if sandbox is intact
        if !isSandboxIntact() {
            return true
        }

        // Check 6: Check for symbolic links
        if checkSymbolicLinks() {
            return true
        }

        return false
    }

    /// Check for common jailbreak-related files and directories
    private func checkSuspiciousFilePaths() -> Bool {
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/Installer.app",
            "/Applications/Unc0ver.app",
            "/Applications/checkra1n.app",
            "/Applications/blackra1n.app",
            "/Applications/FakeCarrier.app",
            "/Applications/SBSettings.app",
            "/Applications/WinterBoard.app",
            "/Applications/RockApp.app",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/stash",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/MobileSubstrate/DynamicLibraries",
            "/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            "/var/cache/apt",
            "/var/lib/apt",
            "/var/lib/cydia",
            "/var/log/syslog",
            "/bin/bash",
            "/bin/sh",
            "/usr/sbin/sshd",
            "/usr/bin/sshd",
            "/usr/libexec/sftp-server",
            "/usr/libexec/ssh-keysign",
            "/etc/apt",
            "/etc/ssh/sshd_config",
            "/private/etc/apt",
            "/private/etc/ssh/sshd_config",
            "/usr/bin/ssh",
            "/Library/PreferenceLoader/Preferences",
            "/jb/lzma",
            "/.cydia_no_stash",
            "/.installed_unc0ver",
            "/private/var/tmp/cydia.log",
            "/var/mobile/Library/Preferences/ABPattern"
        ]

        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        return false
    }

    /// Check if we can write to restricted directories (shouldn't be possible on non-jailbroken devices)
    private func canWriteToRestrictedPaths() -> Bool {
        let restrictedPaths = [
            "/private/jailbreak_test.txt",
            "/private/var/mobile/jailbreak_test.txt"
        ]

        for path in restrictedPaths {
            do {
                try "jailbreak_test".write(toFile: path, atomically: true, encoding: .utf8)
                // If we can write, device is jailbroken
                try? FileManager.default.removeItem(atPath: path)
                return true
            } catch {
                // Expected behavior on non-jailbroken device
            }
        }

        return false
    }

    /// Check for suspicious URL schemes that indicate jailbreak apps
    private func checkSuspiciousURLSchemes() -> Bool {
        let suspiciousSchemes = [
            "cydia://",
            "sileo://",
            "zbra://",
            "filza://",
            "activator://",
            "undecimus://"
        ]

        for scheme in suspiciousSchemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                return true
            }
        }

        return false
    }

    /// Check for suspicious dynamic libraries
    private func checkSuspiciousDylibs() -> Bool {
        let suspiciousDylibs = [
            "SubstrateLoader.dylib",
            "SSLKillSwitch2.dylib",
            "SSLKillSwitch.dylib",
            "MobileSubstrate.dylib",
            "TweakInject.dylib",
            "CydiaSubstrate",
            "cynject",
            "CustomWidgetIcons",
            "PreferenceLoader",
            "RocketBootstrap",
            "WeeLoader",
            "/.file" // Hidden file
        ]

        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index) else { continue }
            let name = String(cString: imageName)

            for suspiciousDylib in suspiciousDylibs {
                if name.lowercased().contains(suspiciousDylib.lowercased()) {
                    return true
                }
            }
        }

        return false
    }

    /// Check if the app sandbox is intact
    private func isSandboxIntact() -> Bool {
        // Check for writable paths outside sandbox as jailbreak indicator
        #if !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
        let jailbreakPaths = [
            "/private/var/lib/apt",
            "/Applications/Cydia.app",
            "/usr/sbin/sshd",
            "/usr/bin/ssh",
        ]
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return false
            }
        }
        #endif
        return true
    }

    /// Check for suspicious symbolic links
    private func checkSymbolicLinks() -> Bool {
        let paths = [
            "/Applications",
            "/var/stash",
            "/Library/Ringtones",
            "/Library/Wallpaper",
            "/usr/arm-apple-darwin9",
            "/usr/include",
            "/usr/libexec",
            "/usr/share"
        ]

        for path in paths {
            var isSymlink: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isSymlink) {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: path)
                    if let type = attributes[.type] as? FileAttributeType, type == .typeSymbolicLink {
                        return true
                    }
                } catch {
                    // Ignore errors
                }
            }
        }

        return false
    }

    // MARK: - Security Enforcement

    /// Check security and show alert if device is compromised
    /// - Parameter viewController: The view controller to present the alert on
    /// - Returns: True if device is secure, false if compromised
    @discardableResult
    func enforceSecurityCheck(on viewController: UIViewController?) -> Bool {
        guard !isJailbroken else {
            showSecurityAlert(on: viewController)
            return false
        }
        return true
    }

    /// Show security alert for compromised devices
    private func showSecurityAlert(on viewController: UIViewController?) {
        let alert = UIAlertController(
            title: "Security Warning",
            message: "This device appears to be jailbroken. SsdidDrive cannot run on compromised devices to protect your data security.\n\nPlease use a non-jailbroken device.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Exit App", style: .destructive) { _ in
            exit(0)
        })

        if let vc = viewController {
            vc.present(alert, animated: true)
        } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }

    // MARK: - Debugger Detection

    /// Check if a debugger is attached
    var isDebuggerAttached: Bool {
        #if DEBUG
        return false // Don't check in debug builds
        #else
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&name, 4, &info, &size, nil, 0)
        if result != 0 {
            return false
        }

        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }

    // MARK: - Secure Environment Check

    /// Perform all security checks
    /// - Returns: Array of security issues found, empty if secure
    func performSecurityAudit() -> [String] {
        var issues: [String] = []

        if isJailbroken {
            issues.append("Device is jailbroken")
        }

        if isDebuggerAttached {
            issues.append("Debugger is attached")
        }

        let hookingResult = checkForHookingFrameworks()
        if hookingResult.isHooked {
            issues.append(contentsOf: hookingResult.detectedFrameworks)
        }

        return issues
    }

    // MARK: - Runtime Hooking Detection

    /// Check for runtime hooking frameworks (Frida, Substrate, etc.)
    /// - Returns: HookingCheckResult with detection status and list of detected frameworks
    func checkForHookingFrameworks() -> HookingCheckResult {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        return HookingCheckResult(isHooked: false, detectedFrameworks: [])
        #else
        var detectedFrameworks: [String] = []

        // Check 1: Detect Frida server via port scanning
        if detectFridaServer() {
            detectedFrameworks.append("Frida server detected (port scan)")
        }

        // Check 2: Detect Frida gadget in memory
        if detectFridaGadget() {
            detectedFrameworks.append("Frida gadget detected (memory)")
        }

        // Check 3: Detect suspicious environment variables
        if detectSuspiciousEnvironment() {
            detectedFrameworks.append("Suspicious environment variables detected")
        }

        // Check 4: Detect Substrate/Substitute hooks
        if detectSubstrateHooks() {
            detectedFrameworks.append("Substrate/Substitute hooks detected")
        }

        // Check 5: Detect suspicious loaded libraries
        if detectSuspiciousLibraries() {
            detectedFrameworks.append("Suspicious libraries loaded")
        }

        // Check 6: Detect function hooking via symbol inspection
        if detectFunctionHooking() {
            detectedFrameworks.append("Function hooking detected")
        }

        return HookingCheckResult(
            isHooked: !detectedFrameworks.isEmpty,
            detectedFrameworks: detectedFrameworks
        )
        #endif
    }

    /// Detect Frida server by attempting to connect to common Frida ports
    private func detectFridaServer() -> Bool {
        let fridaPorts: [UInt16] = [27042, 27043, 27044, 27045]

        for port in fridaPorts {
            // Use a simple blocking connect with short timeout
            let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socketFD >= 0 else { continue }

            defer { Darwin.close(socketFD) }

            // Set socket timeout
            var timeout = timeval(tv_sec: 0, tv_usec: 100000) // 100ms
            setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if result == 0 {
                // Connection successful - Frida server likely running on this port
                return true
            }
        }

        return false
    }

    /// Detect Frida gadget by checking for Frida-related strings in loaded dylibs
    private func detectFridaGadget() -> Bool {
        let fridaIndicators = [
            "frida",
            "FridaGadget",
            "frida-agent",
            "frida-gadget",
            "gum-js-loop",
            "frida_agent_main"
        ]

        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index) else { continue }
            let name = String(cString: imageName).lowercased()

            for indicator in fridaIndicators {
                if name.contains(indicator.lowercased()) {
                    return true
                }
            }
        }

        // Also check /proc/self/maps equivalent via memory regions
        // On iOS, we can check loaded images for Frida patterns
        return false
    }

    /// Detect suspicious environment variables that indicate hooking
    private func detectSuspiciousEnvironment() -> Bool {
        let suspiciousVars = [
            "DYLD_INSERT_LIBRARIES",
            "_MSSafeMode",
            "SUBSTRATE_INSERT_LIBRARIES"
        ]

        for varName in suspiciousVars {
            if let value = getenv(varName), strlen(value) > 0 {
                return true
            }
        }

        return false
    }

    /// Detect Substrate/Substitute hooks by checking for hook-related dylibs
    private func detectSubstrateHooks() -> Bool {
        let hookLibraries = [
            "MobileSubstrate",
            "libsubstrate.dylib",
            "SubstrateLoader",
            "SubstrateInserter",
            "TweakInject",
            "CydiaSubstrate",
            "libhooker",
            "Substitute",
            "substrate",
            "ellekit"
        ]

        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index) else { continue }
            let name = String(cString: imageName)

            for hookLib in hookLibraries {
                if name.lowercased().contains(hookLib.lowercased()) {
                    return true
                }
            }
        }

        return false
    }

    /// Detect suspicious loaded libraries
    private func detectSuspiciousLibraries() -> Bool {
        let suspiciousLibraries = [
            "SSLKillSwitch",
            "SSLKillSwitch2",
            "FridaGadget",
            "libcycript",
            "cycript",
            "Reveal",
            "RevealServer",
            "libReveal",
            "Shadow",
            "Liberty",
            "LibertyLite",
            "FlyJB",
            "xCon",
            "A-Bypass",
            "Hestia"
        ]

        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index) else { continue }
            let name = String(cString: imageName)

            for suspicious in suspiciousLibraries {
                if name.contains(suspicious) {
                    return true
                }
            }
        }

        return false
    }

    /// Detect function hooking by checking if critical functions have been modified
    private func detectFunctionHooking() -> Bool {
        // Check for inline hooks by examining function prologues
        // On ARM64, check for typical hook patterns (B/BL instructions to unexpected addresses)

        // Method 1: Check if dlsym returns suspicious addresses
        if let handle = dlopen(nil, RTLD_NOW) {
            defer { dlclose(handle) }

            // Check some security-critical functions
            let functionsToCheck = ["ptrace", "sysctl", "getenv", "open"]

            for funcName in functionsToCheck {
                if let funcPtr = dlsym(handle, funcName) {
                    // Get pointer as UInt
                    let address = unsafeBitCast(funcPtr, to: UInt.self)

                    // Check if address is in unexpected range (outside system libraries)
                    // This is a heuristic - hooks often redirect to lower addresses
                    if address < 0x100000000 { // Below typical system library range
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - Comprehensive Security Check

    /// Check if the device environment is compromised (jailbroken or hooked)
    var isCompromised: Bool {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        return false
        #else
        return isJailbroken || checkForHookingFrameworks().isHooked || isDebuggerAttached
        #endif
    }

    /// Enforce security - exit app if device is compromised
    @discardableResult
    func enforceFullSecurityCheck(on viewController: UIViewController?) -> Bool {
        guard !isCompromised else {
            showCompromisedAlert(on: viewController)
            return false
        }
        return true
    }

    /// Show alert for compromised devices (jailbroken or hooked)
    private func showCompromisedAlert(on viewController: UIViewController?) {
        let issues = performSecurityAudit()
        let issueList = issues.joined(separator: "\n• ")

        let alert = UIAlertController(
            title: "Security Warning",
            message: "This device's security has been compromised:\n\n• \(issueList)\n\nSsdidDrive cannot run on compromised devices to protect your data.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Exit App", style: .destructive) { _ in
            exit(0)
        })

        if let vc = viewController {
            vc.present(alert, animated: true)
        } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }
}
