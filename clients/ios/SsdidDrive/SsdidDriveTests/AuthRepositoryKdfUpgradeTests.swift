import XCTest
import CryptoKit
@testable import SsdidDrive

/// Tests for KDF profile upgrade decision logic used by AuthRepositoryImpl.upgradeKdfProfileIfNeeded().
///
/// Since AuthRepositoryImpl takes a concrete APIClient actor (not a protocol), we can't inject
/// mocks to test upgradeKdfProfileIfNeeded() end-to-end through login(). Instead, we test the
/// core decision logic and cryptographic operations that the upgrade path depends on:
///
/// 1. Upgrade decision: comparing current salt profile vs device profile
/// 2. Salt re-creation with stronger profile
/// 3. Master key re-encryption with new derived key
/// 4. Legacy (non-tiered) salt detection triggering upgrade
final class AuthRepositoryKdfUpgradeTests: XCTestCase {

    // MARK: - Upgrade Decision Logic

    func testWeakerProfileShouldTriggerUpgrade() throws {
        // Simulate: device supports argon2idStandard (0x01),
        // server salt has bcryptHkdf (0x03) — weaker, should upgrade
        let deviceProfile = KdfProfile.argon2idStandard
        let serverSalt = KdfProfile.createSaltWithProfile(.bcryptHkdf)

        let currentProfile = try KdfProfile.fromByte(serverSalt[serverSalt.startIndex])

        // Profile bytes: lower = stronger (0x01 < 0x03)
        // upgradeKdfProfileIfNeeded checks: currentProfile.rawValue > deviceProfile.rawValue
        let needsUpgrade = currentProfile.rawValue > deviceProfile.rawValue
        XCTAssertTrue(needsUpgrade, "bcryptHkdf (0x03) should trigger upgrade to argon2idStandard (0x01)")
    }

    func testSameProfileShouldNotTriggerUpgrade() throws {
        // Simulate: device supports argon2idStandard (0x01),
        // server salt also uses argon2idStandard (0x01) — no upgrade needed
        let deviceProfile = KdfProfile.argon2idStandard
        let serverSalt = KdfProfile.createSaltWithProfile(.argon2idStandard)

        let currentProfile = try KdfProfile.fromByte(serverSalt[serverSalt.startIndex])

        let needsUpgrade = currentProfile.rawValue > deviceProfile.rawValue
        XCTAssertFalse(needsUpgrade, "Same profile should not trigger upgrade")
    }

    func testStrongerProfileShouldNotTriggerUpgrade() throws {
        // Simulate: device supports argon2idLow (0x02),
        // server salt uses argon2idStandard (0x01) — already stronger
        let deviceProfile = KdfProfile.argon2idLow
        let serverSalt = KdfProfile.createSaltWithProfile(.argon2idStandard)

        let currentProfile = try KdfProfile.fromByte(serverSalt[serverSalt.startIndex])

        let needsUpgrade = currentProfile.rawValue > deviceProfile.rawValue
        XCTAssertFalse(needsUpgrade, "Stronger existing profile should not trigger downgrade")
    }

    func testLegacySaltShouldAlwaysTriggerUpgrade() {
        // Legacy salts (16 bytes, no profile byte) should always trigger upgrade
        let legacySalt = Data(repeating: 0x42, count: 16)
        let needsUpgrade = !KdfProfile.isTieredSalt(legacySalt)
        XCTAssertTrue(needsUpgrade, "Legacy 16-byte salt should always trigger upgrade")
    }

    func testArgon2idLowShouldUpgradeToStandard() throws {
        // Simulate: device supports standard, server uses low
        let deviceProfile = KdfProfile.argon2idStandard
        let serverSalt = KdfProfile.createSaltWithProfile(.argon2idLow)

        let currentProfile = try KdfProfile.fromByte(serverSalt[serverSalt.startIndex])

        let needsUpgrade = currentProfile.rawValue > deviceProfile.rawValue
        XCTAssertTrue(needsUpgrade, "argon2idLow (0x02) should upgrade to argon2idStandard (0x01)")
    }

