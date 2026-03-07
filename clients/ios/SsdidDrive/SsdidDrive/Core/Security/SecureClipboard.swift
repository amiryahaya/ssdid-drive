import UIKit

/// Secure clipboard manager with automatic expiration for sensitive data
final class SecureClipboard {

    // MARK: - Singleton

    static let shared = SecureClipboard()

    private init() {}

    // MARK: - Types

    /// Options for secure clipboard operations
    struct CopyOptions {
        /// Time interval after which the clipboard should be cleared (in seconds)
        /// Set to 0 for no expiration
        let expirationInterval: TimeInterval

        /// Whether to prevent the content from being shared to other devices via Universal Clipboard
        let localOnly: Bool

        /// Default options: 60 second expiration, local only
        static let `default` = CopyOptions(expirationInterval: 60, localOnly: true)

        /// Sensitive options: 30 second expiration, local only
        static let sensitive = CopyOptions(expirationInterval: 30, localOnly: true)

        /// No expiration (use with caution)
        static let noExpiration = CopyOptions(expirationInterval: 0, localOnly: false)
    }

    // MARK: - Properties

    /// Timer for clearing the clipboard
    private var clearTimer: Timer?

    /// The content that was last copied (for verification)
    private var lastCopiedContent: String?

    /// Whether secure clipboard is enabled
    private(set) var isEnabled = true

    // MARK: - Public Methods

    /// Enable secure clipboard functionality
    func enable() {
        isEnabled = true
    }

    /// Disable secure clipboard functionality
    func disable() {
        isEnabled = false
        cancelClearTimer()
    }

    /// Copy text to clipboard with security options
    /// - Parameters:
    ///   - text: The text to copy
    ///   - options: Security options for the copy operation
    func copy(_ text: String, options: CopyOptions = .default) {
        let pasteboard = UIPasteboard.general

        // Cancel any existing timer
        cancelClearTimer()

        // Configure pasteboard options
        var pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [:]

        if options.localOnly {
            // Prevent Universal Clipboard sharing
            pasteboardOptions[.localOnly] = true
        }

        // Set expiration if specified (iOS 10+)
        if options.expirationInterval > 0 {
            let expirationDate = Date().addingTimeInterval(options.expirationInterval)
            pasteboardOptions[.expirationDate] = expirationDate
        }

        // Copy with options
        pasteboard.setItems([[UIPasteboard.typeAutomatic: text]], options: pasteboardOptions)
        lastCopiedContent = text

        // Set up manual clear timer as backup
        if options.expirationInterval > 0 && isEnabled {
            setupClearTimer(interval: options.expirationInterval)
        }

        #if DEBUG
        print("[SecureClipboard] Content copied with \(options.expirationInterval)s expiration")
        #endif
    }

    /// Copy sensitive data (uses stricter security options)
    /// - Parameter text: The sensitive text to copy
    func copySensitive(_ text: String) {
        copy(text, options: .sensitive)
    }

    /// Clear the clipboard immediately
    func clear() {
        cancelClearTimer()

        let pasteboard = UIPasteboard.general

        // Only clear if the content matches what we copied
        // This prevents clearing content the user copied from elsewhere
        if let lastContent = lastCopiedContent,
           pasteboard.string == lastContent {
            pasteboard.string = ""
            lastCopiedContent = nil

            #if DEBUG
            print("[SecureClipboard] Clipboard cleared")
            #endif
        }
    }

    /// Force clear the clipboard regardless of content
    func forceClear() {
        cancelClearTimer()
        UIPasteboard.general.items = []
        lastCopiedContent = nil

        #if DEBUG
        print("[SecureClipboard] Clipboard force cleared")
        #endif
    }

    // MARK: - Private Methods

    private func setupClearTimer(interval: TimeInterval) {
        clearTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.clear()
        }
    }

    private func cancelClearTimer() {
        clearTimer?.invalidate()
        clearTimer = nil
    }
}

// MARK: - UIPasteboard Extension

extension UIPasteboard {

    /// Copy text securely with automatic expiration
    /// - Parameters:
    ///   - text: The text to copy
    ///   - expiresIn: Expiration interval in seconds (default: 60)
    func copySecurely(_ text: String, expiresIn: TimeInterval = 60) {
        SecureClipboard.shared.copy(text, options: .init(expirationInterval: expiresIn, localOnly: true))
    }
}

// MARK: - String Extension for Secure Copy

extension String {

    /// Copy this string to clipboard with secure options
    /// - Parameter options: Security options for the copy operation
    func copyToClipboard(options: SecureClipboard.CopyOptions = .default) {
        SecureClipboard.shared.copy(self, options: options)
    }

    /// Copy this string as sensitive data (30 second expiration)
    func copyAsSensitive() {
        SecureClipboard.shared.copySensitive(self)
    }
}
