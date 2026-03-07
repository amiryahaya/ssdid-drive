/*
 * ML-DSA Swift Wrapper for SsdidDrive
 * NIST FIPS 204 ML-DSA-65 Digital Signature Algorithm
 *
 * Wraps the MlDsaNative.xcframework which uses liboqs for real PQC.
 */

import Foundation
import CryptoKit

#if canImport(MlDsaNative)
import MlDsaNative
#endif

// MARK: - Error Types

/// Errors that can occur during ML-DSA operations
public enum MlDsaError: Error, LocalizedError, Sendable {
    case invalidParameter(String)
    case memoryAllocation
    case randomGenerationFailed
    case cryptographicError
    case notInitialized
    case invalidKeySize
    case invalidSignatureSize
    case verificationFailed
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
        case -8: self = .verificationFailed
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
            return "ML-DSA is not initialized. Call MlDsa.initialize() first."
        case .invalidKeySize:
            return "Invalid key size"
        case .invalidSignatureSize:
            return "Invalid signature size"
        case .verificationFailed:
            return "Signature verification failed"
        case .libraryNotAvailable:
            return "ML-DSA library (liboqs) not available"
        case .unknown(let code):
            return "Unknown error (code: \(code))"
        }
    }
}

// MARK: - Key Types

/// An ML-DSA key pair containing both public and secret keys
public final class MlDsaKeyPair: @unchecked Sendable {
    public let publicKey: Data
    private var _secretKey: Data

    public var secretKey: Data { _secretKey }
    public var publicKeySize: Int { publicKey.count }
    public var secretKeySize: Int { _secretKey.count }

    internal init(publicKey: Data, secretKey: Data) {
        self.publicKey = publicKey
        self._secretKey = secretKey
    }

    public func getPublicKey() -> MlDsaPublicKey {
        return MlDsaPublicKey(data: publicKey)
    }

    deinit {
        mlDsaSecureZero(&_secretKey)
    }
}

/// An ML-DSA public key (safe to share)
public struct MlDsaPublicKey: Sendable {
    public let data: Data
    public var size: Int { data.count }

    public init(data: Data) {
        self.data = data
    }
}

/// Result of a signing operation
public struct MlDsaSignatureResult: Sendable {
    public let signature: Data
    public let message: Data

    public var signatureSize: Int { signature.count }
    public var messageSize: Int { message.count }

    internal init(signature: Data, message: Data) {
        self.signature = signature
        self.message = message
    }
}

/// Result of a verification operation
public struct MlDsaVerificationResult: Sendable {
    public let isValid: Bool
    public let message: Data?

    internal init(isValid: Bool, message: Data? = nil) {
        self.isValid = isValid
        self.message = message
    }
}

// MARK: - MlDsa Main Class

/// ML-DSA-65 Post-Quantum Digital Signature Algorithm
public final class MlDsa: @unchecked Sendable {

    private static let lock = NSLock()
    private static var _current: MlDsa?

    // ML-DSA-65 sizes
    public static let publicKeySize = 1952
    public static let secretKeySize = 4032
    public static let signatureSize = 3309

    public static var version: String {
        #if canImport(MlDsaNative)
        guard let ptr = ml_dsa_version() else { return "unknown" }
        return String(cString: ptr)
        #else
        return "placeholder-1.0.0"
        #endif
    }

