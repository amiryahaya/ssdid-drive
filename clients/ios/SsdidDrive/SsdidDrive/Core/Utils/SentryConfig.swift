import Foundation
import CryptoKit
#if canImport(Sentry)
import Sentry
#endif

/// Sentry crash reporting configuration and utilities
/// SECURITY: This class implements privacy-focused crash reporting with:
/// - No PII (emails, names) sent to Sentry
/// - Comprehensive data scrubbing for sensitive information
/// - Screenshots disabled to prevent capturing decrypted content
/// - Network/file tracing disabled to prevent path leakage
final class SentryConfig {

    // MARK: - Singleton

    static let shared = SentryConfig()
    private init() {}

    // MARK: - Properties

    private let initializationLock = NSLock()
    private var isInitialized = false

    /// Sensitive keys that should be scrubbed from all Sentry data
    private static let sensitiveKeys: Set<String> = [
        "authorization", "auth", "token", "access_token", "refresh_token",
        "password", "passwd", "secret", "key", "api_key", "apikey",
        "credential", "private", "x-device-signature", "x-tenant-id",
        "email", "phone", "ssn", "credit_card", "card_number",
        "master_key", "encryption_key", "private_key", "session"
    ]

    /// Categories that should not generate breadcrumbs (security-sensitive operations)
    private static let blockedBreadcrumbCategories: Set<String> = [
        "keychain", "crypto", "biometric", "encryption", "decryption"
    ]

    // MARK: - Initialization

    /// Initialize Sentry SDK with configured options
    /// Call this early in AppDelegate.application(_:didFinishLaunchingWithOptions:)
    func initialize() {
        #if canImport(Sentry)
        initializationLock.lock()
        defer { initializationLock.unlock() }

        guard Constants.Sentry.isEnabled else {
            debugLog("Sentry: Disabled or DSN not configured")
            return
        }

        guard !isInitialized else {
            debugLog("Sentry: Already initialized")
            return
        }

        SentrySDK.start { [weak self] options in
            options.dsn = Constants.Sentry.dsn
            options.environment = Constants.Sentry.environment

            // Debug logging (only in debug builds)
            #if DEBUG
            options.debug = true
            #endif

            // Performance monitoring (higher rate in debug)
            #if DEBUG
            options.tracesSampleRate = NSNumber(value: 1.0)
            options.profilesSampleRate = NSNumber(value: 1.0)
            #else
            options.tracesSampleRate = NSNumber(value: Constants.Sentry.tracesSampleRate)
            options.profilesSampleRate = NSNumber(value: Constants.Sentry.profilesSampleRate)
            #endif

            // SECURITY: Disable screenshot and view hierarchy to prevent
            // capturing sensitive data (decrypted files, passwords, keys)
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // App lifecycle tracking
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 60000 // 1 minute (battery-friendly)

            // SECURITY: Disable network tracking to prevent URL/path leakage
            // URLs may contain file IDs, share tokens, user IDs
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false

            // UI interaction tracking
            options.enableSwizzling = true
            options.enableUIViewControllerTracing = true
            // SECURITY: Disable user interaction tracing to prevent capturing
            // tap targets that may contain sensitive text (file names, share tokens)
            options.enableUserInteractionTracing = false

            // Crash handling
            options.enableCrashHandler = true

            // SECURITY: Disable file I/O tracing to prevent path leakage
            // File paths may reveal encrypted file storage locations
            options.enableFileIOTracing = false

            // SECURITY: Disable Core Data tracing to prevent schema/query leakage
            options.enableCoreDataTracing = false

            // App version
            options.releaseName = "\(Constants.App.bundleId)@\(Constants.App.version)+\(Constants.App.build)"

            // SECURITY: Filter breadcrumbs before they are recorded
            options.beforeBreadcrumb = { breadcrumb in
                // Block breadcrumbs from security-sensitive categories
                let category = breadcrumb.category.lowercased()
                if SentryConfig.blockedBreadcrumbCategories.contains(category) {
                    return nil
                }

                // Scrub sensitive data from breadcrumb
                if var data = breadcrumb.data {
                    // SECURITY: If self is deallocated, return empty dict rather than unscrubbed data
                    data = self?.scrubDictionary(data) ?? [:]
                    // Scrub URLs in breadcrumb data
                    if let url = data["url"] as? String {
                        data["url"] = self?.scrubURL(url) ?? "[REDACTED]"
                    }
                    if let requestUrl = data["request_url"] as? String {
                        data["request_url"] = self?.scrubURL(requestUrl) ?? "[REDACTED]"
                    }
                    breadcrumb.data = data
                }

                return breadcrumb
            }

            // SECURITY: Comprehensive data scrubbing before sending events
            options.beforeSend = { [weak self] event in
                // SECURITY: If self is deallocated, drop the event rather than sending unscrubbed data
                guard let self = self else { return nil }

                // Scrub breadcrumbs
                event.breadcrumbs = event.breadcrumbs?.compactMap { breadcrumb in
                    if var data = breadcrumb.data {
                        data = self.scrubDictionary(data)
                        breadcrumb.data = data
                    }
                    // SECURITY: Scrub breadcrumb messages for sensitive patterns
                    if let message = breadcrumb.message, self.containsSensitivePattern(message) {
                        breadcrumb.message = "[REDACTED]"
                    }
                    return breadcrumb
                }

                // Scrub extras
                if var extras = event.extra {
                    extras = self.scrubDictionary(extras)
                    event.extra = extras
                }

                // Scrub tags
                if var tags = event.tags {
                    for (key, value) in tags {
                        if self.isSensitiveKey(key) {
                            tags[key] = "[REDACTED]"
                        } else if self.containsSensitivePattern(value) {
                            tags[key] = "[REDACTED]"
                        }
                    }
                    event.tags = tags
                }

                // Scrub user data (keep only anonymized ID)
                if let user = event.user {
                    user.email = nil
                    user.username = nil
                    user.name = nil
                    // Scrub user data dictionary
                    if var userData = user.data {
                        userData = self.scrubDictionary(userData) as? [String: Any] ?? [:]
                        user.data = userData
                    }
                }

                // Scrub request data
                if let request = event.request {
                    request.headers = nil // Remove all headers
                    request.cookies = nil
                    if let url = request.url {
                        request.url = self.scrubURL(url)
                    }
                }

                return event
            }
        }

        isInitialized = true
        debugLog("Sentry: Initialized successfully")
        #else
        debugLog("Sentry: SDK not available")
        #endif
    }

