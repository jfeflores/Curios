import Foundation

/// A bounded scheduling proposal, not a guarantee of OS acceptance or delivery.
/// Only opaque identifiers and dates cross the task-data boundary; preview text
/// is deliberately constant and never includes task, project, or calendar data.
public struct NotificationPlan: Equatable, Sendable {
    public static let title = "Curios reminder"
    public static let body = "Open Curios to review your reminders."
    /// Leave headroom rather than relying on an undocumented macOS queue limit.
    /// Reconcile periodically to refill this window as reminders become due.
    public static let schedulingLimit = 60

    public struct Reminder: Equatable, Sendable {
        public let identifier: String
        public let date: Date
        public var title: String { NotificationPlan.title }
        public var body: String { NotificationPlan.body }
    }

    public let enabled: Bool
    public let reminders: [Reminder]

    public static func owns(_ identifier: String) -> Bool {
        // Preserve ownership of requests created before the Curios rename.
        identifier.hasPrefix("daybook-") || identifier.hasPrefix("curios-")
    }

    public init(database: Database, now: Date = Date()) {
        enabled = database.preferences.notifications
        guard enabled else { reminders = []; return }
        let excludedProjects = Set(database.items.filter {
            $0.kind == .project && ($0.isTemplate || !$0.isOpen)
        }.map(\.id))
        let eligible = database.items.filter { item in
            item.kind == .task && item.isOpen && !item.isTemplate &&
                item.projectID.map { excludedProjects.contains($0) } != true &&
                item.reminder.map { $0.timeIntervalSinceReferenceDate.isFinite && $0 > now } == true
        }.sorted {
            if $0.reminder != $1.reminder { return $0.reminder! < $1.reminder! }
            return $0.id.uuidString < $1.id.uuidString
        }
        var seen = Set<UUID>()
        var selected: [Reminder] = []
        for item in eligible where seen.insert(item.id).inserted {
            selected.append(Reminder(identifier: "curios-\(item.id.uuidString)", date: item.reminder!))
            if selected.count == Self.schedulingLimit { break }
        }
        reminders = selected
    }
}
