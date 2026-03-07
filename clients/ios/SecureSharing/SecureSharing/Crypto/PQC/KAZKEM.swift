/*
 * KAZ-KEM Swift Wrapper for SecureSharing
 * Post-Quantum Key Encapsulation Mechanism
 *
 * Wraps the KazKemNative.xcframework for iOS
 */

import Foundation
import KazKemNative
import Security

// MARK: - Security Level

/// KAZ-KEM security levels corresponding to NIST post-quantum security categories.
public enum KazKemSecurityLevel: Int, Sendable, CaseIterable {
    /// 128-bit security (NIST Level 1) - Equivalent to AES-128
    case level128 = 128
    /// 192-bit security (NIST Level 3) - Equivalent to AES-192
    case level192 = 192
    /// 256-bit security (NIST Level 5) - Equivalent to AES-256
    case level256 = 256

    /// Human-readable description
    public var description: String {
        switch self {
        case .level128: return "128-bit (NIST Level 1)"
        case .level192: return "192-bit (NIST Level 3)"
        case .level256: return "256-bit (NIST Level 5)"
        }
    }

    /// Bit mask for generating random values smaller than modulus N
    internal var randomMask: UInt8 {
        switch self {
        case .level128: return 0x7F  // Clear 1 bit
        case .level192: return 0x1F  // Clear 3 bits
        case .level256: return 0x1F  // Clear 3 bits
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during KAZ-KEM operations.
public enum KazKemError: Error, LocalizedError, Sendable {
    case invalidParameter(String)
    case memoryAllocation
    case randomGenerationFailed
    case cryptographicError
    case messageTooLarge
    case notInitialized
    case invalidSecurityLevel(Int)
    case unknown(Int32)

    internal static func from(code: Int32, operation: String = "") -> KazKemError {
        switch code {
        case -1: return .invalidParameter(operation)
        case -2: return .memoryAllocation
        case -3: return .randomGenerationFailed
        case -4: return .cryptographicError
        case -5: return .messageTooLarge
        case -6: return .notInitialized
        case -7: return .invalidSecurityLevel(0)
        default: return .unknown(code)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidParameter(let operation):
            return "Invalid parameter\(operation.isEmpty ? "" : " in \(operation)")"
        case .memoryAllocation:
            return "Memory allocation failed"
        case .randomGenerationFailed:
            return "Random number generation failed"
        case .cryptographicError:
            return "Cryptographic operation failed"
        case .messageTooLarge:
            return "Message value exceeds modulus"
        case .notInitialized:
            return "KAZ-KEM is not initialized. Call KazKem.initialize() first."
        case .invalidSecurityLevel(let level):
            return "Invalid security level: \(level). Valid levels are 128, 192, or 256."
        case .unknown(let code):
            return "Unknown error (code: \(code))"
        }
    }
}

// MARK: - Key Types

/// A KAZ-KEM key pair containing both public and private keys.
public final class KazKemKeyPair: @unchecked Sendable {
    public let publicKey: Data
    private var _privateKey: Data
    public let securityLevel: KazKemSecurityLevel

    public var privateKey: Data { _privateKey }
    public var publicKeySize: Int { publicKey.count }
    public var privateKeySize: Int { _privateKey.count }

    internal init(publicKey: Data, privateKey: Data, securityLevel: KazKemSecurityLevel) {
        self.publicKey = publicKey
        self._privateKey = privateKey
        self.securityLevel = securityLevel
    }

    public func getPublicKey() -> KazKemPublicKey {
        return KazKemPublicKey(data: publicKey, securityLevel: securityLevel)
    }

    deinit {
        kazKemSecureZero(&_privateKey)
    }
}

/// A KAZ-KEM public key (safe to share).
public struct KazKemPublicKey: Sendable {
    public let data: Data
    public let securityLevel: KazKemSecurityLevel
    public var size: Int { data.count }

    public init(data: Data, securityLevel: KazKemSecurityLevel) {
        self.data = data
        self.securityLevel = securityLevel
    }
}

/// Result of an encapsulation operation.
public struct KazKemEncapsulationResult: @unchecked Sendable {
    public let ciphertext: Data
    private var _sharedSecret: Data

    public var sharedSecret: Data { _sharedSecret }
    public var ciphertextSize: Int { ciphertext.count }
    public var sharedSecretSize: Int { _sharedSecret.count }

    internal init(ciphertext: Data, sharedSecret: Data) {
        self.ciphertext = ciphertext
        self._sharedSecret = sharedSecret
    }

    public mutating func clear() {
        kazKemSecureZero(&_sharedSecret)
    }
}

// MARK: - KazKem Main Class

/// KAZ-KEM Post-Quantum Key Encapsulation Mechanism.
public final class KazKem: @unchecked Sendable {

    private static let lock = NSLock()
    private static var _current: KazKem?

    private let _securityLevel: KazKemSecurityLevel
    private let _publicKeySize: Int
    private let _privateKeySize: Int
    private let _ciphertextSize: Int
    private let _sharedSecretSize: Int

    public var securityLevel: KazKemSecurityLevel { _securityLevel }
    public var publicKeySize: Int { _publicKeySize }
    public var privateKeySize: Int { _privateKeySize }
    public var ciphertextSize: Int { _ciphertextSize }
    public var sharedSecretSize: Int { _sharedSecretSize }

    public static var version: String {
        guard let ptr = kaz_kem_version() else { return "unknown" }
        return String(cString: ptr)
    }

    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _current != nil && kaz_kem_is_initialized() != 0
    }

    public static var current: KazKem {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            guard let instance = _current else {
                throw KazKemError.notInitialized
            }
            return instance
        }
    }

    private init(level: KazKemSecurityLevel) {
        self._securityLevel = level
        self._publicKeySize = Int(kaz_kem_publickey_bytes())
        self._privateKeySize = Int(kaz_kem_privatekey_bytes())
        self._ciphertextSize = Int(kaz_kem_ciphertext_bytes())
        self._sharedSecretSize = Int(kaz_kem_shared_secret_bytes())
    }

    @discardableResult
    public static func initialize(level: KazKemSecurityLevel = .level128) throws -> KazKem {
        lock.lock()
        defer { lock.unlock() }

        if let current = _current, current._securityLevel == level {
            return current
        }

        if _current != nil {
            kaz_kem_cleanup()
            _current = nil
        }

        let result = kaz_kem_init(Int32(level.rawValue))
        if result != 0 {
            throw KazKemError.from(code: result, operation: "initialize")
        }

        let instance = KazKem(level: level)
        _current = instance
        return instance
    }

    public static func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        if _current != nil {
            kaz_kem_cleanup()
            _current = nil
        }
    }

