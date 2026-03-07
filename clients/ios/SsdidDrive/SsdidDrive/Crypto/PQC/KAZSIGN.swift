/*
 * KAZ-SIGN Swift Wrapper for SsdidDrive
 * Post-Quantum Digital Signature Algorithm
 *
 * Wraps the KazSignNative.xcframework for iOS
 */

import Foundation
import KazSignNative

// MARK: - Security Level

/// Security level for KAZ-SIGN operations
public enum KazSignSecurityLevel: Int, CaseIterable, Sendable {
    /// 128-bit security (SHA-256)
    case level128 = 128
    /// 192-bit security (SHA-384)
    case level192 = 192
    /// 256-bit security (SHA-512)
    case level256 = 256

    /// Secret key size in bytes
    public var secretKeyBytes: Int {
        switch self {
        case .level128: return 32
        case .level192: return 50
        case .level256: return 64
        }
    }

    /// Public key size in bytes
    public var publicKeyBytes: Int {
        switch self {
        case .level128: return 54
        case .level192: return 88
        case .level256: return 118
        }
    }

    /// Signature overhead in bytes (excluding message)
    public var signatureOverhead: Int {
        switch self {
        case .level128: return 162  // S1(54) + S2(54) + S3(54)
        case .level192: return 264  // S1(88) + S2(88) + S3(88)
        case .level256: return 356  // S1(118) + S2(119) + S3(119)
        }
    }

    /// Hash output size in bytes
    public var hashBytes: Int {
        switch self {
        case .level128: return 32  // SHA-256
        case .level192: return 48  // SHA-384
        case .level256: return 64  // SHA-512
        }
    }

    /// Algorithm name
    public var algorithmName: String {
        "KAZ-SIGN-\(rawValue)"
    }
}

// MARK: - Error Types

/// Errors that can occur during KAZ-SIGN operations
public enum KazSignError: Error, LocalizedError, Sendable, Equatable {
    case memoryAllocationFailed
    case randomGenerationFailed
    case invalidParameter
    case verificationFailed
    case notInitialized
    case invalidKeySize
    case invalidSignatureSize
    case unknownError(Int32)

    public var errorDescription: String? {
        switch self {
        case .memoryAllocationFailed:
            return "Memory allocation failed"
        case .randomGenerationFailed:
            return "Random number generation failed"
        case .invalidParameter:
            return "Invalid parameter"
        case .verificationFailed:
            return "Signature verification failed"
        case .notInitialized:
            return "Signer not initialized"
        case .invalidKeySize:
            return "Invalid key size"
        case .invalidSignatureSize:
            return "Invalid signature size"
        case .unknownError(let code):
            return "Unknown error (code: \(code))"
        }
    }

    init(code: Int32) {
        switch code {
        case -1: self = .memoryAllocationFailed
        case -2: self = .randomGenerationFailed
        case -3: self = .invalidParameter
        case -4: self = .verificationFailed
        default: self = .unknownError(code)
        }
    }
}

// MARK: - Key Types

/// A KAZ-SIGN key pair containing public and secret keys
public struct KazSignKeyPair: Sendable {
    /// Public verification key
    public let publicKey: Data
    /// Secret signing key
    public let secretKey: Data
    /// Security level
    public let level: KazSignSecurityLevel

    init(publicKey: Data, secretKey: Data, level: KazSignSecurityLevel) {
        self.publicKey = publicKey
        self.secretKey = secretKey
        self.level = level
    }
}

/// Result of a signing operation
public struct KazSignSignatureResult: Sendable {
    /// The signature (includes the message)
    public let signature: Data
    /// The original message
    public let message: Data
    /// Security level used
    public let level: KazSignSecurityLevel

    /// Signature overhead (signature bytes without message)
    public var overhead: Int {
        signature.count - message.count
    }
}

/// Result of a verification operation
public struct KazSignVerificationResult: Sendable {
    /// Whether the signature is valid
    public let isValid: Bool
    /// The recovered message (if valid)
    public let message: Data?
    /// Security level used
    public let level: KazSignSecurityLevel
}

