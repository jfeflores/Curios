import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct Persistence {
    public let url: URL
    private static let byteLimit = 64 * 1024 * 1024
    // Copies of one store share an observation; independent initializations do not.
    private final class Observation {
        let mutex = NSLock()
        var revision: Revision? = nil
        var known = true // New stores may create a missing file, not overwrite an unseen one.
    }
    private let observation = Observation()
    private struct Revision: Equatable {
        let device: UInt64, inode: UInt64, size: Int64
        let modifiedSeconds: Int64, modifiedNanos: Int64, changedSeconds: Int64, changedNanos: Int64
        init(_ value: stat) {
            device = UInt64(value.st_dev); inode = UInt64(value.st_ino); size = Int64(value.st_size)
            #if canImport(Darwin)
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec); modifiedNanos = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec); changedNanos = Int64(value.st_ctimespec.tv_nsec)
            #else
            modifiedSeconds = Int64(value.st_mtim.tv_sec); modifiedNanos = Int64(value.st_mtim.tv_nsec)
            changedSeconds = Int64(value.st_ctim.tv_sec); changedNanos = Int64(value.st_ctim.tv_nsec)
            #endif
        }
    }
    public init(url: URL) { self.url = url }
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["DAYBOOK_DATA_DIR"], !path.isEmpty { return URL(fileURLWithPath: path).appendingPathComponent("daybook.json") }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Daybook/daybook.json")
    }
    public static func encode(_ database: Database) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database.validated())
        try checkSize(data.count)
        return data
    }
    public static func decode(_ data: Data) throws -> Database {
        try checkSize(data.count)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Database.self, from: data).validated()
    }
    private static func checkSize(_ count: Int) throws {
        guard count <= byteLimit else { throw DataError.invalid("The file exceeds the 64 MiB limit.") }
    }
    private static func failure(_ operation: String) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(errno)))"])
    }
    private static func unsafe() -> Error { DataError.invalid("Expected a regular, singly linked file owned by the current user, with no final symlink.") }
    private static func conflict() -> Error { DataError.invalid("The database changed on disk. Reload before saving or restoring.") }

    /// POSIX modes do not override macOS ACL grants. Strip inherited/explicit
    /// extended ACLs from app-managed objects before exposing sensitive bytes.
    private static func clearExtendedACL(_ fd: Int32) throws {
        #if canImport(Darwin)
        guard let current = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT || errno == ENOTSUP { return }
            throw failure("Inspect privacy ACL")
        }
        defer { acl_free(UnsafeMutableRawPointer(current)) }
        var entry: acl_entry_t?
        if acl_get_entry(current, ACL_FIRST_ENTRY.rawValue, &entry) != 0 {
            if errno == EINVAL { return } // A valid empty ACL has no first entry.
            throw failure("Inspect privacy ACL entries")
        }
        guard let empty = acl_init(0) else { throw failure("Create private ACL") }
        defer { acl_free(UnsafeMutableRawPointer(empty)) }
        guard acl_set_fd_np(fd, empty, ACL_TYPE_EXTENDED) == 0 else { throw failure("Remove shared ACL grants") }
        #endif
    }
    private static func physicalPath(_ path: String) throws -> String {
        guard let resolved = realpath(path, nil) else { throw failure("Resolve directory") }
        defer { free(resolved) }
        return String(cString: resolved)
    }
    // Pin directories by descriptor. Resolve platform aliases such as /var before
    // traversing; no later path operation follows a symlink. Never chmod export parents.
    private static func parent(of url: URL, create: Bool, managed: Bool) throws -> Int32 {
        guard url.isFileURL, !url.lastPathComponent.isEmpty else { throw unsafe() }
        let directory = url.deletingLastPathComponent().standardizedFileURL
        var original = stat()
        if lstat(directory.path, &original) == 0, (original.st_mode & S_IFMT) == S_IFLNK { throw unsafe() }
        var existing = directory
        var missing: [String] = []
        while lstat(existing.path, &original) != 0, errno == ENOENT, existing.path != "/" {
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        // POSIX realpath preserves the physical /private/var spelling. Foundation
        // may normalize a file URL back to /var, defeating O_NOFOLLOW traversal.
        var canonical = try physicalPath(existing.path)
        for part in missing.reversed() { canonical = (canonical as NSString).appendingPathComponent(part) }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw failure("Open root directory") }
        do {
            for part in (canonical as NSString).pathComponents.dropFirst() {
                var next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0, errno == ENOENT, create {
                    if mkdirat(fd, part, 0o700) != 0, errno != EEXIST { throw failure("Create private directory") }
                    next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw failure("Open data directory") }
                var info = stat()
                guard fstat(next, &info) == 0 else { close(next); throw failure("Inspect directory") }
                guard (info.st_uid == getuid() || info.st_uid == 0),
                      (info.st_mode & 0o022 == 0 || info.st_mode & S_ISVTX != 0 || info.st_uid == getuid()) else {
                    close(next); throw unsafe()
                }
                close(fd); fd = next
            }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == getuid() else { throw unsafe() }
            // Never chmod shared temporary/home/root directories for legacy callers.
            let protected = ["/", FileManager.default.homeDirectoryForCurrentUser.path,
                             FileManager.default.temporaryDirectory.path, "/private/tmp", "/tmp"]
                .map { (try? physicalPath($0)) ?? $0 }
            if managed, !protected.contains(canonical) {
                guard fchmod(fd, 0o700) == 0 else { throw failure("Make data directory private") }
                try clearExtendedACL(fd)
            }
            return fd
        } catch { close(fd); throw error }
    }
    private static func inspect(_ fd: Int32) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw failure("Inspect file") }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 else { throw unsafe() }
        return info
    }
    private static func openFile(_ directory: Int32, _ name: String, privateMode: Bool = false) throws -> Int32? {
        let fd = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { if errno == ENOENT { return nil }; throw failure("Open file") }
        do {
            let info = try inspect(fd)
            if privateMode {
                if info.st_mode & 0o777 != 0o600, fchmod(fd, 0o600) != 0 { throw failure("Make file private") }
                try clearExtendedACL(fd)
            }
            return fd
        } catch { close(fd); throw error }
    }
    private static func revision(_ directory: Int32, _ name: String) throws -> Revision? {
        guard let fd = try openFile(directory, name) else { return nil }
        defer { close(fd) }
        return Revision(try inspect(fd))
    }
    private static func read(_ fd: Int32) throws -> Data {
        let before = try inspect(fd)
        guard before.st_size >= 0, before.st_size <= byteLimit else { throw DataError.invalid("The file exceeds the 64 MiB limit.") }
        var data = Data()
        data.reserveCapacity(Int(before.st_size)) // Only after descriptor size/type checks.
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                readSystem(fd, raw.baseAddress!, min(raw.count, byteLimit - data.count + 1))
            }
            if count < 0 { if errno == EINTR { continue }; throw failure("Read file") }
            if count == 0 { break }
            try checkSize(data.count + count)
            data.append(contentsOf: buffer.prefix(count))
        }
        guard Revision(before) == Revision(try inspect(fd)), data.count == Int(before.st_size) else { throw conflict() }
        return data
    }
    private static func readSystem(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.read(fd, buffer, count)
        #else
        return Glibc.read(fd, buffer, count)
        #endif
    }
    public static func readData(from url: URL) throws -> Data {
        let directory = try parent(of: url, create: false, managed: false)
        defer { close(directory) }
        guard let fd = try openFile(directory, url.lastPathComponent) else { throw DataError.invalid("The file does not exist.") }
        defer { close(fd) }
        return try read(fd)
    }
    private func transaction<T>(create: Bool, _ body: (Int32, String) throws -> T) throws -> T {
        observation.mutex.lock(); defer { observation.mutex.unlock() }
        let directory = try Self.parent(of: url, create: create, managed: true)
        defer { close(directory) }
        let name = url.lastPathComponent
        let lock = openat(directory, name + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw Self.failure("Open database lock") }
        defer { close(lock) }
        _ = try Self.inspect(lock)
        guard fchmod(lock, 0o600) == 0 else { throw Self.failure("Make lock private") }
        try Self.clearExtendedACL(lock)
        while flock(lock, LOCK_EX) != 0 { if errno != EINTR { throw Self.failure("Lock database") } }
        defer { _ = flock(lock, LOCK_UN) }
        guard try Self.revision(directory, name + ".lock") == Revision(Self.inspect(lock)) else { throw Self.conflict() }
        return try body(directory, name)
    }
    public func load() throws -> Database? {
        do {
            return try transaction(create: false) { directory, name in
                guard let fd = try Self.openFile(directory, name, privateMode: true) else {
                    observation.revision = nil; observation.known = true; return nil
                }
                defer { close(fd) }
                observation.revision = Revision(try Self.inspect(fd)); observation.known = true
                let bytes = try Self.read(fd)
                guard try Self.revision(directory, name) == observation.revision else { observation.known = false; throw Self.conflict() }
                return try Self.decode(bytes)
            }
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            // Only an actually absent parent means a new database. An unrelated
            // ENOENT from an ACL/read operation must never hide existing data.
            var info = stat()
            guard lstat(url.deletingLastPathComponent().path, &info) != 0, errno == ENOENT else { throw error }
            observation.mutex.lock(); defer { observation.mutex.unlock() }
            observation.revision = nil; observation.known = true
            return nil
        }
    }
    private func requireCurrent(_ directory: Int32, _ name: String) throws {
        guard observation.known, try Self.revision(directory, name) == observation.revision else { throw Self.conflict() }
    }
    private static func writeAll(_ fd: Int32, _ bytes: Data) throws {
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                #if canImport(Darwin)
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                #else
                let count = Glibc.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                #endif
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw failure("Write file") }
                offset += count
            }
        }
    }
    // All throwing operations precede rename. Post-commit directory sync is best
    // effort, never an ambiguous failure after the new primary is already visible.
    private static func replace(_ directory: Int32, _ name: String, writer: (Int32) throws -> Void,
                                beforeCommit: () throws -> Void = {}) throws -> Revision? {
        _ = try revision(directory, name)
        let temporary = ".daybook-" + UUID().uuidString + ".tmp"
        let fd = openat(directory, temporary, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw failure("Create private staged file") }
        defer { close(fd); _ = unlinkat(directory, temporary, 0) }
        guard fchmod(fd, 0o600) == 0 else { throw failure("Set staged file permissions") }
        try clearExtendedACL(fd)
        try writer(fd)
        guard fsync(fd) == 0 else { throw failure("Sync staged file") }
        try beforeCommit()
        _ = try revision(directory, name)
        guard renameat(directory, temporary, directory, name) == 0 else { throw failure("Replace file") }
        _ = fsync(directory)
        var info = stat()
        return fstat(fd, &info) == 0 ? Revision(info) : nil
    }
    public func save(_ database: Database) throws {
        let bytes = try Self.encode(database)
        try transaction(create: true) { directory, name in
            try requireCurrent(directory, name)
            if let fd = try Self.openFile(directory, name, privateMode: true) {
                defer { close(fd) }
                observation.revision = Revision(try Self.inspect(fd))
                let previous = try Self.read(fd)
                _ = try Self.decode(previous)
                _ = try Self.replace(directory, name + ".backup", writer: { try Self.writeAll($0, previous) },
                                     beforeCommit: { try requireCurrent(directory, name) })
            }
            let revision = try Self.replace(directory, name, writer: { try Self.writeAll($0, bytes) },
                                            beforeCommit: { try requireCurrent(directory, name) })
            observation.revision = revision; observation.known = revision != nil
        }
    }
    public static func export(_ database: Database, to url: URL) throws {
        let bytes = try encode(database)
        let directory = try parent(of: url, create: false, managed: false)
        defer { close(directory) }
        _ = try replace(directory, url.lastPathComponent, writer: { try writeAll($0, bytes) })
    }
    public func restoreBackup() throws -> Database {
        try transaction(create: false) { directory, name in
            // Explicit restore may recover a corrupt primary, but never an unobserved
            // or externally changed primary. A failed load acknowledges corrupt bytes.
            try requireCurrent(directory, name)
            guard let backup = try Self.openFile(directory, name + ".backup", privateMode: true) else { throw DataError.invalid("No backup exists.") }
            defer { close(backup) }
            let bytes = try Self.read(backup), database = try Self.decode(bytes)
            if let old = try Self.openFile(directory, name, privateMode: true) {
                defer { close(old) }
                let original = try Self.inspect(old)
                observation.revision = Revision(original)
                // Stream recovery copies, even for oversized/corrupt inputs. Keep the
                // primary in place until the final atomic replacement is ready.
                let recovery = name + ".recovery-" + UUID().uuidString
                _ = try Self.replace(directory, recovery, writer: { target in
                    var remaining = Int64(original.st_size)
                    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                    while remaining > 0 {
                        let count = buffer.withUnsafeMutableBytes { Self.readSystem(old, $0.baseAddress!, min($0.count, Int(min(remaining, 65536)))) }
                        if count < 0, errno == EINTR { continue }
                        guard count > 0 else { throw Self.failure("Copy recovery file") }
                        try Self.writeAll(target, Data(buffer.prefix(count)))
                        remaining -= Int64(count)
                    }
                    guard Revision(original) == Revision(try Self.inspect(old)) else { throw Self.conflict() }
                }, beforeCommit: { try requireCurrent(directory, name) })
            }
            let revision = try Self.replace(directory, name, writer: { try Self.writeAll($0, bytes) },
                                            beforeCommit: { try requireCurrent(directory, name) })
            observation.revision = revision; observation.known = revision != nil
            return database
        }
    }
}

