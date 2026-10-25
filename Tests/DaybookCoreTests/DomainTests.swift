#if DAYBOOK_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
@testable import DaybookCore

final class DomainTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
    func day(_ value: String) -> Day { Day(iso: value)! }
    func testDaysValidateLeapDates() throws {
        XCTAssertNil(Day(iso: "2025-02-29")); XCTAssertNil(Day(iso: "2026-13-01"))
        XCTAssertEqual(day("2024-02-29").adding(.day, 1, calendar: calendar), day("2024-03-01"))
        XCTAssertThrowsError(try JSONDecoder().decode(Day.self, from: Data("\"nonsense\"".utf8)))
    }
    func testCalendarDaySurvivesDST() {
        XCTAssertEqual(day("2026-03-07").adding(.day, 2, calendar: calendar), day("2026-03-09"))
    }
    func testStartAndDeadlineAreIndependent() {
        let today = day("2026-10-20")
        var item = Item("Report", placement: .anytime); item.deadline = today.adding(.day, 3)
        var db = Database(); db.items = [item]
        XCTAssertTrue(db.items(in: .today, today: today).isEmpty)
        XCTAssertEqual(db.items(in: .anytime, today: today).count, 1)
        XCTAssertEqual(db.items(in: .upcoming, today: today).count, 1)
        db.items[0].deadline = today
        XCTAssertEqual(db.items(in: .today, today: today).count, 1)
    }
    func testFutureStartHidesTaskUntilReadyAndOverdueCarriesForward() {
        var db = Database(); db.items = [Item("Later", placement: .scheduled, start: day("2026-10-21"))]
        XCTAssertTrue(db.items(in: .today, today: day("2026-10-20")).isEmpty)
        XCTAssertTrue(db.items(in: .anytime, today: day("2026-10-20")).isEmpty)
        XCTAssertEqual(db.items(in: .today, today: day("2026-10-22")).count, 1)
    }
    func testProjectSchedulingAndSomedayAreInherited() {
        var db = Database(); let project = Item("Project", kind: .project, placement: .someday)
        var task = Item("Task", placement: .scheduled, start: day("2026-10-20")); task.projectID = project.id
        db.items = [project, task]
        XCTAssertFalse(db.isToday(task, today: day("2026-10-20")))
        XCTAssertEqual(db.items(in: .someday).count, 2)
        db.schedule(project.id, placement: .scheduled, day: day("2026-10-25"))
        XCTAssertFalse(db.isAvailable(task, today: day("2026-10-20")))
    }
    func testInboxNotInAnytimeAndFinishedNotActive() {
        var db = Database(); let task = Item("Inbox"); db.items = [task]
        XCTAssertEqual(db.items(in: .inbox).count, 1); XCTAssertTrue(db.items(in: .anytime).isEmpty)
        db.setStatus(task.id, .completed)
        XCTAssertTrue(db.items(in: .inbox).isEmpty); XCTAssertEqual(db.items(in: .logbook).count, 1)
    }
    func testTagsInheritProjectAreaAndAncestorsWithoutDuplicating() {
        let parent = Tag("Place"), child = Tag("Home")
        var nested = child; nested.parentID = parent.id
        let area = Area("Personal", tagIDs: [parent.id])
        var project = Item("Project", kind: .project, placement: .anytime); project.tagIDs = [child.id]; project.areaID = area.id
        var task = Item("Task", placement: .anytime); task.projectID = project.id
        var db = Database(); db.items = [project, task]; db.tags = [parent, nested]; db.areas = [area]
        XCTAssertEqual(db.effectiveTags(for: task), [parent.id, child.id])
        XCTAssertEqual(task.tagIDs, [])
        XCTAssertEqual(db.search("Home").count, 2)
    }
    func testNestedTagCycleRejected() {
        var a = Tag("a"), b = Tag("b"); a.parentID = b.id; b.parentID = a.id
        var db = Database(); db.tags = [a, b]
        XCTAssertThrowsError(try db.validated())
    }
    func testFullSearchIncludesNotesChecklistsAndLogbook() {
        var item = Item("Capture"); item.notes = "A hidden phrase"; item.checklist = [ChecklistEntry("Bring passport")]; item.status = .completed
        var db = Database(); db.items = [item]
        XCTAssertTrue(db.search("hidden", full: false).isEmpty)
        XCTAssertEqual(db.search("hidden").count, 1); XCTAssertEqual(db.search("passport").count, 1)
        XCTAssertTrue(db.search("passport missing").isEmpty)
    }
    func testRegularMonthlyAnchorDoesNotDrift() {
        var rule = RepeatRule(); rule.unit = .month; rule.anchor = day("2026-01-31")
        XCTAssertEqual(rule.next(after: day("2026-01-31"), calendar: calendar), day("2026-02-28"))
        XCTAssertEqual(rule.next(after: day("2026-02-28"), calendar: calendar), day("2026-03-31"))
    }
    func testWeeklySelectedDaysAndIntervals() {
        var rule = RepeatRule(); rule.unit = .week; rule.anchor = day("2026-10-19"); rule.weekdays = [2, 4, 6]
        XCTAssertEqual(rule.first(calendar: calendar), day("2026-10-19"))
        XCTAssertEqual(rule.next(after: day("2026-10-19"), calendar: calendar), day("2026-10-21"))
        XCTAssertEqual(rule.next(after: day("2026-10-23"), calendar: calendar), day("2026-10-26"))
    }
    func testNthAndLastWeekday() {
        var rule = RepeatRule(); rule.unit = .month; rule.anchor = day("2026-10-01"); rule.ordinal = 3; rule.ordinalWeekday = 3
        XCTAssertEqual(rule.first(calendar: calendar), day("2026-10-20"))
        rule.ordinal = -1; rule.ordinalWeekday = 6
        XCTAssertEqual(rule.first(calendar: calendar), day("2026-10-30"))
    }
    func testRepeatEndAndValidation() {
        var rule = RepeatRule(); rule.unit = .day; rule.anchor = day("2026-10-20"); rule.end = rule.anchor
        XCTAssertNil(rule.next(after: rule.anchor, calendar: calendar))
        rule.interval = 0; XCTAssertThrowsError(try rule.validate())
    }
    func testRegularCopiesAreIdempotentAndIndependent() {
        let today = day("2026-10-20")
        var rule = RepeatRule(); rule.unit = .day; rule.anchor = today.adding(.day, -2)
        var template = Item("Daily", placement: .anytime); template.recurrence = rule; template.nextOccurrence = rule.first(calendar: calendar); template.checklist = [ChecklistEntry("Step")]
        var db = Database(); db.items = [template]
        XCTAssertEqual(db.materialize(asOf: today, calendar: calendar), 3)
        XCTAssertEqual(db.materialize(asOf: today, calendar: calendar), 0)
        let copies = db.items.filter { $0.templateID == template.id }
        XCTAssertEqual(copies.count, 3); XCTAssertEqual(Set(copies.flatMap { $0.checklist.map(\.id) }).count, 3)
        XCTAssertTrue(db.item(template.id)!.isTemplate)
        XCTAssertEqual(db.items(in: .today, today: today).count, 3)
    }
    func testAfterCompletionUsesActualCompletionDay() {
        let today = day("2026-10-20")
        var rule = RepeatRule(); rule.mode = .afterCompletion; rule.unit = .week; rule.anchor = today
        var template = Item("Water plants", placement: .anytime); template.recurrence = rule; template.nextOccurrence = rule.first(calendar: calendar)
        var db = Database(); db.items = [template]
        XCTAssertEqual(db.materialize(asOf: today, calendar: calendar), 1)
        let copy = db.items.first { $0.templateID == template.id }!
        XCTAssertNil(db.item(template.id)!.nextOccurrence)
        let actualDay = today.adding(.day, 3)
        db.setStatus(copy.id, .completed, at: actualDay.date(calendar: calendar), calendar: calendar)
        XCTAssertEqual(db.item(template.id)!.nextOccurrence, actualDay.adding(.day, 7))
    }
    func testLeadTimeAndDeadline() {
        let today = day("2026-10-20")
        var rule = RepeatRule(); rule.anchor = today.adding(.day, 5); rule.unit = .month; rule.addDeadline = true; rule.leadDays = 5
        var template = Item("Pay bill", placement: .anytime); template.recurrence = rule; template.nextOccurrence = rule.anchor
        var db = Database(); db.items = [template]
        XCTAssertEqual(db.materialize(asOf: today, calendar: calendar), 1)
        let copy = db.items.first { $0.templateID == template.id }!
        XCTAssertEqual(copy.start, today); XCTAssertEqual(copy.deadline, today.adding(.day, 5))
    }
    func testPausedTemplatesDoNotGenerate() {
        var rule = RepeatRule(); rule.paused = true
        var task = Item("Paused", placement: .anytime); task.recurrence = rule; task.nextOccurrence = rule.anchor
        var db = Database(); db.items = [task]
        XCTAssertEqual(db.materialize(), 0)
    }
    func testRepeatingProjectRemapsHeadingsAndResetsChildren() throws {
        let today = day("2026-10-20")
        var project = Item("Weekly review", kind: .project, placement: .anytime)
        var rule = RepeatRule(); rule.anchor = today; project.recurrence = rule; project.nextOccurrence = today
        var heading = Item("Review", kind: .heading, placement: .anytime); heading.projectID = project.id
        var child = Item("Review inbox", placement: .anytime); child.projectID = project.id; child.headingID = heading.id
        var db = Database(); db.items = [project, heading, child]
        XCTAssertEqual(db.materialize(asOf: today, calendar: calendar), 1)
        let copy = db.items.first { $0.templateID == project.id }!
        let children = db.items.filter { $0.projectID == copy.id }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.first { $0.kind == .task }?.headingID, children.first { $0.kind == .heading }?.id)
        _ = try db.validated()
    }
    func testProjectCompletionAndReopenPreservePreviouslyFinishedChild() {
        let earlier = Date(timeIntervalSince1970: 100), later = Date(timeIntervalSince1970: 200)
        let project = Item("Project", kind: .project, placement: .anytime)
        var a = Item("A", placement: .anytime), b = Item("B", placement: .anytime)
        a.projectID = project.id; b.projectID = project.id; a.status = .completed; a.statusDate = earlier
        var db = Database(); db.items = [project, a, b]
        db.setStatus(project.id, .completed, at: later); XCTAssertEqual(db.progress(project.id), 1)
        db.setStatus(project.id, .open)
        XCTAssertEqual(db.item(a.id)?.status, .completed); XCTAssertEqual(db.item(b.id)?.status, .open)
    }
    func testTrashRestoreAndPurgeHierarchy() throws {
        let project = Item("Project", kind: .project, placement: .anytime)
        var task = Item("Task", placement: .anytime); task.projectID = project.id
        var db = Database(); db.items = [project, task]
        db.trash(project.id); XCTAssertEqual(db.items(in: .trash).count, 2)
        db.restore(task.id); XCTAssertNil(db.item(project.id)?.trashedAt); XCTAssertNil(db.item(task.id)?.trashedAt)
        db.trash(project.id); db.emptyTrash(); XCTAssertTrue(db.items.isEmpty); _ = try db.validated()
    }
    func testMoveToProjectAndInboxClearStaleContainer() throws {
        let project = Item("Project", kind: .project, placement: .anytime); let item = Item("Task")
        var db = Database(); db.items = [project, item]
        db.move(item.id, to: .project(project.id)); XCTAssertEqual(db.item(item.id)?.placement, .anytime)
        db.move(item.id, to: .list(.inbox)); XCTAssertNil(db.item(item.id)?.projectID); _ = try db.validated()
    }
    func testDuplicateProjectRemapsReferences() throws {
        let project = Item("Project", kind: .project, placement: .anytime)
        var h = Item("Heading", kind: .heading, placement: .anytime); h.projectID = project.id
        var t = Item("Task", placement: .anytime); t.projectID = project.id; t.headingID = h.id
        var db = Database(); db.items = [project, h, t]
        let copy = db.duplicate(project.id)!
        XCTAssertEqual(db.items.filter { $0.projectID == copy }.count, 2); _ = try db.validated()
    }
    func testParserHandlesDatesTimesAndRejectsGarbage() {
        let now = day("2026-10-20").date(calendar: calendar)
        XCTAssertEqual(DateParser.parse("in 4 days", now: now, calendar: calendar), .date(day("2026-10-24"), reminder: nil))
        XCTAssertEqual(DateParser.parse("someday", now: now, calendar: calendar), .someday)
        XCTAssertNil(DateParser.parse("somedayish", now: now, calendar: calendar))
        guard case .date(let date, let reminder) = DateParser.parse("tomorrow at 8pm", now: now, calendar: calendar) else { return XCTFail("Time parser failed") }
        XCTAssertEqual(date, day("2026-10-21")); XCTAssertEqual(calendar.component(.hour, from: reminder!), 20)
    }
    func testPersistenceAndBackupAndInvalidImport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = Persistence(url: folder.appendingPathComponent("test.json"))
        let db = Database.sample(); try storage.save(db)
        XCTAssertEqual(try storage.load()?.items.map(\.id), db.items.map(\.id))
        try storage.save(db); XCTAssertTrue(FileManager.default.fileExists(atPath: storage.url.appendingPathExtension("backup").path))
        var invalid = db; invalid.items.append(db.items[0]); XCTAssertThrowsError(try storage.save(invalid))
        XCTAssertEqual(try storage.load()?.items.count, db.items.count)
        invalid = db; invalid.schemaVersion = 99; XCTAssertThrowsError(try Persistence.decode(JSONEncoder().encode(invalid)))
    }
    func testCorruptFileIsNeverOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        let persistence = Persistence(url: url)
        XCTAssertThrowsError(try persistence.load()); XCTAssertThrowsError(try persistence.save(Database.sample()))
        XCTAssertEqual(try String(contentsOf: url), "broken")
    }
    func testReschedulingMovesReminderClockTimeWithoutChangingDeadline() {
        var task = Item("Reminder", placement: .scheduled, start: day("2026-10-20"))
        task.reminder = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: task.start!.date(calendar: calendar))
        task.deadline = day("2026-10-29")
        var db = Database(); db.items = [task]
        db.schedule(task.id, placement: .scheduled, day: day("2026-10-22"), calendar: calendar)
        XCTAssertEqual(Day(db.items[0].reminder!, calendar: calendar), day("2026-10-22"))
        XCTAssertEqual(calendar.component(.hour, from: db.items[0].reminder!), 17)
        XCTAssertEqual(db.items[0].deadline, task.deadline)
        db.schedule(task.id, placement: .someday, calendar: calendar)
        XCTAssertNil(db.items[0].reminder); XCTAssertNil(db.items[0].start)
    }
    func testRestoringRepeatingProjectRestoresCopyChildren() throws {
        var project = Item("Template", kind: .project, placement: .anytime)
        project.recurrence = RepeatRule(); project.nextOccurrence = Day()
        var child = Item("Child", placement: .anytime); child.projectID = project.id
        var db = Database(); db.items = [project, child]; db.materialize()
        db.trash(project.id); XCTAssertTrue(db.items.allSatisfy { $0.trashedAt != nil })
        db.restore(project.id); XCTAssertTrue(db.items.allSatisfy { $0.trashedAt == nil })
        _ = try db.validated()
    }
    func testTrashDoesNotChangeUnrelatedOrPreviouslyDeletedChildren() {
        let first = Item("First", kind: .project, placement: .anytime), second = Item("Second", kind: .project, placement: .anytime)
        var a = Item("A", placement: .anytime), b = Item("B", placement: .anytime)
        a.projectID = first.id; b.projectID = second.id
        var db = Database(); db.items = [first, second, a, b]
        let earlier = Date(timeIntervalSince1970: 10), later = Date(timeIntervalSince1970: 20)
        db.trash(first.id, at: earlier); db.trash(second.id, at: later)
        XCTAssertEqual(db.item(a.id)?.trashedAt, earlier)
        db.restore(first.id); XCTAssertNil(db.item(a.id)?.trashedAt); XCTAssertEqual(db.item(b.id)?.trashedAt, later)
    }
    func testSampleValidates() throws { _ = try Database.sample().validated() }
}
