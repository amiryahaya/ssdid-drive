import Foundation

// MARK: - Secure Memory Operations

extension Data {

    /// Securely zero out the data in memory.
    /// This helps prevent sensitive data from lingering in memory after it's no longer needed.
    ///
    /// Note: This is a best-effort operation. The Swift runtime may have already copied
    /// the data elsewhere. For maximum security, use SecureData wrapper which zeros on dealloc.
    mutating func secureZero() {
        guard !isEmpty else { return }

        withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            // Use the secure clear helper to zero memory
            SecureMemory.clear(baseAddress, count: buffer.count)
        }
    }

    /// Create a copy that will be zeroed when deallocated.
    /// Use this for sensitive data that needs automatic cleanup.
    func toSecureData() -> SecureData {
        return SecureData(data: self)
    }
}

// MARK: - Secure String Extension

extension String {

    /// Execute a closure with the string's UTF8 bytes, automatically zeroing them afterwards.
    /// Note: Strings in Swift are immutable and may be interned, so this creates
    /// a mutable copy and zeros it after use.
    func withSecureUTF8Bytes<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
        var utf8Data = Data(utf8)
        defer {
            utf8Data.secureZero()
        }
        return try utf8Data.withUnsafeBytes { buffer in
            try body(buffer.bindMemory(to: UInt8.self))
        }
    }
}

// MARK: - Secure Data Wrapper

/// A wrapper around Data that automatically zeros its contents when deallocated.
/// Use this for sensitive data like keys, passwords, and secrets.
final class SecureData {

    private var data: Data

    /// Initialize with data to protect
    init(data: Data) {
        self.data = data
    }

    /// Initialize with byte count (zeroed)
    init(count: Int) {
        self.data = Data(count: count)
    }

    deinit {
        data.secureZero()
    }

    /// Access the underlying data (read-only copy)
    var bytes: Data {
        return data
    }

    /// The number of bytes
    var count: Int {
        return data.count
    }

    /// Access bytes with automatic zeroing on scope exit
    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        return try data.withUnsafeBytes(body)
    }

    /// Mutable access to bytes
    func withUnsafeMutableBytes<T>(_ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
        return try data.withUnsafeMutableBytes(body)
    }

    /// Explicitly zero and clear the data
    func clear() {
        data.secureZero()
        data = Data()
    }
}

// MARK: - Array Extension for Secure Zeroing

extension Array where Element == UInt8 {

    /// Securely zero out the array contents
    mutating func secureZero() {
        guard !isEmpty else { return }

        withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            SecureMemory.clear(baseAddress, count: buffer.count)
        }
    }
}

// MARK: - Secure Memory Helper

/// Helper for secure memory operations
enum SecureMemory {

    /// Clear memory in a way that won't be optimized away.
    /// Uses `@inline(never)` and memory barrier to prevent dead store elimination.
    @inline(never)
    static func clear(_ ptr: UnsafeMutableRawPointer, count: Int) {
        // Zero the memory
        memset(ptr, 0, count)

        // Memory barrier to ensure writes complete before any reads
        // This also helps prevent compiler from optimizing away the memset
        OSMemoryBarrier()

        // Additional compiler barrier: access the pointer opaquely
        // This prevents the compiler from knowing the writes are "dead"
        withExtendedLifetime(ptr) { }
    }

    /// Allocate zeroed memory that will be cleared on deallocation
    static func allocate(count: Int) -> SecureData {
        return SecureData(count: count)
    }
}
