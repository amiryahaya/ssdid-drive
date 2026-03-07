/*
 * ML-KEM Swift Wrapper for SecureSharing
 * NIST FIPS 203 ML-KEM-768 Key Encapsulation Mechanism
 *
 * Wraps the MlKemNative.xcframework which uses liboqs for real PQC.
 */

import Foundation
import CryptoKit

#if canImport(MlKemNative)
import MlKemNative
#endif

// MARK: - Error Types

/// Errors that can occur during ML-KEM operations
public enum MlKemError: Error, LocalizedError, Sendable {
    case invalidParameter(String)
    case memoryAllocation
    case randomGenerationFailed
    case cryptographicError
    case notInitialized
    case invalidKeySize
    case invalidCiphertextSize
    case libraryNotAvailable
    case unknown(Int32)

    init(code: Int32, operation: String = "") {
        switch code {
        case -1: self = .invalidParameter(operation)
        case -2: self = .memoryAllocation
        case -3: self = .randomGenerationFailed
        case -4: self = .cryptographicError
        case -5: self = .notInitialized
        case -6: self = .invalidKeySize
        case -7: self = .libraryNotAvailable
        default: self = .unknown(code)
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
        case .notInitialized:
            return "ML-KEM is not initialized. Call MlKem.initialize() first."
        case .invalidKeySize:
            return "Invalid key size"
        case .invalidCiphertextSize:
            return "Invalid ciphertext size"
        case .libraryNotAvailable:
            return "ML-KEM library (liboqs) not available"
        case .unknown(let code):
            return "Unknown error (code: \(code))"
        }
    }
}

// MARK: - Key Types

/// An ML-KEM key pair containing both public and secret keys
public final class MlKemKeyPair: @unchecked Sendable {
    public let publicKey: Data
    private var _secretKey: Data

    public var secretKey: Data { _secretKey }
    public var publicKeySize: Int { publicKey.count }
    public var secretKeySize: Int { _secretKey.count }

    internal init(publicKey: Data, secretKey: Data) {
        self.publicKey = publicKey
        self._secretKey = secretKey
    }

    public func getPublicKey() -> MlKemPublicKey {
        return MlKemPublicKey(data: publicKey)
    }

    deinit {
        mlKemSecureZero(&_secretKey)
    }
}

/// An ML-KEM public key (safe to share)
public struct MlKemPublicKey: Sendable {
    public let data: Data
    public var size: Int { data.count }

    public init(data: Data) {
        self.data = data
    }
}

/// Result of an encapsulation operation
public struct MlKemEncapsulationResult: @unchecked Sendable {
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
        mlKemSecureZero(&_sharedSecret)
    }
}

// MARK: - MlKem Main Class

/// ML-KEM-768 Post-Quantum Key Encapsulation Mechanism
public final class MlKem: @unchecked Sendable {

    private static let lock = NSLock()
    private static var _current: MlKem?

    // ML-KEM-768 sizes
    public static let publicKeySize = 1184
    public static let secretKeySize = 2400
    public static let ciphertextSize = 1088
    public static let sharedSecretSize = 32

    public static var version: String {
        #if canImport(MlKemNative)
        guard let ptr = ml_kem_version() else { return "unknown" }
        return String(cString: ptr)
        #else
        return "placeholder-1.0.0"
        #endif
    }

