import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable { case regular, afterCompletion }
public enum RepeatUnit: String, Codable, CaseIterable, Sendable {
    case day, week, month, year
    public var component: Calendar.Component {
        switch self { case .day: return .day; case .week: return .weekOfYear; case .month: return .month; case .year: return .year }
    }
}
public struct RepeatRule: Codable, Equatable, Sendable {
    public var mode: RepeatMode = .regular
    public var unit: RepeatUnit = .week
    public var interval = 1
    public var anchor = Day()
    /// Calendar weekday numbers: Sunday=1 ... Saturday=7.
    public var weekdays: Set<Int> = []
    public var monthDays: Set<Int> = []
    /// First/second/third/fourth/last weekday in a month (last = -1).
    public var ordinal: Int?
    public var ordinalWeekday: Int = 2
    public var end: Day?
    public var paused = false
    public var addDeadline = false
    public var leadDays = 0
    public init() {}
    public var summary: String {
        let period = interval == 1 ? unit.rawValue : "\(interval) \(unit.rawValue)s"
        return (paused ? "Paused · " : "") + (mode == .afterCompletion ? "\(period.capitalized) after completion" : "Every \(period)")
    }
    public func validate() throws {
        guard (1...999).contains(interval), (0...365).contains(leadDays), weekdays.isSubset(of: Set(1...7)),
              monthDays.isSubset(of: Set(1...31)), (1...7).contains(ordinalWeekday),
              ordinal == nil || [-1, 1, 2, 3, 4, 5].contains(ordinal!) else { throw DataError.invalid("Invalid repeating rule.") }
        guard Day(iso: anchor.iso) != nil, end.map({ Day(iso: $0.iso) != nil }) ?? true else { throw DataError.invalid("Invalid repeat calendar day.") }
        if let end, end < anchor { throw DataError.invalid("The repeat end must not precede its start.") }
    }
    /// Computes from the original anchor, avoiding January-31 → February-28 → March-28 drift.
    public func next(after day: Day, calendar: Calendar = .current) -> Day? {
        guard (try? validate()) != nil, Day(iso: day.iso) != nil else { return nil }
        let component: Calendar.Component = mode == .afterCompletion ? unit.component : .day
        let amount = mode == .afterCompletion ? interval : 1
        guard let date = calendar.date(byAdding: component, value: amount, to: day.date(calendar: calendar)),
              let lower = boundedDay(date, calendar: calendar), lower > day else { return nil }
        if mode == .afterCompletion { return end.map { lower <= $0 } ?? true ? lower : nil }
        return regularNext(onOrAfter: max(lower, anchor), calendar: calendar)
    }
    public func first(calendar: Calendar = .current) -> Day? {
        guard (try? validate()) != nil else { return nil }
        if mode == .afterCompletion { return anchor }
        return regularNext(onOrAfter: anchor, calendar: calendar)
    }
    private func boundedDay(_ date: Date, calendar: Calendar) -> Day? {
        let result = Day(date, calendar: calendar)
        guard Day(iso: result.iso) != nil,
              calendar.component(.era, from: date) == calendar.component(.era, from: anchor.date(calendar: calendar)) else { return nil }
        return result
    }
    private func regularNext(onOrAfter lower: Day, calendar: Calendar) -> Day? {
        if let end, lower > end { return nil }
        let start = anchor.date(calendar: calendar), lowerDate = lower.date(calendar: calendar)
        let anchorParts = calendar.dateComponents([.day, .month, .weekday], from: start)
        if unit == .day {
            let delta = max(0, calendar.dateComponents([.day], from: start, to: lowerDate).day ?? 0)
            let offset = delta + (interval - delta % interval) % interval
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  let result = boundedDay(date, calendar: calendar) else { return nil }
            return end.map { result <= $0 } ?? true ? result : nil
        }
        let component: Calendar.Component = unit == .week ? .weekOfYear : (unit == .month ? .month : .year)
        guard let base = calendar.dateInterval(of: component, for: start)?.start,
              let lowerBase = calendar.dateInterval(of: component, for: lowerDate)?.start else { return nil }
        let delta: Int
        if unit == .week { delta = (calendar.dateComponents([.day], from: base, to: lowerBase).day ?? 0) / 7 }
        else { delta = calendar.dateComponents([component], from: base, to: lowerBase).value(for: component) ?? 0 }
        var period = max(0, delta / interval)
        // Jump directly between eligible periods, selecting dates arithmetically.
        // The entire representable calendar contains fewer than 120,000 months;
        // Gregorian impossible fifth-weekday schedules stop on a 400-year cycle.
        var seenGregorianPeriods: Set<Int> = []
        for _ in 0..<120_000 {
            guard let periodStart = calendar.date(byAdding: component, value: period * interval, to: base),
                  periodStart < start || boundedDay(periodStart, calendar: calendar) != nil else { return nil }
            var dates: [Date] = []
            if unit == .week {
                let days = weekdays.isEmpty ? Set([anchorParts.weekday!]) : weekdays
                let firstWeekday = calendar.component(.weekday, from: periodStart)
                dates = days.compactMap { calendar.date(byAdding: .day, value: ($0 - firstWeekday + 7) % 7, to: periodStart) }
            } else {
                let month: Date
                if unit == .year {
                    guard let value = calendar.date(byAdding: .month, value: anchorParts.month! - 1, to: periodStart) else { return nil }
                    month = value
                } else { month = periodStart }
                let parts = calendar.dateComponents([.year, .month, .weekday], from: month)
                if calendar.identifier == .gregorian && periodStart >= lowerDate {
                    let key = (parts.year! % 400) * 12 + parts.month!
                    guard seenGregorianPeriods.insert(key).inserted else { return nil }
                }
                guard let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
                let last = range.count
                let selected: Set<Int>
                if let ordinal {
                    let first = 1 + (ordinalWeekday - parts.weekday! + 7) % 7
                    let value = ordinal == -1 ? first + ((last - first) / 7) * 7 : first + (ordinal - 1) * 7
                    selected = value <= last ? [value] : []
                } else if !monthDays.isEmpty { selected = Set(monthDays.map { min($0, last) }) }
                else { selected = [min(anchorParts.day!, last)] }
                dates = selected.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
            }
            for date in dates.sorted() {
                guard let result = boundedDay(date, calendar: calendar), result >= lower, result >= anchor else { continue }
                return end.map { result <= $0 } ?? true ? result : nil
            }
            if let end, let first = boundedDay(periodStart, calendar: calendar), first > end { return nil }
            period += 1
        }
        return nil
    }
}

