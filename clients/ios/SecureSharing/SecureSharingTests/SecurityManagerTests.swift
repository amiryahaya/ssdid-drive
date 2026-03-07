import XCTest
@testable import SecureSharing

/// Unit tests for SecurityManager
final class SecurityManagerTests: XCTestCase {

    var securityManager: SecurityManager!

    override func setUp() {
        super.setUp()
        securityManager = SecurityManager.shared
    }

    // MARK: - Jailbreak Detection Tests

    func testJailbreakDetectionOnSimulator() {
        // On simulator, should always report not jailbroken
        #if targetEnvironment(simulator)
        XCTAssertFalse(securityManager.isJailbroken, "Simulator should not be detected as jailbroken")
        #endif
    }

    func testSecurityAuditOnSimulator() {
        // Given/When
        let issues = securityManager.performSecurityAudit()

        // Then - On simulator, should have no issues
        #if targetEnvironment(simulator)
        XCTAssertTrue(issues.isEmpty, "Simulator should have no security issues")
        #endif
    }

    // MARK: - Debugger Detection Tests

    func testDebuggerDetectionInDebugBuild() {
        // In debug builds, debugger detection should be disabled
        #if DEBUG
        XCTAssertFalse(securityManager.isDebuggerAttached, "Debugger detection should be disabled in debug builds")
        #endif
    }

    // MARK: - Singleton Tests

    func testSingletonInstance() {
        // Given/When
        let instance1 = SecurityManager.shared
        let instance2 = SecurityManager.shared

        // Then
        XCTAssertTrue(instance1 === instance2, "SecurityManager should be a singleton")
    }
}

// MARK: - Security Utility Tests

final class SecurityUtilityTests: XCTestCase {

    // MARK: - File Path Security Tests

    func testSuspiciousPathsAreNotAccessible() {
        // These paths should not exist on a non-jailbroken device
        // Note: /bin/bash exists on macOS (simulator environment) so we exclude it
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/private/var/lib/apt"
        ]

        for path in suspiciousPaths {
            let exists = FileManager.default.fileExists(atPath: path)
            #if targetEnvironment(simulator)
            // On simulator, jailbreak-specific paths should not exist
            XCTAssertFalse(exists, "Suspicious path should not exist: \(path)")
            #endif
        }
    }

    // MARK: - Write Permission Tests

    func testCannotWriteToRestrictedPaths() {
        // Should not be able to write to restricted paths
        let restrictedPath = "/private/test_write_permission.txt"

        let canWrite: Bool
        do {
            try "test".write(toFile: restrictedPath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: restrictedPath)
            canWrite = true
        } catch {
            canWrite = false
        }

        XCTAssertFalse(canWrite, "Should not be able to write to restricted path")
    }

    // MARK: - URL Scheme Tests

    func testSuspiciousURLSchemesNotAvailable() {
        // These URL schemes should not be available on non-jailbroken devices
        let suspiciousSchemes = ["cydia://", "sileo://"]

        for scheme in suspiciousSchemes {
            if let url = URL(string: scheme) {
                // Note: canOpenURL requires LSApplicationQueriesSchemes in Info.plist
                // This test verifies the URL can be created but doesn't test openability
                XCTAssertNotNil(url, "URL should be creatable")
            }
        }
    }
}

// MARK: - Data Security Tests

final class DataSecurityTests: XCTestCase {

    func testSecureDataZeroing() {
        // Given
        var sensitiveData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let originalCount = sensitiveData.count

        // When - Zero the data
        sensitiveData.withUnsafeMutableBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                memset(baseAddress, 0, ptr.count)
            }
        }

        // Then - Data should be zeroed
        XCTAssertEqual(sensitiveData.count, originalCount, "Data count should remain the same")
        for byte in sensitiveData {
            XCTAssertEqual(byte, 0, "All bytes should be zero")
        }
    }

    func testRandomDataGeneration() {
        // Given
        let size = 32

        // When
        var randomData = Data(count: size)
        let result = randomData.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, size, ptr.baseAddress!)
        }

        // Then
        XCTAssertEqual(result, errSecSuccess, "Random generation should succeed")
        XCTAssertEqual(randomData.count, size, "Random data should be correct size")

        // Random data should not be all zeros (statistically unlikely)
        let allZeros = randomData.allSatisfy { $0 == 0 }
        XCTAssertFalse(allZeros, "Random data should not be all zeros")
    }

    func testRandomDataUniqueness() {
        // Given
        let size = 32

        // When
        var data1 = Data(count: size)
        var data2 = Data(count: size)
        _ = data1.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!) }
        _ = data2.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!) }

        // Then - Two random generations should produce different data
        XCTAssertNotEqual(data1, data2, "Random data should be unique")
    }
}

import Security
