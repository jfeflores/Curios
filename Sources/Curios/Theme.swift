import SwiftUI
import CuriosCore

extension ListID {
    var symbol: String {
        switch self {
        case .inbox: return "tray.fill"
        case .today: return "star.fill"
        case .upcoming, .tomorrow: return "calendar"
        case .anytime: return "square.stack.3d.up.fill"
        case .someday: return "archivebox.fill"
        case .logbook, .loggedProjects: return "checkmark.square.fill"
        case .trash: return "trash"
        case .deadlines: return "flag.fill"
        case .repeating: return "repeat"
        case .projects: return "circle.dotted.circle"
        }
    }
    var color: Color {
        switch self {
        case .inbox: return Color(red: 0.23, green: 0.56, blue: 0.90)
        case .today: return Color(red: 0.99, green: 0.72, blue: 0.08)
        case .upcoming, .tomorrow: return Color(red: 0.91, green: 0.31, blue: 0.37)
        case .anytime: return Color(red: 0.23, green: 0.67, blue: 0.64)
        case .someday: return Color(red: 0.76, green: 0.58, blue: 0.36)
        case .logbook, .loggedProjects: return Color(red: 0.35, green: 0.68, blue: 0.42)
        case .trash: return .secondary
        case .deadlines: return .pink
        case .repeating: return .blue
        case .projects: return .blue
        }
    }
}
enum Style {
    static let blue = Color(red: 0.22, green: 0.51, blue: 0.89)
    static let selection = Color.accentColor.opacity(0.11)
    static let paper = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let hairline = Color.primary.opacity(0.08)
}
struct ProjectProgress: View {
    var progress: Double
    var size: CGFloat = 18
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.45), lineWidth: 1.5)
            if progress > 0 { Circle().trim(from: 0, to: progress).stroke(Style.blue, style: StrokeStyle(lineWidth: size * 0.34, lineCap: .butt)).rotationEffect(.degrees(-90)).padding(size * 0.2) }
        }.frame(width: size, height: size).accessibilityLabel("Project \(Int(progress * 100)) percent complete")
    }
}
/// A real AppKit checkbox owns its mouse tracking and accessibility action. It is
/// deliberately outside the row's selection and drag gestures.
struct TaskCheckbox: NSViewRepresentable {
    let status: ItemStatus
    var disabled = false
    let title: String
    var itemID: UUID? = nil
    var disabledReason: String? = nil
    let action: () -> Void
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func pressed(_ sender: NSButton) { action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        button.allowsMixedState = true
        button.controlSize = .regular
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? { CGSize(width: 24, height: 24) }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.state = status == .open ? .off : (status == .canceled ? .mixed : .on)
        button.isEnabled = !disabled
        button.setAccessibilityLabel("\(status == .open ? "Complete" : "Reopen") \(title)")
        button.setAccessibilityIdentifier("task-completion-\(itemID?.uuidString ?? title)")
        button.toolTip = disabled ? (disabledReason ?? "Restore trashed items first; complete a generated copy rather than a template.") : "Complete (⌘K); Option-click to cancel"
    }
}
struct SmallPill: View {
    let text: String
    var color: Color = .secondary
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3).foregroundStyle(color).background(color.opacity(0.09), in: Capsule()) }
}
struct MarkdownNotes: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let heading = line.hasPrefix("# ") || line.hasPrefix("## ")
                let cleaned = heading ? String(line.drop(while: { $0 == "#" || $0 == " " })) : line
                Text((try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(cleaned))
                    .font(.system(size: heading ? 16 : 13, weight: heading ? .semibold : .regular)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
