import Foundation

/// A calendar day, not an instant: changing time zones must not move a task's date.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let iso: String
    public var description: String { iso }
    public init(_ date: Date = Date(), calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        iso = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public init?(iso: String) {
        // Check the fixed-size ASCII representation before splitting/converting input.
        guard iso.utf8.count == 10 else { return nil }
        let bytes = Array(iso.utf8)
        guard bytes.enumerated().allSatisfy({ index, byte in
            index == 4 || index == 7 ? byte == 45 : (48...57).contains(byte)
        }) else { return nil }
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]) else { return nil }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = c.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              Day(date, calendar: c).iso == iso else { return nil }
        self.iso = iso
    }
    public func date(calendar: Calendar = .current) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }
    public func adding(_ component: Calendar.Component = .day, _ count: Int, calendar: Calendar = .current) -> Day {
        Day(calendar.date(byAdding: component, value: count, to: date(calendar: calendar))!, calendar: calendar)
    }
    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.iso < rhs.iso }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer(); let raw = try c.decode(String.self)
        guard let day = Day(iso: raw) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid calendar day: \(raw)") }
        self = day
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(iso) }
    public func label(relativeTo today: Day = Day(), calendar: Calendar = .current) -> String {
        if self == today { return "Today" }
        if self == today.adding(.day, 1, calendar: calendar) { return "Tomorrow" }
        if self == today.adding(.day, -1, calendar: calendar) { return "Yesterday" }
        let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "EEE, d MMM"
        return f.string(from: date(calendar: calendar))
    }
}

