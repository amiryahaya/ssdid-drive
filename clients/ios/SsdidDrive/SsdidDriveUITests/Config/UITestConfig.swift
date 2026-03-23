import Foundation

/// Configuration for UI tests
enum UITestConfig {

    // MARK: - Environment

    /// Base URL for the test backend
    static var baseURL: String {
        ProcessInfo.processInfo.environment["BASE_URL"] ?? "http://localhost:4000"
    }

    /// PII Service URL
    static var piiServiceURL: String {
        ProcessInfo.processInfo.environment["PII_SERVICE_URL"] ?? "http://localhost:4001"
    }

    // MARK: - Test Credentials

    /// Admin test user email
    static var adminEmail: String {
        ProcessInfo.processInfo.environment["ADMIN_EMAIL"] ?? "admin@ssdid-drive.test"
    }

    /// Admin test user password
    static var adminPassword: String {
        ProcessInfo.processInfo.environment["ADMIN_PASSWORD"] ?? "Test123!@#"
    }

    /// Regular test user email
    static var testUserEmail: String {
        ProcessInfo.processInfo.environment["TEST_USER_EMAIL"] ?? "user1@e2e-test.local"
    }

    /// Regular test user password
    static var testUserPassword: String {
        ProcessInfo.processInfo.environment["TEST_USER_PASSWORD"] ?? "Test123!@#"
    }

    // MARK: - Timeouts

    /// Default timeout for element existence checks
    static let defaultTimeout: TimeInterval = 10

    /// Extended timeout for network operations
    static let networkTimeout: TimeInterval = 30

    /// Short timeout for quick checks
    static let shortTimeout: TimeInterval = 3

    // MARK: - Test Data

    /// Test organization name
    static let testOrganization = "E2E Test Organization"

    /// Test folder names
    static let testFolderName = "Test Folder"
    static let testFileName = "test-document.txt"

    /// Test file content
    static let testFileContent = """
    This is a test document for E2E testing.
    Email: test@example.com
    Phone: 555-1234
    """

    // MARK: - Feature Flags

    /// Whether auth-dependent UI tests should run.
    ///
    /// Set to `false` until a wallet-based test session mechanism is implemented.
    /// Tests gated on this flag are skipped gracefully rather than failing.
    static var isAuthTestEnabled: Bool {
        ProcessInfo.processInfo.environment["AUTH_TEST_ENABLED"] == "1"
    }

    // MARK: - Launch Arguments

    /// Get launch arguments for UI testing
    static var launchArguments: [String] {
        [
            "-UITesting",
            "-ResetStateOnLaunch",
            "-DisableAnimations"
        ]
    }

    /// Get launch environment for UI testing
    static var launchEnvironment: [String: String] {
        [
            "UI_TESTING": "1",
            "BASE_URL": baseURL,
            "PII_SERVICE_URL": piiServiceURL,
            "ANIMATIONS_DISABLED": "1"
        ]
    }
}
