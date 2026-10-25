import Foundation
import CryptoKit
import CuriosCore

// Synthetic test material only. The request goes directly to the independent
// reader's stdin, not to a public artifact or a production recovery flow.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
guard directory.lastPathComponent.hasPrefix("interop-") else { fatalError("Expected a synthetic test directory") }
let passphrase = "Synthetic interoperability passphrase"
let e = try Vault.enroll(passphrase: passphrase)
let payload = try Persistence.encode(Database.sample())
let path = directory.appendingPathComponent("synthetic.curiosvault")
try e.session.seal(payload, kind: .export).write(to: path)
let request = ["path": path.path, "passphrase": passphrase, "recovery": e.recoveryCode,
               "sha256": SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()]
let bytes = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
FileHandle.standardOutput.write(bytes)