    public static var algorithm: String {
        #if canImport(MlKemNative)
        guard let ptr = ml_kem_algorithm() else { return "ML-KEM-768" }
        return String(cString: ptr)
        #else
        return "ML-KEM-768-placeholder"
        #endif
    }

    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(MlKemNative)
        return _current != nil && ml_kem_is_initialized() != 0
        #else
        return _current != nil
        #endif
    }

    public static var isNativeAvailable: Bool {
        #if canImport(MlKemNative)
        return true
        #else
        return false
        #endif
    }

    public static var current: MlKem {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            guard let instance = _current else {
                throw MlKemError.notInitialized
            }
            return instance
        }
    }

    private init() {}

    @discardableResult
    public static func initialize() throws -> MlKem {
        lock.lock()
        defer { lock.unlock() }

        if let current = _current {
            return current
        }

        #if canImport(MlKemNative)
        let result = ml_kem_init()
        if result != 0 {
            throw MlKemError(code: result, operation: "initialize")
        }
        #endif

        let instance = MlKem()
        _current = instance
        return instance
    }

    public static func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        if _current != nil {
            #if canImport(MlKemNative)
            ml_kem_cleanup()
            #endif
            _current = nil
        }
    }

    // MARK: - Key Generation

    public func generateKeyPair() throws -> MlKemKeyPair {
        #if canImport(MlKemNative)
        guard ml_kem_is_initialized() != 0 else {
            throw MlKemError.notInitialized
        }

        var publicKey = [UInt8](repeating: 0, count: MlKem.publicKeySize)
        var secretKey = [UInt8](repeating: 0, count: MlKem.secretKeySize)

        let result = ml_kem_keypair(&publicKey, &secretKey)
        if result != 0 {
            mlKemSecureZero(&secretKey)
            throw MlKemError(code: result, operation: "generateKeyPair")
        }

        return MlKemKeyPair(
            publicKey: Data(publicKey),
            secretKey: Data(secretKey)
        )
        #else
        // Placeholder implementation for builds without native library
        return try generateKeyPairPlaceholder()
        #endif
    }

    public static func generateKeyPair() throws -> MlKemKeyPair {
        return try current.generateKeyPair()
    }

    // MARK: - Encapsulation

    public func encapsulate(publicKey: MlKemPublicKey) throws -> MlKemEncapsulationResult {
        return try encapsulate(publicKey: publicKey.data)
    }

    public func encapsulate(publicKey: Data) throws -> MlKemEncapsulationResult {
        guard publicKey.count == MlKem.publicKeySize else {
            throw MlKemError.invalidKeySize
        }

        #if canImport(MlKemNative)
        guard ml_kem_is_initialized() != 0 else {
            throw MlKemError.notInitialized
        }

        var ciphertext = [UInt8](repeating: 0, count: MlKem.ciphertextSize)
        var sharedSecret = [UInt8](repeating: 0, count: MlKem.sharedSecretSize)

        let result = publicKey.withUnsafeBytes { pkPtr -> Int32 in
            return ml_kem_encapsulate(
                &ciphertext,
                &sharedSecret,
                pkPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            )
        }

        if result != 0 {
            mlKemSecureZero(&sharedSecret)
            throw MlKemError(code: result, operation: "encapsulate")
        }

        return MlKemEncapsulationResult(
            ciphertext: Data(ciphertext),
            sharedSecret: Data(sharedSecret)
        )
        #else
        return try encapsulatePlaceholder(publicKey: publicKey)
        #endif
    }

    public static func encapsulate(publicKey: Data) throws -> MlKemEncapsulationResult {
        return try current.encapsulate(publicKey: publicKey)
    }

    // MARK: - Decapsulation

    public func decapsulate(ciphertext: Data, keyPair: MlKemKeyPair) throws -> Data {
        return try decapsulate(ciphertext: ciphertext, secretKey: keyPair.secretKey)
    }

    public func decapsulate(ciphertext: Data, secretKey: Data) throws -> Data {
        guard ciphertext.count == MlKem.ciphertextSize else {
            throw MlKemError.invalidCiphertextSize
        }
        guard secretKey.count == MlKem.secretKeySize else {
            throw MlKemError.invalidKeySize
        }

        #if canImport(MlKemNative)
        guard ml_kem_is_initialized() != 0 else {
            throw MlKemError.notInitialized
        }

        var sharedSecret = [UInt8](repeating: 0, count: MlKem.sharedSecretSize)

        let result = ciphertext.withUnsafeBytes { ctPtr -> Int32 in
            secretKey.withUnsafeBytes { skPtr -> Int32 in
                return ml_kem_decapsulate(
                    &sharedSecret,
                    ctPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    skPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                )
            }
        }

        if result != 0 {
            mlKemSecureZero(&sharedSecret)
            throw MlKemError(code: result, operation: "decapsulate")
        }

        return Data(sharedSecret)
        #else
        return try decapsulatePlaceholder(ciphertext: ciphertext, secretKey: secretKey)
        #endif
    }

    public static func decapsulate(ciphertext: Data, secretKey: Data) throws -> Data {
        return try current.decapsulate(ciphertext: ciphertext, secretKey: secretKey)
    }

    // MARK: - Placeholder Implementation (fallback when native not available)

    #if !canImport(MlKemNative)
    private static let domainSeparator = "SecureSharing-MLKEM-Placeholder-v1".data(using: .utf8)!

    private func generateKeyPairPlaceholder() throws -> MlKemKeyPair {
        // Generate random seed
        var seed = Data(count: 64)
        let result = seed.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 64, ptr.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw MlKemError.randomGenerationFailed
        }

        let publicKey = deriveKeyMaterial(from: seed, info: "mlkem-public-key", length: MlKem.publicKeySize)
        let secretKey = deriveKeyMaterial(from: seed, info: "mlkem-secret-key", length: MlKem.secretKeySize)

        return MlKemKeyPair(publicKey: publicKey, secretKey: secretKey)
    }

    private func encapsulatePlaceholder(publicKey: Data) throws -> MlKemEncapsulationResult {
        var randomness = Data(count: 32)
        let result = randomness.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw MlKemError.randomGenerationFailed
        }

        let combinedInput = randomness + publicKey
        let ciphertext = deriveKeyMaterial(from: combinedInput, info: "mlkem-ciphertext", length: MlKem.ciphertextSize)
        let sharedSecret = deriveKeyMaterial(from: combinedInput, info: "mlkem-shared-secret", length: MlKem.sharedSecretSize)

        return MlKemEncapsulationResult(ciphertext: ciphertext, sharedSecret: sharedSecret)
    }

    private func decapsulatePlaceholder(ciphertext: Data, secretKey: Data) throws -> Data {
        // Placeholder cannot properly decapsulate
        // Return deterministic output for testing
        let combinedInput = ciphertext + secretKey
        return deriveKeyMaterial(from: combinedInput, info: "mlkem-shared-secret", length: MlKem.sharedSecretSize)
    }

    private func deriveKeyMaterial(from input: Data, info: String, length: Int) -> Data {
        let infoData = info.data(using: .utf8)!
        let salt = MlKem.domainSeparator

        let inputKey = SymmetricKey(data: input)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: infoData,
            outputByteCount: length
        )

        return derivedKey.withUnsafeBytes { Data($0) }
    }
    #endif
}

