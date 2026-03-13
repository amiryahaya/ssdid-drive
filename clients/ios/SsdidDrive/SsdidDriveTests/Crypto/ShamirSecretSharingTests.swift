import XCTest
import Security
@testable import SsdidDrive

final class ShamirSecretSharingTests: XCTestCase {

    // MARK: - Split and Reconstruct

    func testSplitAndReconstructWithShares12() throws {
        let secret = Data(0..<32)
        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let result = try ShamirSecretSharing.reconstruct(shares: [shares[0], shares[1]], threshold: 2)
        XCTAssertEqual(result, secret)
    }

    func testSplitAndReconstructWithShares13() throws {
        let secret = Data(0..<32)
        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let result = try ShamirSecretSharing.reconstruct(shares: [shares[0], shares[2]], threshold: 2)
        XCTAssertEqual(result, secret)
    }

    func testSplitAndReconstructWithShares23() throws {
        let secret = Data(0..<32)
        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let result = try ShamirSecretSharing.reconstruct(shares: [shares[1], shares[2]], threshold: 2)
        XCTAssertEqual(result, secret)
    }

    func testAllCombinationsWithRandomKey() throws {
        var secret = Data(count: 32)
        _ = secret.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }

        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let combos: [(Int, Int)] = [(0, 1), (0, 2), (1, 2)]
        for (i, j) in combos {
            let result = try ShamirSecretSharing.reconstruct(shares: [shares[i], shares[j]], threshold: 2)
            XCTAssertEqual(result, secret, "Failed for combination (\(i), \(j))")
        }
    }

    // MARK: - Threshold 3 of 5

    func testThreshold3of5() throws {
        let secret = Data(0..<16)
        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 3, totalShares: 5)
        let result = try ShamirSecretSharing.reconstruct(shares: [shares[0], shares[2], shares[4]], threshold: 3)
        XCTAssertEqual(result, secret)
    }

    // MARK: - Single Share Insufficient

    func testSingleShareCannotReconstruct() throws {
        let secret = Data(0..<32)
        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        XCTAssertThrowsError(
            try ShamirSecretSharing.reconstruct(shares: [shares[0]], threshold: 2)
        ) { error in
            XCTAssertTrue(
                error is ShamirSecretSharing.Error,
                "Expected ShamirSecretSharing.Error, got \(error)"
            )
        }
    }

    // MARK: - Share Serialization Roundtrip

    func testShareSerializeDeserializeRoundtrip() throws {
        let secret = Data(0..<32)
        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 3)
        let share = shares[0]

        let serialized = share.serialize()
        let restored = try ShamirSecretSharing.Share.deserialize(serialized)

        XCTAssertEqual(restored.index, share.index)
        XCTAssertEqual(restored.data, share.data)
    }

    // MARK: - Share Indices are Unique

    func testShareIndicesAreUnique() throws {
        let secret = Data(repeating: 0xAB, count: 16)
        let shares = try ShamirSecretSharing.split(secret: secret, threshold: 2, totalShares: 5)
        let indices = shares.map { $0.index }
        XCTAssertEqual(indices.count, Set(indices).count, "All share indices must be unique")
    }

    // MARK: - Empty Secret

    func testEmptySecretThrows() {
        XCTAssertThrowsError(
            try ShamirSecretSharing.split(secret: Data(), threshold: 2, totalShares: 3)
        ) { error in
            XCTAssertEqual(
                error as? ShamirSecretSharing.Error,
                .emptySecret
            )
        }
    }

    // MARK: - Invalid Threshold

    func testThresholdBelowTwoThrows() {
        XCTAssertThrowsError(
            try ShamirSecretSharing.split(secret: Data(0..<16), threshold: 1, totalShares: 3)
        ) { error in
            XCTAssertEqual(
                error as? ShamirSecretSharing.Error,
                .invalidThreshold
            )
        }
    }

    func testThresholdExceedsTotalSharesThrows() {
        XCTAssertThrowsError(
            try ShamirSecretSharing.split(secret: Data(0..<16), threshold: 4, totalShares: 3)
        ) { error in
            XCTAssertEqual(
                error as? ShamirSecretSharing.Error,
                .invalidThreshold
            )
        }
    }
}

// MARK: - Equatable conformance for assertion helpers

extension ShamirSecretSharing.Error: Equatable {
    public static func == (lhs: ShamirSecretSharing.Error, rhs: ShamirSecretSharing.Error) -> Bool {
        switch (lhs, rhs) {
        case (.invalidThreshold, .invalidThreshold),
             (.insufficientShares, .insufficientShares),
             (.invalidShareFormat, .invalidShareFormat),
             (.duplicateShareIndices, .duplicateShareIndices),
             (.randomGenerationFailed, .randomGenerationFailed),
             (.emptySecret, .emptySecret):
            return true
        default:
            return false
        }
    }
}
