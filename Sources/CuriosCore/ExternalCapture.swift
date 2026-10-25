import Foundation

/// Small, allow-listed URL protocol. Parsing never mutates a database.
public enum ExternalCapture {
    public static let maximumURLBytes = 32 * 1024
    public static let maximumTitleBytes = 1024
    public static let maximumNotesBytes = 16 * 1024
    public static let maximumScheduleBytes = 128
    public static let maximumPasteBytes = 256 * 1024
    public static let maximumPasteTasks = 1000

    public enum Command: Equatable, Sendable {
        case add(title: String, notes: String, schedule: ParsedSchedule?)
        case show(ListID)
    }

    public static func parse(_ url: URL, now: Date = Date()) throws -> Command {
        func reject() -> DataError { .invalid("This capture link is unsupported, malformed, or too large. Nothing was added.") }
        guard url.absoluteString.utf8.count <= maximumURLBytes,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["curios", "daybook"].contains(scheme),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.fragment == nil,
              let host = parts.host, ["add", "show"].contains(host),
              let query = parts.percentEncodedQuery else { throw reject() }
        // Decode each field only once; reject duplicate decoded names rather than choosing a winner.
        let fields = query.split(separator: "&", omittingEmptySubsequences: false)
        guard fields.count <= (host == "add" ? 3 : 1) else { throw reject() }
        var arguments: [String: String] = [:]
        let allowed: Set<String> = host == "add" ? ["title", "notes", "when"] : ["list"]
        for field in fields {
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, let name = String(pair[0]).removingPercentEncoding,
                  let value = String(pair[1]).removingPercentEncoding,
                  allowed.contains(name), arguments[name] == nil else { throw reject() }
            arguments[name] = value
        }
        if host == "show" {
            guard let name = arguments["list"], let list = ListID(rawValue: name) else { throw reject() }
            return .show(list)
        }
        guard let rawTitle = arguments["title"], rawTitle.utf8.count <= maximumTitleBytes else { throw reject() }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = arguments["notes"] ?? ""
        guard !title.isEmpty, !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              notes.utf8.count <= maximumNotesBytes,
              !notes.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t" }) else { throw reject() }
        var schedule: ParsedSchedule?
        if let when = arguments["when"] {
            guard !when.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  when.utf8.count <= maximumScheduleBytes,
                  let parsed = DateParser.parse(when, now: now) else { throw reject() }
            schedule = parsed
        }
        return .add(title: title, notes: notes, schedule: schedule)
    }

    /// Bound text before splitting or allocating task drafts.
    public static func pasteTitles(_ text: String) throws -> [String] {
        guard text.utf8.count <= maximumPasteBytes else { throw DataError.invalid("Clipboard text is too large. Paste at most 256 KB at once.") }
        let titles = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard titles.count <= maximumPasteTasks else { throw DataError.invalid("Paste at most 1,000 tasks at once.") }
        guard titles.allSatisfy({ $0.utf8.count <= maximumTitleBytes && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
            throw DataError.invalid("Each pasted task must be at most 1,024 UTF-8 bytes and contain no control characters.")
        }
        return titles
    }
}