    public static var algorithm: String {
        #if canImport(MlDsaNative)
        guard let ptr = ml_dsa_algorithm() else { return "ML-DSA-65" }
        return String(cString: ptr)
        #else
        return "ML-DSA-65-placeholder"
        #endif
    }

    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(MlDsaNative)
        return _current != nil && ml_dsa_is_initialized() != 0
        #else
        return _current != nil
        #endif
    }

    public static var isNativeAvailable: Bool {
        #if canImport(MlDsaNative)
        return true
        #else
        return false
        #endif
    }

    public static var current: MlDsa {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            guard let instance = _current else {
                throw MlDsaError.notInitialized
            }
            return instance
        }
    }

    private init() {}

    @discardableResult
    public static func initialize() throws -> MlDsa {
        lock.lock()
        defer { lock.unlock() }

        if let current = _current {
            return current
        }

        #if canImport(MlDsaNative)
        let result = ml_dsa_init()
        if result != 0 {
            throw MlDsaError(code: result, operation: "initialize")
        }
        #endif

        let instance = MlDsa()
        _current = instance
        return instance
    }

    public static func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        if _current != nil {
            #if canImport(MlDsaNative)
            ml_dsa_cleanup()
            #endif
            _current = nil
        }
    }

    // MARK: - Key Generation

    public func generateKeyPair() throws -> MlDsaKeyPair {
        #if canImport(MlDsaNative)
        guard ml_dsa_is_initialized() != 0 else {
            throw MlDsaError.notInitialized
        }

        var publicKey = [UInt8](repeating: 0, count: MlDsa.publicKeySize)
        var secretKey = [UInt8](repeating: 0, count: MlDsa.secretKeySize)

        let result = ml_dsa_keypair(&publicKey, &secretKey)
        if result != 0 {
            mlDsaSecureZero(&secretKey)
            throw MlDsaError(code: result, operation: "generateKeyPair")
        }

        return MlDsaKeyPair(
            publicKey: Data(publicKey),
            secretKey: Data(secretKey)
        )
        #else
        return try generateKeyPairPlaceholder()
        #endif
    }

    public static func generateKeyPair() throws -> MlDsaKeyPair {
        return try current.generateKeyPair()
    }

    // MARK: - Signing

    public func sign(message: Data, keyPair: MlDsaKeyPair) throws -> MlDsaSignatureResult {
        return try sign(message: message, secretKey: keyPair.secretKey)
    }

    public func sign(message: Data, secretKey: Data) throws -> MlDsaSignatureResult {
        guard secretKey.count == MlDsa.secretKeySize else {
            throw MlDsaError.invalidKeySize
        }

        #if canImport(MlDsaNative)
        guard ml_dsa_is_initialized() != 0 else {
            throw MlDsaError.notInitialized
        }

        var signature = [UInt8](repeating: 0, count: MlDsa.signatureSize)
        var signatureLength: Int = 0

        let result = message.withUnsafeBytes { msgPtr -> Int32 in
            secretKey.withUnsafeBytes { skPtr -> Int32 in
                return ml_dsa_sign(
                    &signature,
                    &signatureLength,
                    msgPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    message.count,
                    skPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                )
            }
        }

        if result != 0 {
            throw MlDsaError(code: result, operation: "sign")
        }

        return MlDsaSignatureResult(
            signature: Data(signature.prefix(signatureLength)),
            message: message
        )
        #else
        return try signPlaceholder(message: message, secretKey: secretKey)
        #endif
    }

    public func sign(message: String, secretKey: Data) throws -> MlDsaSignatureResult {
        guard let messageData = message.data(using: .utf8) else {
            throw MlDsaError.invalidParameter("message encoding")
        }
        return try sign(message: messageData, secretKey: secretKey)
    }

    public static func sign(message: Data, secretKey: Data) throws -> MlDsaSignatureResult {
        return try current.sign(message: message, secretKey: secretKey)
    }

    // MARK: - Verification

    public func verify(signature: Data, message: Data, publicKey: Data) throws -> Bool {
        guard publicKey.count == MlDsa.publicKeySize else {
            throw MlDsaError.invalidKeySize
        }
        guard signature.count <= MlDsa.signatureSize else {
            throw MlDsaError.invalidSignatureSize
        }

        #if canImport(MlDsaNative)
        guard ml_dsa_is_initialized() != 0 else {
            throw MlDsaError.notInitialized
        }

        let result = message.withUnsafeBytes { msgPtr -> Int32 in
            signature.withUnsafeBytes { sigPtr -> Int32 in
                publicKey.withUnsafeBytes { pkPtr -> Int32 in
                    return ml_dsa_verify(
                        msgPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        message.count,
                        sigPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        signature.count,
                        pkPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    )
                }
            }
        }

        return result == 0
        #else
        return try verifyPlaceholder(signature: signature, message: message, publicKey: publicKey)
        #endif
    }

    public func verify(signature: Data, message: String, publicKey: Data) throws -> Bool {
        guard let messageData = message.data(using: .utf8) else {
            throw MlDsaError.invalidParameter("message encoding")
        }
        return try verify(signature: signature, message: messageData, publicKey: publicKey)
    }

    public static func verify(signature: Data, message: Data, publicKey: Data) throws -> Bool {
        return try current.verify(signature: signature, message: message, publicKey: publicKey)
    }

    // MARK: - Placeholder Implementation (fallback when native not available)

    #if !canImport(MlDsaNative)
    private static let domainSeparator = "SsdidDrive-MLDSA-Placeholder-v1".data(using: .utf8)!
    private static let hmacSize = 64

    private func generateKeyPairPlaceholder() throws -> MlDsaKeyPair {
        var seed = Data(count: 64)
        let result = seed.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 64, ptr.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw MlDsaError.randomGenerationFailed
        }

        let signingKey = deriveKeyMaterial(from: seed, info: "mldsa-signing-key", length: 64)

        var publicKey = signingKey
        publicKey.append(deriveKeyMaterial(
            from: seed,
            info: "mldsa-public-key-padding",
            length: MlDsa.publicKeySize - 64
        ))

        var secretKey = seed
        secretKey.append(deriveKeyMaterial(
            from: seed,
            info: "mldsa-secret-key-padding",
            length: MlDsa.secretKeySize - 64
        ))

        return MlDsaKeyPair(publicKey: publicKey, secretKey: secretKey)
    }

    private func signPlaceholder(message: Data, secretKey: Data) throws -> MlDsaSignatureResult {
        let seed = secretKey.prefix(64)
        let signingKey = deriveKeyMaterial(from: Data(seed), info: "mldsa-signing-key", length: 64)

        let signatureKey = SymmetricKey(data: signingKey)
        let signatureInput = MlDsa.domainSeparator + message

        var signature = Data(HMAC<SHA512>.authenticationCode(for: signatureInput, using: signatureKey))

        if signature.count < MlDsa.signatureSize {
            let padding = deriveKeyMaterial(
                from: signature,
                info: "mldsa-signature-padding",
                length: MlDsa.signatureSize - MlDsa.hmacSize
            )
            signature.append(padding)
        }

        return MlDsaSignatureResult(signature: signature, message: message)
    }

    private func verifyPlaceholder(signature: Data, message: Data, publicKey: Data) throws -> Bool {
        let signatureHMAC = signature.prefix(MlDsa.hmacSize)
        let signingKey = publicKey.prefix(64)

        let signatureKey = SymmetricKey(data: signingKey)
        let signatureInput = MlDsa.domainSeparator + message

        let expectedHMAC = Data(HMAC<SHA512>.authenticationCode(for: signatureInput, using: signatureKey))

        return constantTimeCompare(Data(signatureHMAC), expectedHMAC)
    }

    private func deriveKeyMaterial(from input: Data, info: String, length: Int) -> Data {
        let infoData = info.data(using: .utf8)!
        let salt = MlDsa.domainSeparator

        let inputKey = SymmetricKey(data: input)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: infoData,
            outputByteCount: length
        )

        return derivedKey.withUnsafeBytes { Data($0) }
    }

    private func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[a.startIndex.advanced(by: i)] ^ b[b.startIndex.advanced(by: i)]
        }
        return result == 0
    }
    #endif
}

