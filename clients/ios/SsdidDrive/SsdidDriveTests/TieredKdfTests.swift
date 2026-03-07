import XCTest
@testable import SsdidDrive

final class TieredKdfTests: XCTestCase {

    // MARK: - KdfProfile Tests

    func testProfileBytesMatchSpec() {
        XCTAssertEqual(KdfProfile.argon2idStandard.rawValue, 0x01)
        XCTAssertEqual(KdfProfile.argon2idLow.rawValue, 0x02)
        XCTAssertEqual(KdfProfile.bcryptHkdf.rawValue, 0x03)
    }

    func testProfileFromByteRoundtrip() throws {
        for profile in [KdfProfile.argon2idStandard, .argon2idLow, .bcryptHkdf] {
            let parsed = try KdfProfile.fromByte(profile.rawValue)
            XCTAssertEqual(profile, parsed)
        }
    }

    func testProfileFromInvalidByteThrows() {
        XCTAssertThrowsError(try KdfProfile.fromByte(0x00))
        XCTAssertThrowsError(try KdfProfile.fromByte(0x04))
        XCTAssertThrowsError(try KdfProfile.fromByte(0xFF))
    }

    // MARK: - Salt Format Tests

    func testCreateSaltWithProfileSize() {
        for profile in [KdfProfile.argon2idStandard, .argon2idLow, .bcryptHkdf] {
            let salt = KdfProfile.createSaltWithProfile(profile)
            XCTAssertEqual(salt.count, KdfProfile.wireSaltSize)
        }
    }

    func testCreateSaltWithProfileByte() {
        for profile in [KdfProfile.argon2idStandard, .argon2idLow, .bcryptHkdf] {
            let salt = KdfProfile.createSaltWithProfile(profile)
            XCTAssertEqual(salt[0], profile.rawValue)
        }
    }

    func testCreateSaltProducesUniqueSalts() {
        let salt1 = KdfProfile.createSaltWithProfile(.argon2idStandard)
        let salt2 = KdfProfile.createSaltWithProfile(.argon2idStandard)
        XCTAssertNotEqual(salt1, salt2)
    }

    func testIsTieredSaltValid() {
        for profile in [KdfProfile.argon2idStandard, .argon2idLow, .bcryptHkdf] {
            let salt = KdfProfile.createSaltWithProfile(profile)
            XCTAssertTrue(KdfProfile.isTieredSalt(salt))
        }
    }

    func testIsTieredSaltLegacy16Bytes() {
        let legacySalt = Data(repeating: 0x42, count: 16)
        XCTAssertFalse(KdfProfile.isTieredSalt(legacySalt))
    }

    func testIsTieredSaltLegacy32Bytes() {
        let legacySalt = Data(repeating: 0x42, count: 32)
        XCTAssertFalse(KdfProfile.isTieredSalt(legacySalt))
    }

    // MARK: - Tiered KDF Derivation Tests

    func testArgon2idStandardDeterministic() throws {
        let salt = KdfProfile.createSaltWithProfile(.argon2idStandard)
        let key1 = try TieredKdf.deriveKey(password: "test password", saltWithProfile: salt)
        let key2 = try TieredKdf.deriveKey(password: "test password", saltWithProfile: salt)

        XCTAssertEqual(
            key1.withUnsafeBytes { Data($0) },
            key2.withUnsafeBytes { Data($0) }
        )
    }

    func testArgon2idLowDeterministic() throws {
        let salt = KdfProfile.createSaltWithProfile(.argon2idLow)
        let key1 = try TieredKdf.deriveKey(password: "test password", saltWithProfile: salt)
        let key2 = try TieredKdf.deriveKey(password: "test password", saltWithProfile: salt)

        XCTAssertEqual(
            key1.withUnsafeBytes { Data($0) },
            key2.withUnsafeBytes { Data($0) }
        )
    }

    func testBcryptHkdfDeterministic() throws {
        let salt = KdfProfile.createSaltWithProfile(.bcryptHkdf)
        let key1 = try TieredKdf.deriveKey(password: "test password", saltWithProfile: salt)
        let key2 = try TieredKdf.deriveKey(password: "test password", saltWithProfile: salt)

        XCTAssertEqual(
            key1.withUnsafeBytes { Data($0) },
            key2.withUnsafeBytes { Data($0) }
        )
    }

