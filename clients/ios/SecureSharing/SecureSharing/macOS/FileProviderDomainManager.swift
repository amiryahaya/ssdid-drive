import Foundation
#if canImport(FileProvider) && !targetEnvironment(macCatalyst)
import FileProvider
#endif

/// Manages the NSFileProviderDomain lifecycle for SecureSharing.
/// Registers the domain on login so files appear in Files.app,
/// and removes it on logout.
///
/// On Mac Catalyst, NSFileProviderManager APIs are unavailable — the File Provider
/// extension is managed by the system directly. This class is a no-op on Catalyst.
final class FileProviderDomainManager {

    #if !targetEnvironment(macCatalyst)
    private let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "com.securesharing.user-files")
    #endif

    /// Register the File Provider domain after successful login.
    func registerDomain(displayName: String = "SecureSharing") {
        #if !targetEnvironment(macCatalyst)
        let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: displayName)

        NSFileProviderManager.add(domain) { error in
            if let error {
                #if DEBUG
                print("[FileProviderDomainManager] Failed to register domain: \(error)")
                #endif
            }
        }
        #endif
    }

    /// Remove the File Provider domain on logout.
    func unregisterDomain() {
        #if !targetEnvironment(macCatalyst)
        let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "SecureSharing")

        NSFileProviderManager.remove(domain) { error in
            if let error {
                #if DEBUG
                print("[FileProviderDomainManager] Failed to remove domain: \(error)")
                #endif
            }
        }
        #endif
    }

    /// Signal the enumerator to refresh after file changes (upload, delete, rename).
    func signalEnumerator() {
        #if !targetEnvironment(macCatalyst)
        let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "SecureSharing")

        guard let manager = NSFileProviderManager(for: domain) else { return }

        manager.signalEnumerator(for: .rootContainer) { error in
            if let error {
                #if DEBUG
                print("[FileProviderDomainManager] Failed to signal enumerator: \(error)")
                #endif
            }
        }
        #endif
    }
}
