#if CURIOS_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
import CryptoKit
@testable import CuriosCore

final class VaultTests: XCTestCase {
    private let password = "Synthetic test passphrase only"
    private func fixture(_ run: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("curios-vault-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try run(folder.appendingPathComponent("curios.json"))
    }
    func testPlatformPBKDF2KnownAnswerAndInputBounds() throws {
        let key = try Vault.passwordKey("password", salt: Data("0123456789abcdef".utf8), rounds: 600_000)
        let actual = key.withUnsafeBytes { Vault.hex(Data($0)).lowercased() }
        XCTAssertEqual(actual, "996d7c90f74a4a169cf7adef42b06848f7d1bac3e568d1cc94d4f79be1ee0263")
        XCTAssertThrowsError(try Vault.passwordKey("password", salt: Data(repeating: 0, count: 16), rounds: 1))
        XCTAssertThrowsError(try Vault.passwordKey("password", salt: Data(repeating: 0, count: 16), rounds: Int.max))
        let context = Vault.WrapContext(vaultID: UUID(), generation: UUID(), route: "passphrase", salt: Data(repeating: 255, count: 16), iterations: 600_000)
        XCTAssertFalse(String(decoding: try Vault.json(context), as: UTF8.self).contains("\\/"))
        XCTAssertThrowsError(try Vault.enroll(passphrase: "short"))
        XCTAssertThrowsError(try Vault.enroll(passphrase: String(repeating: "é", count: 513)))
    }
    func testPlatformAESGCMKnownAnswer() throws {
        // NIST AES-256-GCM: zero key, 96-bit zero IV, 16 zero plaintext bytes.
        let box = try AES.GCM.seal(Data(repeating: 0, count: 16), using: SymmetricKey(data: Data(repeating: 0, count: 32)), nonce: AES.GCM.Nonce(data: Data(repeating: 0, count: 12)))
        XCTAssertEqual(Vault.hex(box.ciphertext).lowercased(), "cea7403d4d606b6e074ec5d3baf39d18")
        XCTAssertEqual(Vault.hex(box.tag).lowercased(), "d0d1c8a799996bf0265b98b5d48ab919")
    }
    func testPassphraseAndIndependentRecoveryRoundTrip() throws {
        let enrolled = try Vault.enroll(passphrase: password)
        let payload = try Persistence.encode(Database.sample())
        let bytes = try enrolled.session.seal(payload)
        let descriptor = try Vault.inspect(bytes)
        let unlocked = try Vault.unlock(descriptor, with: .passphrase(password))
        XCTAssertEqual(try unlocked.open(bytes), payload)
        let recovered = try Vault.unlock(descriptor, with: .recovery(enrolled.recoveryCode.lowercased()))
        XCTAssertEqual(try recovered.open(bytes), payload)
        XCTAssertTrue(enrolled.session.verifiesRecovery(enrolled.recoveryCode))
        XCTAssertFalse(enrolled.session.verifiesRecovery("not a recovery code"))
        XCTAssertThrowsError(try Vault.unlock(descriptor, with: .passphrase(password + "wrong")))
        XCTAssertThrowsError(try Vault.unlock(descriptor, with: .recovery(String(enrolled.recoveryCode.dropLast()) + "Z")))
        XCTAssertFalse(bytes.range(of: Data("Welcome".utf8)) != nil)
    }
    func testUnicodeAndWhitespacePasswordsAreNotNormalized() throws {
        let value = "  独立した長いパスフレーズ 🔒  "
        let enrollment = try Vault.enroll(passphrase: value)
        let bytes = try enrollment.session.seal(Data("synthetic".utf8))
        XCTAssertEqual(try Vault.unlock(Vault.inspect(bytes), with: .passphrase(value)).open(bytes), Data("synthetic".utf8))
        XCTAssertThrowsError(try Vault.unlock(Vault.inspect(bytes), with: .passphrase(value.trimmingCharacters(in: .whitespaces))))
    }
    func testFreshNoncesTamperingTruncationAndTrailingBytes() throws {
        let e = try Vault.enroll(passphrase: password)
        let payload = Data("SYNTHETIC-CANARY-TASK-CONTENT".utf8)
        let a = try e.session.seal(payload), b = try e.session.seal(payload)
        XCTAssertFalse(a == b)
        let padded = Data([0]) + a
        XCTAssertEqual(try e.session.open(padded.dropFirst()), payload)
        XCTAssertNil(a.range(of: payload))
        for index in [0, 8, 12, 16, a.count - 29, a.count - 1] {
            var bad = a; bad[index] ^= 1
            XCTAssertThrowsError(try e.session.open(bad))
        }
        for count in [0, 7, 15, 16, a.count - 1] { XCTAssertThrowsError(try e.session.open(Data(a.prefix(count)))) }
        XCTAssertThrowsError(try e.session.open(a + Data([0])))
        XCTAssertThrowsError(try e.session.open(a, kind: .export))
        let other = try Vault.enroll(passphrase: password)
        XCTAssertThrowsError(try other.session.open(a))
    }
    func testMalformedHeadersAreRejectedBeforeExpensiveKDF() throws {
        let e = try Vault.enroll(passphrase: password)
        let d = e.session.descriptor
        let excessive = Vault.Descriptor(version: 1, cipher: "AES-256-GCM", vaultID: d.vaultID, generation: d.generation, kind: .database,
            passphrase: Vault.Slot(salt: d.passphrase.salt, iterations: Int.max, wrappedKey: d.passphrase.wrappedKey), recovery: d.recovery)
        XCTAssertThrowsError(try Vault.unlock(excessive, with: .passphrase(password)))
        let future = Vault.Descriptor(version: 2, cipher: d.cipher, vaultID: d.vaultID, generation: d.generation, kind: .database, passphrase: d.passphrase, recovery: d.recovery)
        XCTAssertThrowsError(try Vault.unlock(future, with: .recovery(e.recoveryCode)))
        var malformed = Vault.magic
        Vault.append(UInt32.max, to: &malformed); Vault.append(28, to: &malformed)
        XCTAssertThrowsError(try Vault.inspect(malformed))
    }
    func testEncryptedPersistenceRejectsPlaintextAndStaleWrites() throws {
        try fixture { url in
            let enrollment = try Vault.enroll(passphrase: password)
            let initial = Persistence(url: url)
            let store = try initial.enableEncryption(using: enrollment.session, initial: .sample())
            let original = try store.load()!
            for suffix in ["", ".lock", ".backup", ".vault", ".recovery-test"] {
                XCTAssertThrowsError(try store.validateExportDestination(URL(fileURLWithPath: url.path + suffix)))
            }
            try store.validateExportDestination(url.deletingLastPathComponent().appendingPathComponent("separate-export.curiosvault"))
            let stale = Persistence(url: url, encryption: enrollment.session); _ = try stale.load()
            var next = original; next.items.append(Item("PRIVATE SYNTHETIC CANARY"))
            try store.save(next)
            XCTAssertThrowsError(try stale.save(original))
            XCTAssertThrowsError(try Persistence(url: url).load())
            XCTAssertThrowsError(try Persistence(url: url).save(original))
            for name in [url.path, url.path + ".backup", url.path + ".vault"] {
                let bytes = try Data(contentsOf: URL(fileURLWithPath: name))
                XCTAssertTrue(Vault.isEncrypted(bytes)); XCTAssertNil(bytes.range(of: Data("PRIVATE SYNTHETIC CANARY".utf8)))
            }
            XCTAssertEqual(try store.load()?.items.count, next.items.count)
            let restored = try store.restoreBackup()
            XCTAssertEqual(restored, original)
        }
    }
    func testLegacyMigrationConvertsEveryKnownCopyAndPreventsDowngrade() throws {
        try fixture { url in
            let legacy = Persistence(url: url)
            var db = Database.sample(); try legacy.save(db)
            db.items.append(Item("MIGRATION SYNTHETIC CANARY")); try legacy.save(db)
            let recovery = url.appendingPathExtension("recovery-test")
            let oldRecovery = url.deletingLastPathComponent().appendingPathComponent("recovered-old")
            try Data("damaged old recovery bytes".utf8).write(to: recovery)
            try Data("legacy recovery".utf8).write(to: oldRecovery)
            let stale = Persistence(url: url); _ = try stale.load()
            let e = try Vault.enroll(passphrase: password)
            let encrypted = try legacy.enableEncryption(using: e.session)
            XCTAssertEqual(try encrypted.load()?.items.count, db.items.count)
            for file in [url, url.appendingPathExtension("backup"), recovery, oldRecovery, url.appendingPathExtension("vault")] {
                XCTAssertTrue(Vault.isEncrypted(try Data(contentsOf: file)))
            }
            XCTAssertThrowsError(try stale.save(db))
            let originalSnapshot = try e.session.open(Data(contentsOf: url.appendingPathExtension("vault")))
            XCTAssertEqual(try Persistence.decode(originalSnapshot).items.count, db.items.count)
            // A legacy app/user restoring plaintext does not authorize a plaintext save.
            try Persistence.encode(db).write(to: url)
            XCTAssertThrowsError(try Persistence(url: url).load())
            if case .encrypted(_, let pending) = try Persistence(url: url).storageState() { XCTAssertTrue(pending) }
            else { XCTFail("Missing migration barrier") }
        }
    }
    func testMigrationPreflightFailurePreservesAllInputs() throws {
        try fixture { url in
            let legacy = Persistence(url: url); try legacy.save(.sample()); _ = try legacy.load()
            let bytes = try Data(contentsOf: url)
            try Data("corrupt backup".utf8).write(to: url.appendingPathExtension("backup"))
            let e = try Vault.enroll(passphrase: password)
            XCTAssertThrowsError(try legacy.enableEncryption(using: e.session))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".vault"))
        }
    }
    func testInterruptedMigrationResumesAndMissingPrimaryNeverSeedsSamples() throws {
        try fixture { url in
            let legacy = Persistence(url: url); try legacy.save(.sample()); _ = try legacy.load()
            let e = try Vault.enroll(passphrase: password)
            let original = try Data(contentsOf: url)
            // A process interruption after writing the encrypted enrollment snapshot.
            try e.session.seal(original).write(to: url.appendingPathExtension("vault"))
            let restarted = Persistence(url: url)
            if case .encrypted(_, let pending) = try restarted.storageState() { XCTAssertTrue(pending) }
            else { XCTFail("Expected resumable migration") }
            let store = try restarted.enableEncryption(using: e.session)
            XCTAssertEqual(try store.load()?.items.count, Database.sample().items.count)
            try FileManager.default.removeItem(at: url)
            XCTAssertThrowsError(try Persistence(url: url).load())
            let recovered = Persistence(url: url); _ = try recovered.storageState()
            let reopened = try recovered.enableEncryption(using: e.session)
            XCTAssertEqual(try reopened.load()?.items.count, Database.sample().items.count)
        }
    }
    func testExactPayloadLimitAndEncryptedOverheadRemainReadable() throws {
        try fixture { url in
            let e = try Vault.enroll(passphrase: password)
            let payload = Data(repeating: 0x61, count: Vault.plaintextLimit)
            let bytes = try e.session.seal(payload)
            XCTAssertTrue(bytes.count > Vault.plaintextLimit && bytes.count <= Vault.fileLimit)
            try bytes.write(to: url)
            XCTAssertEqual(try e.session.open(Persistence.readData(from: url)).count, Vault.plaintextLimit)
            XCTAssertThrowsError(try e.session.seal(payload + Data([0])))
        }
    }
    func testUnsafeAndOversizedMigrationArtifactsStopBeforeBarrierCreation() throws {
        try fixture { url in
            let legacy = Persistence(url: url); try legacy.save(.sample()); _ = try legacy.load()
            let original = try Data(contentsOf: url), copy = url.appendingPathExtension("recovery-unsafe")
            let e = try Vault.enroll(passphrase: password)
            try FileManager.default.createSymbolicLink(at: copy, withDestinationURL: url)
            XCTAssertThrowsError(try legacy.enableEncryption(using: e.session))
            try FileManager.default.removeItem(at: copy)
            _ = FileManager.default.createFile(atPath: copy.path, contents: Data())
            let fd = try FileHandle(forWritingTo: copy); try fd.truncate(atOffset: UInt64(Vault.fileLimit + 1)); try fd.close()
            XCTAssertThrowsError(try legacy.enableEncryption(using: e.session))
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".vault"))
        }
    }
    func testMissingPrimaryWithBackupRequiresExplicitRecovery() throws {
        try fixture { url in
            let e = try Vault.enroll(passphrase: password)
            let initial = Persistence(url: url)
            let store = try initial.enableEncryption(using: e.session, initial: .sample())
            let original = try store.load()!
            var next = original; next.items.append(Item("Later synthetic data")); try store.save(next)
            try FileManager.default.removeItem(at: url)
            let missing = Persistence(url: url)
            if case .encrypted(_, let pending) = try missing.storageState() { XCTAssertFalse(pending) }
            else { XCTFail("Expected locked recovery state") }
            XCTAssertThrowsError(try missing.encrypted(using: e.session).load())
            XCTAssertEqual(try missing.encrypted(using: e.session).restoreBackup(), original)
        }
    }
    func testPortableExportUsesIndependentKeysAndAtomicPrivateWriter() throws {
        try fixture { url in
            let e = try Vault.enroll(passphrase: password)
            try Persistence.exportEncrypted(.sample(), to: url, passphrase: password)
            let bytes = try Persistence.readData(from: url)
            XCTAssertTrue(Vault.isEncrypted(bytes))
            XCTAssertFalse(try Vault.inspect(bytes).vaultID == e.session.descriptor.vaultID)
            XCTAssertThrowsError(try e.session.open(bytes, kind: .export))
            XCTAssertEqual(try Vault.decryptExport(bytes, with: .passphrase(password)).items.count, Database.sample().items.count)
            XCTAssertThrowsError(try Vault.decryptExport(bytes, with: .passphrase("wrong")))
            let before = try Data(contentsOf: url)
            XCTAssertThrowsError(try Persistence.exportEncrypted(.sample(), to: url, passphrase: "short"))
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }
}
