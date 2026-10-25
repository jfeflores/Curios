import SwiftUI
import CuriosCore

struct ItemEditor: View {
    @EnvironmentObject private var store: AppStore
    @State private var value: Item
    @State private var checklistText = ""
    @State private var preview = false
    @State private var showWhen = false
    @State private var showDeadline = false
    @State private var showTags = false
    @State private var showRepeat = false
    @State private var finished = false
    @State private var existedAtOpen = false
    @State private var openedSession: UUID?
    private let original: Item
    @FocusState private var titleFocused: Bool
    let onSave: (Item) -> Void
    let onCancel: () -> Void
    init(item: Item, onSave: @escaping (Item) -> Void, onCancel: @escaping () -> Void) {
        original = item; _value = State(initialValue: item); self.onSave = onSave; self.onCancel = onCancel
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                if value.kind == .task && !value.isTemplate {
                    TaskCheckbox(status: store.database.item(value.id)?.status ?? value.status,
                                 disabled: value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.readOnly || value.trashedAt != nil || store.database.isTemplateChild(value),
                                 title: value.title, itemID: value.id,
                                 disabledReason: value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add a title before completing this task." : nil,
                                 action: { finishByCheckbox(cancel: NSEvent.modifierFlags.contains(.option)) }).frame(width: 24, height: 24)
                } else {
                    Image(systemName: value.isTemplate ? "repeat.circle" : (value.kind == .project ? "circle.dotted" : "text.alignleft"))
                        .font(.system(size: 20)).foregroundStyle(.secondary).padding(.top, 3)
                }
                TextField(value.kind == .project ? "New Project" : (value.kind == .heading ? "New Heading" : "New To-Do"), text: $value.title, axis: .vertical)
                    .font(.system(size: value.kind == .project ? 23 : 17, weight: .medium)).textFieldStyle(.plain)
                    .focused($titleFocused).accessibilityLabel(value.kind == .project ? "Project title" : "Task title")
            }
            if value.kind != .heading {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("NOTES").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.tertiary)
                        Spacer()
                        Button(preview ? "Edit" : "Preview Markdown") { preview.toggle() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if preview { MarkdownNotes(text: value.notes).frame(minHeight: 55) }
                    else { TextEditor(text: $value.notes).font(.system(size: 13)).scrollContentBackground(.hidden).frame(minHeight: 65, maxHeight: 130).accessibilityLabel("Notes") }
                }.padding(.leading, 32)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach($value.checklist) { $entry in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $entry.completed).labelsHidden().toggleStyle(.checkbox)
                                .disabled(value.isTemplate || store.database.isTemplateChild(value)).accessibilityLabel("Complete checklist item \(entry.title)")
                            TextField("Checklist item", text: $entry.title).textFieldStyle(.plain).font(.system(size: 13)).strikethrough(entry.completed)
                            Button { value.checklist.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("Remove checklist item")
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(.tertiary)
                        TextField("Add a checklist item…", text: $checklistText).textFieldStyle(.plain).font(.system(size: 12))
                            .onSubmit(addChecklist).accessibilityLabel("Add checklist item")
                        if !checklistText.isEmpty { Button("Add", action: addChecklist).controlSize(.small) }
                    }
                }.padding(.leading, 33)
                HStack(spacing: 8) {
                    ForEach(store.database.tags.filter { value.tagIDs.contains($0.id) }) { tag in SmallPill(text: tag.name) }
                    Spacer(minLength: 0)
                }.padding(.leading, 32)
                Divider().padding(.leading, 32)
                HStack(spacing: 14) {
                    Button { showWhen.toggle() } label: { Label(whenLabel, systemImage: "calendar") }
                        .foregroundStyle(value.start == nil ? Color.secondary : Style.blue)
                        .popover(isPresented: $showWhen) { WhenPicker(item: $value) }
                    Button { showDeadline.toggle() } label: { Label(value.deadline?.label() ?? "Deadline", systemImage: "flag") }
                        .foregroundStyle(value.deadline == nil ? Color.secondary : Color.pink)
                        .popover(isPresented: $showDeadline) { DeadlinePicker(item: $value) }
                    Button { showTags.toggle() } label: { Image(systemName: "tag") }.help("Tags")
                        .popover(isPresented: $showTags) { TagPicker(selected: $value.tagIDs) }
                    Button { showRepeat.toggle() } label: { Image(systemName: "repeat") }.help("Repeat")
                        .disabled(value.templateID != nil || store.database.isTemplateChild(value))
                        .popover(isPresented: $showRepeat) { RepeatPicker(rule: $value.recurrence) }
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).buttonStyle(.plain).padding(.leading, 32)
                if let rule = value.recurrence { Label(rule.summary, systemImage: "repeat").font(.system(size: 11)).foregroundStyle(Style.blue).padding(.leading, 32) }
                HStack {
                    Toggle("Remind me", isOn: Binding(get: { value.reminder != nil }, set: { enabled in
                        value.reminder = enabled ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: (value.start ?? Day()).date()) : nil
                    })).toggleStyle(.checkbox)
                    if value.reminder != nil {
                        DatePicker("Reminder", selection: Binding(get: { value.reminder ?? Date() }, set: { value.reminder = $0 }), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    }
                    Spacer()
                }.font(.system(size: 11)).padding(.leading, 32)
                if value.reminder != nil && !store.database.preferences.notifications { Text("Notifications are off. Enable them in Settings to receive this reminder.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 32) }
                if value.kind == .task {
                    HStack {
                        Menu {
                            Button("No project or area") { value.projectID = nil; value.areaID = nil; value.headingID = nil }
                            ForEach(store.database.areas) { area in Button(area.title) { value.areaID = area.id; value.projectID = nil; value.headingID = nil; if value.placement == .inbox { value.placement = .anytime } } }
                            Divider()
                            ForEach(store.database.items.filter { $0.kind == .project && $0.isOpen && (!value.isTemplate || !$0.isTemplate) }) { project in
                                Button(project.title) { value.projectID = project.id; value.areaID = nil; value.headingID = nil; if value.placement == .inbox { value.placement = .anytime } }
                            }
                        } label: { Label(store.database.item(value.projectID)?.title ?? store.database.area(value.areaID)?.title ?? "Move to a list…", systemImage: "folder") }
                        .menuStyle(.borderlessButton).fixedSize()
                        if let project = value.projectID {
                            Picker("Heading", selection: $value.headingID) {
                                Text("No heading").tag(Optional<UUID>.none)
                                ForEach(store.database.items.filter { $0.kind == .heading && $0.projectID == project && $0.isOpen }) { heading in Text(heading.title).tag(Optional(heading.id)) }
                            }.labelsHidden().frame(maxWidth: 180)
                        }
                        Spacer()
                    }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 30)
                } else if value.kind == .project {
                    Picker("Area", selection: $value.areaID) {
                        Text("No area").tag(Optional<UUID>.none)
                        ForEach(store.database.areas) { area in Text(area.title).tag(Optional(area.id)) }
                    }.font(.system(size: 11)).padding(.leading, 32)
                }
            }
            HStack {
                Text("⌘↩ to save").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { finished = true; onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
                    .disabled(value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.controlSize(.small).padding(.leading, 32)
        }.padding(22).background(Style.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Style.hairline))
            .shadow(color: .black.opacity(0.07), radius: 16, y: 5)
            .focusedValue(\.curiosFinishEditor, { cancel in finishByCheckbox(cancel: cancel) })
            .onAppear { openedSession = store.sessionGeneration; existedAtOpen = store.database.item(original.id) != nil; titleFocused = true }
            .onDisappear { if openedSession == store.sessionGeneration, store.canReadContent, !finished, existedAtOpen, !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.commitEdit(value, original: original, allowCreate: false) } }
    }
    var whenLabel: String {
        if value.placement == .someday { return "Someday" }
        if value.bucket == .evening && value.start == Day() { return "This Evening" }
        return value.start?.label() ?? "When"
    }
    func addChecklist() {
        let lines = checklistText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        value.checklist += lines.map { ChecklistEntry($0) }; checklistText = ""
    }
    func save() {
        guard openedSession == store.sessionGeneration, store.canReadContent else { return }
        addChecklist()
        guard let saved = store.commitEdit(value, original: original, allowCreate: !existedAtOpen) else { return }
        finished = true; onSave(saved)
    }
    func finishByCheckbox(cancel: Bool) {
        guard openedSession == store.sessionGeneration, store.canReadContent else { return }
        addChecklist()
        guard let saved = store.commitEdit(value, original: original, allowCreate: !existedAtOpen) else { return }
        store.complete([saved.id], cancel: cancel)
        guard let updated = store.database.item(saved.id) else { return }
        value = updated; finished = true; onSave(updated)
    }
}

