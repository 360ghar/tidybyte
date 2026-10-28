import MacOSCleanerCore
import SwiftUI
import UserNotifications

public struct MacOSCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppViewModel.bootstrap()
    @AppStorage(AppDelegate.menuBarExtraKey) private var showsMenuBarExtra = false

    /// Set by the executable when Sparkle is linked (direct builds only).
    @MainActor public static var checkForUpdates: (() -> Void)?

    public init() {}

    public var body: some Scene {
        Window(AppIdentity.displayName, id: "main") {
            ContentView(model: model)
                .frame(minWidth: Spacing.windowMinWidth, minHeight: Spacing.windowMinHeight)
                .onOpenURL { url in
                    // tidybyte://<destination>, plus tidybyte://swipe for Swipe Review.
                    guard url.scheme == AppIdentity.urlScheme, let host = url.host else { return }
                    if host == "swipe" {
                        model.destination = .media
                        model.cleanup.selectedTool = .swipe
                    } else if let destination = AppDestination(rawValue: host),
                        AppDestination.available.contains(destination) {
                        model.destination = destination
                    }
                }
                .modifier(MainWindowRegistration(model: model, delegate: appDelegate))
        }
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands { CleanerCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }

        MenuBarExtra(AppIdentity.displayName, systemImage: "internaldrive", isInserted: $showsMenuBarExtra) {
            MenuBarView()
        }
    }
}

private struct MainWindowRegistration: ViewModifier {
    let model: AppViewModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            delegate.setModel(model, openMainWindow: { openWindow(id: "main") })
            model.setRemovalWatching(UserDefaults.standard.object(forKey: AppDelegate.removalWatchKey) as? Bool ?? true)
        }
    }
}

// MARK: - Menu Bar

/// The menu bar extra is a native menu: two status lines, then short commands
/// (each label stays under 30 characters).
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let disk = DiskGaugeData.currentHomeVolume()
        if let free = disk.freeBytes {
            Text(String(localized: "\(free.formattedByteCount) free on disk", comment: "Menu bar disk status"))
        }
        if let memory = SystemStatus.memory() {
            Text(memoryLine(memory))
        }
        Divider()
        Button(String(localized: "Open Tidybyte", comment: "Menu bar: open main window")) { showMainWindow() }
            .keyboardShortcut("o", modifiers: [.command])
        Button(String(localized: "Scan Now", comment: "Menu bar: scan")) {
            showMainWindow()
            AppDelegate.shared?.scanNow()
        }
        Button(String(localized: "Undo Last Cleanup", comment: "Menu bar: undo last cleanup action")) {
            Task { @MainActor in await AppDelegate.shared?.undoLastAction() }
        }
        Divider()
        SettingsLink { Text(String(localized: "Settings…")) }
        Button(String(localized: "Quit Tidybyte", comment: "Menu bar: quit application")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func memoryLine(_ memory: MemorySnapshot) -> String {
        let used = memory.usedBytes.formattedByteCount
        let total = memory.totalBytes.formattedByteCount
        return switch memory.pressure {
        case .normal: String(localized: "Memory \(used) of \(total)", comment: "Menu bar memory, normal pressure")
        case .warning: String(localized: "Memory pressure is high", comment: "Menu bar memory warning")
        case .critical: String(localized: "Memory pressure is critical", comment: "Menu bar memory critical")
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var shared: AppDelegate?
    private var model: AppViewModel?
    private var openMainWindow: (() -> Void)?
    /// A notification tap that arrived before the window existed (it launched the app).
    private var pendingRoute: [AnyHashable: Any]?

    /// The delegate must be set before launch finishes, or a tap that launches
    /// the app is lost.
    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        // UNUserNotificationCenter traps outside an .app bundle (`swift run`).
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func setModel(_ model: AppViewModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
        Self.shared = self
        if let pending = pendingRoute {
            pendingRoute = nil
            Task { await route(pending) }
        }
    }

    private func route(_ info: [AnyHashable: Any]) async {
        guard let model else {
            pendingRoute = info
            return
        }
        if info[NotificationScheduler.routeKey] as? String == "leftovers",
            let bundleID = info[NotificationScheduler.bundleIDKey] as? String {
            await model.reviewLeftovers(
                ofRemovedApp: bundleID,
                name: info[NotificationScheduler.appNameKey] as? String ?? bundleID,
                bundlePath: info[NotificationScheduler.bundlePathKey] as? String ?? "")
        } else {
            model.destination = .media
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // userInfo holds only property-list strings; copy them out before hopping actors.
        let info = response.notification.request.content.userInfo
        let strings = info.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        Task { @MainActor in
            await route(strings)
            openMainWindow?()
            NSApp.activate()
            NSApp.windows.first(where: \.canBecomeKey)?.makeKeyAndOrderFront(nil)
        }
        completionHandler()
    }

    static let menuBarExtraKey = "showsMenuBarExtra"
    static let removalWatchKey = "watchesAppRemovals"

    /// Quit with the last window unless the menu bar extra keeps the app useful.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Self.menuBarExtraKey)
    }

    func scanNow() {
        model?.scanAll()
    }

    /// Restores the newest change, whichever history it is in.
    func undoLastAction() async {
        guard let model else { return }
        guard !model.isScanning, !model.isExecuting, !model.cleanup.isBusy else {
            model.setStatusMessage(
                String(
                    localized: "Undo skipped. A scan or cleanup is already running.",
                    comment: "Menu-bar undo during busy state"
                ))
            return
        }
        let mediaEvent = model.cleanup.activity
            .filter { $0.state == .complete && !$0.restored && $0.item.url != nil }
            .max { $0.date < $1.date }
        var systemRecord: UndoRecord?
        var systemDate = Date.distantPast
        if DistributionChannel.supportsAdvanced {
            await model.loadUndoHistory()
            systemRecord = model.undoRecords.first { $0.status == .available }
            if let record = systemRecord, let log = await model.historyOperation(id: record.operationLogID) {
                systemDate = log.timestamp
            }
        }
        if let mediaEvent, systemRecord == nil || mediaEvent.date >= systemDate {
            await model.cleanup.restore(mediaEvent)
        } else if let systemRecord {
            await model.restore(systemRecord)
        } else {
            model.setStatusMessage(
                String(
                    localized: "Nothing to undo. No completed cleanup operations yet.",
                    comment: "Menu-bar undo with empty history"
                ))
        }
    }
}