public enum ParsedSchedule: Equatable, Sendable {
    case date(Day, reminder: Date?), anytime, someday, evening(Day)
}
public enum DateParser {
    /// Deliberately bounded English parser. Unrecognized text never silently schedules a task.
    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedSchedule? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let today = Day(now, calendar: calendar)
        if text == "anytime" || text == "clear" { return .anytime }
        if text == "someday" { return .someday }
        if ["tonight", "evening", "this evening"].contains(text) { return .evening(today) }
        var time: (Int, Int)?
        let pattern = #"\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#
        if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let hourRange = Range(match.range(at: 1), in: text), let rawHour = Int(text[hourRange]) {
            let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
            let period = Range(match.range(at: 3), in: text).map { String(text[$0]) }
            let hasTime = period != nil || match.range(at: 2).location != NSNotFound
            if hasTime {
                guard (0...59).contains(minute), period == nil ? (0...23).contains(rawHour) : (1...12).contains(rawHour) else { return nil }
                var hour = rawHour
                if let period { hour = rawHour % 12 + (period == "pm" ? 12 : 0) }
                time = (hour, minute)
                text = String(text[..<Range(match.range, in: text)!.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        var day: Day?
        if text == "today" || text.isEmpty { day = today }
        else if text == "tomorrow" || text == "tom" { day = today.adding(.day, 1, calendar: calendar) }
        else if text == "next week" { day = today.adding(.day, 7, calendar: calendar) }
        else if text == "next month" { day = today.adding(.month, 1, calendar: calendar) }
        else if let parsed = Day(iso: text) { day = parsed }
        else {
            let parts = text.split(separator: " ")
            if parts.count == 3, parts[0] == "in", let number = Int(parts[1]), (1...36500).contains(number) {
                let component: Calendar.Component?
                switch parts[2] { case "day", "days": component = .day; case "week", "weeks": component = .weekOfYear; case "month", "months": component = .month; case "year", "years": component = .year; default: component = nil }
                if let component { day = today.adding(component, number, calendar: calendar) }
            } else {
                let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
                let word = text.replacingOccurrences(of: "next ", with: "")
                if word.count >= 3, let weekday = names.firstIndex(where: { $0.hasPrefix(word) }) {
                    let offset = (weekday + 1 - calendar.component(.weekday, from: now) + 7) % 7
                    day = today.adding(.day, offset == 0 ? 7 : offset, calendar: calendar)
                }
            }
        }
        guard let day, Day(iso: day.iso) != nil else { return nil }
        let reminder = time.flatMap { calendar.date(bySettingHour: $0.0, minute: $0.1, second: 0, of: day.date(calendar: calendar)) }
        return .date(day, reminder: reminder)
    }
}