    // MARK: - User Identification

    /// Set the current user for crash reports
    /// SECURITY: Only anonymized user ID is sent - no email or PII
    /// - Parameters:
    ///   - userId: User's unique identifier (will be hashed)
    ///   - tenantId: Current tenant ID (optional, will be hashed)
    func setUser(userId: String, tenantId: String? = nil) {
        #if canImport(Sentry)
        guard isInitialized else { return }

        let user = Sentry.User()
        // SECURITY: Hash the user ID to prevent PII exposure
        user.userId = anonymizeIdentifier(userId)

        // SECURITY: Hash tenant ID if provided
        if let tenantId = tenantId {
            user.data = ["tenant_hash": anonymizeIdentifier(tenantId)]
        }

        // SECURITY: Never set email, username, or name
        user.email = nil
        user.username = nil
        user.name = nil

        SentrySDK.setUser(user)
        #endif
    }

    /// Clear user data on logout
    func clearUser() {
        #if canImport(Sentry)
        guard isInitialized else { return }
        SentrySDK.setUser(nil)
        #endif
    }

    // MARK: - Context & Tags

    /// Set additional context for crash reports
    /// SECURITY: Values are automatically scrubbed for sensitive data
    /// - Parameters:
    ///   - key: Context key
    ///   - value: Context data dictionary
    func setContext(_ key: String, value: [String: Any]) {
        #if canImport(Sentry)
        guard isInitialized else { return }
        let scrubbedValue = scrubDictionary(value)
        SentrySDK.configureScope { scope in
            scope.setContext(value: scrubbedValue, key: key)
        }
        #endif
    }