// MARK: - KazSigner

/// Main class for KAZ-SIGN cryptographic operations
public final class KazSigner: @unchecked Sendable {
    /// The security level being used
    public let level: KazSignSecurityLevel

    private let lock = NSLock()
    private var isInitialized = false

    /// Library version string
    public static var version: String {
        String(cString: kaz_sign_version())
    }

    /// Library version number
    public static var versionNumber: Int {
        Int(kaz_sign_version_number())
    }

    /// Create a new KazSigner with the specified security level
    public init(level: KazSignSecurityLevel) throws {
        self.level = level
        try initialize()
    }

    deinit {
        cleanup()
    }

    // MARK: - Initialization

    private var cLevel: kaz_sign_level_t {
        kaz_sign_level_t(rawValue: UInt32(level.rawValue))
    }

    private func initialize() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isInitialized else { return }

        let result = kaz_sign_init_level(cLevel)
        guard result == 0 else {
            throw KazSignError(code: result)
        }

        isInitialized = true
    }

    private func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        if isInitialized {
            kaz_sign_clear_level(cLevel)
            isInitialized = false
        }
    }

    private func ensureInitialized() throws {
        guard isInitialized else {
            throw KazSignError.notInitialized
        }
    }

    // MARK: - Key Generation

    /// Generate a new key pair
    public func generateKeyPair() throws -> KazSignKeyPair {
        try ensureInitialized()

        var publicKey = Data(count: level.publicKeyBytes)
        var secretKey = Data(count: level.secretKeyBytes)

        let result = publicKey.withUnsafeMutableBytes { pkPtr in
            secretKey.withUnsafeMutableBytes { skPtr in
                kaz_sign_keypair_ex(
                    cLevel,
                    pkPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    skPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                )
            }
        }

        guard result == 0 else {
            throw KazSignError(code: result)
        }

        return KazSignKeyPair(publicKey: publicKey, secretKey: secretKey, level: level)
    }

    // MARK: - Signing

    /// Sign a message
    public func sign(message: Data, secretKey: Data) throws -> KazSignSignatureResult {
        try ensureInitialized()

        guard secretKey.count == level.secretKeyBytes else {
            throw KazSignError.invalidKeySize
        }

        var signature = Data(count: level.signatureOverhead + message.count)
        var signatureLength: UInt64 = 0

        let result = signature.withUnsafeMutableBytes { sigPtr in
            message.withUnsafeBytes { msgPtr in
                secretKey.withUnsafeBytes { skPtr in
                    kaz_sign_signature_ex(
                        cLevel,
                        sigPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        &signatureLength,
                        msgPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        UInt64(message.count),
                        skPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    )
                }
            }
        }

        guard result == 0 else {
            throw KazSignError(code: result)
        }

        signature = signature.prefix(Int(signatureLength))
        return KazSignSignatureResult(signature: signature, message: message, level: level)
    }

    /// Sign a string message
    public func sign(message: String, secretKey: Data) throws -> KazSignSignatureResult {
        guard let messageData = message.data(using: .utf8) else {
            throw KazSignError.invalidParameter
        }
        return try sign(message: messageData, secretKey: secretKey)
    }

    // MARK: - Verification

    /// Verify a signature and extract the message
    public func verify(signature: Data, publicKey: Data) throws -> KazSignVerificationResult {
        try ensureInitialized()

        guard publicKey.count == level.publicKeyBytes else {
            throw KazSignError.invalidKeySize
        }

        guard signature.count >= level.signatureOverhead else {
            return KazSignVerificationResult(isValid: false, message: nil, level: level)
        }

        let maxMessageLength = signature.count - level.signatureOverhead
        var message = Data(count: maxMessageLength)
        var messageLength: UInt64 = 0

        let result = message.withUnsafeMutableBytes { msgPtr in
            signature.withUnsafeBytes { sigPtr in
                publicKey.withUnsafeBytes { pkPtr in
                    kaz_sign_verify_ex(
                        cLevel,
                        msgPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        &messageLength,
                        sigPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        UInt64(signature.count),
                        pkPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    )
                }
            }
        }

        if result == 0 {
            message = message.prefix(Int(messageLength))
            return KazSignVerificationResult(isValid: true, message: message, level: level)
        } else {
            return KazSignVerificationResult(isValid: false, message: nil, level: level)
        }
    }

    /// Verify a signature and extract the message as a string
    public func verifyString(signature: Data, publicKey: Data) throws -> (isValid: Bool, message: String?) {
        let result = try verify(signature: signature, publicKey: publicKey)
        let messageString = result.message.flatMap { String(data: $0, encoding: .utf8) }
        return (result.isValid, messageString)
    }

    // MARK: - Hashing

    /// Hash a message using the appropriate hash function for this security level
    public func hash(message: Data) throws -> Data {
        var hashOutput = Data(count: level.hashBytes)

        let result = hashOutput.withUnsafeMutableBytes { hashPtr in
            message.withUnsafeBytes { msgPtr in
                kaz_sign_hash_ex(
                    cLevel,
                    msgPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    UInt64(message.count),
                    hashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                )
            }
        }

        guard result == 0 else {
            throw KazSignError(code: result)
        }

        return hashOutput
    }

    /// Hash a string message
    public func hash(message: String) throws -> Data {
        guard let messageData = message.data(using: .utf8) else {
            throw KazSignError.invalidParameter
        }
        return try hash(message: messageData)
    }
}

