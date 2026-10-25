import SwiftUI
import AppKit
import CuriosCore

private struct ItemSection: Identifiable {
    var id: String
    var title: String? = nil
    var symbol: String? = nil
    var items: [Item]
}
struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var destination: Destination = .list(.today)
    @State private var selected: Set<UUID> = []
    @State private var expandedID: UUID?
    @State private var draft: Item?
    @State private var sheetItem: Item?
    @State private var showSidebar = true
    @State private var finding = false
    @State private var query = ""
    @State private var filters: Set<UUID> = []
    @State private var managingTags = false
    @State private var addingArea = false
    @State private var areaTitle = ""
    @State private var editingArea: Area?
    @State private var confirmEmptyTrash = false
    @State private var showBatchWhen = false
    @State private var showBatchDeadline = false
    @State private var showBatchTags = false
    private var db: Database { store.database }
    private var project: Item? { if case .project(let id) = destination { return db.item(id) }; return nil }
    private var area: Area? { if case .area(let id) = destination { return db.area(id) }; return nil }
    private var list: ListID? { if case .list(let list) = destination { return list }; return nil }
    private var title: String {
        switch destination {
        case .list(let list): return list.title
        case .project(let id): return db.item(id)?.title ?? "Project"
        case .area(let id): return db.area(id)?.title ?? "Area"
        case .tag(let id): return db.tag(id)?.name ?? "Tag"
        case .search: return "Search Results"
        }
    }
    private var unfilteredItems: [Item] { store.visibleItems(in: destination, query: query) }
    private var items: [Item] { unfilteredItems.filter { filters.isSubset(of: db.effectiveTags(for: $0)) } }
    private var sections: [ItemSection] {
        let visible = items
        if list == .today {
            let evening = visible.filter { $0.bucket == .evening && db.effectiveStart($0) == store.today }
            return [ItemSection(id: "day", items: visible.filter { !evening.contains($0) })] + (evening.isEmpty ? [] : [ItemSection(id: "evening", title: "This Evening", symbol: "moon.fill", items: evening)])
        }
        if let project {
            let headings = db.items.filter { $0.kind == .heading && $0.projectID == project.id && $0.trashedAt == nil && $0.status == .open }.sorted { $0.position < $1.position }
            let ids = Set(headings.map(\.id))
            return [ItemSection(id: "unheaded", items: visible.filter { $0.headingID == nil || !ids.contains($0.headingID!) })] + headings.map { h in ItemSection(id: h.id.uuidString, title: h.title, items: visible.filter { $0.headingID == h.id }) }
        }
        if list == .upcoming || list == .deadlines || list == .logbook || list == .loggedProjects || list == .trash {
            var groups: [String: [Item]] = [:]
            for item in visible {
                let date: Day?
                if list == .upcoming { date = db.displayDate(item, today: store.today) }
                else if list == .deadlines { date = item.deadline }
                else { date = (item.trashedAt ?? item.statusDate).map { Day($0) } }
                groups[date?.iso ?? "Earlier", default: []].append(item)
            }
            if list == .upcoming && db.preferences.calendarEnabled {
                for event in store.integrations.events where Day(event.startDate) > store.today { groups[Day(event.startDate).iso, default: []] += [] }
            }
            let keys = groups.keys.sorted { list == .upcoming || list == .deadlines ? $0 < $1 : $0 > $1 }
            return keys.map { ItemSection(id: $0, title: Day(iso: $0)?.label() ?? $0, items: groups[$0]!) }
        }
        if list == .anytime || list == .someday {
            var keys: [String] = []; var groups: [String: [Item]] = [:]
            for item in visible {
                let name = db.containerName(for: item) ?? ""
                if groups[name] == nil { keys.append(name) }; groups[name, default: []].append(item)
            }
            return keys.map { ItemSection(id: $0, title: $0.isEmpty ? nil : $0, items: groups[$0]!) }
        }
        return [ItemSection(id: "main", items: visible)]
    }
    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(destination: Binding(get: { destination }, set: navigate), create: create, newArea: { addingArea = true }, manageTags: { managingTags = true })
                    .frame(minWidth: 210, idealWidth: 235, maxWidth: 260)
                Rectangle().fill(Style.hairline).frame(width: 1)
            }
            VStack(spacing: 0) {
                topBar
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            heading
                            filterBar
                            if list == .today { CalendarAgenda(day: store.today).environmentObject(store.integrations).padding(.bottom, 24) }
                            if let project, !project.notes.isEmpty { MarkdownNotes(text: project.notes).foregroundStyle(.secondary).padding(.bottom, 25) }
                            if draft != nil {
                                ItemEditor(item: draft!, onSave: { item in if store.put(item) { draft = nil; selected = [item.id] } }, onCancel: { draft = nil }).padding(.bottom, 12)
                            }
                            ForEach(sections) { section in sectionView(section) }
                            if items.isEmpty && draft == nil { emptyState }
                            Color.clear.frame(height: 60)
                        }.frame(maxWidth: 760).padding(.horizontal, 45).padding(.top, 33).frame(maxWidth: .infinity, alignment: .center)
                    }.onChange(of: expandedID) { _, id in if let id { withAnimation(.easeInOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) } } }
                }
                footer
            }.background(Style.paper)
        }.background(Style.sidebar).frame(minWidth: 870, minHeight: 620)
            .focusedSceneValue(\.curiosActions, actions)
            .background(KeyRouter(onKey: handleKey).frame(width: 0, height: 0))
            .onChange(of: store.database.items.map(\.id)) { _, ids in selected.formIntersection(ids) }
            .onReceive(NotificationCenter.default.publisher(for: .curiosQuickEntry)) { _ in openWindow(id: "quick-entry") }
            .onOpenURL { url in if let target = store.handleURL(url) { navigate(target) } }
            #if CURIOS_DIAGNOSTICS
            .onAppear(perform: configureSnapshotState)
            #endif
            .sheet(isPresented: $finding) { QuickFindView(query: $query, navigate: navigate, chooseItem: revealItem).environmentObject(store) }
            .sheet(item: $sheetItem) { item in
                ItemEditor(item: item, onSave: { value in if store.put(value) { sheetItem = nil; if value.kind == .project { navigate(.project(value.id)) } } }, onCancel: { sheetItem = nil }).frame(width: 610).padding(16)
            }
            .sheet(item: Binding(get: { store.pendingCapture }, set: { value in
                if value == nil, let current = store.pendingCapture { store.cancelCapture(current.id) }
            })) { item in
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add task from a link?").font(.title2.bold())
                    Text("An external app or website requested this task. Review it before adding it to Inbox.").foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.title).font(.headline).textSelection(.enabled)
                            if !item.notes.isEmpty { Text(item.notes).textSelection(.enabled) }
                            if let start = item.start { Text("Scheduled: \(start.iso)\(item.bucket == .evening ? " · Evening" : "")") }
                            else { Text("Placement: \(item.placement.rawValue)") }
                            if let reminder = item.reminder { Text("Reminder: \(reminder.formatted())") }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 280)
                    if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel) { store.cancelCapture(item.id) }.keyboardShortcut(.cancelAction)
                        Button("Add to Inbox") { if let target = store.confirmCapture(item.id) { navigate(target) } }.keyboardShortcut(.defaultAction)
                    }
                }.padding(24).frame(width: 520)
            }
            .sheet(isPresented: $managingTags) { TagManagerView().environmentObject(store) }
            .sheet(item: $editingArea) { area in AreaEditorView(area: area).environmentObject(store) }
            .alert("New Area", isPresented: $addingArea) {
                TextField("Area name", text: $areaTitle)
                Button("Cancel", role: .cancel) { areaTitle = "" }
                Button("Create") { store.addArea(areaTitle); areaTitle = "" }
            } message: { Text("An ongoing responsibility, such as Work or Personal.") }
            .alert("Empty Trash?", isPresented: $confirmEmptyTrash) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) { store.transact("Empty Trash") { $0.emptyTrash() } }
            } message: { Text("Permanently remove the items in Curios's Trash. You can undo this while Curios stays open.") }
            .alert("Curios", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
            .popover(isPresented: $showBatchWhen) { if let first = selected.compactMap({ db.item($0) }).first { BatchWhenHost(item: first, ids: selected, deadline: false).environmentObject(store) } }
            .popover(isPresented: $showBatchDeadline) { if let first = selected.compactMap({ db.item($0) }).first { BatchWhenHost(item: first, ids: selected, deadline: true).environmentObject(store) } }
            .popover(isPresented: $showBatchTags) { BatchTagHost(ids: selected).environmentObject(store) }
    }
    private var topBar: some View {
        HStack {
            Button { withAnimation(.easeInOut(duration: 0.15)) { showSidebar.toggle() } } label: { Image(systemName: "sidebar.left") }.help("Show or hide sidebar (⌘/)")
            Spacer()
            Text(project == nil ? title : (db.area(for: project!)?.title ?? "Projects")).font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            Button { query = ""; finding = true } label: { Image(systemName: "magnifyingglass") }.help("Quick Find (⌘F)")
            Menu {
                Button("New Window") { openWindow(id: "main") }
                Button("Manage Tags…") { managingTags = true }
                Button(db.preferences.showCompleted ? "Hide completed items" : "Show completed items") { store.preferences { $0.showCompleted.toggle() } }
                Divider()
                Button("Encrypted Backup…") { store.exportEncryptedFile() }
                Button("Import Encrypted Backup…") { store.importEncryptedFile() }
                Button("Import Curios / Legacy JSON…") { store.importFile() }
                Button("Export Plaintext JSON…") { store.exportFile() }
                Button("Lock Curios Vault") { store.requestLockVault() }.disabled(!store.isEncrypted)
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 21)
        }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.leading, showSidebar ? 0 : 70).frame(height: 43)
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 11) {
            if list == .today { Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack(spacing: 13) {
                if let project { ProjectProgress(progress: db.progress(project.id), size: 31) }
                else { Image(systemName: list?.symbol ?? (area != nil ? "square.stack.3d.up" : "tag.fill")).font(.system(size: 30, weight: .regular)).foregroundStyle(list?.color ?? Style.blue) }
                Text(title).font(.system(size: 31, weight: .bold)).tracking(-0.6).textSelection(.enabled)
                Spacer()
                if let project {
                    Menu {
                        Button("Edit Project…") { sheetItem = project }
                        if !project.isTemplate { Button(project.status == .open ? "Complete Project" : "Reopen Project") { store.complete([project.id]) } }
                        else { Button("Create Next Copy") { store.transact("Create repeat copy") { $0.createNextCopy(project.id) } } }
                        Button("New Heading") { create(.heading) }
                        Button("Duplicate Project") { if let id = store.duplicate(project.id) { navigate(.project(id)) } }
                        Divider()
                        Button("Move Project to Trash", role: .destructive) { store.trash([project.id]); navigate(.list(.today)) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                } else if let area {
                    Menu { Button("Edit Area…") { editingArea = area }; Button("New Project") { create(.project) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
                }
                if list == .trash && !items.isEmpty { Button("Empty Trash…") { confirmEmptyTrash = true }.controlSize(.small) }
            }
            if let project, project.isTemplate { SmallPill(text: "Repeating template · \(project.recurrence?.summary ?? "")", color: Style.blue) }
            if destination == .search { Text("Results for “\(query)” · Including notes, checklists and logged items").font(.system(size: 12)).foregroundStyle(.secondary) }
        }.padding(.bottom, 24)
    }
    private var filterBar: some View {
        let tags = db.tags.filter { tag in unfilteredItems.contains { db.effectiveTags(for: $0).contains(tag.id) } || filters.contains(tag.id) }
        return Group {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        Button("All") { filters = [] }.foregroundStyle(filters.isEmpty ? Color.primary : .secondary)
                        ForEach(tags) { tag in
                            Button(tag.name) {
                                if NSEvent.modifierFlags.contains(.command) { if filters.contains(tag.id) { filters.remove(tag.id) } else { filters.insert(tag.id) } }
                                else { filters = filters == [tag.id] ? [] : [tag.id] }
                            }.foregroundStyle(filters.contains(tag.id) ? Style.blue : Color.secondary)
                        }
                    }.font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                }.padding(.bottom, 23)
            }
        }
    }
    @ViewBuilder private func sectionView(_ section: ItemSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let text = section.title {
                HStack(spacing: 8) {
                    if let symbol = section.symbol { Image(systemName: symbol).foregroundStyle(.indigo) }
                    Text(text).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if let id = UUID(uuidString: section.id), let heading = db.item(id) {
                        Menu {
                            Button("Rename Heading") { sheetItem = heading }
                            Button("Archive Heading") { store.transact("Archive heading") { $0.setStatus(id, .completed) } }
                            Button("Delete Heading", role: .destructive) { store.trash([id]) }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18)
                    }
                }.padding(.top, section.id == "evening" ? 34 : 20).padding(.bottom, 10)
                Rectangle().fill(Style.hairline).frame(height: 1).padding(.bottom, 10)
                if list == .upcoming, let day = Day(iso: section.id) { CalendarAgenda(day: day).environmentObject(store.integrations).padding(.bottom, 10) }
            }
            ForEach(section.items) { item in
                Group {
                    if expandedID == item.id {
                        ItemEditor(item: item, onSave: { if store.put($0) { expandedID = nil } }, onCancel: { expandedID = nil }).padding(.vertical, 8)
                    } else {
                        TaskRow(item: item, isSelected: selected.contains(item.id), contextIDs: selected.contains(item.id) ? selected : [item.id], showContainer: project == nil,
                            select: { select(item) }, open: { open(item) }, navigate: navigate)
                            .padding(.horizontal, -8)
                    }
                }.id(item.id)
                    .dropDestination(for: String.self) { values, _ in
                        let ids = values.compactMap(\.curiosItemID); for id in ids { store.reorder(id, before: item.id) }; return !ids.isEmpty
                    }
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: list == .logbook ? "checkmark.seal" : (list?.symbol ?? "leaf")).font(.system(size: 39, weight: .ultraLight)).foregroundStyle((list?.color ?? Style.blue).opacity(0.5))
            Text(list == .today ? "A little breathing room." : "Nothing here yet.").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
            Text(list == .trash ? "Deleted items will wait here until you empty the Trash." : "Press ⌘N to add a to-do, or just start typing to find something.").font(.system(size: 12)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 74)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Style.hairline).frame(height: 1)
            HStack(spacing: 15) {
                Button { create(.task) } label: { Label("New To-Do", systemImage: "plus") }.help("New to-do (⌘N)")
                if project != nil { Button { create(.heading) } label: { Image(systemName: "text.badge.plus") }.help("New heading (⇧⌘N)") }
                Spacer()
                Text(store.isEncrypted ? "Encrypted vault" : "Legacy profile · encryption off").font(.system(size: 10)).foregroundStyle(store.isEncrypted ? Color.secondary : Color.orange).help("Configure encryption in Settings → Data. FileVault is complementary protection.")
                Text("\(items.filter { $0.kind == .task && $0.status == .open }.count) to-dos").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                if !selected.isEmpty { Button { store.move(selected, to: .list(.trash)) } label: { Image(systemName: "trash") }.help("Move selected items to Trash") }
                Button { openWindow(id: "quick-entry") } label: { Image(systemName: "square.and.pencil") }.help("Quick Entry (⌃⇧Space)")
            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 28).frame(height: 43)
        }
    }
    private var actions: WindowActions {
        WindowActions(create: create, find: { query = ""; finding = true }, navigate: navigate, selected: selected,
                      duplicate: { if let id = selected.first, let created = store.duplicate(id) { selected = [created] } },
                      showWhen: { showBatchWhen = true }, showDeadline: { showBatchDeadline = true }, showTags: { showBatchTags = true },
                      toggleSidebar: { showSidebar.toggle() }, paste: { store.pasteTasks(in: destination) })
    }
    #if CURIOS_DIAGNOSTICS
    private func configureSnapshotState() {
        guard let flag = CommandLine.arguments.firstIndex(of: "--snapshot-state"), flag + 1 < CommandLine.arguments.count else { return }
        let state = CommandLine.arguments[flag + 1]
        if state == "editor", let item = db.items(in: .today, today: store.today).first(where: { $0.kind == .task }) { selected = [item.id]; expandedID = item.id }
        else if state == "project", let item = db.items.first(where: { $0.kind == .project && $0.isOpen }) { destination = .project(item.id) }
        else if let list = ListID(rawValue: state) { destination = .list(list) }
    }
    #endif
    private func create(_ kind: ItemKind) {
        if kind == .heading && project == nil { store.errorMessage = "Open a project to add a heading."; return }
        expandedID = nil
        let value = store.draft(kind: kind, in: destination)
        if kind == .task { draft = value } else { sheetItem = value }
    }
    private func navigate(_ target: Destination) {
        selected = []; expandedID = nil; draft = nil; filters = []
        destination = target; finding = false
    }
    private func revealItem(_ item: Item) {
        if item.kind == .project { navigate(.project(item.id)); return }
        if let project = item.projectID { navigate(.project(project)) }
        else { destination = .search }
        selected = [item.id]; expandedID = item.id; finding = false
    }
    private func open(_ item: Item) { if item.kind == .project { navigate(.project(item.id)) } else { selected = [item.id]; expandedID = item.id } }
    private func select(_ item: Item) {
        if NSEvent.modifierFlags.contains(.command) { if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) } }
        else if NSEvent.modifierFlags.contains(.shift), let first = selected.first, let a = items.firstIndex(where: { $0.id == first }), let b = items.firstIndex(where: { $0.id == item.id }) { selected.formUnion(items[min(a, b)...max(a, b)].map(\.id)) }
        else { selected = [item.id] }
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.control) {
            guard let key = event.charactersIgnoringModifiers, let tag = db.tag(forShortcut: key) else { return false }
            if event.modifierFlags.contains(.option) { if filters.contains(tag.id) { filters.remove(tag.id) } else { filters.insert(tag.id) } }
            else { store.toggleTag(tag.id, on: selected) }
            return true
        }
        switch event.keyCode {
        case 36: if let item = selected.first.flatMap({ db.item($0) }) { open(item); return true }
        case 51, 117: if !selected.isEmpty { if list == .trash { store.restore(selected) } else { store.trash(selected) }; return true }
        case 49: create(.task); return true
        case 125, 126:
            guard !items.isEmpty else { return false }
            let index = selected.first.flatMap { id in items.firstIndex { $0.id == id } } ?? (event.keyCode == 125 ? -1 : items.count)
            let next = max(0, min(items.count - 1, index + (event.keyCode == 125 ? 1 : -1)))
            if event.modifierFlags.contains(.shift) { selected.insert(items[next].id) } else { selected = [items[next].id] }
            return true
        case 53: filters = []; selected = []; return true
        default:
            if let text = event.characters, text.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }), !text.isEmpty { query = text; finding = true; return true }
        }
        return false
    }
}

private struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openSettings) private var openSettings
    @Binding var destination: Destination
    var create: (ItemKind) -> Void
    var newArea: () -> Void
    var manageTags: () -> Void
    @State private var collapsed: Set<UUID> = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) { Image(systemName: "checkmark.square.fill").foregroundStyle(Style.blue); Text("Curios").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 18).padding(.top, 39).padding(.bottom, 23)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ListID.sidebar, id: \.self) { list in
                        row(title: list.title, icon: list.symbol, color: list.color, destination: .list(list), count: list == .inbox || list == .today ? store.database.items(in: list, today: store.today).count : nil)
                    }
                    Rectangle().fill(Style.hairline).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 18)
                    ForEach(store.database.areas.sorted { $0.position < $1.position }) { area in
                        VStack(spacing: 1) {
                            HStack(spacing: 0) {
                                Button { if collapsed.contains(area.id) { collapsed.remove(area.id) } else { collapsed.insert(area.id) } } label: { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(collapsed.contains(area.id) ? 0 : 90)).foregroundStyle(.tertiary).frame(width: 14) }.buttonStyle(.plain)
                                Button { destination = .area(area.id) } label: { HStack { Text(area.title).font(.system(size: 12, weight: .semibold)); Spacer() }.contentShape(Rectangle()) }.buttonStyle(.plain).padding(.vertical, 8)
                            }.padding(.horizontal, 8).background(destination == .area(area.id) ? Style.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .dropDestination(for: String.self) { values, _ in let ids = values.compactMap(\.curiosItemID); store.move(Set(ids), to: .area(area.id)); return !ids.isEmpty }
                            if !collapsed.contains(area.id) {
                                ForEach(projects.filter { $0.areaID == area.id }) { project in projectRow(project) }
                            }
                        }.padding(.bottom, 12)
                    }
                    ForEach(projects.filter { $0.areaID == nil }) { project in projectRow(project) }
                }.padding(.horizontal, 10)
            }
            HStack {
                Menu {
                    Button("New Project") { create(.project) }
                    Button("New Area…", action: newArea)
                    Divider(); Button("Manage Tags…", action: manageTags)
                } label: { Label("New List", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button { openSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings (⌘,)")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 19).frame(height: 44)
        }.background(Style.sidebar)
    }
    private var projects: [Item] { store.database.items.filter { $0.kind == .project && $0.isOpen }.sorted { $0.position < $1.position } }
    private func projectRow(_ item: Item) -> some View {
        Button { destination = .project(item.id) } label: {
            HStack(spacing: 9) { ProjectProgress(progress: store.database.progress(item.id), size: 14); Text(item.title).font(.system(size: 12)).lineLimit(1); Spacer(minLength: 0); if item.isTemplate { Image(systemName: "repeat").font(.system(size: 9)).foregroundStyle(.tertiary) } }
                .padding(.vertical, 7).padding(.leading, 24).padding(.trailing, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).background(destination == .project(item.id) ? Style.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: String.self) { values, _ in let ids = values.compactMap(\.curiosItemID); store.move(Set(ids), to: .project(item.id)); return !ids.isEmpty }
    }
    private func row(title: String, icon: String, color: Color, destination target: Destination, count: Int?) -> some View {
        Button { destination = target } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color).frame(width: 20)
                Text(title).font(.system(size: 13, weight: destination == target ? .medium : .regular))
                Spacer(minLength: 5)
                if let count, count > 0 { Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 10).frame(height: 31).contentShape(Rectangle())
        }.buttonStyle(.plain).background(destination == target ? Style.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: String.self) { values, _ in let ids = values.compactMap(\.curiosItemID); store.move(Set(ids), to: target); return !ids.isEmpty }
    }
}

