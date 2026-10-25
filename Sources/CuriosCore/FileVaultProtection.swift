import Foundation

/// Complementary boot-volume protection, not a guarantee about the vault/export
/// destination. Never enables FileVault, requests privileges or handles its keys.
public enum FileVaultProtection {
    public enum Status: Equatable, Sendable {
        case on, off, changing, unknown
        public var description: String {
            switch self {
            case .on: return "FileVault reports On for this Mac."
            case .off: return "FileVault reports Off. Consider enabling it in System Settings."
            case .changing: return "FileVault reports an encryption/decryption transition."
            case .unknown: return "FileVault status could not be determined. Check System Settings."
            }
        }
    }
    public static func parse(_ output: String, exitCode: Int32) -> Status {
        guard exitCode == 0, output.utf8.count <= 4096 else { return .unknown }
        let text = output.lowercased()
        if text.contains("in progress") || text.contains("deferred") { return .changing }
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "filevault is on." { return .on }
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "filevault is off." { return .off }
        return .unknown
    }
    public static func status() -> Status {
        #if os(macOS)
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C", "LANG": "C"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Bound waiting as well as output. No shell, sudo or user-controlled arguments.
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            let data = try pipe.fileHandleForReading.read(upToCount: 4096) ?? Data()
            process.waitUntilExit(); timeout.cancel()
            return parse(String(decoding: data, as: UTF8.self), exitCode: process.terminationStatus)
        } catch { return .unknown }
        #else
        return .unknown
        #endif
    }
}