    // MARK: - Key Generation

    public func generateKeyPair() throws -> KazKemKeyPair {
        try ensureInitialized()

        var publicKey = [UInt8](repeating: 0, count: publicKeySize)
        var privateKey = [UInt8](repeating: 0, count: privateKeySize)

        let result = kaz_kem_keypair(&publicKey, &privateKey)
        if result != 0 {
            kazKemSecureZero(&privateKey)
            throw KazKemError.from(code: result, operation: "generateKeyPair")
        }

        return KazKemKeyPair(
            publicKey: Data(publicKey),
            privateKey: Data(privateKey),
            securityLevel: securityLevel
        )
    }

    public static func generateKeyPair() throws -> KazKemKeyPair {
        return try current.generateKeyPair()
    }

    // MARK: - Encapsulation

    public func encapsulate(publicKey: KazKemPublicKey) throws -> KazKemEncapsulationResult {
        return try encapsulate(publicKey: publicKey.data)
    }

    public func encapsulate(publicKey: Data) throws -> KazKemEncapsulationResult {
        try ensureInitialized()

        guard publicKey.count == publicKeySize else {
            throw KazKemError.invalidParameter("Public key must be \(publicKeySize) bytes")
        }

        var sharedSecret = [UInt8](repeating: 0, count: sharedSecretSize)
        let status = SecRandomCopyBytes(kSecRandomDefault, sharedSecretSize, &sharedSecret)
        guard status == errSecSuccess else {
            throw KazKemError.randomGenerationFailed
        }

        sharedSecret[0] &= securityLevel.randomMask

        var ciphertext = [UInt8](repeating: 0, count: ciphertextSize)
        var ctLen: UInt64 = 0

        let result = publicKey.withUnsafeBytes { pkPtr -> Int32 in
            return kaz_kem_encapsulate(
                &ciphertext,
                &ctLen,
                sharedSecret,
                UInt64(sharedSecret.count),
                pkPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            )
        }

        if result != 0 {
            kazKemSecureZero(&sharedSecret)
            throw KazKemError.from(code: result, operation: "encapsulate")
        }

        return KazKemEncapsulationResult(
            ciphertext: Data(ciphertext.prefix(Int(ctLen))),
            sharedSecret: Data(sharedSecret)
        )
    }

    public static func encapsulate(publicKey: Data) throws -> KazKemEncapsulationResult {
        return try current.encapsulate(publicKey: publicKey)
    }

    // MARK: - Decapsulation