private struct TaskRow: View {
    @EnvironmentObject var store: AppStore
    let item: Item
    let isSelected: Bool
    let contextIDs: Set<UUID>
    let showContainer: Bool
    var select: () -> Void
    var open: () -> Void
    var navigate: (Destination) -> Void
    @State private var hovering = false
    @State private var when = false
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            if item.kind == .project { ProjectProgress(progress: store.database.progress(item.id), size: 18) }
            else if item.isTemplate { Image(systemName: "repeat.circle").font(.system(size: 19)).foregroundStyle(Style.blue) }
            else { TaskCheckbox(status: item.status, disabled: store.database.isTemplateChild(item) || item.trashedAt != nil, title: item.title, itemID: item.id) { store.complete([item.id], cancel: NSEvent.modifierFlags.contains(.option)) }.frame(width: 24, height: 24) }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(item.title).font(.system(size: 14, weight: item.kind == .project ? .medium : .regular)).strikethrough(item.status != .open).foregroundStyle(item.status == .open ? Color.primary : Color.secondary).lineLimit(2)
                        if !item.notes.isEmpty { Image(systemName: "doc.text").font(.system(size: 10)).foregroundStyle(.tertiary) }
                        if !item.checklist.isEmpty { Text("\(item.checklist.filter(\.completed).count)/\(item.checklist.count)").font(.system(size: 10)).foregroundStyle(.tertiary) }
                        if item.templateID != nil { Image(systemName: "repeat").font(.system(size: 9)).foregroundStyle(.tertiary) }
                    }
                    if showContainer, let parent = store.database.containerName(for: item) { Text(parent).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1) }
                    if item.isTemplate { Text(item.recurrence?.summary ?? "").font(.system(size: 11)).foregroundStyle(Style.blue) }
                }
                Spacer(minLength: 5)
                if let day = item.deadline {
                    Label(day.label(relativeTo: store.today), systemImage: "flag.fill").font(.system(size: 10)).foregroundStyle(day <= store.today ? .pink : .secondary).lineLimit(1)
                } else if let start = item.start, start > store.today { Text(start.label(relativeTo: store.today)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.contentShape(Rectangle()).onTapGesture(count: 2, perform: open).onTapGesture(perform: select)
                .draggable("curios-item:\(item.id.uuidString)")
            if hovering && !item.isTemplate && item.isOpen {
                Button { when = true } label: { Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(.secondary) }.buttonStyle(.plain).help("When")
                    .popover(isPresented: $when) { WhenHost(item: item) }
            }
        }.padding(.horizontal, 9).padding(.vertical, 10).frame(minHeight: 41).contentShape(Rectangle())
            .background(isSelected ? Style.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain).accessibilityLabel(item.title)
            .contextMenu {
                Button(item.kind == .project ? "Open Project" : "Edit To-Do", action: open)
                if item.trashedAt != nil { Button("Restore") { store.restore(contextIDs) } }
                else {
                    if !item.isTemplate { Button(item.status == .open ? "Complete" : "Reopen") { store.complete(contextIDs) }; Button("Cancel") { store.complete(contextIDs, cancel: true) } }
                    Button("Today") { store.schedule(contextIDs, placement: .scheduled, day: store.today) }
                    Button("This Evening") { store.schedule(contextIDs, placement: .scheduled, day: store.today, bucket: .evening) }
                    Button("Tomorrow") { store.schedule(contextIDs, placement: .scheduled, day: store.today.adding(.day, 1)) }
                    Button("Anytime") { store.schedule(contextIDs, placement: .anytime) }; Button("Someday") { store.schedule(contextIDs, placement: .someday) }
                    Menu("Move to") {
                        Button("Inbox") { store.move(contextIDs, to: .list(.inbox)) }
                        ForEach(store.database.areas) { a in Button(a.title) { store.move(contextIDs, to: .area(a.id)) } }
                        Divider()
                        ForEach(store.database.items.filter { $0.kind == .project && $0.isOpen && $0.id != item.id }) { p in Button(p.title) { store.move(contextIDs, to: .project(p.id)) } }
                    }
                    Button("Duplicate") { _ = store.duplicate(item.id) }
                    if item.isTemplate {
                        Divider(); Button(item.recurrence?.paused == true ? "Resume Repeating" : "Pause Repeating") { store.setRecurrence(item.id, paused: item.recurrence?.paused != true) }
                        Button("Create Next Copy") { store.transact("Create repeat copy") { $0.createNextCopy(item.id) } }
                        Button("Stop Repeating") { store.transact("Stop repetition") { $0.stopRepeating(item.id) } }
                    }
                    if let id = item.templateID { Button("Show Repeating Template") { if let template = store.database.item(id) { navigate(template.kind == .project ? .project(id) : .list(.repeating)) } } }
                    Divider(); Button("Move to Trash", role: .destructive) { store.trash(contextIDs) }
                }
            }
    }
}
private struct WhenHost: View {
    @EnvironmentObject var store: AppStore
    @State var item: Item
    @State private var chosen: ParsedSchedule?
    var body: some View {
        WhenPicker(item: $item, applied: { chosen = $0 })
            .onDisappear { if let chosen { store.editDates([item.id], change: .when(chosen)) } }
    }
}
private struct BatchWhenHost: View {
    @EnvironmentObject var store: AppStore
    @State var item: Item
    let ids: Set<UUID>
    var deadline: Bool
    @State private var change: DateEdit?
    var body: some View {
        Group {
            if deadline { DeadlinePicker(item: $item, applied: { change = .deadline($0) }) }
            else { WhenPicker(item: $item, applied: { change = .when($0) }) }
        }.onDisappear { if let change { store.editDates(ids, change: change) } }
    }
}
private struct BatchTagHost: View {
    @EnvironmentObject var store: AppStore
    var ids: Set<UUID>
    @State private var edit = TagSelectionEdit(items: [])
    var body: some View {
        TagPicker(selected: $edit.selected, mixed: edit.mixed, didChange: { id, selected in edit.set(id, selected: selected) })
            .onAppear { edit = TagSelectionEdit(items: ids.compactMap { store.database.item($0) }) }
            .onDisappear { if !edit.touched.isEmpty { store.editTags(ids, change: edit) } }
    }
}
struct CalendarAgenda: View {
    @EnvironmentObject var integrations: Integrations
    let day: Day
    var body: some View {
        let events = integrations.events.filter { Day($0.startDate) == day }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(events, id: \.eventIdentifier) { event in HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3, height: 14)
                    Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened)).foregroundStyle(Style.blue).frame(width: 65, alignment: .leading)
                    Text(event.title ?? "Calendar event").foregroundStyle(.secondary); Spacer()
                }.font(.system(size: 12)) }
            }.padding(14).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}
extension String { var curiosItemID: UUID? { hasPrefix("curios-item:") ? UUID(uuidString: String(dropFirst(12))) : nil } }

private struct KeyRouter: NSViewRepresentable {
    var onKey: (NSEvent) -> Bool
    final class Coordinator {
        var monitor: Any?
        weak var view: NSView?
        var onKey: (NSEvent) -> Bool
        init(onKey: @escaping (NSEvent) -> Bool) { self.onKey = onKey }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); context.coordinator.view = view
        let c = context.coordinator
        c.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak c] event in
            guard let c, let window = c.view?.window, NSApp.keyWindow === window,
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control),
                  !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField),
                  !(window.firstResponder is NSControl) || (window.firstResponder is NSButton && event.modifierFlags.contains(.control)) else { return event }
            return c.onKey(event) ? nil : event
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onKey = onKey }
}
