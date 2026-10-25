#if CURIOS_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
import Darwin
@testable import CuriosCore

final class PersistenceSecurityTests: XCTestCase {
    func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("curios-security-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
    func database(_ title: String = "Synthetic private task") -> Database {
        var db = Database(); db.items = [Item(title, placement: .anytime)]; return db
    }
    func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue & 0o777
    }
    func hasExtendedACL(_ url: URL) throws -> Bool {
        guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT { return false }
            throw DataError.invalid("Could not inspect synthetic ACL.")
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        return acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry) == 0
    }
    func testInheritedACLDoesNotOverridePrivateFilesOrManagedDirectories() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/chmod")
            child.arguments = ["+a", "everyone allow read,execute,readattr,readextattr,readsecurity,file_inherit,directory_inherit", directory.path]
            try child.run(); child.waitUntilExit()
            XCTAssertEqual(child.terminationStatus, 0)
            XCTAssertTrue(try hasExtendedACL(directory))
            let exported = directory.appendingPathComponent("private-export.json")
            try Persistence.export(database(), to: exported)
            XCTAssertFalse(try hasExtendedACL(exported))
            XCTAssertTrue(try hasExtendedACL(directory), "An export must not alter its destination directory ACL.")
            let managed = directory.appendingPathComponent("app-data")
            let url = managed.appendingPathComponent("daybook.json"), storage = Persistence(url: managed.appendingPathComponent("daybook.json"))
            try storage.save(database()); try storage.save(database("Second"))
            XCTAssertFalse(try hasExtendedACL(managed))
            XCTAssertFalse(try hasExtendedACL(url))
            XCTAssertFalse(try hasExtendedACL(url.appendingPathExtension("backup")))
            _ = try storage.restoreBackup()
            XCTAssertFalse(try hasExtendedACL(url))
        }
    }
    func testPrivateCreationBackupRestoreAndExportUnderPermissiveUmasks() throws {
        for mask: mode_t in [0o022, 0o000] {
            let original = umask(mask); defer { umask(original) }
            try withDirectory { directory in
                let url = directory.appendingPathComponent("daybook.json"), storage = Persistence(url: directory.appendingPathComponent("daybook.json"))
                try storage.save(database("Original")); try storage.save(database("Changed"))
                XCTAssertEqual(try mode(directory), 0o700)
                for file in [url, url.appendingPathExtension("backup"), url.appendingPathExtension("lock")] {
                    XCTAssertEqual(try mode(file), 0o600)
                }
                let restored = try storage.restoreBackup()
                XCTAssertEqual(restored.items.first?.title, "Original")
                XCTAssertEqual(try mode(url), 0o600)
                let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                XCTAssertEqual(copies.filter { $0.lastPathComponent.contains(".recovery-") }.count, 1)
                for copy in copies { XCTAssertEqual(try mode(copy), 0o600) }
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
                let exported = directory.appendingPathComponent("export.json")
                try Persistence.export(restored, to: exported)
                XCTAssertEqual(try mode(exported), 0o600)
                XCTAssertEqual(try mode(directory), 0o755, "Exports must not chmod their selected parent.")
            }
        }
    }
    func testSerializedLimitRejectsSaveWithoutReplacingGoodFiles() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("daybook.json"), storage = Persistence(url: directory.appendingPathComponent("daybook.json"))
            try storage.save(database()); try storage.save(database("Second"))
            let primary = try Persistence.readData(from: url), backup = try Persistence.readData(from: url.appendingPathExtension("backup"))
            var large = Database()
            let note = String(repeating: "x", count: InputLimits.notesUTF8Bytes - 256)
            large.items = (0..<64).map { index in var item = Item("Boundary \(index)", placement: .anytime); item.notes = note; return item }
            _ = try large.validated() // Each field and total text fit; JSON framing does not.
            XCTAssertThrowsError(try storage.save(large))
            XCTAssertEqual(try Persistence.readData(from: url), primary)
            XCTAssertEqual(try Persistence.readData(from: url.appendingPathExtension("backup")), backup)
            XCTAssertEqual(try storage.load()?.items.first?.title, "Second")
        }
    }
    func testOversizedSparseInputIsRejectedBeforeReadingAndFailedSaveIsNonDestructive() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let large = directory.appendingPathComponent("oversized.json")
            FileManager.default.createFile(atPath: large.path, contents: nil)
            let handle = try FileHandle(forWritingTo: large)
            try handle.truncate(atOffset: 64 * 1024 * 1024 + 1); try handle.close()
            XCTAssertThrowsError(try Persistence.readData(from: large))
            let url = directory.appendingPathComponent("daybook.json"), storage = Persistence(url: directory.appendingPathComponent("daybook.json"))
            try storage.save(database())
            let before = try Persistence.readData(from: url)
            try FileManager.default.createDirectory(at: url.appendingPathExtension("backup"), withIntermediateDirectories: false)
            XCTAssertThrowsError(try storage.save(database("Must not replace")))
            XCTAssertEqual(try Persistence.readData(from: url), before)
        }
    }
    func testStaleAndUnobservedWritersMustReload() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("daybook.json"), first = Persistence(url: directory.appendingPathComponent("daybook.json"))
            try first.save(database("Initial"))
            let unseen = Persistence(url: url)
            XCTAssertThrowsError(try unseen.save(database("Unobserved")))
            let stale = Persistence(url: url); _ = try stale.load()
            try first.save(database("First writer survives"))
            let before = try Persistence.readData(from: url)
            XCTAssertThrowsError(try stale.save(database("Stale overwrite")))
            XCTAssertEqual(try Persistence.readData(from: url), before)
            _ = try stale.load(); try stale.save(database("Reloaded writer"))
            XCTAssertEqual(try stale.load()?.items.first?.title, "Reloaded writer")
        }
    }
    func testASeparateProcessChangeCannotBeSilentlyOverwritten() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("daybook.json"), storage = Persistence(url: directory.appendingPathComponent("daybook.json"))
            try storage.save(database("Observed"))
            let incoming = directory.appendingPathComponent("incoming.json")
            try Persistence.export(database("External process change"), to: incoming)
            let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/cp")
            child.arguments = [incoming.path, url.path]
            try child.run(); child.waitUntilExit()
            XCTAssertEqual(child.terminationStatus, 0)
            XCTAssertThrowsError(try storage.save(database("Stale state")))
            XCTAssertEqual(try Persistence.decode(Persistence.readData(from: url)).items.first?.title, "External process change")
        }
    }
    func testUnsafeFilesAreRejectedWithoutTouchingTheirTargets() throws {
        try withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("target.json")
            try Persistence.export(database(), to: target)
            let before = try Data(contentsOf: target)
            let symlink = directory.appendingPathComponent("linked.json")
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
            XCTAssertThrowsError(try Persistence.readData(from: symlink))
            XCTAssertThrowsError(try Persistence.export(database("Must not write"), to: symlink))
            XCTAssertEqual(try Data(contentsOf: target), before)
            let hardlink = directory.appendingPathComponent("hardlink.json")
            try FileManager.default.linkItem(at: target, to: hardlink)
            XCTAssertThrowsError(try Persistence.readData(from: hardlink))
            try FileManager.default.removeItem(at: hardlink)
            let fifo = directory.appendingPathComponent("pipe.json")
            XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
            XCTAssertThrowsError(try Persistence.readData(from: fifo))
        }
    }
    func testCorruptRestorePreservesOriginalAndRejectsChangedPrimary() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("daybook.json"), storage = Persistence(url: directory.appendingPathComponent("daybook.json"))
            try storage.save(database("Original")); try storage.save(database("Later"))
            try Data("corrupt synthetic input".utf8).write(to: url, options: .atomic)
            XCTAssertThrowsError(try storage.restoreBackup()) // External changes require observation.
            let recovering = Persistence(url: url)
            XCTAssertThrowsError(try recovering.load())
            XCTAssertEqual(try recovering.restoreBackup().items.first?.title, "Original")
            let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.contains(".recovery-") }
            XCTAssertEqual(copies.count, 1)
            XCTAssertEqual(try String(contentsOf: copies[0]), "corrupt synthetic input")
            XCTAssertEqual(try mode(copies[0]), 0o600)
        }
    }
}