    func testDifferentProfilesProduceDifferentKeys() throws {
        let rawSalt = Data(repeating: 0x42, count: 16)

        var saltStandard = Data([0x01])
        saltStandard.append(rawSalt)

        var saltLow = Data([0x02])
        saltLow.append(rawSalt)

        var saltBcrypt = Data([0x03])
        saltBcrypt.append(rawSalt)

        let keyStandard = try TieredKdf.deriveKey(password: "test", saltWithProfile: saltStandard)
        let keyLow = try TieredKdf.deriveKey(password: "test", saltWithProfile: saltLow)
        let keyBcrypt = try TieredKdf.deriveKey(password: "test", saltWithProfile: saltBcrypt)

        let dataStandard = keyStandard.withUnsafeBytes { Data($0) }
        let dataLow = keyLow.withUnsafeBytes { Data($0) }
        let dataBcrypt = keyBcrypt.withUnsafeBytes { Data($0) }

        XCTAssertNotEqual(dataStandard, dataLow)
        XCTAssertNotEqual(dataStandard, dataBcrypt)
        XCTAssertNotEqual(dataLow, dataBcrypt)
    }

    // MARK: - Legacy Fallback Tests

    func testLegacySaltFallsThroughToLegacyKdf() throws {
        // 16-byte legacy salt should use PBKDF2 fallback
        let legacySalt = Data(repeating: 0x42, count: 16)
        let key = try TieredKdf.deriveKey(password: "test password", saltWithProfile: legacySalt)
        // Should succeed without error (using PBKDF2)
        let keyData = key.withUnsafeBytes { Data($0) }
        XCTAssertEqual(keyData.count, 32)
    }

    // MARK: - Device Selection Test

    func testDeviceProfileSelection() {
        let profile = KdfProfile.selectForDevice()
        // On any modern test device/simulator, should be standard or low
        XCTAssertTrue([.argon2idStandard, .argon2idLow, .bcryptHkdf].contains(profile))
    }

    // MARK: - Cross-Platform Test Vector Assertions
    // These test vectors are from docs/crypto/07-test-vectors.md sections 5.2-5.4.
    // All platforms MUST produce identical output for the same inputs.

    private func hexToData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            data.append(UInt8(byteString, radix: 16)!)
            index = nextIndex
        }
        return data
    }

    private func dataToHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func testVector5_2Argon2idStandardMatchesReference() throws {
        let salt = hexToData("0102030405060708090a0b0c0d0e0f10")
        var wireSalt = Data([0x01])
        wireSalt.append(salt)

        let key = try TieredKdf.deriveKey(password: "correct horse battery staple", saltWithProfile: wireSalt)
        let keyData = key.withUnsafeBytes { Data($0) }

        XCTAssertEqual(
            dataToHex(keyData),
            "6ec690471257037ee9c75b275e6161c1c2f4335ab541400534dba6769a444397"
        )
    }

    func testVector5_3Argon2idLowMatchesReference() throws {
        let salt = hexToData("0102030405060708090a0b0c0d0e0f10")
        var wireSalt = Data([0x02])
        wireSalt.append(salt)

        let key = try TieredKdf.deriveKey(password: "correct horse battery staple", saltWithProfile: wireSalt)
        let keyData = key.withUnsafeBytes { Data($0) }

        XCTAssertEqual(
            dataToHex(keyData),
            "1025994eae82eff51c942eed6294d085a1d43526998ed20e22c1f63e1c592a88"
        )
    }

    func testVector5_4BcryptHkdfMatchesReference() throws {
        let salt = hexToData("0102030405060708090a0b0c0d0e0f10")
        var wireSalt = Data([0x03])
        wireSalt.append(salt)

        let key = try TieredKdf.deriveKey(password: "correct horse battery staple", saltWithProfile: wireSalt)
        let keyData = key.withUnsafeBytes { Data($0) }

        XCTAssertEqual(
            dataToHex(keyData),
            "eb9ffe4aa76d3cd79851cd1de39dbfa8ced4ad88b0eec1596c214bb733618279"
        )
    }
}
