import AppKit
import Combine
import EventKit
import UserNotifications
import CuriosCore
import Carbon

@MainActor
final class Integrations: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var calendars: [EKCalendar] = []
    @Published var message: String?
    private let eventStore = EKEventStore()
    private var lastCalendarRefresh = Date.distantPast
    private var calendarRequestRunning = false
    private var displayGeneration = UUID()
    func clearPrivateDisplayState() {
        displayGeneration = UUID(); events = []; calendars = []; message = nil
        lastCalendarRefresh = .distantPast
    }
    func requestCalendar() async -> Bool {
        let generation = displayGeneration
        do {
            guard try await eventStore.requestFullAccessToEvents() else { message = "Calendar access wasn't granted. Nothing was read."; return false }
            guard displayGeneration == generation else { return false }
            calendars = eventStore.calendars(for: .event); lastCalendarRefresh = .distantPast
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func refreshCalendar(_ preferences: Preferences) {
        guard preferences.calendarEnabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            events = []; calendars = []; lastCalendarRefresh = .distantPast
            return
        }
        guard Date().timeIntervalSince(lastCalendarRefresh) > 60, !calendarRequestRunning else { return }
        calendarRequestRunning = true; defer { calendarRequestRunning = false }
        lastCalendarRefresh = Date(); calendars = eventStore.calendars(for: .event)
        let selected = calendars.filter { preferences.calendarIDs.isEmpty || preferences.calendarIDs.contains($0.calendarIdentifier) }
        let start = Calendar.current.startOfDay(for: Date()), end = Calendar.current.date(byAdding: .day, value: 31, to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
    func invalidateCalendar() { lastCalendarRefresh = .distantPast }
    private var queuedNotificationPlan: NotificationPlan?
    private var notificationRevision: UInt64 = 0
    private var notificationReconciliation: Task<Void, Never>?
    private var supportsNotifications: Bool {
        ["local.curios.mac", "local.daybook.mac"].contains(Bundle.main.bundleIdentifier ?? "")
    }
    func requestNotifications() async -> Bool {
        guard supportsNotifications else { message = "Build and open Curios.app to enable notifications."; return false }
        #if CURIOS_DIAGNOSTICS
        guard ProcessInfo.processInfo.environment["CURIOS_UI_TEST_MODE"] != "1" else { return false }
        #endif
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { message = "macOS could not authorize notifications."; return false }
    }
    func updateNotifications(_ database: Database) {
        guard supportsNotifications else { return }
        #if CURIOS_DIAGNOSTICS
        guard ProcessInfo.processInfo.environment["CURIOS_UI_TEST_MODE"] != "1" else { return }
        #endif
        notificationRevision &+= 1
        queuedNotificationPlan = NotificationPlan(database: database)
        guard notificationReconciliation == nil else { return }
        // One worker owns all remove/add operations. New edits supersede queued
        // plans, but never cancel an in-flight OS add: the next pass removes it
        // before adding anything else, including when notifications are disabled.
        notificationReconciliation = Task { [weak self] in
            guard let self else { return }
            while let plan = self.queuedNotificationPlan {
                self.queuedNotificationPlan = nil
                await self.reconcileNotifications(plan, revision: self.notificationRevision)
            }
            self.notificationReconciliation = nil
        }
    }
    private func reconcileNotifications(_ plan: NotificationPlan, revision: UInt64) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard revision == notificationRevision else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { NotificationPlan.owns($0.identifier) }.map(\.identifier))
        let settings = await center.notificationSettings()
        guard revision == notificationRevision else { return }
        let permitted = plan.enabled && settings.authorizationStatus == .authorized
        let delivered = await center.deliveredNotifications()
        guard revision == notificationRevision else { return }
        // Also remove legacy content-bearing previews; leave unrelated requests
        // untouched. Disabled/revoked authorization cleans up all owned previews.
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
            NotificationPlan.owns($0.request.identifier) && (!permitted ||
                $0.request.content.title != NotificationPlan.title || $0.request.content.body != NotificationPlan.body)
        }.map { $0.request.identifier })
        guard permitted else { return }
        for reminder in plan.reminders {
            guard revision == notificationRevision else { return }
            let interval = reminder.date.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title; content.body = reminder.body; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            do { try await center.add(request) }
            catch {
                if revision == notificationRevision { message = "macOS could not schedule a reminder." }
            }
        }
        // Revocation can race an add. A subsequent refresh also retries this
        // cleanup; neither a successful add nor this check proves OS delivery.
        let finalSettings = await center.notificationSettings()
        guard revision == notificationRevision else { return }
        if finalSettings.authorizationStatus != .authorized {
            center.removePendingNotificationRequests(withIdentifiers: plan.reminders.map(\.identifier))
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter { NotificationPlan.owns($0.request.identifier) }.map { $0.request.identifier })
        }
    }
}

extension Notification.Name {
    static let curiosQuickEntry = Notification.Name("Curios.QuickEntry")
    static let curiosUserActivity = Notification.Name("Curios.UserActivity")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var activityMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if CURIOS_DIAGNOSTICS
        if ProcessInfo.processInfo.environment["CURIOS_UI_TEST_MODE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { UICheckboxSelfTest.start() }
            return
        }
        #endif
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { event in
            NotificationCenter.default.post(name: .curiosUserActivity, object: nil)
            return event
        }
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .curiosQuickEntry, object: nil)
            }
            return noErr
        }, 1, &specification, nil, &handler)
        let id = EventHotKeyID(signature: 0x44415942, id: 1)
        // Ctrl-Shift-Space avoids replacing the system's Ctrl-Space input-source shortcut.
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
        #if CURIOS_DIAGNOSTICS
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), flag + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[flag + 1]
            // Rendering only this application's own NSView needs no cross-app access.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.captureOwnWindow(to: path) }
        }
        #endif
    }
    #if CURIOS_DIAGNOSTICS
    private func captureOwnWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 700 }), let view = window.contentView else { print("Snapshot: no main window"); return }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("Snapshot: no bitmap"); return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            guard let bytes = bitmap.representation(using: .png, properties: [:]) else { return }
            try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("Snapshot: \(path), \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        } catch { print("Snapshot error: \(error)") }
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) {
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
