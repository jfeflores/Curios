import Foundation
import CuriosCore

@main
struct VaultAppIntegration {
    @MainActor static func main() async throws {
        func require(_ condition: Bool) { precondition(condition) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("curios-vault-app-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("curios.json")
        let store = AppStore(url: url)
        precondition(store.vaultState == .needsEnrollment && store.readOnly && store.database.items.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: url.path))
        let enrollmentGeneration = store.sessionGeneration
        store.lockVault()
        precondition(store.sessionGeneration != enrollmentGeneration && store.vaultState == .needsEnrollment)
        precondition(!store.put(Item("Must not seed plaintext")))
        print("PASS new profile requires enrollment and writes no plaintext sample")
        let password = "Synthetic vault integration passphrase"
        let e = try Vault.enroll(passphrase: password)
        let rejected = await store.enableVault(e, confirmation: "incorrect recovery")
        precondition(!rejected && !FileManager.default.fileExists(atPath: url.path))
        let enabled = await store.enableVault(e, confirmation: e.recoveryCode)
        precondition(enabled && store.canReadContent && store.isEncrypted)
        let initialCount = store.database.items.count
        var item = store.draft(in: .list(.inbox)); item.title = "ENCRYPTED SYNTHETIC APP CANARY"
        precondition(store.put(item))
        require(Vault.isEncrypted(try Data(contentsOf: url)))
        print("PASS independent recovery confirmation / encrypted enrollment / encrypted mutation")
        _ = store.handleURL(URL(string: "curios://add?title=Pending%20private%20preview")!)
        precondition(store.pendingCapture != nil && store.undoName != nil)
        let beforeLock = try Data(contentsOf: url)
        store.lockVault()
        precondition(store.readOnly && store.database.items.isEmpty && store.undoName == nil && store.pendingCapture == nil)
        precondition(store.integrations.events.isEmpty && store.integrations.calendars.isEmpty)
        store.undo(); store.redo(); store.restoreBackup()
        precondition(!store.put(Item("Locked write")))
        precondition(store.handleURL(URL(string: "curios://add?title=Locked%20capture")!) == nil)
        try require(store.pendingCapture == nil && Data(contentsOf: url) == beforeLock)
        print("PASS lock clears content/history/capture/cache and blocks writes, restore, undo and URLs")
        let wrong = await store.unlockVault(.passphrase("incorrect"))
        try require(!wrong && store.database.items.isEmpty && Data(contentsOf: url) == beforeLock)
        let recovered = await store.unlockVault(.recovery(e.recoveryCode))
        precondition(recovered && store.database.item(item.id)?.title == item.title)
        print("PASS failed unlock preserves ciphertext; recovery-only unlock restores content")
        store.lockVault()
        let unlocking = Task { await store.unlockVault(.passphrase(password)) }
        for _ in 0..<100 where store.vaultState != .unlocking { await Task.yield() }
        precondition(store.vaultState == .unlocking)
        store.lockVault()
        let late = await unlocking.value
        precondition(!late && store.vaultState == .locked && store.database.items.isEmpty)
        print("PASS lock invalidates an in-flight password derivation / late unlock callback")
        let unlocked = await store.unlockVault(.passphrase(password)); precondition(unlocked)
        let exportURL = folder.appendingPathComponent("portable.curiosvault")
        var incoming = Database(); incoming.items = [Item("ENCRYPTED IMPORT CANARY")]
        try Persistence.exportEncrypted(incoming, to: exportURL, passphrase: password)
        let importing = Task { await store.importData(from: exportURL, credential: .passphrase(password)) }
        for _ in 0..<100 where !store.importing { await Task.yield() }
        precondition(store.importing)
        store.lockVault()
        let importedWhileLocked = await importing.value
        precondition(!importedWhileLocked && store.database.items.isEmpty)
        let reopened = await store.unlockVault(.passphrase(password)); precondition(reopened)
        precondition(!store.database.items.contains { $0.title == "ENCRYPTED IMPORT CANARY" })
        let imported = await store.importData(from: exportURL, credential: .passphrase(password))
        precondition(imported && store.database.items.contains { $0.title == "ENCRYPTED IMPORT CANARY" })
        print("PASS encrypted portable import / late import rejected across lock")
        let restart = AppStore(url: url)
        precondition(restart.vaultState == .locked && restart.database.items.isEmpty)
        let restartUnlocked = await restart.unlockVault(.passphrase(password)); precondition(restartUnlocked)
        precondition(restart.database.items.count == initialCount + 2)
        print("PASS restart is locked; durable data survives passphrase unlock")
        // Corrupt authenticated bytes while preserving the enrollment snapshot and backup.
        var corrupt = try Data(contentsOf: url); corrupt[corrupt.count - 1] ^= 1
        try corrupt.write(to: url)
        let damaged = AppStore(url: url)
        precondition(damaged.vaultState == .locked)
        let badOpen = await damaged.unlockVault(.passphrase(password))
        try require(!badOpen && Data(contentsOf: url) == corrupt)
        let restored = await damaged.unlockVault(.recovery(e.recoveryCode), restoreBackup: true)
        precondition(restored && damaged.canReadContent && damaged.database.item(item.id) != nil)
        print("PASS damaged vault is not overwritten; explicit authenticated backup recovery succeeds")
        precondition(FileVaultProtection.parse("FileVault is On.\n", exitCode: 0) == .on)
        precondition(FileVaultProtection.parse("FileVault is Off.", exitCode: 0) == .off)
        precondition(FileVaultProtection.parse("Encryption in progress", exitCode: 0) == .changing)
        precondition(FileVaultProtection.parse("FileVault is On.", exitCode: 1) == .unknown)
        precondition(FileVaultProtection.parse("unexpected output", exitCode: 0) == .unknown)
        print("PASS bounded FileVault status parsing; unknown/error is never advertised as protected")
        print("All encrypted application integration checks passed")
    }
}
