import Foundation
import DaybookCore

@main
struct AppIntegrationSmoke {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("daybook-app-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("daybook.json")
        let store = AppStore(url: url)
        precondition(!store.readOnly && !store.database.items.isEmpty, "Initial data failed")
        print("PASS app initial launch / local persistence")
        var item = store.draft(in: .list(.today)); item.title = "App integration test"; item.notes = "Independent test content"
        store.put(item)
        precondition(store.database.item(item.id)?.title == item.title && store.database.items(in: .today).contains(where: { $0.id == item.id }))
        print("PASS create task in selected list")
        store.complete([item.id]); precondition(store.database.item(item.id)?.status == .completed)
        precondition(store.visibleItems(in: .list(.today)).contains { $0.id == item.id && $0.status == .completed }, "Completion must be visibly acknowledged before leaving Today")
        store.undo(); precondition(store.database.item(item.id)?.status == .open)
        store.redo(); precondition(store.database.item(item.id)?.status == .completed)
        print("PASS completion / visible feedback / undo / redo")
        store.undo(); store.schedule([item.id], placement: .scheduled, day: Day().adding(.day, 4), bucket: .evening)
        precondition(!store.database.items(in: .today).contains(where: { $0.id == item.id }))
        precondition(store.database.item(item.id)?.bucket == .evening)
        print("PASS app scheduling and Today availability")
        store.trash([item.id]); precondition(store.database.item(item.id)?.trashedAt != nil)
        store.restore([item.id]); precondition(store.database.item(item.id)?.trashedAt == nil)
        print("PASS app trash / restore")
        let link = URL(string: "daybook://add?title=Captured%20from%20URL&notes=Some%20notes&when=tomorrow")!
        let beforeCapture = store.database, bytesBeforeCapture = try Data(contentsOf: url), historyBeforeCapture = store.undoName
        precondition(store.handleURL(link) == nil && store.database == beforeCapture)
        let firstPreview = store.pendingCapture!
        _ = store.handleURL(link)
        precondition(store.pendingCapture?.id == firstPreview.id)
        _ = store.handleURL(URL(string: "curios://add?title=Must%20not%20replace%20preview")!)
        precondition(store.pendingCapture?.id == firstPreview.id)
        store.cancelCapture(UUID()); precondition(store.pendingCapture != nil)
        store.cancelCapture(firstPreview.id)
        precondition(store.pendingCapture == nil && store.database == beforeCapture && store.undoName == historyBeforeCapture)
        let bytesAfterCancel = try Data(contentsOf: url)
        precondition(bytesAfterCancel == bytesBeforeCapture)
        _ = store.handleURL(link)
        let approvedID = store.pendingCapture!.id
        precondition(store.confirmCapture(firstPreview.id) == nil)
        precondition(store.confirmCapture(approvedID) == .list(.inbox))
        precondition(store.confirmCapture(approvedID) == nil)
        _ = store.handleURL(link)
        _ = store.handleURL(URL(string: link.absoluteString.replacingOccurrences(of: "daybook:", with: "curios:"))!)
        precondition(store.pendingCapture == nil)
        precondition(store.database.items.filter { $0.title == "Captured from URL" && $0.start == Day().adding(.day, 1) }.count == 1)
        let count = store.database.items.count, approvedBytes = try Data(contentsOf: url)
        for bad in ["daybook://unknown", "things:///add?title=X", "curios://delete?id=X", "curios://add?title=X&title=Y", "curios://add?title=X&completed=true", "curios://add?title=X&when=nonsense", "curios://add?title=" + String(repeating: "x", count: ExternalCapture.maximumURLBytes + 1)] {
            precondition(store.handleURL(URL(string: bad)!) == nil && store.pendingCapture == nil && store.database.items.count == count)
        }
        let bytesAfterRejectedLinks = try Data(contentsOf: url)
        precondition(bytesAfterRejectedLinks == approvedBytes)
        precondition(store.handleURL(URL(string: "curios://show?list=today")!) == .list(.today))
        precondition(!store.pasteTasks(String(repeating: "x", count: ExternalCapture.maximumPasteBytes + 1), in: .list(.inbox)))
        precondition(store.database.items.count == count)
        store.errorMessage = nil
        print("PASS explicit URL preview / cancel / identity-bound approval / retry deduplication / rejected inputs make no writes")
        let tag = Tag("App test tag"); store.putTag(tag)
        store.deleteTag(tag.id); precondition(store.database.tag(tag.id) == nil)
        print("PASS app tag management")
        var template = store.draft(in: .list(.anytime)); template.title = "App repeating test"
        var rule = RepeatRule(); rule.unit = .day; template.recurrence = rule
        store.put(template)
        let copy = store.database.items.first { $0.templateID == template.id }
        precondition(copy != nil && store.database.item(template.id)?.isTemplate == true)
        template = store.database.item(template.id)!; template.recurrence = nil; store.put(template)
        precondition(store.database.item(copy!.id)?.templateID == nil)
        print("PASS app repeat-template generation / stop")
        let project = Item("Batch completion review", kind: .project, placement: .anytime)
        var a = Item("Batch A", placement: .anytime), b = Item("Batch B", placement: .anytime)
        a.projectID = project.id; b.projectID = project.id
        store.put(project); store.put(a); store.put(b)
        store.complete([project.id, a.id, b.id])
        precondition([project.id, a.id, b.id].allSatisfy { store.database.item($0)?.status == .completed })
        store.complete([project.id, a.id, b.id])
        precondition([project.id, a.id, b.id].allSatisfy { store.database.item($0)?.status == .open })
        store.complete([a.id]); store.complete([a.id, b.id])
        precondition([a.id, b.id].allSatisfy { store.database.item($0)?.status == .completed })
        store.complete([a.id, b.id])
        print("PASS deterministic parent/child and mixed-status batch completion")
        let uniqueA = Tag("Unique A"), uniqueB = Tag("Unique B"), common = Tag("Shared review")
        for tag in [uniqueA, uniqueB, common] { store.putTag(tag) }
        a = store.database.item(a.id)!; b = store.database.item(b.id)!
        a.tagIDs = [uniqueA.id]; b.tagIDs = [uniqueB.id]; store.put(a); store.put(b)
        var edit = TagSelectionEdit(items: [a, b]); let history = store.undoName
        store.editTags([a.id, b.id], change: edit)
        precondition(store.database.item(a.id)?.tagIDs == a.tagIDs && store.database.item(b.id)?.tagIDs == b.tagIDs && store.undoName == history)
        edit.set(common.id, selected: true); store.editTags([a.id, b.id], change: edit)
        precondition(store.database.item(a.id)?.tagIDs == [uniqueA.id, common.id] && store.database.item(b.id)?.tagIDs == [uniqueB.id, common.id])
        print("PASS dismissing batch tags is a no-op; tag patches preserve unique tags")
        a = store.database.item(a.id)!; b = store.database.item(b.id)!
        a.placement = .scheduled; b.placement = .scheduled; a.start = Day(); b.start = Day()
        a.reminder = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Day().date())
        b.reminder = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Day().date())
        store.put(a); store.put(b)
        store.editDates([a.id, b.id], change: .when(.date(Day().adding(.day, 1), reminder: nil)))
        precondition(Calendar.current.component(.hour, from: store.database.item(a.id)!.reminder!) == 9 && Calendar.current.component(.hour, from: store.database.item(b.id)!.reminder!) == 17)
        print("PASS batch scheduling preserves each task's reminder time")
        var shortcut = uniqueA; shortcut.shortcut = "x"; store.putTag(shortcut)
        store.toggleTag(shortcut.id, on: [a.id, b.id]); precondition([a.id, b.id].allSatisfy { store.database.item($0)!.tagIDs.contains(shortcut.id) })
        precondition(store.database.tag(forShortcut: "X")?.id == shortcut.id)
        store.toggleTag(shortcut.id, on: [a.id, b.id]); precondition([a.id, b.id].allSatisfy { !store.database.item($0)!.tagIDs.contains(shortcut.id) })
        print("PASS custom tag shortcuts and uniform batch toggling")
        store.preferences { $0.keepFinishedInToday = true }
        var kept = store.draft(in: .list(.today)); kept.title = "Keep checkmarks visible"; store.put(kept); store.complete([kept.id])
        let persistentView = AppStore(url: url)
        precondition(persistentView.completionFeedback.isEmpty && persistentView.visibleItems(in: .list(.today)).contains { $0.id == kept.id && $0.status == .completed })
        precondition(persistentView.database.items(in: .logbook).contains { $0.id == kept.id })
        print("PASS optional finished-in-Today presentation survives restart without delaying Logbook")
        var editing = store.draft(in: .list(.today)); editing.title = "Editor snapshot review"; store.put(editing)
        let openingSnapshot = store.database.item(editing.id)!
        var dirtyDraft = openingSnapshot; dirtyDraft.notes = "Unsaved notes must survive completion"
        store.complete([editing.id])
        let committed = store.commitEdit(dirtyDraft, original: openingSnapshot, allowCreate: false)
        precondition(committed?.status == .completed && committed?.notes == dirtyDraft.notes)
        store.trash([editing.id]); _ = store.commitEdit(dirtyDraft, original: openingSnapshot, allowCreate: false)
        precondition(store.database.item(editing.id)?.trashedAt != nil)
        store.transact("Test permanent removal") { $0.emptyTrash() }
        let countAfterRemoval = store.database.items.count
        precondition(store.commitEdit(dirtyDraft, original: openingSnapshot, allowCreate: false) == nil && store.database.items.count == countAfterRemoval)
        print("PASS stale editor commits preserve completion/trash and cannot resurrect removed items")
        let reopened = AppStore(url: url)
        precondition(!reopened.readOnly && reopened.database.items.map(\.id) == store.database.items.map(\.id))
        print("PASS restart restores saved data")
        let before = reopened.database
        var invalid = reopened.draft(in: .list(.inbox)); invalid.title = "Missing project"; invalid.projectID = UUID()
        reopened.put(invalid)
        precondition(reopened.errorMessage != nil && reopened.database == before)
        print("PASS invalid transaction rollback")
        try Data("deliberately corrupt test file".utf8).write(to: url)
        let protected = AppStore(url: url)
        precondition(protected.readOnly)
        protected.put(Item("Must not overwrite corrupt input"))
        let preserved = try String(contentsOf: url)
        precondition(preserved == "deliberately corrupt test file")
        print("PASS corrupt data is read-only and preserved")
        let sharedURL = folder.appendingPathComponent("shared/daybook.json")
        let firstWriter = AppStore(url: sharedURL), staleWriter = AppStore(url: sharedURL)
        precondition(firstWriter.put(Item("First writer must survive")))
        let staleBefore = staleWriter.database
        _ = staleWriter.handleURL(URL(string: "curios://add?title=Stale%20capture")!)
        let stalePreview = staleWriter.pendingCapture!.id
        precondition(staleWriter.confirmCapture(stalePreview) == nil && staleWriter.pendingCapture?.id == stalePreview)
        precondition(staleWriter.errorMessage != nil && staleWriter.database == staleBefore)
        precondition(staleWriter.duplicate(staleBefore.items[0].id) == nil)
        let onDisk = try Persistence.decode(Persistence.readData(from: sharedURL))
        let encodedFirstWriter = try Persistence.decode(Persistence.encode(firstWriter.database))
        precondition(onDisk == encodedFirstWriter && onDisk.items.contains { $0.title == "First writer must survive" })
        staleWriter.cancelCapture(stalePreview)
        print("PASS stale writer cannot acknowledge capture or duplication, overwrite the first save, or discard its preview")

        let ioStore = AppStore(url: folder.appendingPathComponent("io/daybook.json"))
        let ioBefore = ioStore.database
        let importURL = folder.appendingPathComponent("incoming.json")
        var incoming = Database(); incoming.items = [Item("Bounded import")]
        try Persistence.export(incoming, to: importURL)
        let imported = await ioStore.importData(from: importURL)
        precondition(imported && ioStore.database.items.contains { $0.title == "Bounded import" })
        try Data("invalid JSON".utf8).write(to: importURL)
        let beforeFailedImport = ioStore.database
        let invalidImported = await ioStore.importData(from: importURL)
        precondition(!invalidImported && ioStore.database == beforeFailedImport)
        ioStore.restoreBackup()
        let encodedIOBefore = try Persistence.decode(Persistence.encode(ioBefore))
        precondition(!ioStore.readOnly && ioStore.database == encodedIOBefore)
        print("PASS bounded asynchronous import preserves state on failure; hardened backup restore succeeds")
        print("All application integration checks passed")
    }
}