/// Accounting for atomic copies. The source database is validated before these
/// counters are computed, so additions stay within explicit schema ceilings.
private struct CopyResources {
    var rows = 0
    var entries = 0
    var assignments = 0
    var text = 0
    init() {}
    init(_ item: Item) {
        rows = 1
        entries = item.checklist.count
        assignments = item.tagIDs.count
        text = item.title.utf8.count + item.notes.utf8.count
        for entry in item.checklist { text += entry.title.utf8.count }
    }
    mutating func add(_ other: CopyResources) {
        rows += other.rows; entries += other.entries
        assignments += other.assignments; text += other.text
    }
    func fits(adding other: CopyResources) -> Bool {
        rows + other.rows <= InputLimits.maximumItems &&
        entries + other.entries <= InputLimits.totalChecklistEntries &&
        assignments + other.assignments <= InputLimits.totalTagAssignments &&
        text + other.text <= InputLimits.totalTextUTF8Bytes
    }
}

extension Database {
    public mutating func upsert(_ item: Item) {
        var value = item; value.modifiedAt = Date()
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = value }
        else { items.append(value) }
    }
    public mutating func schedule(_ id: UUID, placement: Placement, day: Day? = nil, bucket: StartBucket = .day, calendar: Calendar = .current) {
        guard let i = items.firstIndex(where: { $0.id == id }), placement != .scheduled || day != nil else { return }
        if let reminder = items[i].reminder, placement == .scheduled, let day {
            let time = calendar.dateComponents([.hour, .minute], from: reminder)
            items[i].reminder = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day.date(calendar: calendar))
        } else if placement != .scheduled { items[i].reminder = nil }
        items[i].placement = placement; items[i].start = placement == .scheduled ? day : nil
        items[i].bucket = bucket; items[i].modifiedAt = Date()
    }
    public mutating func setStatus(_ id: UUID, _ status: ItemStatus, at now: Date = Date(), calendar: Calendar = .current) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].trashedAt == nil, !items[i].isTemplate, !isTemplateChild(items[i]) else { return }
        let original = items[i]
        guard original.status != status else { return }
        let group = status == .open ? nil : UUID()
        items[i].status = status; items[i].statusDate = status == .open ? nil : now; items[i].modifiedAt = now; items[i].statusGroupID = group
        if original.kind == .project || original.kind == .heading {
            for j in items.indices where (original.kind == .project ? items[j].projectID == id : items[j].headingID == id) && items[j].trashedAt == nil {
                let sameCompletion = original.statusGroupID.map { items[j].statusGroupID == $0 } ?? (items[j].statusDate == original.statusDate)
                if status != .open && items[j].status == .open {
                    items[j].status = status; items[j].statusDate = now; items[j].statusGroupID = group; items[j].modifiedAt = now
                } else if status == .open && items[j].status != .open && sameCompletion {
                    items[j].status = .open; items[j].statusDate = nil; items[j].statusGroupID = nil; items[j].modifiedAt = now
                }
            }
        }
        // Reopening a task must not strand it inside a closed heading/project.
        // Reopen its containers, not their other already-completed children.
        if status == .open {
            for parentID in [original.projectID, original.headingID].compactMap({ $0 }) {
                if let parent = items.firstIndex(where: { $0.id == parentID }), items[parent].trashedAt == nil {
                    items[parent].status = .open; items[parent].statusDate = nil; items[parent].statusGroupID = nil; items[parent].modifiedAt = now
                }
            }
        }
        if status != .open, original.status == .open, let templateID = original.templateID,
           let index = items.firstIndex(where: { $0.id == templateID }), let rule = items[index].recurrence,
           rule.mode == .afterCompletion {
            items[index].nextOccurrence = rule.next(after: Day(now, calendar: calendar), calendar: calendar)
        }
    }
    public mutating func trash(_ id: UUID, at date: Date = Date()) {
        guard item(id) != nil else { return }
        var affected: Set<UUID> = [id]
        var previous = -1
        while previous != affected.count {
            previous = affected.count
            for item in items where [item.projectID, item.headingID, item.templateID].compactMap({ $0 }).contains(where: affected.contains) { affected.insert(item.id) }
        }
        // Preserve the trash date of previously deleted children/unrelated projects.
        for i in items.indices where affected.contains(items[i].id) && items[i].trashedAt == nil { items[i].trashedAt = date }
    }
    public mutating func restore(_ id: UUID) {
        guard let target = item(id) else { return }
        let parent = item(target.projectID)
        let root = parent?.trashedAt != nil ? parent! : target
        let date = root.trashedAt
        var affected: Set<UUID> = [root.id, id]
        var previous = -1
        while previous != affected.count {
            previous = affected.count
            for item in items where item.trashedAt == date && [item.projectID, item.headingID, item.templateID].compactMap({ $0 }).contains(where: affected.contains) { affected.insert(item.id) }
        }
        for i in items.indices where affected.contains(items[i].id) { items[i].trashedAt = nil }
        if let h = target.headingID, let j = items.firstIndex(where: { $0.id == h }) { items[j].trashedAt = nil }
    }
    public mutating func emptyTrash() {
        let removed = Set(items.filter { $0.trashedAt != nil }.map(\.id))
        items.removeAll { removed.contains($0.id) }
        for i in items.indices {
            if items[i].templateID.map({ removed.contains($0) }) == true { items[i].templateID = nil }
            if items[i].headingID.map({ removed.contains($0) }) == true { items[i].headingID = nil }
        }
    }
    public mutating func move(_ id: UUID, to destination: Destination, today: Day = Day()) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].kind != .heading else { return }
        switch destination {
        case .project(let project):
            guard items[i].kind == .task, item(project)?.kind == .project, item(project)?.isOpen == true,
                  !items[i].isTemplate || item(project)?.isTemplate != true else { return }
            items[i].projectID = project; items[i].areaID = nil; items[i].headingID = nil
            if items[i].placement == .inbox { items[i].placement = .anytime }
        case .area(let area):
            guard self.area(area) != nil else { return }
            items[i].areaID = area; items[i].projectID = nil; items[i].headingID = nil
            if items[i].placement == .inbox { items[i].placement = .anytime }
        case .tag(let tag): if self.tag(tag) != nil { items[i].tagIDs.insert(tag) }
        case .list(let list):
            switch list {
            case .inbox:
                guard items[i].kind == .task else { return }
                items[i].projectID = nil; items[i].areaID = nil; items[i].headingID = nil
                schedule(id, placement: .inbox)
            case .today: schedule(id, placement: .scheduled, day: today)
            case .tomorrow: schedule(id, placement: .scheduled, day: today.adding(.day, 1))
            case .anytime: schedule(id, placement: .anytime)
            case .someday: schedule(id, placement: .someday)
            case .trash: trash(id)
            case .logbook: setStatus(id, .completed)
            default: break
            }
        case .search: break
        }
    }
    public mutating func duplicate(_ id: UUID) -> UUID? {
        guard let source = item(id) else { return nil }
        var copy = source; copy.id = UUID(); copy.title += " — copy"; copy.position += 0.01
        copy.createdAt = Date(); copy.modifiedAt = Date(); copy.templateID = nil; copy.occurrence = nil
        copy.checklist = source.checklist.map { ChecklistEntry($0.title, completed: $0.completed) }
        items.append(copy)
        if source.kind == .project {
            let children = items.filter { $0.projectID == source.id && $0.trashedAt == nil }
            let mapping = Dictionary(uniqueKeysWithValues: children.map { ($0.id, UUID()) })
            for var child in children {
                child.id = mapping[child.id]!; child.projectID = copy.id
                child.headingID = child.headingID.flatMap { mapping[$0] }
                child.templateID = nil; child.occurrence = nil
                child.checklist = child.checklist.map { ChecklistEntry($0.title, completed: $0.completed) }
                items.append(child)
            }
        }
        return copy.id
    }
    public mutating func stopRepeating(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].recurrence = nil; items[index].nextOccurrence = nil
        for i in items.indices where items[i].templateID == id { items[i].templateID = nil }
    }
    private var copyResources: CopyResources {
        var result = CopyResources()
        for item in items { result.add(CopyResources(item)) }
        for tag in tags { result.text += tag.name.utf8.count }
        for area in areas { result.text += area.title.utf8.count; result.assignments += area.tagIDs.count }
        result.text += preferences.appearance.utf8.count
        for identifier in preferences.calendarIDs { result.text += identifier.utf8.count }
        return result
    }
    /// Generates instances, not edits to the template. The occurrence key makes refresh idempotent.
    @discardableResult
    public mutating func materialize(asOf today: Day = Day(), calendar: Calendar = .current, workBudget: Int = InputLimits.recurrenceWorkBudget) -> Int {
        // Invalid in-memory/imported data must not reach date arithmetic or copying.
        guard Day(iso: today.iso) != nil, (try? validated()) != nil else { return 0 }
        let templates = items.indices.filter { items[$0].isTemplate && items[$0].isOpen && items[$0].recurrence?.paused == false }
        let children = Dictionary(grouping: items.filter { $0.projectID != nil && $0.trashedAt == nil }, by: { $0.projectID! })
        var occurrences: [UUID: Set<Day>] = [:]
        for item in items {
            if let id = item.templateID, let day = item.occurrence { occurrences[id, default: []].insert(day) }
        }
        var usage = copyResources
        let budget = min(max(workBudget, 0), InputLimits.recurrenceWorkBudget)
        var attempts = 0, copied = CopyResources(), generated = 0
        for index in templates {
            let template = items[index], id = template.id, rule = template.recurrence!
            let descendants = template.kind == .project ? children[id] ?? [] : []
            var cost = CopyResources(template)
            for child in descendants { cost.add(CopyResources(child)) }
            var cursor = template.nextOccurrence
            while let occurrence = cursor, attempts < budget, rule.end.map({ occurrence <= $0 }) ?? true {
                guard let start = occurrenceStart(occurrence, rule: rule, calendar: calendar), start <= today else { break }
                if occurrences[id]?.contains(occurrence) != true {
                    guard usage.fits(adding: cost) else { break }
                    // A project is indivisible. Permit one oversized atomic copy,
                    // bounded by the schema-wide ceilings, but no other copies in
                    // that refresh. Otherwise cap aggregate rows, entries and bytes.
                    if generated > 0 && (copied.rows + cost.rows > budget ||
                        copied.entries + cost.entries > InputLimits.recurrenceChecklistBudget ||
                        copied.text + cost.text > InputLimits.recurrenceTextUTF8Bytes) { break }
                    createInstance(template, children: descendants, occurrence: occurrence, start: start, calendar: calendar)
                    usage.add(cost); copied.add(cost); occurrences[id, default: []].insert(occurrence)
                    generated += 1
                }
                cursor = rule.mode == .afterCompletion ? nil : rule.next(after: occurrence, calendar: calendar)
                attempts += 1
                if copied.rows >= budget || copied.entries >= InputLimits.recurrenceChecklistBudget || copied.text >= InputLimits.recurrenceTextUTF8Bytes { break }
            }
            // Advance only past occurrences actually present (including old copies).
            // Budget/resource exhaustion leaves the first unprocessed day resumable.
            items[index].nextOccurrence = cursor
            if attempts >= budget || copied.rows >= budget || copied.entries >= InputLimits.recurrenceChecklistBudget || copied.text >= InputLimits.recurrenceTextUTF8Bytes { break }
        }
        return generated
    }
    public mutating func createNextCopy(_ id: UUID, calendar: Calendar = .current) {
        guard (try? validated()) != nil,
              let i = items.firstIndex(where: { $0.id == id }), let rule = items[i].recurrence,
              let day = items[i].nextOccurrence, rule.end.map({ day <= $0 }) ?? true,
              let start = occurrenceStart(day, rule: rule, calendar: calendar),
              !items.contains(where: { $0.templateID == id && $0.occurrence == day }) else { return }
        let template = items[i]
        let children = template.kind == .project ? items.filter { $0.projectID == id && $0.trashedAt == nil } : []
        var cost = CopyResources(template)
        for child in children { cost.add(CopyResources(child)) }
        guard copyResources.fits(adding: cost) else { return }
        var candidate = self
        candidate.createInstance(template, children: children, occurrence: day, start: start, calendar: calendar)
        candidate.items[i].nextOccurrence = rule.mode == .afterCompletion ? nil : rule.next(after: day, calendar: calendar)
        // Explicit copies use the same global bounds and commit atomically.
        if (try? candidate.validated()) != nil { self = candidate }
    }
    private func occurrenceStart(_ occurrence: Day, rule: RepeatRule, calendar: Calendar) -> Day? {
        guard rule.addDeadline else { return occurrence }
        guard let date = calendar.date(byAdding: .day, value: -rule.leadDays, to: occurrence.date(calendar: calendar)) else { return nil }
        let result = Day(date, calendar: calendar)
        guard Day(iso: result.iso) != nil, result <= occurrence,
              calendar.component(.era, from: date) == calendar.component(.era, from: occurrence.date(calendar: calendar)) else { return nil }
        return result
    }
    private mutating func createInstance(_ template: Item, children: [Item], occurrence: Day, start: Day, calendar: Calendar) {
        guard let rule = template.recurrence else { return }
        let id = template.id
        var copy = template; copy.id = UUID(); copy.recurrence = nil; copy.nextOccurrence = nil
        copy.templateID = id; copy.occurrence = occurrence; copy.placement = .scheduled; copy.start = start
        copy.createdAt = Date(); copy.modifiedAt = Date(); copy.status = .open; copy.statusDate = nil; copy.statusGroupID = nil
        copy.deadline = rule.addDeadline ? occurrence : nil
        copy.checklist = copy.checklist.map { ChecklistEntry($0.title) }
        if let reminder = template.reminder {
            let time = calendar.dateComponents([.hour, .minute], from: reminder)
            copy.reminder = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: start.date(calendar: calendar))
        }
        items.append(copy)
        if template.kind == .project {
            let ids = Dictionary(uniqueKeysWithValues: children.map { ($0.id, UUID()) })
            for var child in children {
                child.id = ids[child.id]!; child.projectID = copy.id; child.headingID = child.headingID.flatMap { ids[$0] }
                child.status = .open; child.statusDate = nil; child.statusGroupID = nil; child.recurrence = nil; child.nextOccurrence = nil
                child.templateID = nil; child.occurrence = nil; child.checklist = child.checklist.map { ChecklistEntry($0.title) }
                items.append(child)
            }
        }
    }
}
