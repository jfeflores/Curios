import SwiftUI
import AppKit
import CuriosCore

struct QuickEntryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var draft: Item?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "square.and.pencil").foregroundStyle(Style.blue); Text("Quick Entry").font(.headline); Spacer(); Text("Inbox").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 8)
            if let draft { ItemEditor(item: draft, onSave: { value in store.put(value); if store.database.item(value.id) != nil { self.draft = nil; dismissWindow(id: "quick-entry") } }, onCancel: { self.draft = nil; dismissWindow(id: "quick-entry") }) }
        }.padding(20).frame(width: 590).onAppear { draft = store.draft(in: .list(.inbox)) }
    }
}
private struct FindTarget: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var symbol: String
    var color: Color
    var destination: Destination
}
struct QuickFindView: View {
    @EnvironmentObject var store: AppStore
    @Binding var query: String
    var navigate: (Destination) -> Void
    var chooseItem: (Item) -> Void
    @FocusState private var focused: Bool
    private var targets: [FindTarget] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let match: (String) -> Bool = { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }
        var values = ListID.allCases.filter { match($0.title) }.map { FindTarget(id: "list-\($0.rawValue)", title: $0.title, subtitle: "List", symbol: $0.symbol, color: $0.color, destination: .list($0)) }
        values += store.database.areas.filter { match($0.title) }.map { FindTarget(id: $0.id.uuidString, title: $0.title, subtitle: "Area", symbol: "square.stack.3d.up", color: .secondary, destination: .area($0.id)) }
        values += store.database.tags.filter { match($0.name) }.map { FindTarget(id: $0.id.uuidString, title: $0.name, subtitle: "Tag · includes inherited tags", symbol: "tag", color: .secondary, destination: .tag($0.id)) }
        values += store.database.items.filter { $0.kind == .project && $0.isOpen && match($0.title) }.map { FindTarget(id: $0.id.uuidString, title: $0.title, subtitle: "Project", symbol: "circle.dotted", color: Style.blue, destination: .project($0.id)) }
        return Array(values.prefix(14))
    }
    private var matches: [Item] { Array(store.database.search(query, full: false).filter { $0.kind != .project }.prefix(12)) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
                TextField("Find a list, project, tag or to-do", text: $query).textFieldStyle(.plain).font(.system(size: 20)).focused($focused).onSubmit(openFirst).accessibilityLabel("Quick Find search")
                Text("esc").font(.system(size: 10)).foregroundStyle(.tertiary).padding(4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !targets.isEmpty { caption("GO TO") }
                    ForEach(targets) { target in
                        Button { navigate(target.destination) } label: {
                            HStack(spacing: 12) { Image(systemName: target.symbol).foregroundStyle(target.color).frame(width: 22); Text(target.title); Spacer(); Text(target.subtitle).font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if !matches.isEmpty { caption("TO-DOS") }
                    ForEach(matches) { item in
                        Button { chooseItem(item) } label: { HStack(spacing: 12) { Image(systemName: item.kind == .heading ? "text.alignleft" : "square").foregroundStyle(.tertiary).frame(width: 22); Text(item.title).lineLimit(1); Spacer(); Text(store.database.containerName(for: item) ?? "").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1) }.padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle()) }.buttonStyle(.plain)
                    }
                    if targets.isEmpty && matches.isEmpty { Text("No title matches. Continue Search to look in notes, checklists, and the Logbook.").font(.system(size: 12)).foregroundStyle(.secondary).padding(20) }
                }.font(.system(size: 13)).padding(12)
            }.frame(maxHeight: 390)
            Divider()
            HStack { Text("Type to travel. Return to open the first result.").font(.system(size: 10)).foregroundStyle(.tertiary); Spacer(); Button("Continue Search") { navigate(.search) }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty) }.padding(16)
        }.frame(width: 600).onAppear { focused = true }
    }
    func caption(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.top, 15).padding(.bottom, 6) }
    func openFirst() { if let target = targets.first { navigate(target.destination) } else if let item = matches.first { chooseItem(item) } else { navigate(.search) } }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        TabView {
            Form {
                Section("Make yourself at home") {
                    Picker("Appearance", selection: Binding(get: { store.database.preferences.appearance }, set: { value in store.preferences { $0.appearance = value } })) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    Toggle("Show completed to-dos inside projects", isOn: Binding(get: { store.database.preferences.showCompleted }, set: { value in store.preferences { $0.showCompleted = value } }))
                    Toggle("Keep today's finished items visible", isOn: Binding(get: { store.database.preferences.keepFinishedInToday == true }, set: { value in store.preferences { $0.keepFinishedInToday = value } }))
                    Text("Finished items still enter the Logbook immediately. This option keeps their checkmarks visible in Today until the day ends.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Reminders") {
                    Toggle("Allow Curios notifications", isOn: Binding(get: { store.database.preferences.notifications }, set: { value in
                        if value { let token = store.sessionGeneration; Task { if await store.integrations.requestNotifications(), store.sessionGeneration == token, store.canReadContent { store.preferences { $0.notifications = true } } } }
                        else { store.preferences { $0.notifications = false } }
                    }))
                    Text("Permissions are requested only when enabled. Notifications use generic text, never task titles or notes. Curios does not access Things data or Things Cloud.").font(.caption).foregroundStyle(.secondary)
                }
                if let message = store.integrations.message { Text(message).font(.caption).foregroundStyle(.red) }
                Section("About") { Text("Curios \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development") · An independent, local-first task manager.").font(.caption); Text("Open-source Swift todo app. Originated as a Ghidra/Things reverse-engineering skills project; evolving independently. Not affiliated with Cultured Code.").font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            CalendarSettingsView(integrations: store.integrations).environmentObject(store).tabItem { Label("Calendar", systemImage: "calendar") }
            Form {
                Section("Local data") {
                    Text(store.persistence.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text(store.isEncrypted ? "AES-256-GCM task vault, encrypted managed backups/recovery and private atomic writes. Keep independent encrypted backups and your recovery key separately." : "This legacy profile is still unencrypted. Enable the vault to encrypt its primary, backups and known recovery copies. Older binaries must be closed first.").font(.caption).foregroundStyle(.secondary)
                    if store.isEncrypted { Button("Lock Curios Vault") { store.requestLockVault() } }
                    else { Button("Enable Encrypted Vault…") { store.showingEnrollment = true } }
                    HStack { Button("Open Data Folder") { NSWorkspace.shared.open(store.persistence.url.deletingLastPathComponent()) }; Button("Restore Backup…") { restoreBackupConfirmation() } }
                }
                Section("Portable copies") {
                    HStack { Button("Encrypted Backup…") { store.exportEncryptedFile() }; Button("Import Encrypted Backup…") { store.importEncryptedFile() } }
                    HStack { Button("Import JSON…") { store.importFile() }; Button("Export Plaintext JSON…") { store.exportFile() } }
                    Text("Encrypted portable backups use a separate export passphrase. Imports merge by ID and keep current preferences. Plaintext JSON is an explicit interoperability option, not encrypted. No proprietary Things database is accessed.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Complementary system protection") { FileVaultGuidanceView() }
                Section("Cloud") { Text("This build is local-only. Cloud sync, mail capture, collaboration, and mobile clients are not implemented.").font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped).tabItem { Label("Data", systemImage: "externaldrive") }
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("A little less clicking.").font(.title2.bold()).padding(.bottom, 8)
                    shortcut("New to-do", "⌘ N"); shortcut("New project / heading", "⌥⌘ N / ⇧⌘ N")
                    shortcut("Complete / cancel selected", "⌘ K / ⌥⌘ K"); shortcut("Quick Find", "⌘ F or just type")
                    shortcut("Inbox through Logbook", "⌘ 1 … ⌘ 6"); shortcut("Today / This Evening", "⌘ T / ⌘ E")
                    shortcut("Anytime / Someday", "⌘ R / ⌘ O"); shortcut("When / Deadline / Tags", "⌘ S / ⇧⌘ D / ⇧⌘ T")
                    shortcut("Save editing / cancel", "⌘ Return / Esc"); shortcut("Quick Entry (system-wide)", "⌃⇧ Space")
                    shortcut("Paste multiple new to-dos", "⇧⌘ V"); shortcut("Hide sidebar", "⌘ /")
                    shortcut("Multiple selection", "⌘ click / ⇧ click"); shortcut("Filter by multiple tags", "⌘ click tags")
                    Text("The global shortcut is registered only while Curios is running. It avoids macOS's Control-Space input-source shortcut.").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                }.padding(28)
            }.tabItem { Label("Keyboard", systemImage: "keyboard") }
        }.sheet(isPresented: $store.showingEnrollment) {
            ScrollView { VaultEnrollmentView().padding(28) }.environmentObject(store).frame(width: 600, height: 620)
        }
    }
    func shortcut(_ title: String, _ key: String) -> some View { HStack { Text(title); Spacer(); Text(key).foregroundStyle(.secondary).font(.system(size: 12, design: .monospaced)) }.font(.system(size: 12)) }
    func restoreBackupConfirmation() {
        let alert = NSAlert(); alert.messageText = "Restore Curios's backup?"; alert.informativeText = "The current file will be preserved under a unique recovery filename. The backup must validate before anything changes."; alert.addButton(withTitle: "Restore Backup"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.restoreBackup() }
    }
}
private struct CalendarSettingsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var integrations: Integrations
    var body: some View {
        Form {
            Section("Read-only calendar integration") {
                Text("Display events next to your to-dos in Today and Upcoming. Curios never creates or changes calendar events.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show calendar events", isOn: Binding(get: { store.database.preferences.calendarEnabled }, set: { enabled in
                    if enabled { let token = store.sessionGeneration; Task { if await integrations.requestCalendar(), store.sessionGeneration == token, store.canReadContent { store.preferences { $0.calendarEnabled = true }; integrations.invalidateCalendar(); integrations.refreshCalendar(store.database.preferences) } } }
                    else { store.preferences { $0.calendarEnabled = false }; integrations.refreshCalendar(store.database.preferences) }
                }))
                if store.database.preferences.calendarEnabled {
                    Text("Select calendars (none selected means all)").font(.caption).foregroundStyle(.secondary)
                    ForEach(integrations.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title, isOn: Binding(get: { store.database.preferences.calendarIDs.contains(calendar.calendarIdentifier) }, set: { selected in
                            store.preferences { if selected { $0.calendarIDs.insert(calendar.calendarIdentifier) } else { $0.calendarIDs.remove(calendar.calendarIdentifier) } }
                            integrations.invalidateCalendar(); integrations.refreshCalendar(store.database.preferences)
                        })).toggleStyle(.checkbox)
                    }
                }
                if let message = integrations.message { Text(message).font(.caption).foregroundStyle(.red) }
            }
        }.formStyle(.grouped).onAppear { integrations.refreshCalendar(store.database.preferences) }
    }
}
struct TagManagerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var name = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Tags").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Divider()
            HStack(spacing: 0) {
                VStack {
                    List(selection: $selected) { ForEach(store.database.tags) { tag in Text((tag.parentID == nil ? "" : "    ") + tag.name).tag(tag.id) } }
                    HStack { TextField("New tag", text: $name).textFieldStyle(.roundedBorder).onSubmit(add); Button { add() } label: { Image(systemName: "plus") }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }.padding(12)
                }.frame(width: 210)
                Divider()
                if let tag = store.database.tag(selected) { TagDetailView(tag: tag).environmentObject(store).id(tag.id) }
                else { Text("Create a tag, or select one to rename it,\nchange its parent, or remove it.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }.frame(width: 640, height: 430)
    }
    func add() { let text = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; let tag = Tag(text); store.putTag(tag); selected = tag.id; name = "" }
}
private struct TagDetailView: View {
    @EnvironmentObject var store: AppStore
    @State var tag: Tag
    @State private var error: String?
    var body: some View {
        Form {
            TextField("Name", text: $tag.name)
            Picker("Parent", selection: $tag.parentID) { Text("No parent").tag(Optional<UUID>.none); ForEach(store.database.tags.filter { $0.id != tag.id }) { value in Text(value.name).tag(Optional(value.id)) } }
            HStack { Text("Keyboard shortcut"); TextField("a–z / 0–9", text: $tag.shortcut).frame(width: 85).onChange(of: tag.shortcut) { _, value in tag.shortcut = String(value.lowercased().prefix(1)) } }
            Text("Control + key toggles this tag on selected items. Control + Option + key toggles its list filter. Shortcuts are unique and do not intercept text editing.").font(.caption).foregroundStyle(.secondary)
            Text("Tasks inherit ancestor tags. Selecting several tags in a filter uses AND, not OR.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Button("Delete Tag", role: .destructive) { store.deleteTag(tag.id) }; Spacer(); Button("Save", action: save).buttonStyle(.borderedProminent).disabled(tag.name.trimmingCharacters(in: .whitespaces).isEmpty) }
            Text("Deleting a tag never deletes its tasks.").font(.caption).foregroundStyle(.tertiary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func save() {
        tag.name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        tag.shortcut = tag.shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidate = store.database
        if let i = candidate.tags.firstIndex(where: { $0.id == tag.id }) { candidate.tags[i] = tag }
        do {
            _ = try candidate.validated(); store.putTag(tag)
            error = store.database.tag(tag.id) == tag ? nil : store.errorMessage
        } catch { self.error = error.localizedDescription }
    }
}
struct AreaEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var area: Area
    @State private var showTags = false
    @State private var removing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Edit Area").font(.title2.bold())
            TextField("Area name", text: $area.title).textFieldStyle(.roundedBorder)
            HStack { Button("Tags…") { showTags = true }.popover(isPresented: $showTags) { TagPicker(selected: $area.tagIDs) }; ForEach(store.database.tags.filter { area.tagIDs.contains($0.id) }) { tag in SmallPill(text: tag.name) } }
            HStack { Button("Remove Area…", role: .destructive) { removing = true }; Spacer(); Button("Cancel") { dismiss() }; Button("Save") { area.title = area.title.trimmingCharacters(in: .whitespacesAndNewlines); store.putArea(area); dismiss() }.buttonStyle(.borderedProminent).disabled(area.title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(28).frame(width: 500).alert("Remove this area?", isPresented: $removing) { Button("Cancel", role: .cancel) {}; Button("Remove", role: .destructive) { store.deleteArea(area.id); dismiss() } } message: { Text("Projects and to-dos are preserved. Only their area assignment is removed.") }
    }
}
