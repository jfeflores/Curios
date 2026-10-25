#if CURIOS_STANDALONE_TESTS
import Foundation
#else
import XCTest
#endif
@testable import CuriosCore

final class ReviewRegressionTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func testDismissingMixedTagsDoesNotEraseUniqueTags() {
        let shared = Tag("Shared"), a = Tag("Only A"), b = Tag("Only B")
        var first = Item("A"), second = Item("B"); first.tagIDs = [shared.id, a.id]; second.tagIDs = [shared.id, b.id]
        var db = Database(); db.tags = [shared, a, b]; db.items = [first, second]
        let before = db, edit = TagSelectionEdit(items: db.items)
        XCTAssertEqual(edit.selected, [shared.id]); XCTAssertEqual(edit.mixed, [a.id, b.id])
        edit.apply(to: &db, ids: [first.id, second.id])
        XCTAssertEqual(db, before)
    }
    func testBatchTagPatchPreservesUneditedTags() {
        let shared = Tag("Shared"), a = Tag("Only A"), b = Tag("Only B"), new = Tag("New")
        var first = Item("A"), second = Item("B"); first.tagIDs = [shared.id, a.id]; second.tagIDs = [shared.id, b.id]
        var db = Database(); db.tags = [shared, a, b, new]; db.items = [first, second]
        var edit = TagSelectionEdit(items: db.items)
        edit.set(shared.id, selected: false); edit.set(new.id, selected: true)
        edit.apply(to: &db, ids: [first.id, second.id])
        XCTAssertEqual(db.items[0].tagIDs, [a.id, new.id]); XCTAssertEqual(db.items[1].tagIDs, [b.id, new.id])
    }
    func testMixedTagCanBeExplicitlyRemovedFromWholeSelection() {
        let tag = Tag("Mixed"); var a = Item("A"); a.tagIDs = [tag.id]; let b = Item("B")
        var db = Database(); db.tags = [tag]; db.items = [a, b]
        var edit = TagSelectionEdit(items: db.items)
        edit.set(tag.id, selected: true); edit.set(tag.id, selected: false)
        edit.apply(to: &db, ids: [a.id, b.id]); XCTAssertTrue(db.items.allSatisfy { $0.tagIDs.isEmpty })
    }
    func testBatchSchedulingPreservesIndividualReminderTimes() {
        let old = Day(iso: "2026-10-20")!, next = Day(iso: "2026-10-22")!
        var a = Item("A", placement: .scheduled, start: old), b = Item("B", placement: .scheduled, start: old)
        a.reminder = calendar.date(bySettingHour: 9, minute: 10, second: 0, of: old.date(calendar: calendar))
        b.reminder = calendar.date(bySettingHour: 17, minute: 45, second: 0, of: old.date(calendar: calendar))
        var db = Database(); db.items = [a, b]
        DateEdit.when(.date(next, reminder: nil)).apply(to: &db, ids: [a.id, b.id], calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: db.items[0].reminder!), 9)
        XCTAssertEqual(calendar.component(.minute, from: db.items[0].reminder!), 10)
        XCTAssertEqual(calendar.component(.hour, from: db.items[1].reminder!), 17)
        XCTAssertEqual(calendar.component(.minute, from: db.items[1].reminder!), 45)
        XCTAssertTrue(db.items.allSatisfy { $0.start == next && Day($0.reminder!, calendar: calendar) == next })
    }
    func testExplicitBatchReminderSetsBothButDoesNotChangeDeadlines() {
        let day = Day(iso: "2026-10-20")!, deadline = Day(iso: "2026-10-30")!
        var a = Item("A"), b = Item("B"); a.deadline = deadline; b.deadline = deadline
        let time = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day.date(calendar: calendar))!
        var db = Database(); db.items = [a, b]
        DateEdit.when(.date(day, reminder: time)).apply(to: &db, ids: [a.id, b.id], calendar: calendar)
        XCTAssertTrue(db.items.allSatisfy { $0.reminder == time && $0.deadline == deadline })
    }
    func testDeadlinePatchDoesNotCopySchedulingFields() {
        var a = Item("A", placement: .someday), b = Item("B", placement: .scheduled, start: Day())
        a.deadline = Day(); b.deadline = Day(); b.bucket = .evening; b.reminder = Date()
        var db = Database(); db.items = [a, b]
        DateEdit.deadline(nil).apply(to: &db, ids: [a.id, b.id])
        XCTAssertTrue(db.items.allSatisfy { $0.deadline == nil })
        XCTAssertEqual(db.items[0].placement, .someday); XCTAssertEqual(db.items[1].bucket, .evening)
        XCTAssertEqual(db.items[1].reminder, b.reminder)
    }
    func testStatusAssignmentIsIdempotent() {
        let item = Item("Task"); var db = Database(); db.items = [item]
        db.setStatus(item.id, .completed, at: Date(timeIntervalSince1970: 1))
        let before = db
        db.setStatus(item.id, .completed, at: Date(timeIntervalSince1970: 99))
        XCTAssertEqual(db, before)
    }
    func testTrashedItemsCannotBeCompleted() {
        let item = Item("Trashed"); var db = Database(); db.items = [item]; db.trash(item.id)
        let before = db; db.setStatus(item.id, .completed); XCTAssertEqual(db, before)
    }
    func testReopeningChildReopensContainersButNotSiblings() {
        let project = Item("Project", kind: .project, placement: .anytime)
        var heading = Item("Heading", kind: .heading, placement: .anytime); heading.projectID = project.id
        var a = Item("A", placement: .anytime), b = Item("B", placement: .anytime)
        a.projectID = project.id; a.headingID = heading.id; b.projectID = project.id; b.headingID = heading.id
        var db = Database(); db.items = [project, heading, a, b]
        db.setStatus(project.id, .completed); db.setStatus(a.id, .open)
        XCTAssertEqual(db.item(project.id)?.status, .open); XCTAssertEqual(db.item(heading.id)?.status, .open)
        XCTAssertEqual(db.item(b.id)?.status, .completed)
        XCTAssertTrue(db.items(in: .anytime).contains { $0.id == a.id })
    }
    func testProjectReopenPreservesEarlierChildAfterTimestampRoundTrip() throws {
        let project = Item("Project", kind: .project, placement: .anytime)
        var a = Item("A", placement: .anytime), b = Item("B", placement: .anytime); a.projectID = project.id; b.projectID = project.id
        var db = Database(); db.items = [project, a, b]
        // Both dates serialize to the same whole second with ISO-8601 encoding.
        db.setStatus(a.id, .completed, at: Date(timeIntervalSince1970: 200.1))
        db.setStatus(project.id, .completed, at: Date(timeIntervalSince1970: 200.9))
        db = try Persistence.decode(Persistence.encode(db)); db.setStatus(project.id, .open)
        XCTAssertEqual(db.item(a.id)?.status, .completed); XCTAssertEqual(db.item(b.id)?.status, .open)
    }
    func testTagShortcutsAreUniqueAndCaseInsensitive() throws {
        var a = Tag("A"), b = Tag("B"); a.shortcut = "f"; b.shortcut = "F"
        var db = Database(); db.tags = [a, b]
        XCTAssertThrowsError(try db.validated())
        db.tags[1].shortcut = "g"; _ = try db.validated()
        XCTAssertEqual(db.tag(forShortcut: "F")?.id, a.id); XCTAssertNil(db.tag(forShortcut: "ff"))
        db.tags[1].shortcut = "!"; XCTAssertThrowsError(try db.validated())
    }
    func testStaleEditorCannotRevertCompletionTrashOrOtherWindowChanges() throws {
        let original = Item("Original", placement: .anytime)
        var draft = original; draft.title = "Renamed here"
        var current = original; current.notes = "Changed in another window"; current.position = 99
        current.status = .completed; current.statusDate = Date(); current.statusGroupID = UUID(); current.trashedAt = Date()
        let merged = try current.mergingUserEdits(draft, original: original)
        XCTAssertEqual(merged.title, draft.title); XCTAssertEqual(merged.notes, current.notes)
        XCTAssertEqual(merged.status, .completed); XCTAssertEqual(merged.statusGroupID, current.statusGroupID)
        XCTAssertEqual(merged.trashedAt, current.trashedAt); XCTAssertEqual(merged.position, 99)
    }
    func testEditorTagDeltaPreservesOtherWindowsNewTags() throws {
        let shared = UUID(), removed = UUID(), remote = UUID(), added = UUID()
        var original = Item("Original"); original.tagIDs = [shared, removed]
        var draft = original; draft.tagIDs = [shared, added]
        var current = original; current.tagIDs.insert(remote)
        let merged = try current.mergingUserEdits(draft, original: original)
        XCTAssertEqual(merged.tagIDs, [shared, remote, added])
    }
    func testEditorCannotReplaceAnotherRecord() {
        let original = Item("Original"); var draft = original; draft.id = UUID()
        XCTAssertThrowsError(try original.mergingUserEdits(draft, original: original))
    }
    func testTagShortcutToggleUsesOneBatchIntent() {
        let tag = Tag("Focus"); var a = Item("A"); a.tagIDs = [tag.id]; let b = Item("B")
        var db = Database(); db.tags = [tag]; db.items = [a, b]
        db.toggleTag(tag.id, on: [a.id, b.id]); XCTAssertTrue(db.items.allSatisfy { $0.tagIDs.contains(tag.id) })
        db.toggleTag(tag.id, on: [a.id, b.id]); XCTAssertTrue(db.items.allSatisfy { $0.tagIDs.isEmpty })
    }
}