    /// Set a tag for filtering crash reports
    /// SECURITY: Value is checked for sensitive patterns
    /// - Parameters:
    ///   - key: Tag name
    ///   - value: Tag value
    func setTag(_ key: String, value: String) {
        #if canImport(Sentry)
        guard isInitialized else { return }

        // Don't set tags with sensitive keys or values
        guard !isSensitiveKey(key), !containsSensitivePattern(value) else {
            debugLog("Sentry: Blocked sensitive tag: \(key)")
            return
        }

        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
        #endif
    }

    // MARK: - Breadcrumbs

    /// Add a breadcrumb for debugging
    /// SECURITY: Data is automatically scrubbed for sensitive information
    /// - Parameters:
    ///   - message: Breadcrumb message
    ///   - category: Category for grouping (e.g., "navigation", "api")
    ///   - level: Severity level
    ///   - data: Additional data dictionary (will be scrubbed)
    func addBreadcrumb(
        message: String,
        category: String,
        level: BreadcrumbLevel = .info,
        data: [String: Any]? = nil
    ) {
        #if canImport(Sentry)
        guard isInitialized else { return }

        // Block security-sensitive categories
        guard !Self.blockedBreadcrumbCategories.contains(category.lowercased()) else {
            debugLog("Sentry: Blocked breadcrumb category: \(category)")
            return
        }

        let breadcrumb = Breadcrumb()
        breadcrumb.message = message
        breadcrumb.category = category
        breadcrumb.level = level.sentryLevel

        // Scrub data before adding
        if let data = data {
            breadcrumb.data = scrubDictionary(data)
        }

        SentrySDK.addBreadcrumb(breadcrumb)
        #endif
    }

    // MARK: - Error Capture

    /// Capture a non-fatal error
    /// SECURITY: Extras are scrubbed and scoped to this event only
    /// - Parameters:
    ///   - error: The error to capture
    ///   - extras: Additional context data (will be scrubbed)
    func captureError(_ error: Error, extras: [String: Any]? = nil) {
        #if canImport(Sentry)
        guard isInitialized else { return }

        // Use event-specific scope to prevent extras leaking to other events
        SentrySDK.capture(error: error) { scope in
            if let extras = extras {
                let scrubbedExtras = self.scrubDictionary(extras)
                for (key, value) in scrubbedExtras {
                    scope.setExtra(value: value, key: key)
                }
            }
        }
        #endif
    }

    /// Capture a message
    /// SECURITY: Message is scrubbed for sensitive patterns before sending
    /// - Parameters:
    ///   - message: Message to capture
    ///   - level: Severity level
    func captureMessage(_ message: String, level: BreadcrumbLevel = .info) {
        #if canImport(Sentry)
        guard isInitialized else { return }
        let scrubbedMessage = scrubString(message)
        SentrySDK.capture(message: scrubbedMessage) { scope in
            scope.setLevel(level.sentryLevel)
        }
        #endif
    }

    // MARK: - Performance

    /// Start a performance transaction
    /// - Parameters:
    ///   - name: Transaction name
    ///   - operation: Operation type (e.g., "file.upload", "api.call")
    /// - Returns: Transaction span for finishing later
    func startTransaction(name: String, operation: String) -> Any? {
        #if canImport(Sentry)
        guard isInitialized else { return nil }
        return SentrySDK.startTransaction(name: name, operation: operation)
        #else
        return nil
        #endif
    }

    /// Finish a transaction
    /// - Parameter transaction: The transaction to finish
    func finishTransaction(_ transaction: Any?) {
        #if canImport(Sentry)
        guard let span = transaction as? Span else { return }
        span.finish()
        #endif
    }

    // MARK: - Private Helpers

