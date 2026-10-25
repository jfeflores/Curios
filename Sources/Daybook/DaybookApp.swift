import SwiftUI
import DaybookCore

struct WindowActions {
    var create: (ItemKind) -> Void
    var find: () -> Void
    var navigate: (Destination) -> Void
    var selected: Set<UUID>
    var duplicate: () -> Void
    var showWhen: () -> Void
    var showDeadline: () -> Void
    var showTags: () -> Void
    var toggleSidebar: () -> Void
    var paste: () -> Void
}
private struct WindowActionsKey: FocusedValueKey { typealias Value = WindowActions }
private struct EditorFinishKey: FocusedValueKey { typealias Value = (Bool) -> Void }
extension FocusedValues {
    var daybookActions: WindowActions? { get { self[WindowActionsKey.self] } set { self[WindowActionsKey.self] = newValue } }
    var daybookFinishEditor: ((Bool) -> Void)? { get { self[EditorFinishKey.self] } set { self[EditorFinishKey.self] = newValue } }
}
@main
struct DaybookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("Curios", id: "main") {
            ContentView().environmentObject(store)
                .preferredColorScheme(store.database.preferences.appearance == "dark" ? .dark : (store.database.preferences.appearance == "light" ? .light : nil))
        }.windowStyle(.hiddenTitleBar).defaultSize(width: 1120, height: 790)
            .commands { DaybookCommands(store: store) }
        Window("Quick Entry", id: "quick-entry") {
            QuickEntryView().environmentObject(store)
        }.defaultSize(width: 570, height: 460).windowResizability(.contentSize)
        Settings { SettingsView().environmentObject(store).frame(width: 590, height: 490) }
    }
}
struct DaybookCommands: Commands {
    @ObservedObject var store: AppStore
    @FocusedValue(\.daybookActions) private var actions
    @FocusedValue(\.daybookFinishEditor) private var finishEditor
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New To-Do") { actions?.create(.task) }.keyboardShortcut("n")
            Button("New Project") { actions?.create(.project) }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Heading") { actions?.create(.heading) }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Quick Entry") { openWindow(id: "quick-entry") }.keyboardShortcut(" ", modifiers: [.control, .shift])
            Button("New Window") { openWindow(id: "main") }.keyboardShortcut("n", modifiers: [.command, .control])
        }
        CommandGroup(replacing: .undoRedo) {
            Button(store.undoName.map { "Undo \($0)" } ?? "Undo") { store.undo() }.keyboardShortcut("z").disabled(store.undoName == nil)
            Button(store.redoName.map { "Redo \($0)" } ?? "Redo") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.redoName == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("New To-Dos from Clipboard") { actions?.paste() }.keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Duplicate Item") { actions?.duplicate() }.keyboardShortcut("d").disabled(actions?.selected.isEmpty != false)
        }
        CommandMenu("Items") {
            Button("Complete / Reopen") { if let finishEditor { finishEditor(false) } else { store.complete(actions?.selected ?? []) } }.keyboardShortcut("k").disabled(actions?.selected.isEmpty != false && finishEditor == nil)
            Button("Cancel Item") { if let finishEditor { finishEditor(true) } else { store.complete(actions?.selected ?? [], cancel: true) } }.keyboardShortcut("k", modifiers: [.command, .option]).disabled(actions?.selected.isEmpty != false && finishEditor == nil)
            Divider()
            Button("When…") { actions?.showWhen() }.keyboardShortcut("s").disabled(actions?.selected.isEmpty != false)
            Button("Today") { store.schedule(actions?.selected ?? [], placement: .scheduled, day: store.today) }.keyboardShortcut("t")
            Button("This Evening") { store.schedule(actions?.selected ?? [], placement: .scheduled, day: store.today, bucket: .evening) }.keyboardShortcut("e")
            Button("Anytime") { store.schedule(actions?.selected ?? [], placement: .anytime) }.keyboardShortcut("r")
            Button("Someday") { store.schedule(actions?.selected ?? [], placement: .someday) }.keyboardShortcut("o")
            Button("Deadline…") { actions?.showDeadline() }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Tags…") { actions?.showTags() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Move to Trash") { store.trash(actions?.selected ?? []) }.disabled(actions?.selected.isEmpty != false)
        }
        CommandMenu("Navigate") {
            ForEach(Array(ListID.sidebar.prefix(6).enumerated()), id: \.element) { index, list in
                Button(list.title) { actions?.navigate(.list(list)) }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
            ForEach([ListID.tomorrow, .deadlines, .repeating, .projects, .loggedProjects], id: \.self) { list in
                Button(list.title) { actions?.navigate(.list(list)) }
            }
            Divider()
            Button("Quick Find") { actions?.find() }.keyboardShortcut("f")
            Button("Show / Hide Sidebar") { actions?.toggleSidebar() }.keyboardShortcut("/")
        }
        CommandGroup(after: .importExport) {
            Button("Import Curios / Daybook JSON…") { store.importFile() }
            Button("Export Curios JSON…") { store.exportFile() }
        }
    }
}
