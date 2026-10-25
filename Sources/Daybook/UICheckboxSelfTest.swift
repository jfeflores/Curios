#if DAYBOOK_DIAGNOSTICS
import AppKit
import DaybookCore

/// Opt-in, in-process regression test. It can run only against a newly created,
/// explicitly named synthetic profile, never the user's normal application data.
@MainActor
enum UICheckboxSelfTest {
    static func start() {
        let env = ProcessInfo.processInfo.environment
        guard env["DAYBOOK_UI_TEST_MODE"] == "1", let directory = env["DAYBOOK_DATA_DIR"],
              URL(fileURLWithPath: directory).lastPathComponent.hasPrefix("ui-test-"),
              let reportPath = env["DAYBOOK_UI_TEST_REPORT"] else { return }
        let dataURL = URL(fileURLWithPath: directory).appendingPathComponent("daybook.json")
        let reportURL = URL(fileURLWithPath: reportPath)
        var report: [String: Any] = ["passed": false, "scenario": env["DAYBOOK_UI_SCENARIO"] ?? "today", "method": "In-process NSWindow mouse-down/up events against a real NSButton, with disk and rendered-state readback"]
        do {
            let before = try Persistence.decode(Data(contentsOf: dataURL))
            guard let item = before.items(in: .today).first(where: { $0.kind == .task && !$0.isTemplate }),
                  let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 700 }),
                  let checkbox = findButton(in: window.contentView, id: "task-completion-\(item.id.uuidString)") else {
                throw DataError.invalid("Could not find the rendered native checkbox for the synthetic task.")
            }
            report["targetID"] = item.id.uuidString
            report["initialStateOpen"] = item.status == .open && checkbox.state == .off
            report["checkboxEnabled"] = checkbox.isEnabled
            window.makeKeyAndOrderFront(nil)
            report["clickFrame"] = NSStringFromRect(checkbox.convert(checkbox.bounds, to: nil))
            click(checkbox, in: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                do {
                    let completed = try Persistence.decode(Data(contentsOf: dataURL))
                    let button = findButton(in: window.contentView, id: "task-completion-\(item.id.uuidString)")
                    report["persistedCompleted"] = completed.item(item.id)?.status == .completed
                    report["visibleCheckmark"] = button?.state == .on
                    report["presentInLogbook"] = completed.items(in: .logbook).contains { $0.id == item.id }
                    report["noUnexpectedNewTask"] = before.items.count == completed.items.count
                    capture(window, to: reportURL.deletingLastPathComponent().appendingPathComponent("checkbox-checked.png"))
                    guard let button, button.state == .on, completed.item(item.id)?.status == .completed else {
                        throw DataError.invalid("Mouse click did not produce BOTH a visible checkmark and persisted completion.")
                    }
                    click(button, in: window)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        do {
                            let reopened = try Persistence.decode(Data(contentsOf: dataURL))
                            let button = findButton(in: window.contentView, id: "task-completion-\(item.id.uuidString)")
                            report["secondClickReopened"] = reopened.item(item.id)?.status == .open && button?.state == .off
                            report["passed"] = report["secondClickReopened"] as? Bool == true && report["initialStateOpen"] as? Bool == true && report["noUnexpectedNewTask"] as? Bool == true
                            capture(window, to: reportURL.deletingLastPathComponent().appendingPathComponent("checkbox-reopened.png"))
                        } catch { report["error"] = error.localizedDescription }
                        finish(report, at: reportURL)
                    }
                } catch { report["error"] = error.localizedDescription; finish(report, at: reportURL) }
            }
        } catch { report["error"] = error.localizedDescription; finish(report, at: reportURL) }
    }
    private static func findButton(in view: NSView?, id: String) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.accessibilityIdentifier() == id { return button }
        for child in view.subviews { if let found = findButton(in: child, id: id) { return found } }
        return nil
    }
    private static func click(_ button: NSButton, in window: NSWindow) {
        let rect = button.convert(button.bounds, to: nil)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        let time = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { return }
        // NSButton tracks mouseDown synchronously; enqueue its matching mouseUp first.
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }
    private static func capture(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url, options: .atomic) }
    }
    private static func finish(_ report: [String: Any], at url: URL) {
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic) }
        catch { print("UI test report error: \(error)") }
        print("Checkbox UI test: \(report["passed"] as? Bool == true ? "PASS" : "FAIL")")
        NSApp.terminate(nil)
    }
}
#endif
