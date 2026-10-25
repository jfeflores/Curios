#if CURIOS_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
@testable import CuriosCore

final class ValidationSecurityTests: XCTestCase {
    func testIndexedTagGraphHandlesWideInputAndBoundsDepth() throws {
        var db = Database(); let root = Tag("Root"); db.tags = [root]
        for index in 1..<InputLimits.maximumTags { db.tags.append(Tag("Synthetic \(index)", parentID: root.id)) }
        _ = try db.validated()
        db.tags = []
        for index in 0..<InputLimits.tagHierarchyDepth { db.tags.append(Tag("Depth \(index)", parentID: db.tags.last?.id)) }
        _ = try db.validated()
        db.tags.append(Tag("Over depth", parentID: db.tags.last!.id))
        XCTAssertThrowsError(try db.validated())
        db.tags[0].parentID = db.tags.last!.id
        XCTAssertThrowsError(try db.validated())
    }
    func testTextChecklistAndAssignmentBoundsRejectUnsafeData() throws {
        var db = Database(); var task = Item("Valid", placement: .anytime); db.items = [task]
        task.title = String(repeating: "é", count: InputLimits.titleUTF8Bytes / 2 + 1); db.items = [task]
        XCTAssertThrowsError(try db.validated())
        task.title = "Valid"; task.notes = String(repeating: "x", count: InputLimits.notesUTF8Bytes + 1); db.items = [task]
        XCTAssertThrowsError(try db.validated())
        task.notes = ""; task.checklist = (0...InputLimits.checklistEntriesPerItem).map { ChecklistEntry("\($0)") }; db.items = [task]
        XCTAssertThrowsError(try db.validated())
        task.checklist = []; db.tags = (0...InputLimits.tagAssignmentsPerRecord).map { Tag("\($0)") }
        task.tagIDs = Set(db.tags.map(\.id)); db.items = [task]
        XCTAssertThrowsError(try db.validated())
    }
    func testRelationshipCyclesAndBadCalendarStringsAreRejected() {
        var a = Item("A"), b = Item("B"); a.templateID = b.id; b.templateID = a.id
        var db = Database(); db.items = [a, b]
        XCTAssertThrowsError(try db.validated())
        for value in ["2026-02-30", "2026-10-2x", "0000-01-01", String(repeating: "1", count: 100_000)] {
            XCTAssertNil(Day(iso: value))
        }
    }
    func testRecurrenceBudgetIsGlobalAndRemainingWorkIsResumable() throws {
        let today = Day(iso: "2026-10-25")!
        var rule = RepeatRule(); rule.unit = .day; rule.anchor = today
        var db = Database()
        for index in 0..<(InputLimits.recurrenceWorkBudget + 10) {
            var item = Item("Repeater \(index)", placement: .anytime); item.recurrence = rule; item.nextOccurrence = today; db.items.append(item)
        }
        let before = db
        XCTAssertEqual(db.materialize(asOf: today, workBudget: 0), 0); XCTAssertEqual(db, before)
        XCTAssertEqual(db.materialize(asOf: today), InputLimits.recurrenceWorkBudget)
        XCTAssertEqual(db.materialize(asOf: today), 10)
        XCTAssertEqual(db.materialize(asOf: today), 0)
        XCTAssertEqual(db.items.filter { $0.templateID != nil }.count, InputLimits.recurrenceWorkBudget + 10)
        _ = try db.validated()
    }
    func testLargeRepeatingProjectCopiesAtomicallyOnce() throws {
        let today = Day(iso: "2026-10-25")!
        var rule = RepeatRule(); rule.unit = .week; rule.anchor = today
        var project = Item("Large synthetic project", kind: .project, placement: .anytime)
        project.recurrence = rule; project.nextOccurrence = today
        var db = Database(); db.items = [project]
        for index in 0...InputLimits.recurrenceWorkBudget {
            var child = Item("Child \(index)", placement: .anytime); child.projectID = project.id; db.items.append(child)
        }
        XCTAssertEqual(db.materialize(asOf: today), 1)
        let copy = db.items.first { $0.templateID == project.id }!
        XCTAssertEqual(db.items.filter { $0.projectID == copy.id }.count, InputLimits.recurrenceWorkBudget + 1)
        XCTAssertEqual(db.materialize(asOf: today), 0)
        _ = try db.validated()
    }
    func testInvalidAndOutOfRangeRecurrenceDoesNotReachUnsafeCopying() {
        let lastDay = Day(iso: "9999-12-31")!
        var rule = RepeatRule(); rule.anchor = lastDay; rule.unit = .year
        XCTAssertNil(rule.next(after: lastDay))
        rule.interval = 0
        var item = Item("Invalid repeater", placement: .anytime); item.recurrence = rule; item.nextOccurrence = lastDay
        var db = Database(); db.items = [item]; let before = db
        XCTAssertEqual(db.materialize(asOf: lastDay), 0); XCTAssertEqual(db, before)
    }
}