    public func decapsulate(ciphertext: Data, keyPair: KazKemKeyPair) throws -> Data {
        return try decapsulate(ciphertext: ciphertext, privateKey: keyPair.privateKey)
    }

    public func decapsulate(ciphertext: Data, privateKey: Data) throws -> Data {
        try ensureInitialized()

        guard privateKey.count == privateKeySize else {
            throw KazKemError.invalidParameter("Private key must be \(privateKeySize) bytes")
        }

        guard ciphertext.count > 0 && ciphertext.count <= ciphertextSize else {
            throw KazKemError.invalidParameter("Invalid ciphertext size")
        }

        var sharedSecret = [UInt8](repeating: 0, count: sharedSecretSize)
        var ssLen: UInt64 = 0

        let result = ciphertext.withUnsafeBytes { ctPtr -> Int32 in
            privateKey.withUnsafeBytes { skPtr -> Int32 in
                return kaz_kem_decapsulate(
                    &sharedSecret,
                    &ssLen,
                    ctPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    UInt64(ciphertext.count),
                    skPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                )
            }
        }

        if result != 0 {
            kazKemSecureZero(&sharedSecret)
            throw KazKemError.from(code: result, operation: "decapsulate")
        }

        return Data(sharedSecret.prefix(Int(ssLen)))
    }

    public static func decapsulate(ciphertext: Data, privateKey: Data) throws -> Data {
        return try current.decapsulate(ciphertext: ciphertext, privateKey: privateKey)
    }

    private func ensureInitialized() throws {
        guard kaz_kem_is_initialized() != 0 else {
            throw KazKemError.notInitialized
        }
    }
}

// MARK: - Secure Memory Utilities

@inline(__always)
internal func kazKemSecureZero(_ data: inout Data) {
    data.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset(baseAddress, 0, ptr.count)
            OSMemoryBarrier()
        }
    }
    data = Data()
}

@inline(__always)
internal func kazKemSecureZero(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset(baseAddress, 0, ptr.count)
            OSMemoryBarrier()
        }
    }
}

// MARK: - Static Compatibility API

/// Static compatibility layer for CryptoManager/KeyManager integration.
/// Provides the same interface as MLKEM enum for consistency.
enum KAZKEM {

    // MARK: - Key Sizes

    static var publicKeySize: Int {
        // Get from initialized instance or use level128 defaults
        return (try? KazKem.current.publicKeySize) ?? 236
    }

    static var privateKeySize: Int {
        return (try? KazKem.current.privateKeySize) ?? 86
    }

    static var ciphertextSize: Int {
        return (try? KazKem.current.ciphertextSize) ?? 236
    }

    static var sharedSecretSize: Int {
        return (try? KazKem.current.sharedSecretSize) ?? 32
    }

    // MARK: - Errors

    enum Error: Swift.Error {
        case keyGenerationFailed
        case encapsulationFailed
        case decapsulationFailed
        case invalidKeySize
        case initializationFailed
    }

    // MARK: - Key Generation

    /// Generate a KAZ-KEM key pair
    /// - Returns: Tuple of (publicKey, privateKey)
    static func generateKeyPair() throws -> (publicKey: Data, privateKey: Data) {
        let kem = try ensureInitialized()
        let keyPair = try kem.generateKeyPair()
        return (keyPair.publicKey, keyPair.privateKey)
    }

    // MARK: - Encapsulation

    /// Encapsulate a shared secret using recipient's public key
    /// - Parameter publicKey: Recipient's KAZ-KEM public key
    /// - Returns: Tuple of (ciphertext, sharedSecret)
    static func encapsulate(publicKey: Data) throws -> (ciphertext: Data, sharedSecret: Data) {
        let kem = try ensureInitialized()
        let result = try kem.encapsulate(publicKey: publicKey)
        return (result.ciphertext, result.sharedSecret)
    }

    // MARK: - Decapsulation

    /// Decapsulate a ciphertext to recover the shared secret
    /// - Parameters:
    ///   - ciphertext: The ciphertext from encapsulation
    ///   - privateKey: The recipient's private key
    /// - Returns: The shared secret
    static func decapsulate(ciphertext: Data, privateKey: Data) throws -> Data {
        let kem = try ensureInitialized()
        return try kem.decapsulate(ciphertext: ciphertext, privateKey: privateKey)
    }

    // MARK: - Private Helpers

    private static func ensureInitialized() throws -> KazKem {
        if KazKem.isInitialized {
            return try KazKem.current
        }
        // Default to level128 (NIST Level 1)
        return try KazKem.initialize(level: .level128)
    }
}