public enum ItemKind: String, Codable, CaseIterable, Sendable { case task, project, heading }
public enum ItemStatus: String, Codable, CaseIterable, Sendable { case open, completed, canceled }
public enum Placement: String, Codable, CaseIterable, Sendable { case inbox, anytime, someday, scheduled }
public enum StartBucket: String, Codable, Sendable { case day, evening }
public struct ChecklistEntry: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var completed = false
    public init(_ title: String, completed: Bool = false) { self.title = title; self.completed = completed }
}
public struct Tag: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var parentID: UUID?
    public var shortcut: String = ""
    public init(_ name: String, parentID: UUID? = nil) { self.name = name; self.parentID = parentID }
}
public struct Area: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var tagIDs: Set<UUID> = []
    public var position: Double = 0
    public init(_ title: String, tagIDs: Set<UUID> = [], position: Double = 0) {
        self.title = title; self.tagIDs = tagIDs; self.position = position
    }
}
public struct Item: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var kind: ItemKind = .task
    public var title: String = ""
    public var notes: String = ""
    public var checklist: [ChecklistEntry] = []
    public var tagIDs: Set<UUID> = []
    public var projectID: UUID?
    public var areaID: UUID?
    public var headingID: UUID?
    public var placement: Placement = .inbox
    public var start: Day?
    public var bucket: StartBucket = .day
    public var deadline: Day?
    public var reminder: Date?
    public var status: ItemStatus = .open
    public var statusDate: Date?
    /// Groups a container completion with only the children changed by that action.
    public var statusGroupID: UUID?
    public var trashedAt: Date?
    public var createdAt = Date()
    public var modifiedAt = Date()
    public var position: Double = 0
    public var recurrence: RepeatRule?
    public var nextOccurrence: Day?
    public var templateID: UUID?
    public var occurrence: Day?
    public var isTemplate: Bool { recurrence != nil }
    public var isOpen: Bool { status == .open && trashedAt == nil }
    public init(_ title: String = "", kind: ItemKind = .task, placement: Placement = .inbox, start: Day? = nil, position: Double = 0) {
        self.title = title; self.kind = kind; self.placement = placement; self.start = start; self.position = position
    }
}
public enum ListID: String, Codable, CaseIterable, Sendable {
    case inbox, today, upcoming, anytime, someday, logbook, trash, tomorrow, deadlines, repeating, projects, loggedProjects
    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .anytime: return "Anytime"
        case .someday: return "Someday"
        case .logbook: return "Logbook"
        case .trash: return "Trash"
        case .tomorrow: return "Tomorrow"
        case .deadlines: return "Deadlines"
        case .repeating: return "Repeating"
        case .projects: return "All Projects"
        case .loggedProjects: return "Logged Projects"
        }
    }
    public static var sidebar: [ListID] { [.inbox, .today, .upcoming, .anytime, .someday, .logbook, .trash] }
}
public enum Destination: Hashable, Sendable {
    case list(ListID), project(UUID), area(UUID), tag(UUID), search
}
public struct Preferences: Codable, Equatable, Sendable {
    public var appearance = "system"
    public var showCompleted = true
    /// Optional for compatibility with existing version-1 exports.
    public var keepFinishedInToday: Bool?
    public var notifications = false
    public var calendarEnabled = false
    public var calendarIDs: Set<String> = []
    public var weekStartsMonday = true
    public init() {}
}
public struct Database: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var items: [Item] = []
    public var areas: [Area] = []
    public var tags: [Tag] = []
    public var preferences = Preferences()
    public init() {}
    public func item(_ id: UUID?) -> Item? { items.first { $0.id == id } }
    public func area(_ id: UUID?) -> Area? { areas.first { $0.id == id } }
    public func tag(_ id: UUID?) -> Tag? { tags.first { $0.id == id } }
    public func project(for item: Item) -> Item? { self.item(item.projectID) }
    public func area(for item: Item) -> Area? { area(project(for: item)?.areaID ?? item.areaID) }
    public func containerName(for item: Item) -> String? { project(for: item)?.title ?? area(for: item)?.title }
    public func effectiveTags(for item: Item) -> Set<UUID> {
        var result = item.tagIDs.union(project(for: item)?.tagIDs ?? []).union(area(for: item)?.tagIDs ?? [])
        var pending = Array(result)
        while let id = pending.popLast() {
            if let parent = tag(id)?.parentID, result.insert(parent).inserted { pending.append(parent) }
        }
        return result
    }
    public func isTemplateChild(_ item: Item) -> Bool { project(for: item)?.isTemplate == true }
    public func effectivePlacement(_ item: Item) -> Placement {
        if project(for: item)?.placement == .someday { return .someday }
        return item.placement
    }
    public func effectiveStart(_ item: Item) -> Day? {
        [item.start, project(for: item)?.start].compactMap { $0 }.max()
    }
    public func isAvailable(_ item: Item, today: Day) -> Bool {
        item.isOpen && !item.isTemplate && !isTemplateChild(item) && effectivePlacement(item) != .someday &&
        effectivePlacement(item) != .inbox && (effectiveStart(item).map { $0 <= today } ?? true) &&
        (project(for: item).map { $0.isOpen } ?? true)
    }
    public func isToday(_ item: Item, today: Day) -> Bool {
        isAvailable(item, today: today) && ((effectiveStart(item).map { $0 <= today } ?? false) || (item.deadline.map { $0 <= today } ?? false))
    }
    public func displayDate(_ item: Item, today: Day) -> Day? {
        let repeatStart: Day?
        if let rule = item.recurrence, !rule.paused, let next = item.nextOccurrence { repeatStart = rule.addDeadline ? next.adding(.day, -rule.leadDays) : next }
        else { repeatStart = nil }
        return ([effectiveStart(item), item.deadline, repeatStart].compactMap { $0 }.filter { $0 > today }).min()
    }
    public func items(in list: ListID, today: Day = Day()) -> [Item] {
        let results = items.filter { item in
            guard item.kind != .heading else { return false }
            if list == .trash { return item.trashedAt != nil }
            guard item.trashedAt == nil else { return false }
            if list == .logbook { return item.status != .open && !item.isTemplate }
            if list == .loggedProjects { return item.kind == .project && item.status != .open }
            if list == .repeating { return item.isTemplate }
            guard item.status == .open else { return false }
            if list == .projects { return item.kind == .project && !item.isTemplate }
            if list == .upcoming { return !isTemplateChild(item) && effectivePlacement(item) != .someday && displayDate(item, today: today) != nil }
            guard !item.isTemplate, !isTemplateChild(item) else { return false }
            switch list {
            case .inbox: return item.kind == .task && item.projectID == nil && item.placement == .inbox
            case .today: return isToday(item, today: today)
            case .anytime: return isAvailable(item, today: today)
            case .someday: return effectivePlacement(item) == .someday
            case .tomorrow: return effectiveStart(item) == today.adding(.day, 1)
            case .deadlines: return item.deadline != nil
            default: return false
            }
        }
        return results.sorted {
            if list == .logbook || list == .loggedProjects || list == .trash {
                let a = $0.trashedAt ?? $0.statusDate ?? $0.modifiedAt, b = $1.trashedAt ?? $1.statusDate ?? $1.modifiedAt
                if a != b { return a > b }
            }
            if list == .upcoming || list == .deadlines || list == .repeating {
                let a = list == .deadlines ? $0.deadline : (list == .repeating ? $0.nextOccurrence : displayDate($0, today: today))
                let b = list == .deadlines ? $1.deadline : (list == .repeating ? $1.nextOccurrence : displayDate($1, today: today))
                if a != b { return (a?.iso ?? "9999-12-31") < (b?.iso ?? "9999-12-31") }
            }
            return $0.position == $1.position ? $0.createdAt < $1.createdAt : $0.position < $1.position
        }
    }
    public func search(_ query: String, full: Bool = true) -> [Item] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }
        return items.filter { item in
            guard item.trashedAt == nil, full || item.status == .open else { return false }
            var text = item.title
            if full { text += " " + item.notes + " " + item.checklist.map(\.title).joined(separator: " ") }
            text += " " + effectiveTags(for: item).compactMap { tag($0)?.name }.joined(separator: " ")
            return terms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }.sorted { $0.position < $1.position }
    }
    public func progress(_ projectID: UUID) -> Double {
        let children = items.filter { $0.projectID == projectID && $0.kind == .task && $0.trashedAt == nil }
        return children.isEmpty ? 0 : Double(children.filter { $0.status != .open }.count) / Double(children.count)
    }
    public func validated() throws -> Database {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw DataError.invalid(message) } }
        try require(schemaVersion == 1, "Unsupported file version. Your existing data has not been changed.")
        try require(items.count <= InputLimits.maximumItems && tags.count <= InputLimits.maximumTags && areas.count <= InputLimits.maximumAreas, "Import is too large.")
        try require(Set(items.map(\.id)).count == items.count, "Duplicate item IDs.")
        try require(Set(tags.map(\.id)).count == tags.count, "Duplicate tag IDs.")
        try require(Set(areas.map(\.id)).count == areas.count, "Duplicate area IDs.")
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let tagIDs = Set(tags.map(\.id)), areaIDs = Set(areas.map(\.id))
        var textBytes = 0, checklistCount = 0, assignmentCount = 0
        func text(_ value: String, limit: Int, named: Bool = false) throws {
            let count = value.utf8.count
            try require(count <= limit, "Text exceeds the UTF-8 byte limit.")
            textBytes += count
            try require(textBytes <= InputLimits.totalTextUTF8Bytes, "Total text is too large.")
            if named { try require(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A title or name is required.") }
        }
        func assignments(_ ids: Set<UUID>) throws {
            try require(ids.count <= InputLimits.tagAssignmentsPerRecord && ids.isSubset(of: tagIDs), "Invalid or excessive tag assignments.")
            assignmentCount += ids.count
            try require(assignmentCount <= InputLimits.totalTagAssignments, "Too many tag assignments.")
        }
        // Explicit DFS stacks and memoized longest paths: O(vertices + edges),
        // independent of array order, with no recursive stack growth.
        func graph(_ edges: [UUID: [UUID]], limit: Int) throws {
            var depths: [UUID: Int] = [:]
            var visiting: Set<UUID> = []
            for root in edges.keys where depths[root] == nil {
                var stack: [(id: UUID, next: Int)] = [(root, 0)]
                visiting.insert(root)
                while let frame = stack.last {
                    let parents = edges[frame.id]!
                    if frame.next < parents.count {
                        let parent = parents[frame.next]
                        stack[stack.count - 1].next += 1
                        try require(edges[parent] != nil, "Missing relationship.")
                        if depths[parent] != nil { continue }
                        try require(!visiting.contains(parent), "Cyclic relationship hierarchy.")
                        try require(stack.count < limit, "Relationship hierarchy is too deep.")
                        visiting.insert(parent); stack.append((parent, 0))
                    } else {
                        let depth = 1 + (parents.compactMap { depths[$0] }.max() ?? 0)
                        try require(depth <= limit, "Relationship hierarchy is too deep.")
                        depths[frame.id] = depth; visiting.remove(frame.id); stack.removeLast()
                    }
                }
            }
        }
        var shortcuts: Set<String> = []
        var tagEdges: [UUID: [UUID]] = [:]
        for tag in tags {
            try text(tag.name, limit: InputLimits.titleUTF8Bytes, named: true)
            try require(tag.shortcut.utf8.count <= 1, "Tag shortcuts must be one letter or number.")
            if !tag.shortcut.isEmpty {
                let shortcut = tag.shortcut.lowercased()
                try require(shortcut.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) }, "Tag shortcuts must be one letter or number.")
                try require(shortcuts.insert(shortcut).inserted, "Each tag keyboard shortcut must be unique.")
            }
            tagEdges[tag.id] = tag.parentID.map { [$0] } ?? []
        }
        try graph(tagEdges, limit: InputLimits.tagHierarchyDepth)
        for area in areas {
            try text(area.title, limit: InputLimits.titleUTF8Bytes, named: true)
            try assignments(area.tagIDs)
            try require(area.position.isFinite, "Invalid area order.")
        }
        var itemEdges: [UUID: [UUID]] = [:]
        for item in items {
            try text(item.title, limit: InputLimits.titleUTF8Bytes, named: true)
            try text(item.notes, limit: InputLimits.notesUTF8Bytes)
            try require(item.position.isFinite, "Items need a valid order.")
            try assignments(item.tagIDs)
            try require(item.checklist.count <= InputLimits.checklistEntriesPerItem, "Checklist is too large.")
            checklistCount += item.checklist.count
            try require(checklistCount <= InputLimits.totalChecklistEntries, "Too many checklist entries.")
            try require(Set(item.checklist.map(\.id)).count == item.checklist.count, "Duplicate checklist IDs.")
            for entry in item.checklist { try text(entry.title, limit: InputLimits.titleUTF8Bytes) }
            for day in [item.start, item.deadline, item.nextOccurrence, item.occurrence].compactMap({ $0 }) {
                try require(Day(iso: day.iso) != nil, "Invalid calendar day.")
            }
            try require([item.createdAt, item.modifiedAt, item.reminder, item.statusDate, item.trashedAt].compactMap({ $0 }).allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite }, "Invalid timestamp.")
            if let area = item.areaID { try require(areaIDs.contains(area), "Missing area.") }
            if let id = item.projectID { try require(itemByID[id]?.kind == .project && item.kind != .project, "Invalid project relationship.") }
            if let id = item.headingID { try require(itemByID[id]?.kind == .heading && itemByID[id]?.projectID == item.projectID && item.projectID != nil, "Invalid heading relationship.") }
            try require(item.kind != .heading || item.projectID != nil, "Headings must belong to a project.")
            try require(item.placement != .scheduled || item.start != nil || item.isTemplate, "Scheduled items require a start date.")
            if let template = item.templateID { try require(itemByID[template] != nil && template != item.id, "Missing repeating template.") }
            if let rule = item.recurrence {
                try rule.validate()
                try require(item.kind != .heading && item.templateID == nil && item.projectID.flatMap { itemByID[$0] }?.isTemplate != true, "Nested repeating templates aren't supported.")
            }
            itemEdges[item.id] = [item.projectID, item.headingID, item.templateID].compactMap { $0 }
        }
        try graph(itemEdges, limit: InputLimits.relationshipDepth)
        try text(preferences.appearance, limit: InputLimits.titleUTF8Bytes)
        try require(preferences.calendarIDs.count <= InputLimits.calendarIdentifiers, "Too many calendar identifiers.")
        for id in preferences.calendarIDs { try text(id, limit: InputLimits.calendarIdentifierUTF8Bytes) }
        return self
    }
}
public enum DataError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