// MARK: - Static Compatibility API

/// Static compatibility layer for CryptoManager/KeyManager integration.
/// Provides the same interface as MLDSA enum for consistency.
enum KAZSIGN {

    // MARK: - Key Sizes (using level128 defaults)

    static let publicKeySize = 54   // level128 public key size
    static let privateKeySize = 32  // level128 secret key size
    static let signatureSize = 162  // level128 signature overhead

    // MARK: - Errors

    enum Error: Swift.Error {
        case keyGenerationFailed
        case signingFailed
        case verificationFailed
        case invalidKeySize
        case invalidSignature
        case initializationFailed
    }

    // MARK: - Private State

    private static var _signer: KazSigner?
    private static let lock = NSLock()

    // MARK: - Key Generation

    /// Generate a KAZ-SIGN key pair
    /// - Returns: Tuple of (publicKey, privateKey)
    static func generateKeyPair() throws -> (publicKey: Data, privateKey: Data) {
        let signer = try ensureInitialized()
        let keyPair = try signer.generateKeyPair()
        return (keyPair.publicKey, keyPair.secretKey)
    }

    // MARK: - Signing

    /// Sign a message using private key
    /// - Parameters:
    ///   - message: The message to sign
    ///   - privateKey: The signer's private key
    /// - Returns: The signature
    static func sign(message: Data, privateKey: Data) throws -> Data {
        let signer = try ensureInitialized()
        let result = try signer.sign(message: message, secretKey: privateKey)
        return result.signature
    }

    // MARK: - Verification

    /// Verify a signature
    /// - Parameters:
    ///   - signature: The signature to verify
    ///   - message: The original message (used to verify that the signed message matches)
    ///   - publicKey: The signer's public key
    /// - Returns: True if valid and message matches, false otherwise
    static func verify(signature: Data, message: Data, publicKey: Data) throws -> Bool {
        let signer = try ensureInitialized()
        let result = try signer.verify(signature: signature, publicKey: publicKey)

        // Signature must be valid AND the extracted message must match the expected message
        guard result.isValid, let extractedMessage = result.message else {
            return false
        }
        return extractedMessage == message
    }

    // MARK: - Private Helpers

    private static func ensureInitialized() throws -> KazSigner {
        lock.lock()
        defer { lock.unlock() }

        if let signer = _signer {
            return signer
        }

        // Default to level128 (128-bit security)
        let signer = try KazSigner(level: .level128)
        _signer = signer
        return signer
    }
}
