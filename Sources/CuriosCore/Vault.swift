import Foundation
import CryptoKit
import CommonCrypto
import Security

/// V1 portable vault format. Authentication precedes domain decoding. No key material
/// is logged or stored outside authenticated key wrappers and the unlocked session.
public enum Vault {
    public static let plaintextLimit = 64 * 1024 * 1024
    public static let fileLimit = plaintextLimit + 64 * 1024
    static let headerLimit = 16 * 1024
    static let iterations = 600_000
    static let maximumIterations = 2_000_000
    static let magic = Data("CURIOSV1".utf8)
    public enum Kind: String, Codable, Sendable { case database, recovery, export }
    public enum Credential: Sendable { case passphrase(String), recovery(String) }
    public struct Slot: Codable, Equatable, Sendable {
        let salt: Data
        let iterations: Int
        let wrappedKey: Data
    }
    public struct Descriptor: Codable, Equatable, Sendable {
        let version: Int
        let cipher: String
        public let vaultID: UUID
        let generation: UUID
        public let kind: Kind
        let passphrase: Slot
        let recovery: Slot
        func validated() throws {
            guard version == 1, cipher == "AES-256-GCM",
                  passphrase.salt.count == 16, recovery.salt.count == 16,
                  (Vault.iterations...Vault.maximumIterations).contains(passphrase.iterations),
                  recovery.iterations == 0,
                  passphrase.wrappedKey.count == 60, recovery.wrappedKey.count == 60 else {
                throw Vault.invalid("Unsupported or malformed vault metadata.")
            }
        }
    }
    public struct Enrollment: Sendable {
        public let session: Session
        public let recoveryCode: String
    }
    public struct Session: Sendable {
        public let descriptor: Descriptor
        private let master: SymmetricKey
        fileprivate init(descriptor: Descriptor, master: SymmetricKey) { self.descriptor = descriptor; self.master = master }
        public func seal(_ plaintext: Data, kind: Kind = .database) throws -> Data {
            guard plaintext.count <= Vault.plaintextLimit else { throw Vault.invalid("The plaintext exceeds the 64 MiB limit.") }
            let d = Descriptor(version: descriptor.version, cipher: descriptor.cipher, vaultID: descriptor.vaultID,
                               generation: descriptor.generation, kind: kind, passphrase: descriptor.passphrase, recovery: descriptor.recovery)
            let header = try Vault.json(d)
            guard header.count <= Vault.headerLimit else { throw Vault.invalid("Vault header is too large.") }
            let boxSize = plaintext.count + 28
            var aad = Vault.magic
            Vault.append(UInt32(header.count), to: &aad); Vault.append(UInt32(boxSize), to: &aad); aad.append(header)
            let box = try AES.GCM.seal(plaintext, using: contentKey(), authenticating: aad)
            guard let combined = box.combined, combined.count == boxSize else { throw Vault.invalid("Could not seal the vault.") }
            var result = aad; result.append(combined)
            guard result.count <= Vault.fileLimit else { throw Vault.invalid("Encrypted file is too large.") }
            return result
        }
        public func open(_ bytes: Data, kind: Kind = .database) throws -> Data {
            let parsed = try Vault.parse(bytes)
            guard parsed.descriptor.vaultID == descriptor.vaultID,
                  parsed.descriptor.generation == descriptor.generation,
                  parsed.descriptor.kind == kind else { throw Vault.invalid("This file belongs to another vault or has the wrong content type.") }
            do {
                let result = try AES.GCM.open(AES.GCM.SealedBox(combined: parsed.box), using: contentKey(), authenticating: parsed.aad)
                guard result.count <= Vault.plaintextLimit else { throw Vault.invalid("Decrypted file is too large.") }
                return result
            } catch { throw Vault.invalid("The vault could not be authenticated. Its original bytes have not been changed.") }
        }
        public func verifiesRecovery(_ code: String) -> Bool {
            guard let other = try? Vault.unlock(descriptor, with: .recovery(code)) else { return false }
            // A real authenticated round-trip verifies equivalence without a plaintext key comparison.
            guard let challenge = try? seal(Data("Curios recovery verification v1".utf8)),
                  let opened = try? other.open(challenge) else { return false }
            return opened == Data("Curios recovery verification v1".utf8)
        }
        private func contentKey() -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: Data(descriptor.vaultID.uuidString.utf8),
                                  info: Data("Curios content key v1".utf8), outputByteCount: 32)
        }
    }
    struct Parsed { let descriptor: Descriptor; let aad: Data; let box: Data }
    struct WrapContext: Encodable {
        let purpose = "Curios VMK wrapper v1"
        let vaultID: UUID
        let generation: UUID
        let route: String
        let salt: Data
        let iterations: Int
    }
    static func invalid(_ message: String) -> Error { DataError.invalid(message) }
    static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func random(_ count: Int) throws -> Data {
        var result = Data(count: count)
        let status = result.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw invalid("System cryptographic randomness is unavailable.") }
        return result
    }
    public static func isEncrypted(_ data: Data) -> Bool { data.starts(with: magic) }
    public static func inspect(_ data: Data) throws -> Descriptor { try parse(data).descriptor }
    static func append(_ value: UInt32, to data: inout Data) {
        var big = value.bigEndian; withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
    static func integer(_ bytes: Data, at offset: Int) -> Int {
        bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }
    static func parse(_ input: Data) throws -> Parsed {
        guard input.count <= fileLimit else { throw invalid("Encrypted file is too large.") }
        let bytes = Data(input) // Normalize slice indices before offset-based parsing.
        guard bytes.count >= 16, bytes.count <= fileLimit, isEncrypted(bytes) else { throw invalid("Not a supported Curios encrypted file.") }
        let headerCount = integer(bytes, at: 8), boxCount = integer(bytes, at: 12)
        guard headerCount > 0, headerCount <= headerLimit, boxCount >= 28,
              boxCount <= plaintextLimit + 28, bytes.count == 16 + headerCount + boxCount else {
            throw invalid("Invalid encrypted-file lengths.")
        }
        let end = 16 + headerCount
        let descriptor = try JSONDecoder().decode(Descriptor.self, from: bytes.subdata(in: 16..<end))
        try descriptor.validated()
        return Parsed(descriptor: descriptor, aad: bytes.subdata(in: 0..<end), box: bytes.subdata(in: end..<bytes.count))
    }
    static func passwordKey(_ password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        guard !password.isEmpty, password.utf8.count <= 1024, salt.count == 16,
              (iterations...maximumIterations).contains(rounds) else { throw invalid("Invalid passphrase or password-derivation parameters.") }
        let input = Data(password.utf8)
        var output = Data(count: 32)
        let status = input.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { keyBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.bindMemory(to: Int8.self).baseAddress!, input.count,
                                        saltBytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), keyBytes.bindMemory(to: UInt8.self).baseAddress!, 32)
                }
            }
        }
        guard status == kCCSuccess else { throw invalid("Passphrase derivation failed.") }
        let key = SymmetricKey(data: output); output.resetBytes(in: 0..<output.count)
        return key
    }
    static func recoveryKey(_ secret: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), salt: salt,
                              info: Data("Curios recovery wrapping key v1".utf8), outputByteCount: 32)
    }
    static func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02X", $0) }.joined() }
    static func recoveryCode(_ secret: Data) -> String {
        "CURIOS1-" + hex(secret) + "-" + hex(Data(SHA256.hash(data: secret).prefix(4)))
    }
    static func recoverySecret(_ code: String) throws -> Data {
        guard code.utf8.count <= 256 else { throw invalid("Invalid recovery key.") }
        let value = code.filter { !$0.isWhitespace && $0 != "-" }.uppercased()
        guard value.hasPrefix("CURIOS1"), value.count == 79 else { throw invalid("Invalid recovery key or checksum.") }
        let hexValue = Array(value.dropFirst(7).utf8)
        var bytes = Data()
        for i in stride(from: 0, to: hexValue.count, by: 2) {
            guard let byte = UInt8(String(decoding: hexValue[i..<(i + 2)], as: UTF8.self), radix: 16) else { throw invalid("Invalid recovery key.") }
            bytes.append(byte)
        }
        let secret = Data(bytes.prefix(32))
        guard bytes.suffix(4) == Data(SHA256.hash(data: secret).prefix(4)) else { throw invalid("Invalid recovery key checksum.") }
        return secret
    }
    public static func enroll(passphrase: String) throws -> Enrollment {
        guard passphrase.utf8.count <= 1024, passphrase.count >= 12 else { throw invalid("Use a passphrase of at least 12 characters (at most 1024 UTF-8 bytes). A long, unique passphrase is recommended.") }
        let id = UUID(), generation = UUID(), master = try random(32), recovery = try random(32)
        let passwordSalt = try random(16), recoverySalt = try random(16)
        func wrap(_ key: SymmetricKey, salt: Data, rounds: Int, route: String) throws -> Slot {
            let context = WrapContext(vaultID: id, generation: generation, route: route, salt: salt, iterations: rounds)
            let box = try AES.GCM.seal(master, using: key, authenticating: json(context))
            guard let combined = box.combined else { throw invalid("Key wrapping failed.") }
            return Slot(salt: salt, iterations: rounds, wrappedKey: combined)
        }
        let passwordSlot = try wrap(passwordKey(passphrase, salt: passwordSalt, rounds: iterations), salt: passwordSalt, rounds: iterations, route: "passphrase")
        let recoverySlot = try wrap(recoveryKey(recovery, salt: recoverySalt), salt: recoverySalt, rounds: 0, route: "recovery")
        let d = Descriptor(version: 1, cipher: "AES-256-GCM", vaultID: id, generation: generation, kind: .database, passphrase: passwordSlot, recovery: recoverySlot)
        return Enrollment(session: Session(descriptor: d, master: SymmetricKey(data: master)), recoveryCode: recoveryCode(recovery))
    }
    public static func unlock(_ descriptor: Descriptor, with credential: Credential) throws -> Session {
        try descriptor.validated()
        let slot: Slot, key: SymmetricKey, route: String
        switch credential {
        case .passphrase(let value):
            slot = descriptor.passphrase; route = "passphrase"
            key = try passwordKey(value, salt: slot.salt, rounds: slot.iterations)
        case .recovery(let value):
            slot = descriptor.recovery; route = "recovery"
            key = recoveryKey(try recoverySecret(value), salt: slot.salt)
        }
        let context = WrapContext(vaultID: descriptor.vaultID, generation: descriptor.generation, route: route, salt: slot.salt, iterations: slot.iterations)
        do {
            let master = try AES.GCM.open(AES.GCM.SealedBox(combined: slot.wrappedKey), using: key, authenticating: json(context))
            guard master.count == 32 else { throw invalid("Invalid vault key.") }
            return Session(descriptor: descriptor, master: SymmetricKey(data: master))
        } catch { throw invalid("Incorrect unlock material or damaged vault metadata. No data has been changed.") }
    }
    public static func decryptExport(_ bytes: Data, with credential: Credential) throws -> Database {
        let descriptor = try inspect(bytes)
        guard descriptor.kind == .export else { throw invalid("Choose a portable encrypted export, not a live vault file.") }
        return try Persistence.decode(unlock(descriptor, with: credential).open(bytes, kind: .export))
    }
}
