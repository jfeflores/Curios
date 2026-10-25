import SwiftUI
import AppKit
import CuriosCore

/// Content is removed, not covered by an overlay. Changing session identity tears
/// down editor/search/sheet state in every window when locking or re-enrolling.
struct VaultGate<Content: View>: View {
    @EnvironmentObject var store: AppStore
    @ViewBuilder var content: () -> Content
    var body: some View {
        Group {
            if store.canReadContent { content() }
            else { VaultAccessView() }
        }.id(store.sessionGeneration)
        .onOpenURL { url in if !store.canReadContent { _ = store.handleURL(url) } }
        #if CURIOS_DIAGNOSTICS
        .onAppear { UICheckboxSelfTest.registeredStore = store }
        #endif
    }
}

struct VaultAccessView: View {
    @EnvironmentObject var store: AppStore
    @State private var secret = ""
    @State private var usingRecovery = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Curios", systemImage: "lock.shield").font(.largeTitle.bold())
                if store.vaultState == .needsEnrollment {
                    VaultEnrollmentView()
                } else if store.vaultState == .unlocking {
                    ProgressView("Authenticating and preparing your vault…")
                    Text("No plaintext is written to temporary files. Please keep your recovery key safe.").font(.caption).foregroundStyle(.secondary)
                    Button("Keep Locked") { store.lockVault() }
                } else if store.vaultState == .locked {
                    Text("Your task vault is locked.").font(.title2)
                    Toggle("Use my recovery key", isOn: $usingRecovery).onChange(of: usingRecovery) { _, _ in secret = "" }
                    SecureField(usingRecovery ? "Recovery key" : "Vault passphrase", text: $secret)
                        .textFieldStyle(.roundedBorder).onSubmit { unlock(restoring: false) }
                    HStack {
                        Button("Unlock / Resume Encryption") { unlock(restoring: false) }.buttonStyle(.borderedProminent).disabled(secret.isEmpty)
                        Button("Recover Previous Backup…") { confirmRestore() }.disabled(secret.isEmpty)
                    }
                    Text("Unlock also resumes a previously interrupted enrollment. Recovery replaces only an explicitly selected previous backup after validation and preserves the current bytes. A recovery key is an alternative unlock method, not a password reset. No developer can recover missing unlock material.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Curios could not open its data. Nothing was replaced.").font(.headline)
                    Text("Preserve the data folder before attempting recovery. Do not remove the persistent lock file while any instance is running.").font(.caption)
                    if !store.isEncrypted { Button("Restore Legacy Backup…") { confirmLegacyRestore() } }
                }
                if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                Button("Open Data Folder") { NSWorkspace.shared.open(store.persistence.url.deletingLastPathComponent()) }
                Divider()
                FileVaultGuidanceView()
                Text("Curios is an independent open-source Swift todo app, originating in a Ghidra/Things reverse-engineering skills project. Not affiliated with Cultured Code.").font(.caption2).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: 640)
        }.frame(minWidth: 500, minHeight: 440)
    }
    private func unlock(restoring: Bool) {
        let credential: Vault.Credential = usingRecovery ? .recovery(secret) : .passphrase(secret)
        secret = ""
        let token = store.sessionGeneration
        Task { guard store.sessionGeneration == token else { return }; await store.unlockVault(credential, restoreBackup: restoring) }
    }
    private func confirmRestore() {
        let alert = NSAlert(); alert.messageText = "Recover the previous encrypted backup?"
        alert.informativeText = "The backup must authenticate and validate. Current bytes are preserved as a private encrypted recovery copy. This restores a complete previous state, unlike merge import."
        alert.addButton(withTitle: "Unlock and Restore"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { unlock(restoring: true) }
    }
    private func confirmLegacyRestore() {
        let alert = NSAlert(); alert.messageText = "Restore the previous legacy backup?"
        alert.informativeText = "Current bytes are preserved privately before replacement. Legacy files remain unencrypted until you explicitly enable the vault."
        alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.restoreBackup() }
    }
}

struct VaultEnrollmentView: View {
    @EnvironmentObject var store: AppStore
    @State private var passphrase = ""
    @State private var repeated = ""
    @State private var confirmation = ""
    @State private var enrollment: Vault.Enrollment?
    @State private var preparing = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.vaultState == .legacyPlaintext ? "Encrypt existing Curios data" : "Create your encrypted Curios vault").font(.title2.bold())
            if let enrollment {
                Text("Save this recovery key separately before continuing.").font(.headline)
                Text(enrollment.recoveryCode).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Copy Recovery Key") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(enrollment.recoveryCode, forType: .string)
                }
                Text("Clipboard managers may retain copied secrets. Store this key in a trusted password manager or offline, not beside the vault. Anyone with it can decrypt the vault. Curios cannot replace a lost passphrase and recovery key.").font(.caption).foregroundStyle(.secondary)
                SecureField("Re-enter the complete recovery key", text: $confirmation).textFieldStyle(.roundedBorder)
                Button("Confirm Recovery and Encrypt") {
                    let code = confirmation, token = store.sessionGeneration; confirmation = ""
                    Task { guard store.sessionGeneration == token else { return }; await store.enableVault(enrollment, confirmation: code) }
                }.buttonStyle(.borderedProminent).disabled(confirmation.isEmpty)
                Text("Close older Daybook/Curios instances first. Known backups/recovery copies will also be encrypted. Older binaries cannot open the encrypted store. Locking clears unsaved drafts; save edits first. Existing OS snapshots, external copies and old exports are not securely erased.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Tasks, notes, preferences and managed backups use authenticated AES-256-GCM. The passphrase unlocks a random vault key; it is never stored as plaintext. New profiles are not written until enrollment is confirmed.").font(.caption)
                SecureField("Long, unique passphrase (12+ characters)", text: $passphrase).textFieldStyle(.roundedBorder)
                SecureField("Confirm passphrase", text: $repeated).textFieldStyle(.roundedBorder)
                if preparing { ProgressView("Preparing recovery material…") }
                Button("Prepare Recovery Key", action: prepare).buttonStyle(.borderedProminent)
                    .disabled(preparing || passphrase.count < 12 || passphrase != repeated)
                Text("Use a long, unique passphrase. The source build uses platform PBKDF2-HMAC-SHA-256 (600,000 iterations); no Keychain or Touch ID configuration is assumed.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
    private func prepare() {
        let value = passphrase, generation = store.sessionGeneration
        preparing = true; error = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try Vault.enroll(passphrase: value) }.value
                guard store.sessionGeneration == generation else { return }
                enrollment = result; passphrase = ""; repeated = ""; preparing = false
            } catch {
                guard store.sessionGeneration == generation else { return }
                self.error = error.localizedDescription; preparing = false
            }
        }
    }
}

struct FileVaultGuidanceView: View {
    @State private var status: FileVaultProtection.Status = .unknown
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Complementary protection: FileVault", systemImage: "externaldrive.badge.checkmark").font(.headline)
            Text(status.description).font(.caption)
            Text("FileVault protects the Mac's volume at rest; the Curios vault protects its files independently. This status does not verify external/export drives, secure deletion, or protection from malware while unlocked. Curios never enables FileVault, requests its recovery key, or changes system settings.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Refresh Status") { refresh() }
                Button("Open FileVault Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?FileVault") { NSWorkspace.shared.open(url) }
                }
            }
        }.task { status = await Task.detached { FileVaultProtection.status() }.value }
    }
    private func refresh() { Task { status = await Task.detached { FileVaultProtection.status() }.value } }
}