// MARK: - Secure Memory Utilities

@inline(__always)
internal func mlDsaSecureZero(_ data: inout Data) {
    data.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset(baseAddress, 0, ptr.count)
            OSMemoryBarrier()
        }
    }
    data = Data()
}

@inline(__always)
internal func mlDsaSecureZero(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { ptr in
        if let baseAddress = ptr.baseAddress {
            memset(baseAddress, 0, ptr.count)
            OSMemoryBarrier()
        }
    }
}

// MARK: - Static Compatibility API (MLDSA enum)

/// Static compatibility layer for CryptoManager/KeyManager integration.
/// Maintains the same interface as the original placeholder implementation.
enum MLDSA {

    // MARK: - Key Sizes (ML-DSA-65)

    static let publicKeySize = Constants.Crypto.mlDsaPublicKeySize   // 1952 bytes
    static let privateKeySize = Constants.Crypto.mlDsaPrivateKeySize // 4032 bytes
    static let signatureSize = Constants.Crypto.mlDsaSignatureSize   // 3309 bytes

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case keyGenerationFailed
        case signingFailed
        case verificationFailed
        case invalidKeySize
        case invalidSignature

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "ML-DSA key generation failed"
            case .signingFailed: return "ML-DSA signing failed"
            case .verificationFailed: return "ML-DSA verification failed"
            case .invalidKeySize: return "Invalid ML-DSA key size"
            case .invalidSignature: return "Invalid ML-DSA signature"
            }
        }
    }

    // MARK: - Initialization

    /// Initialize ML-DSA library
    /// - Parameter level: Security level (ignored, always uses ML-DSA-65)
    static func initialize(_ level: Int = 192) throws {
        try MlDsa.initialize()
    }

    // MARK: - Key Generation

    /// Generate an ML-DSA-65 key pair
    /// - Returns: Tuple of (publicKey, privateKey)
    static func generateKeyPair() throws -> (publicKey: Data, privateKey: Data) {
        let dsa = try ensureInitialized()
        let keyPair = try dsa.generateKeyPair()
        return (keyPair.publicKey, keyPair.secretKey)
    }

    // MARK: - Signing

    /// Sign a message using private key
    /// - Parameters:
    ///   - message: The message to sign
    ///   - privateKey: The signer's private key
    /// - Returns: The signature
    static func sign(message: Data, privateKey: Data) throws -> Data {
        guard privateKey.count == privateKeySize else {
            throw Error.invalidKeySize
        }

        let dsa = try ensureInitialized()
        let result = try dsa.sign(message: message, secretKey: privateKey)
        return result.signature
    }

    // MARK: - Verification

    /// Verify a signature
    /// - Parameters:
    ///   - signature: The signature to verify
    ///   - message: The original message
    ///   - publicKey: The signer's public key
    /// - Returns: True if valid, false otherwise
    static func verify(signature: Data, message: Data, publicKey: Data) throws -> Bool {
        guard publicKey.count == publicKeySize else {
            throw Error.invalidKeySize
        }

        let dsa = try ensureInitialized()
        return try dsa.verify(signature: signature, message: message, publicKey: publicKey)
    }

    // MARK: - Private Helpers

    private static func ensureInitialized() throws -> MlDsa {
        if MlDsa.isInitialized {
            return try MlDsa.current
        }
        return try MlDsa.initialize()
    }
}