    // MARK: - Re-encryption Path

    func testMasterKeyReEncryptionWithStrongerProfile() throws {
        // Simulate the full re-encryption path that upgradeKdfProfileIfNeeded performs:
        // 1. Decrypt master key with old salt's derived key
        // 2. Re-encrypt with new (stronger) salt's derived key
        // 3. Verify round-trip

        let password = "test-upgrade-password"

        // Create old salt (bcryptHkdf profile — weakest)
        let oldSalt = KdfProfile.createSaltWithProfile(.bcryptHkdf)
        let oldKey = try TieredKdf.deriveKey(password: password, saltWithProfile: oldSalt)

        // Create a "master key" and encrypt it with old key
        let masterKey = SymmetricKey(size: .bits256)
        let masterKeyData = masterKey.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(masterKeyData, using: oldKey)
        guard let encryptedMasterKey = sealed.combined else {
            XCTFail("Failed to seal master key")
            return
        }

        // Decrypt with old key (as upgradeKdfProfileIfNeeded does)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedMasterKey)
        let decryptedMasterKey = try AES.GCM.open(sealedBox, using: oldKey)

        // Generate new salt with stronger profile
        let newSalt = KdfProfile.createSaltWithProfile(.argon2idStandard)
        XCTAssertEqual(newSalt[0], 0x01, "New salt should have argon2idStandard profile byte")

        let newKey = try TieredKdf.deriveKey(password: password, saltWithProfile: newSalt)

        // Re-encrypt master key with new key
        let newSealed = try AES.GCM.seal(decryptedMasterKey, using: newKey)
        guard let newEncryptedMasterKey = newSealed.combined else {
            XCTFail("Failed to re-seal master key")
            return
        }

        // Verify: decrypt with new key should recover original master key
        let finalBox = try AES.GCM.SealedBox(combined: newEncryptedMasterKey)
        let finalMasterKey = try AES.GCM.open(finalBox, using: newKey)

        XCTAssertEqual(finalMasterKey, masterKeyData, "Re-encrypted master key should decrypt to original")
    }

    func testNewSaltHasCorrectProfileByte() {
        // After upgrade, the new salt must have the device's profile byte
        let profiles: [KdfProfile] = [.argon2idStandard, .argon2idLow, .bcryptHkdf]

        for profile in profiles {
            let salt = KdfProfile.createSaltWithProfile(profile)
            XCTAssertEqual(salt.count, KdfProfile.wireSaltSize)
            XCTAssertEqual(salt[0], profile.rawValue)
            XCTAssertTrue(KdfProfile.isTieredSalt(salt))
        }
    }

    // MARK: - Profile Ordering

    func testProfileOrderingMatchesUpgradeLogic() {
        // The upgrade logic uses rawValue comparison: lower rawValue = stronger
        // Verify the ordering is correct
        XCTAssertLessThan(
            KdfProfile.argon2idStandard.rawValue,
            KdfProfile.argon2idLow.rawValue,
            "argon2idStandard should be stronger (lower byte) than argon2idLow"
        )
        XCTAssertLessThan(
            KdfProfile.argon2idLow.rawValue,
            KdfProfile.bcryptHkdf.rawValue,
            "argon2idLow should be stronger (lower byte) than bcryptHkdf"
        )
    }

    func testAllWeakerProfilesTriggerUpgradeToStandard() throws {
        let deviceProfile = KdfProfile.argon2idStandard
        let weakerProfiles: [KdfProfile] = [.argon2idLow, .bcryptHkdf]

        for weakProfile in weakerProfiles {
            let salt = KdfProfile.createSaltWithProfile(weakProfile)
            let currentProfile = try KdfProfile.fromByte(salt[salt.startIndex])
            let needsUpgrade = currentProfile.rawValue > deviceProfile.rawValue
            XCTAssertTrue(needsUpgrade, "\(weakProfile) should trigger upgrade to argon2idStandard")
        }
    }
}
