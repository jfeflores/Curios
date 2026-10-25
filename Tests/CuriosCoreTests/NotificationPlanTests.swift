#if CURIOS_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
@testable import CuriosCore

final class NotificationPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func task(_ number: Int, after seconds: TimeInterval = 600) -> Item {
        var item = Item("PRIVATE task \(number)")
        item.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
        item.reminder = now.addingTimeInterval(seconds)
        return item
    }
    private func database(_ items: [Item]) -> Database {
        var db = Database(); db.preferences.notifications = true; db.items = items
        return db
    }
    func testPreviewContainsNoTaskOrContainerText() {
        var project = Item("PRIVATE project", kind: .project)
        let area = Area("PRIVATE area"); project.areaID = area.id
        var item = task(1); item.projectID = project.id; item.notes = "PRIVATE notes"
        var db = database([project, item]); db.areas = [area]
        let plan = NotificationPlan(database: db, now: now)
        XCTAssertEqual(plan.reminders.count, 1)
        XCTAssertEqual(plan.reminders.first?.title, "Curios reminder")
        XCTAssertEqual(plan.reminders.first?.body, "Open Curios to review your reminders.")
        let output = plan.reminders.map { "\($0.identifier) \($0.title) \($0.body)" }.joined()
        XCTAssertFalse(output.contains("PRIVATE"))
        db.items[0].title = "Another project"; db.items[1].title = "Another task"; db.items[1].notes = "Other notes"
        db.areas[0].title = "Another area"
        XCTAssertEqual(plan, NotificationPlan(database: db, now: now))
    }
    func testEligibilityExcludesFinishedTrashContainersAndTemplates() {
        let good = task(1)
        var completed = task(2); completed.status = .completed
        var canceled = task(3); canceled.status = .canceled
        var trashed = task(4); trashed.trashedAt = now
        var project = task(5); project.kind = .project
        var heading = task(6); heading.kind = .heading
        var template = task(7); template.recurrence = RepeatRule()
        var templateProject = task(8); templateProject.kind = .project; templateProject.recurrence = RepeatRule()
        var templateChild = task(9); templateChild.projectID = templateProject.id
        var finishedProject = task(10); finishedProject.kind = .project; finishedProject.status = .completed
        var finishedChild = task(11); finishedChild.projectID = finishedProject.id
        var missing = task(12); missing.reminder = nil
        let past = task(13, after: -1), current = task(14, after: 0)
        var invalid = task(15); invalid.reminder = Date(timeIntervalSinceReferenceDate: .infinity)
        let db = database([good, completed, canceled, trashed, project, heading, template,
                           templateProject, templateChild, finishedProject, finishedChild, missing, past, current, invalid])
        XCTAssertEqual(NotificationPlan(database: db, now: now).reminders.map(\.identifier), ["curios-\(good.id.uuidString)"])
    }
    func testDisabledNotificationsProduceEmptyPlan() {
        var db = database([task(1)]); db.preferences.notifications = false
        let plan = NotificationPlan(database: db, now: now)
        XCTAssertFalse(plan.enabled)
        XCTAssertTrue(plan.reminders.isEmpty)
    }
    func testDueDateThenIdentifierSortingIsIndependentOfInputOrder() {
        let first = task(1, after: 10), tieA = task(2, after: 20), tieB = task(3, after: 20)
        let a = NotificationPlan(database: database([tieB, first, tieA]), now: now)
        let b = NotificationPlan(database: database([tieA, tieB, first]), now: now)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.reminders.map(\.identifier), [first, tieA, tieB].map { "curios-\($0.id.uuidString)" })
    }
    func testDeduplicationKeepsEarliestReminderDeterministically() {
        let early = task(1, after: 10)
        var late = early; late.reminder = now.addingTimeInterval(30); late.title = "Different private text"
        let other = task(2, after: 20)
        let plan = NotificationPlan(database: database([late, other, early, early]), now: now)
        XCTAssertEqual(plan.reminders.count, 2)
        XCTAssertEqual(plan.reminders.map(\.date), [early.reminder!, other.reminder!])
        XCTAssertEqual(plan, NotificationPlan(database: database([early, late, early, other]), now: now))
    }
    func testWindowAppliesAfterEligibilitySortingAndDeduplication() {
        let future = (1...80).map { task($0, after: Double($0)) }
        var junk = (81...120).map { task($0, after: -1) }
        junk.append(contentsOf: Array(repeating: future[0], count: 80))
        let db = database(junk + future.reversed())
        let plan = NotificationPlan(database: db, now: now)
        XCTAssertEqual(plan.reminders.count, 60)
        XCTAssertEqual(plan.reminders.map(\.identifier), future.prefix(60).map { "curios-\($0.id.uuidString)" })
        let refilled = NotificationPlan(database: db, now: now.addingTimeInterval(60))
        XCTAssertEqual(refilled.reminders.count, 20)
        XCTAssertEqual(refilled.reminders.first?.date, now.addingTimeInterval(61))
    }
    func testOwnershipKeepsLegacyRequestsAndExcludesOtherApps() {
        XCTAssertTrue(NotificationPlan.owns("daybook-123"))
        XCTAssertTrue(NotificationPlan.owns("curios-123"))
        XCTAssertFalse(NotificationPlan.owns("another-app-123"))
        XCTAssertFalse(NotificationPlan.owns("daybookish-123"))
    }
}