struct WhenPicker: View {
    @Binding var item: Item
    var applied: ((ParsedSchedule) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date()
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When").font(.headline)
            TextField("Tomorrow, Friday, in 3 days…", text: $text).textFieldStyle(.roundedBorder).onSubmit(applyText)
            if invalid { Text("Try a day, YYYY-MM-DD, or ‘tomorrow at 8pm’.").font(.caption).foregroundStyle(.red) }
            quick("Today", symbol: "star.fill", color: .yellow, schedule: .date(Day(), reminder: nil))
            quick("This Evening", symbol: "moon.fill", color: .indigo, schedule: .evening(Day()))
            quick("Tomorrow", symbol: "sunrise", color: .orange, schedule: .date(Day().adding(.day, 1), reminder: nil))
            Divider()
            DatePicker("Start date", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            HStack {
                Button("Anytime") { apply(.anytime) }
                Button("Someday") { apply(.someday) }
                Spacer()
                Button("Schedule") { if text.isEmpty { apply(.date(Day(date), reminder: nil)) } else { applyText() } }.buttonStyle(.borderedProminent)
            }.controlSize(.small)
        }.padding(18).frame(width: 310).onAppear { date = (item.start ?? Day()).date() }
    }
    func quick(_ title: String, symbol: String, color: Color, schedule: ParsedSchedule) -> some View {
        Button { apply(schedule) } label: { HStack { Image(systemName: symbol).foregroundStyle(color).frame(width: 20); Text(title); Spacer() }.padding(.vertical, 3).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
    func apply(_ schedule: ParsedSchedule) { AppStore.apply(schedule, to: &item); applied?(schedule); dismiss() }
    func applyText() { if let parsed = DateParser.parse(text) { apply(parsed) } else { invalid = true } }
}
struct DeadlinePicker: View {
    @Binding var item: Item
    var applied: ((Day?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var text = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Deadline", systemImage: "flag.fill").font(.headline).foregroundStyle(.pink)
            Text("The day this needs to be finished. Your start date stays separate.").font(.caption).foregroundStyle(.secondary)
            TextField("Tomorrow, in 2 weeks, YYYY-MM-DD…", text: $text).textFieldStyle(.roundedBorder).onSubmit(setDeadline)
            if invalid { Text("Enter a valid date.").font(.caption).foregroundStyle(.red) }
            DatePicker("Deadline", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
            HStack { Button("Clear") { item.deadline = nil; applied?(nil); dismiss() }; Spacer(); Button("Set Deadline", action: setDeadline).buttonStyle(.borderedProminent) }
        }.padding(18).frame(width: 310).onAppear { date = (item.deadline ?? Day()).date() }
    }
    func setDeadline() {
        if text.isEmpty { item.deadline = Day(date); applied?(item.deadline); dismiss() }
        else if case .date(let day, _) = DateParser.parse(text) { item.deadline = day; applied?(day); dismiss() }
        else { invalid = true }
    }
}
struct TagPicker: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selected: Set<UUID>
    var mixed: Set<UUID> = []
    var didChange: ((UUID, Bool) -> Void)? = nil
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tags", systemImage: "tag").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.database.tags) { tag in
                        HStack {
                            Toggle(tag.name, isOn: Binding(get: { selected.contains(tag.id) }, set: { value in
                                if value { selected.insert(tag.id) } else { selected.remove(tag.id) }
                                didChange?(tag.id, value)
                            })).toggleStyle(.checkbox)
                            if mixed.contains(tag.id) { Text("Some").font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.leading, tag.parentID == nil ? 0 : 12)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 230)
            Divider()
            HStack { TextField("New tag", text: $name).textFieldStyle(.roundedBorder).onSubmit(add); Button("Add", action: add).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(18).frame(width: 260)
    }
    func add() { let text = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; let tag = Tag(text); store.putTag(tag); if store.database.tag(tag.id) != nil { selected.insert(tag.id); didChange?(tag.id, true) }; name = "" }
}
struct RepeatPicker: View {
    @Binding var rule: RepeatRule?
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RepeatRule()
    @State private var useEnd = false
    @State private var end = Date()
    @State private var anchor = Date()
    @State private var ordinalEnabled = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Repeat", systemImage: "repeat").font(.headline)
            Picker("Pattern", selection: $draft.mode) { Text("Regular schedule").tag(RepeatMode.regular); Text("After completion").tag(RepeatMode.afterCompletion) }
            HStack { Text("Every"); Stepper(value: $draft.interval, in: 1...999) { Text("\(draft.interval)").monospacedDigit().frame(width: 35) }; Picker("Unit", selection: $draft.unit) { ForEach(RepeatUnit.allCases, id: \.self) { Text($0.rawValue + (draft.interval == 1 ? "" : "s")).tag($0) } }.labelsHidden() }
            DatePicker("First occurrence", selection: $anchor, displayedComponents: .date)
            if draft.mode == .regular && draft.unit == .week {
                HStack(spacing: 6) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        let names = ["", "S", "M", "T", "W", "T", "F", "S"]
                        Button { if draft.weekdays.contains(day) { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) } } label: {
                            Text(names[day]).font(.system(size: 12, weight: .medium)).frame(width: 30, height: 29).background(draft.weekdays.contains(day) ? Style.blue : Color.secondary.opacity(0.1), in: Circle()).foregroundStyle(draft.weekdays.contains(day) ? .white : .primary)
                        }.buttonStyle(.plain).help(Calendar.current.weekdaySymbols[day - 1])
                    }
                }
            }
            if draft.mode == .regular && (draft.unit == .month || draft.unit == .year) {
                Toggle("On a particular weekday", isOn: $ordinalEnabled).toggleStyle(.checkbox)
                if ordinalEnabled {
                    HStack {
                        Picker("Occurrence", selection: Binding(get: { draft.ordinal ?? 1 }, set: { draft.ordinal = $0 })) { ForEach([1, 2, 3, 4, -1], id: \.self) { n in Text(n == -1 ? "Last" : ["", "First", "Second", "Third", "Fourth"][n]).tag(n) } }.labelsHidden()
                        Picker("Weekday", selection: $draft.ordinalWeekday) { ForEach(1...7, id: \.self) { n in Text(Calendar.current.weekdaySymbols[n - 1]).tag(n) } }.labelsHidden()
                    }
                }
            }
            if draft.mode == .regular {
                Toggle("End repeating", isOn: $useEnd).toggleStyle(.checkbox)
                if useEnd { DatePicker("End date", selection: $end, displayedComponents: .date) }
            }
            Toggle("Add a deadline to each copy", isOn: $draft.addDeadline).toggleStyle(.checkbox)
            if draft.addDeadline { Stepper(value: $draft.leadDays, in: 0...365) { Text("Show \(draft.leadDays) days before the deadline") } }
            Text(draft.mode == .regular ? "A new copy appears on schedule, even when an earlier copy is unfinished." : "The next copy is scheduled from the day you actually complete the previous copy.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Stop Repeating") { rule = nil; dismiss() }.disabled(rule == nil)
                Spacer()
                Button("Save Rule") {
                    draft.anchor = Day(anchor); draft.end = useEnd ? Day(end) : nil
                    if !ordinalEnabled { draft.ordinal = nil }
                    do { try draft.validate(); rule = draft; dismiss() } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }.controlSize(.small)
        }.font(.system(size: 12)).padding(20).frame(width: 380)
            .onAppear { draft = rule ?? RepeatRule(); anchor = draft.anchor.date(); useEnd = draft.end != nil; end = draft.end?.date() ?? Date(); ordinalEnabled = draft.ordinal != nil }
    }
}