// MARK: - Secure Memory Utilities

@inline(__always)
internal func mlKemSecureZero(_ data: inout Data) {
    data.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset(baseAddress, 0, ptr.count)
            OSMemoryBarrier()
        }
    }
    data = Data()
}

@inline(__always)
internal func mlKemSecureZero(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset(baseAddress, 0, ptr.count)
            OSMemoryBarrier()
        }
    }
}

// MARK: - Static Compatibility API (MLKEM enum)

/// Static compatibility layer for CryptoManager/KeyManager integration.
/// Maintains the same interface as the original placeholder implementation.
enum MLKEM {

    // MARK: - Key Sizes (ML-KEM-768)

    static let publicKeySize = Constants.Crypto.mlKemPublicKeySize   // 1184 bytes
    static let privateKeySize = Constants.Crypto.mlKemPrivateKeySize // 2400 bytes
    static let ciphertextSize = Constants.Crypto.mlKemCiphertextSize // 1088 bytes
    static let sharedSecretSize = Constants.Crypto.mlKemSharedSecretSize // 32 bytes

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case keyGenerationFailed
        case encapsulationFailed
        case decapsulationFailed
        case invalidKeySize
        case libraryNotAvailable

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "ML-KEM key generation failed"
            case .encapsulationFailed: return "ML-KEM encapsulation failed"
            case .decapsulationFailed: return "ML-KEM decapsulation failed"
            case .invalidKeySize: return "Invalid ML-KEM key size"
            case .libraryNotAvailable: return "ML-KEM library not available"
            }
        }
    }

    // MARK: - Initialization

    /// Initialize ML-KEM library
    /// - Parameter level: Security level (ignored, always uses ML-KEM-768)
    static func initialize(_ level: Int = 192) throws {
        try MlKem.initialize()
    }

    // MARK: - Key Generation

    /// Generate an ML-KEM-768 key pair
    /// - Returns: Tuple of (publicKey, privateKey)
    static func generateKeyPair() throws -> (publicKey: Data, privateKey: Data) {
        let kem = try ensureInitialized()
        let keyPair = try kem.generateKeyPair()
        return (keyPair.publicKey, keyPair.secretKey)
    }

    // MARK: - Encapsulation

    /// Encapsulate a shared secret using recipient's public key
    /// - Parameter publicKey: Recipient's ML-KEM-768 public key
    /// - Returns: Tuple of (ciphertext, sharedSecret)
    static func encapsulate(publicKey: Data) throws -> (ciphertext: Data, sharedSecret: Data) {
        guard publicKey.count == publicKeySize else {
            throw Error.invalidKeySize
        }

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
        guard ciphertext.count == ciphertextSize else {
            throw Error.invalidKeySize
        }
        guard privateKey.count == privateKeySize else {
            throw Error.invalidKeySize
        }

        let kem = try ensureInitialized()
        return try kem.decapsulate(ciphertext: ciphertext, secretKey: privateKey)
    }

    // MARK: - Private Helpers

    private static func ensureInitialized() throws -> MlKem {
        if MlKem.isInitialized {
            return try MlKem.current
        }
        return try MlKem.initialize()
    }
}
