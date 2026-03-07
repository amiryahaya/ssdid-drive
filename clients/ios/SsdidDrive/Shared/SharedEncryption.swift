import Foundation
import CryptoKit

/// Encrypts and decrypts data stored in App Group UserDefaults using AES-256-GCM.
/// The symmetric key is stored in the App Group shared container directory,
/// which is accessible only to apps in the same App Group.
final class SharedEncryption {

    private static let keyFileName = "shared_encryption_key"

    private let key: SymmetricKey?

    init() {
        self.key = SharedEncryption.loadOrCreateKey()
    }

    /// Encrypt data with AES-256-GCM. Returns nil if encryption fails or key is unavailable.
    func encrypt(_ data: Data) -> Data? {
        guard let key else { return nil }
        guard let sealedBox = try? AES.GCM.seal(data, using: key),
              let combined = sealedBox.combined else { return nil }
        return combined
    }

    /// Decrypt AES-256-GCM ciphertext. Returns nil if decryption fails or key is unavailable.
    func decrypt(_ data: Data) -> Data? {
        guard let key else { return nil }
        guard let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(sealedBox, using: key) else { return nil }
        return plaintext
    }

    // MARK: - Key Management

    private static func loadOrCreateKey() -> SymmetricKey? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.suiteName
        ) else { return nil }

        let supportDir = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        let keyURL = supportDir.appendingPathComponent(keyFileName)

        // Try to load existing key
        if let keyData = try? Data(contentsOf: keyURL), keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }

        // Generate new key
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        do {
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try keyData.write(to: keyURL, options: .atomic)
            // Restrict file permissions to owner only (0600)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: keyURL.path
            )
            return key
        } catch {
            #if DEBUG
            print("SharedEncryption: Failed to create encryption key - \(error)")
            #endif
            return nil
        }
    }
}
