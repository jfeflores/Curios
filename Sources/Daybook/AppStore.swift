import SwiftUI
import AppKit
import DaybookCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var database = Database()
    @Published var errorMessage: String?
    @Published private(set) var readOnly = false
    @Published private(set) var today = Day()
    @Published private(set) var undoName: String?
    @Published private(set) var redoName: String?
    /// Short-lived presentation state; completion itself is persisted immediately.
    @Published private(set) var completionFeedback: [UUID: UUID] = [:]
    @Published private(set) var pendingCapture: Item?
    @Published private(set) var importing = false
    private var pendingCaptureCommand: ExternalCapture.Command?
    private var approvedCaptures: [ExternalCapture.Command] = []
    let persistence: Persistence
    private var undoStack: [(String, Database)] = []
    private var redoStack: [(String, Database)] = []
    private var refreshTimer: Timer?
    let integrations = Integrations()

    init(url: URL = Persistence.defaultURL()) {
        persistence = Persistence(url: url)
        do {
            if let loaded = try persistence.load() { database = loaded }
            else { database = .sample(); try persistence.save(database) }
            refresh()
        } catch {
            readOnly = true
            errorMessage = "Curios could not load its data. The original file is untouched. Restore its backup in Settings or inspect the data folder.\n\n\(error.localizedDescription)"
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    @discardableResult
    func transact(_ name: String, _ mutation: (inout Database) -> Void) -> Bool {
        guard !readOnly else { errorMessage = "Data is read-only until the loading problem is resolved in Settings."; return false }
        let before = database; var next = before; mutation(&next)
        guard next != before else { return true }
        do {
            next = try next.validated()
            _ = next.materialize(asOf: today)
            next = try next.validated()
            try persistence.save(next)
            undoStack.append((name, before)); if undoStack.count > 80 { undoStack.removeFirst() }
            redoStack.removeAll(); database = next; updateHistory()
            integrations.updateNotifications(next)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    private func updateHistory() { undoName = undoStack.last?.0; redoName = redoStack.last?.0 }
    func undo() {
        guard let (name, state) = undoStack.last else { return }
        do { try persistence.save(state); undoStack.removeLast(); redoStack.append((name, database)); database = state; completionFeedback = [:]; updateHistory(); integrations.updateNotifications(state) }
        catch { errorMessage = error.localizedDescription }
    }
    func redo() {
        guard let (name, state) = redoStack.last else { return }
        do { try persistence.save(state); redoStack.removeLast(); undoStack.append((name, database)); database = state; completionFeedback = [:]; updateHistory(); integrations.updateNotifications(state) }
        catch { errorMessage = error.localizedDescription }
    }
    func refresh() {
        today = Day()
        guard !readOnly else {
            integrations.updateNotifications(Database())
            integrations.refreshCalendar(Preferences())
            return
        }
        do {
            var next = try database.validated()
            _ = next.materialize(asOf: today)
            if next != database { try persistence.save(next); database = next }
        } catch { errorMessage = error.localizedDescription }
        integrations.updateNotifications(database)
        integrations.refreshCalendar(database.preferences)
    }
    func visibleItems(in destination: Destination, query: String = "") -> [Item] {
        var presentation = database
        let keepToday = destination == .list(.today) && database.preferences.keepFinishedInToday == true
        for index in presentation.items.indices where presentation.items[index].trashedAt == nil {
            let item = presentation.items[index]
            let finishedToday = keepToday && item.status != .open && item.statusDate.map({ Day($0) == today }) == true
            if completionFeedback[item.id] != nil || finishedToday { presentation.items[index].status = .open }
        }
        let source: [Item]
        switch destination {
        case .list(let list): source = (list == .logbook || list == .loggedProjects || list == .trash ? database : presentation).items(in: list, today: today)
        case .project(let id): source = presentation.items.filter { $0.projectID == id && $0.kind == .task && $0.trashedAt == nil && ($0.status == .open || database.preferences.showCompleted) }.sorted { $0.position < $1.position }
        case .area(let id): source = presentation.items.filter { $0.areaID == id && $0.projectID == nil && $0.trashedAt == nil && $0.status == .open }.sorted { $0.position < $1.position }
        case .tag(let id): source = presentation.items.filter { $0.kind != .heading && $0.isOpen && presentation.effectiveTags(for: $0).contains(id) }.sorted { $0.position < $1.position }
        case .search: source = database.search(query)
        }
        let actual = Dictionary(database.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return source.compactMap { actual[$0.id] }
    }
    func draft(kind: ItemKind = .task, in destination: Destination) -> Item {
        var item = Item(kind: kind, placement: kind == .task ? .inbox : .anytime, position: (database.items.map(\.position).max() ?? 0) + 1)
        switch destination {
        case .project(let id): if kind != .project { item.projectID = id; item.placement = .anytime }
        case .area(let id): item.areaID = id; item.placement = .anytime
        case .tag(let id): item.tagIDs = [id]
        case .list(let list):
            switch list {
            case .today: item.placement = .scheduled; item.start = today
            case .upcoming, .tomorrow: item.placement = .scheduled; item.start = today.adding(.day, 1)
            case .anytime: item.placement = .anytime
            case .someday: item.placement = .someday
            default: break
            }
        case .search: break
        }
        return item
    }
    @discardableResult
    func put(_ item: Item) -> Bool {
        var value = item; value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty else { return false }
        let old = database.item(value.id)
        guard old != nil || database.items.count < InputLimits.maximumItems else { errorMessage = "The database has reached its task limit. Nothing was added."; return false }
        if old == value { return true }
        do {
            var candidate = database; candidate.upsert(value)
            _ = try candidate.validated()
        } catch { errorMessage = error.localizedDescription; return false }
        if value.recurrence != old?.recurrence { value.nextOccurrence = value.recurrence?.first() }
        return transact(old == nil ? "Create \(value.kind.rawValue)" : "Edit \(value.kind.rawValue)") { db in
            db.upsert(value)
            if old?.isTemplate == true && value.recurrence == nil { db.stopRepeating(value.id) }
        }
    }
    @discardableResult
    func commitEdit(_ draft: Item, original: Item, allowCreate: Bool) -> Item? {
        do {
            if let current = database.item(original.id) {
                guard put(try current.mergingUserEdits(draft, original: original)) else { return nil }
            } else if allowCreate { guard put(draft) else { return nil } }
            // An existing record removed while the editor was open stays removed.
            return database.item(original.id)
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func complete(_ ids: Set<UUID>, cancel: Bool = false) {
        let eligible = database.items.filter { ids.contains($0.id) && $0.trashedAt == nil && !$0.isTemplate && !database.isTemplateChild($0) }
            .sorted { a, b in
                let rank: (ItemKind) -> Int = { $0 == .project ? 0 : ($0 == .heading ? 1 : 2) }
                return rank(a.kind) == rank(b.kind) ? a.id.uuidString < b.id.uuidString : rank(a.kind) < rank(b.kind)
            }
        guard !eligible.isEmpty else { return }
        // Derive a single batch intent before any parent can cascade to its children.
        let status: ItemStatus = cancel ? .canceled : (eligible.contains { $0.status == .open } ? .completed : .open)
        guard transact(cancel ? "Cancel items" : (status == .open ? "Reopen items" : "Complete items"), { db in
            for item in eligible { db.setStatus(item.id, status) }
        }) else { return }
        for item in eligible where database.item(item.id)?.status == .open { completionFeedback.removeValue(forKey: item.id) }
        let closed = eligible.filter { $0.status == .open && database.item($0.id)?.status != .open && database.item($0.id)?.trashedAt == nil }.map(\.id)
        let token = UUID()
        for id in closed { completionFeedback[id] = token }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                for id in closed where self.completionFeedback[id] == token { self.completionFeedback.removeValue(forKey: id) }
            }
        }
    }
    func trash(_ ids: Set<UUID>) { transact("Move to Trash") { db in for id in ids { db.trash(id) } } }
    func restore(_ ids: Set<UUID>) { transact("Restore items") { db in for id in ids { db.restore(id) } } }
    func move(_ ids: Set<UUID>, to destination: Destination) { transact("Move items") { db in for id in ids { db.move(id, to: destination) } } }
    func schedule(_ ids: Set<UUID>, placement: Placement, day: Day? = nil, bucket: StartBucket = .day) {
        transact("Schedule items") { db in for id in ids { db.schedule(id, placement: placement, day: day, bucket: bucket) } }
    }
    func editDates(_ ids: Set<UUID>, change: DateEdit) { transact("Edit dates") { change.apply(to: &$0, ids: ids) } }
    func editTags(_ ids: Set<UUID>, change: TagSelectionEdit) { transact("Edit tags") { change.apply(to: &$0, ids: ids) } }
    func toggleTag(_ id: UUID, on ids: Set<UUID>) { transact("Toggle tag") { $0.toggleTag(id, on: ids) } }
    func duplicate(_ id: UUID) -> UUID? {
        guard let source = database.item(id) else { return nil }
        let copies = 1 + (source.kind == .project ? database.items.lazy.filter { $0.projectID == id && $0.trashedAt == nil }.count : 0)
        guard database.items.count + copies <= InputLimits.maximumItems else { errorMessage = "There is no room to duplicate these items. Nothing was added."; return nil }
        var created: UUID?
        guard transact("Duplicate item", { created = $0.duplicate(id) }) else { return nil }
        return created
    }
    func setRecurrence(_ id: UUID, paused: Bool) {
        transact(paused ? "Pause repetition" : "Resume repetition") { db in
            guard let i = db.items.firstIndex(where: { $0.id == id }) else { return }; db.items[i].recurrence?.paused = paused
        }
    }
    func reorder(_ id: UUID, before target: UUID) {
        guard id != target, let targetItem = database.item(target) else { return }
        transact("Reorder items") { db in
            guard let i = db.items.firstIndex(where: { $0.id == id }) else { return }
            db.items[i].position = targetItem.position - 0.001
            db.items.sort { $0.position < $1.position }
            for j in db.items.indices { db.items[j].position = Double(j) }
        }
    }
    func addArea(_ title: String) { let text = title.trimmingCharacters(in: .whitespacesAndNewlines); if !text.isEmpty { transact("Create area") { $0.areas.append(Area(text, position: Double($0.areas.count))) } } }
    func putArea(_ area: Area) { transact("Edit area") { db in if let i = db.areas.firstIndex(where: { $0.id == area.id }) { db.areas[i] = area } } }
    func deleteArea(_ id: UUID) {
        transact("Remove area") { db in db.areas.removeAll { $0.id == id }; for i in db.items.indices where db.items[i].areaID == id { db.items[i].areaID = nil } }
    }
    func putTag(_ tag: Tag) { transact("Edit tags") { db in if let i = db.tags.firstIndex(where: { $0.id == tag.id }) { db.tags[i] = tag } else { db.tags.append(tag) } } }
    func deleteTag(_ id: UUID) {
        transact("Remove tag") { db in
            db.tags.removeAll { $0.id == id }
            for i in db.tags.indices where db.tags[i].parentID == id { db.tags[i].parentID = nil }
            for i in db.items.indices { db.items[i].tagIDs.remove(id) }
            for i in db.areas.indices { db.areas[i].tagIDs.remove(id) }
        }
    }
    func preferences(_ update: (inout Preferences) -> Void) { transact("Change settings") { update(&$0.preferences) } }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.message = "Merge a Curios or legacy Daybook JSON export. Matching IDs are updated; unrelated items are preserved. This is not a Things database importer."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importData(from: url) }
    }
    @discardableResult
    func importData(from url: URL) async -> Bool {
        guard !importing, !readOnly else { errorMessage = "Resolve the loading problem or wait for the current import before importing."; return false }
        importing = true
        defer { importing = false }
        do {
            let incoming = try await Task.detached(priority: .userInitiated) {
                try Persistence.decode(Persistence.readData(from: url))
            }.value
            let itemIDs = Set(incoming.items.map(\.id)), areaIDs = Set(incoming.areas.map(\.id)), tagIDs = Set(incoming.tags.map(\.id))
            // Check merged counts before allocating the merged arrays. Validate relationships before recurrence.
            guard database.items.lazy.filter({ !itemIDs.contains($0.id) }).count + incoming.items.count <= InputLimits.maximumItems,
                  database.areas.lazy.filter({ !areaIDs.contains($0.id) }).count + incoming.areas.count <= InputLimits.maximumAreas,
                  database.tags.lazy.filter({ !tagIDs.contains($0.id) }).count + incoming.tags.count <= InputLimits.maximumTags else {
                throw DataError.invalid("The merged database would be too large. Nothing was imported.")
            }
            return transact("Import data") { db in
                db.items.removeAll { itemIDs.contains($0.id) }; db.items += incoming.items
                db.areas.removeAll { areaIDs.contains($0.id) }; db.areas += incoming.areas
                db.tags.removeAll { tagIDs.contains($0.id) }; db.tags += incoming.tags
            }
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Curios-\(today.iso).json"
        panel.message = "This export is unencrypted plain text, including task titles, notes, and checklist content. Save it only somewhere you trust."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Persistence.export(database, to: url) }
        catch { errorMessage = error.localizedDescription }
    }
    func pasteTasks(in destination: Destination) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        pasteTasks(text, in: destination)
    }
    @discardableResult
    func pasteTasks(_ text: String, in destination: Destination) -> Bool {
        do {
            let titles = try ExternalCapture.pasteTitles(text)
            guard database.items.count + titles.count <= InputLimits.maximumItems else { throw DataError.invalid("There is no room for these tasks. Nothing was pasted.") }
            let drafts = titles.enumerated().map { offset, title -> Item in
                var value = draft(in: destination); value.title = title; value.position += Double(offset); return value
            }
            return transact("Paste tasks") { $0.items += drafts }
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func restoreBackup() {
        do {
            let restored = try persistence.restoreBackup()
            database = restored; readOnly = false; errorMessage = nil; undoStack = []; redoStack = []; completionFeedback = [:]; updateHistory()
            integrations.updateNotifications(restored)
        } catch { errorMessage = error.localizedDescription }
    }
    func handleURL(_ url: URL) -> Destination? {
        guard let scheme = url.scheme?.lowercased(), ["curios", "daybook"].contains(scheme) else { return nil }
        do {
            let command = try ExternalCapture.parse(url)
            switch command {
            case .show(let list): return .list(list)
            case .add(let title, let notes, let schedule):
                guard !approvedCaptures.contains(command) else { return nil }
                if pendingCapture != nil {
                    if pendingCaptureCommand != command { errorMessage = "Confirm or cancel the current capture before opening another capture link." }
                    return nil
                }
                guard approvedCaptures.count < 1000 else { throw DataError.invalid("The capture limit for this session has been reached. Restart the app to capture more links.") }
                var item = draft(in: .list(.inbox)); item.title = title; item.notes = notes
                if let schedule { Self.apply(schedule, to: &item) }
                pendingCaptureCommand = command; pendingCapture = item
                return nil
            }
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    @discardableResult
    func confirmCapture(_ id: UUID) -> Destination? {
        guard let item = pendingCapture, item.id == id, let command = pendingCaptureCommand else { return nil }
        guard put(item) else { return nil } // Keep the preview available when saving fails.
        approvedCaptures.append(command)
        pendingCapture = nil; pendingCaptureCommand = nil
        return .list(.inbox)
    }
    func cancelCapture(_ id: UUID) {
        guard pendingCapture?.id == id else { return }
        pendingCapture = nil; pendingCaptureCommand = nil
    }
    static func apply(_ parsed: ParsedSchedule, to item: inout Item) {
        var database = Database(); database.items = [item]
        database.applySchedule(parsed, to: [item.id]); item = database.items[0]
    }
}
