import Foundation

/// Tracks user intent, not only the common intersection. Opening and dismissing
/// a mixed selection must never erase each item's unique tags.
public struct TagSelectionEdit: Equatable, Sendable {
    public var selected: Set<UUID>
    public private(set) var mixed: Set<UUID>
    public private(set) var touched: Set<UUID> = []
    public init(items: [Item]) {
        selected = items.first.map(\.tagIDs) ?? []
        var union: Set<UUID> = []
        for item in items { selected.formIntersection(item.tagIDs); union.formUnion(item.tagIDs) }
        mixed = union.subtracting(selected)
    }
    public mutating func set(_ id: UUID, selected value: Bool) {
        touched.insert(id); mixed.remove(id)
        if value { selected.insert(id) } else { selected.remove(id) }
    }
    public func apply(to database: inout Database, ids: Set<UUID>) {
        database.applyTagChanges(to: ids, adding: touched.intersection(selected), removing: touched.subtracting(selected))
    }
}

public enum DateEdit: Equatable, Sendable {
    case when(ParsedSchedule)
    case deadline(Day?)
    public func apply(to database: inout Database, ids: Set<UUID>, calendar: Calendar = .current) {
        switch self {
        case .when(let parsed): database.applySchedule(parsed, to: ids, calendar: calendar)
        case .deadline(let day):
            for i in database.items.indices where ids.contains(database.items[i].id) && database.items[i].trashedAt == nil && database.items[i].deadline != day {
                database.items[i].deadline = day; database.items[i].modifiedAt = Date()
            }
        }
    }
}

extension Database {
    public mutating func applyTagChanges(to ids: Set<UUID>, adding: Set<UUID>, removing: Set<UUID>) {
        let valid = Set(tags.map(\.id)), additions = adding.intersection(valid), removals = removing.intersection(valid)
        for i in items.indices where ids.contains(items[i].id) && items[i].trashedAt == nil {
            let next = items[i].tagIDs.union(additions).subtracting(removals)
            if next != items[i].tagIDs { items[i].tagIDs = next; items[i].modifiedAt = Date() }
        }
    }
    public mutating func toggleTag(_ id: UUID, on ids: Set<UUID>) {
        guard tag(id) != nil else { return }
        let eligible = items.filter { ids.contains($0.id) && $0.trashedAt == nil }
        guard !eligible.isEmpty else { return }
        let remove = eligible.allSatisfy { $0.tagIDs.contains(id) }
        applyTagChanges(to: ids, adding: remove ? [] : [id], removing: remove ? [id] : [])
    }
    public func tag(forShortcut key: String) -> Tag? {
        guard key.count == 1 else { return nil }
        return tags.first { !$0.shortcut.isEmpty && $0.shortcut.lowercased() == key.lowercased() }
    }
    /// A date-only change preserves each item's own reminder clock time; an
    /// explicitly supplied clock time sets that same time on all selected items.
    public mutating func applySchedule(_ parsed: ParsedSchedule, to ids: Set<UUID>, calendar: Calendar = .current) {
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].trashedAt == nil, items[index].kind != .heading else { continue }
            switch parsed {
            case .anytime: schedule(id, placement: .anytime, calendar: calendar)
            case .someday: schedule(id, placement: .someday, calendar: calendar)
            case .evening(let day): schedule(id, placement: .scheduled, day: day, bucket: .evening, calendar: calendar)
            case .date(let day, let reminder):
                schedule(id, placement: .scheduled, day: day, calendar: calendar)
                if let reminder { items[index].reminder = reminder }
            }
        }
    }
}
