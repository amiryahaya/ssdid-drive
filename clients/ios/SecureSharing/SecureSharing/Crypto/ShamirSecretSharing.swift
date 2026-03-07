import Foundation
import Security

/// Shamir's Secret Sharing implementation over GF(256)
/// Allows splitting a secret into n shares such that any k (threshold) shares can reconstruct it.
enum ShamirSecretSharing {

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case invalidThreshold
        case insufficientShares
        case invalidShareFormat
        case duplicateShareIndices
        case randomGenerationFailed
        case emptySecret

        var errorDescription: String? {
            switch self {
            case .invalidThreshold:
                return "Threshold must be at least 2 and not exceed total shares"
            case .insufficientShares:
                return "Not enough shares to reconstruct the secret"
            case .invalidShareFormat:
                return "Invalid share format"
            case .duplicateShareIndices:
                return "Duplicate share indices detected"
            case .randomGenerationFailed:
                return "Failed to generate secure random bytes"
            case .emptySecret:
                return "Secret cannot be empty"
            }
        }
    }

    // MARK: - Share Type

    /// A share of a secret, containing an index and the share data
    struct Share: Codable, Equatable {
        /// The x-coordinate (1-indexed) of this share
        let index: UInt8
        /// The share data (same length as original secret)
        let data: Data

        /// Serialize the share for storage/transmission
        func serialize() -> Data {
            var result = Data()
            result.append(index)
            result.append(data)
            return result
        }

        /// Deserialize a share from stored format
        static func deserialize(_ data: Data) throws -> Share {
            guard data.count >= 2 else {
                throw Error.invalidShareFormat
            }
            let index = data[data.startIndex]
            guard index > 0 else {
                throw Error.invalidShareFormat
            }
            let shareData = data.dropFirst()
            return Share(index: index, data: Data(shareData))
        }
    }

    // MARK: - Galois Field GF(256) Operations

    /// Precomputed exponential table for GF(256) using AES polynomial (0x11B)
    private static let expTable: [UInt8] = {
        var exp = [UInt8](repeating: 0, count: 512)
        var x: UInt16 = 1
        for i in 0..<255 {
            exp[i] = UInt8(x)
            exp[i + 255] = UInt8(x)
            x <<= 1
            if x & 0x100 != 0 {
                x ^= 0x11B // AES irreducible polynomial
            }
        }
        return exp
    }()

    /// Precomputed logarithm table for GF(256)
    private static let logTable: [UInt8] = {
        var log = [UInt8](repeating: 0, count: 256)
        for i in 0..<255 {
            log[Int(expTable[i])] = UInt8(i)
        }
        return log
    }()

    /// Multiply two elements in GF(256)
    private static func gfMultiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
        if a == 0 || b == 0 { return 0 }
        let logA = Int(logTable[Int(a)])
        let logB = Int(logTable[Int(b)])
        return expTable[logA + logB]
    }

    /// Compute multiplicative inverse in GF(256)
    private static func gfInverse(_ a: UInt8) -> UInt8 {
        guard a != 0 else { return 0 }
        return expTable[255 - Int(logTable[Int(a)])]
    }

    /// Add two elements in GF(256) (same as XOR)
    private static func gfAdd(_ a: UInt8, _ b: UInt8) -> UInt8 {
        return a ^ b
    }

    // MARK: - Split Secret

    /// Split a secret into shares using Shamir's Secret Sharing
    /// - Parameters:
    ///   - secret: The secret data to split
    ///   - threshold: Minimum shares needed to reconstruct (k)
    ///   - totalShares: Total number of shares to generate (n)
    /// - Returns: Array of shares
    static func split(secret: Data, threshold: Int, totalShares: Int) throws -> [Share] {
        // Validation
        guard !secret.isEmpty else {
            throw Error.emptySecret
        }
        guard threshold >= 2 else {
            throw Error.invalidThreshold
        }
        guard totalShares >= threshold else {
            throw Error.invalidThreshold
        }
        guard totalShares <= 255 else {
            throw Error.invalidThreshold // GF(256) limits indices to 1-255
        }

        // Generate random coefficients for polynomial
        // For each byte of the secret, we create a polynomial of degree (threshold-1)
        // where the constant term (coefficient[0]) is the secret byte
        var coefficients = [[UInt8]](repeating: [], count: secret.count)

        for i in 0..<secret.count {
            var polyCoeffs = [UInt8](repeating: 0, count: threshold)
            polyCoeffs[0] = secret[secret.startIndex.advanced(by: i)]

            // Generate random coefficients for higher-order terms
            if threshold > 1 {
                var randomBytes = [UInt8](repeating: 0, count: threshold - 1)
                let result = SecRandomCopyBytes(kSecRandomDefault, threshold - 1, &randomBytes)
                guard result == errSecSuccess else {
                    throw Error.randomGenerationFailed
                }

                for j in 1..<threshold {
                    polyCoeffs[j] = randomBytes[j - 1]
                }
            }

            coefficients[i] = polyCoeffs
        }

        // Generate shares by evaluating the polynomial at different x values
        var shares = [Share]()
        for x in 1...totalShares {
            var shareData = Data(count: secret.count)

            for i in 0..<secret.count {
                // Evaluate polynomial at x using Horner's method
                var y: UInt8 = 0
                let xByte = UInt8(x)

                // p(x) = c[0] + c[1]*x + c[2]*x^2 + ... + c[k-1]*x^(k-1)
                // Using Horner's method: p(x) = c[0] + x*(c[1] + x*(c[2] + ...))
                for j in (0..<threshold).reversed() {
                    y = gfAdd(gfMultiply(y, xByte), coefficients[i][j])
                }

                shareData[shareData.startIndex.advanced(by: i)] = y
            }

            shares.append(Share(index: UInt8(x), data: shareData))
        }

        return shares
    }

    // MARK: - Reconstruct Secret

    /// Reconstruct a secret from shares using Lagrange interpolation
    /// - Parameters:
    ///   - shares: The shares to combine (must have at least threshold shares)
    ///   - threshold: The threshold used when splitting
    /// - Returns: The reconstructed secret
    static func reconstruct(shares: [Share], threshold: Int) throws -> Data {
        // Validation
        guard shares.count >= threshold else {
            throw Error.insufficientShares
        }

        guard !shares.isEmpty, let firstShare = shares.first, !firstShare.data.isEmpty else {
            throw Error.invalidShareFormat
        }

        // Check for duplicate indices
        let indices = Set(shares.map { $0.index })
        guard indices.count == shares.count else {
            throw Error.duplicateShareIndices
        }

        // All shares must have the same length
        let secretLength = shares[0].data.count
        guard shares.allSatisfy({ $0.data.count == secretLength }) else {
            throw Error.invalidShareFormat
        }

        // Use exactly threshold shares
        let usedShares = Array(shares.prefix(threshold))

        // Reconstruct each byte using Lagrange interpolation at x=0
        var secret = Data(count: secretLength)

        for byteIndex in 0..<secretLength {
            var result: UInt8 = 0

            for i in 0..<threshold {
                let xi = usedShares[i].index
                let yi = usedShares[i].data[usedShares[i].data.startIndex.advanced(by: byteIndex)]

                // Compute Lagrange basis polynomial L_i(0)
                // L_i(0) = product of (-x_j) / (x_i - x_j) for all j != i
                // In GF(256): -x = x, division = multiply by inverse
                var numerator: UInt8 = 1
                var denominator: UInt8 = 1

                for j in 0..<threshold {
                    if i != j {
                        let xj = usedShares[j].index
                        numerator = gfMultiply(numerator, xj)
                        denominator = gfMultiply(denominator, gfAdd(xi, xj))
                    }
                }

                // L_i(0) * y_i
                let lagrangeTerm = gfMultiply(yi, gfMultiply(numerator, gfInverse(denominator)))
                result = gfAdd(result, lagrangeTerm)
            }

            secret[secret.startIndex.advanced(by: byteIndex)] = result
        }

        return secret
    }

    // MARK: - Convenience Methods

    /// Split and serialize shares for easy storage
    static func splitToSerializedShares(secret: Data, threshold: Int, totalShares: Int) throws -> [Data] {
        let shares = try split(secret: secret, threshold: threshold, totalShares: totalShares)
        return shares.map { $0.serialize() }
    }

    /// Deserialize and reconstruct
    static func reconstructFromSerializedShares(serializedShares: [Data], threshold: Int) throws -> Data {
        let shares = try serializedShares.map { try Share.deserialize($0) }
        return try reconstruct(shares: shares, threshold: threshold)
    }
}