    /// Check if a key name indicates sensitive data
    private func isSensitiveKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return Self.sensitiveKeys.contains { lowercased.contains($0) }
    }

    /// Check if a string value contains sensitive patterns
    private func containsSensitivePattern(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        // Check for JWT tokens
        if value.hasPrefix("eyJ") && value.contains(".") {
            return true
        }
        // Check for Bearer tokens
        if lowercased.hasPrefix("bearer ") {
            return true
        }
        // Check for email patterns
        if value.contains("@") && value.contains(".") {
            return true
        }
        // Check for DID strings (decentralized identifiers)
        if lowercased.hasPrefix("did:") {
            return true
        }
        // Check for long base64 strings (>40 chars) that could be key material
        if value.count > 40 {
            let base64Set = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+/="))
            if value.unicodeScalars.allSatisfy({ base64Set.contains($0) }) {
                return true
            }
        }
        // Check for long hex strings (>32 hex chars) that could be key material
        if value.count > 32 {
            let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            if value.unicodeScalars.allSatisfy({ hexSet.contains($0) }) {
                return true
            }
        }
        return false
    }

    /// Scrub a raw string for sensitive patterns
    private func scrubString(_ value: String) -> String {
        if containsSensitivePattern(value) {
            return "[REDACTED]"
        }
        return value
    }

    /// Scrub sensitive data from a dictionary
    private func scrubDictionary(_ dict: [String: Any]) -> [String: Any] {
        var result = [String: Any]()
        for (key, value) in dict {
            if isSensitiveKey(key) {
                result[key] = "[REDACTED]"
            } else if let stringValue = value as? String {
                if containsSensitivePattern(stringValue) {
                    result[key] = "[REDACTED]"
                } else {
                    result[key] = stringValue
                }
            } else if let nestedDict = value as? [String: Any] {
                result[key] = scrubDictionary(nestedDict)
            } else if let array = value as? [Any] {
                result[key] = scrubArray(array)
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// Scrub sensitive data from an array
    private func scrubArray(_ array: [Any]) -> [Any] {
        return array.map { element in
            if let stringValue = element as? String {
                return containsSensitivePattern(stringValue) ? "[REDACTED]" : stringValue
            } else if let nestedDict = element as? [String: Any] {
                return scrubDictionary(nestedDict)
            } else if let nestedArray = element as? [Any] {
                return scrubArray(nestedArray)
            }
            return element
        }
    }

    /// Scrub sensitive information from URLs
    private func scrubURL(_ url: String) -> String {
        guard var components = URLComponents(string: url) else {
            return url
        }

        // Remove query parameters that might contain sensitive data
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                if isSensitiveKey(item.name) || (item.value != nil && containsSensitivePattern(item.value!)) {
                    return URLQueryItem(name: item.name, value: "[REDACTED]")
                }
                return item
            }
        }

        // Scrub path components that look like IDs or tokens
        // UUIDs, long alphanumeric strings, etc.
        var pathComponents = components.path.split(separator: "/").map(String.init)
        pathComponents = pathComponents.map { component in
            // Keep known safe path components
            let safePaths = ["api", "v1", "v2", "auth", "files", "folders", "shares", "users", "devices", "tenant", "recovery"]
            if safePaths.contains(component.lowercased()) {
                return component
            }
            // Redact UUID-like strings
            if component.count == 36 && component.contains("-") {
                return "[ID]"
            }
            // Redact long alphanumeric strings (likely tokens/IDs)
            if component.count > 20 && component.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                return "[ID]"
            }
            return component
        }
        components.path = "/" + pathComponents.joined(separator: "/")

        return components.string ?? url
    }

    /// Create an anonymized identifier using SHA256 hash
    /// SECURITY: Uses 128-bit (32 hex char) prefix for collision resistance
    internal func anonymizeIdentifier(_ identifier: String) -> String {
        guard let data = identifier.data(using: .utf8) else {
            return "[INVALID]"
        }
        let hash = SHA256.hash(data: data)
        // Return first 32 characters of hex hash (128 bits minimum)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    /// Debug-only logging
    private func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - Breadcrumb Level

enum BreadcrumbLevel {
    case debug
    case info
    case warning
    case error
    case fatal

    #if canImport(Sentry)
    var sentryLevel: SentryLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fatal: return .fatal
        }
    }
    #endif
}
