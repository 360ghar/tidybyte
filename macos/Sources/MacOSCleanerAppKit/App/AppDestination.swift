import MacOSCleanerCore
import SwiftUI

/// One sidebar row per destination. Each review row shows only its own share
/// of the plan, so no action appears twice.
enum AppDestination: String, CaseIterable, Identifiable {
    case overview
    case systemJunk, developer, largeFiles, duplicates, media
    case applications, leftovers, loginItems
    case explorer, changes, history

    var id: String { rawValue }

    /// Rows backed by the shared review list (ActionStackView).
    var isReview: Bool { [.systemJunk, .developer, .largeFiles, .leftovers].contains(self) }
    /// App Store History shows Photos & Media activity only, which has no search.
    var supportsSearch: Bool {
        isReview || [.duplicates, .applications, .explorer].contains(self)
            || (self == .history && DistributionChannel.supportsAdvanced)
    }
    var supportsInspector: Bool { supportsSearch }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .systemJunk: String(localized: "System Junk")
        case .developer: String(localized: "Developer")
        case .largeFiles: String(localized: "Large & Old Files")
        case .duplicates: String(localized: "Duplicates")
        case .media: String(localized: "Photos & Media")
        case .applications: String(localized: "Applications")
        case .leftovers: String(localized: "Leftovers")
        case .loginItems: String(localized: "Login Items")
        case .explorer: String(localized: "Space Explorer")
        case .changes: String(localized: "Changes")
        case .history: String(localized: "History")
        }
    }

    var icon: String {
        switch self {
        case .overview: "internaldrive"
        case .systemJunk: "trash"
        case .developer: "hammer"
        case .largeFiles: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .media: "photo.on.rectangle"
        case .applications: "square.grid.3x3"
        case .leftovers: "shippingbox"
        case .loginItems: "power"
        case .explorer: "chart.pie"
        case .changes: "chart.line.uptrend.xyaxis"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// Rows this build shows; routes and menus go nowhere else.
    static var available: [AppDestination] { sections.flatMap(\.rows) }

    /// Sidebar sections in order. The App Store build has no system access,
    /// so it shows only the folder-scoped rows.
    static var sections: [(title: String?, rows: [AppDestination])] {
        guard DistributionChannel.supportsAdvanced else {
            return [(nil, [.overview]), (String(localized: "Clean"), [.media]), (nil, [.history])]
        }
        return [
            (nil, [.overview]),
            (String(localized: "Clean"), [.systemJunk, .developer, .largeFiles, .duplicates, .media]),
            (String(localized: "Apps"), [.applications, .leftovers, .loginItems]),
            (String(localized: "Insights"), [.explorer, .changes, .history])
        ]
    }

    /// The row that owns a finding category. Exhaustive on purpose: a new
    /// category does not compile until it has a home in the sidebar.
    static func forCategory(_ category: FindingCategory?) -> AppDestination {
        guard let category else { return .largeFiles }
        return switch category {
        case .cache, .log, .systemDeep, .userEssentials, .finderMetadata, .macOSSystemCache, .sandboxedAppCache,
            .browserCache, .cloudStorageCache, .officeAppCache, .applicationSupportCache, .appleSiliconUpdate,
            .iosDeviceBackup, .timeMachineBackup:
            .systemJunk
        case .developerArtifact, .codingAgentArtifact, .packageManagerCleanup, .dockerCleanup, .developerToolCache,
            .developmentAppCache, .vmToolCache:
            .developer
        case .largeFile, .largeFileReview, .oldDownload, .oldInstaller, .screenshot, .organization, .protected:
            .largeFiles
        case .duplicate:
            .duplicates
        case .appLeftover, .uninstalledAppData:
            .leftovers
        }
    }
}

struct CleanerCommands: Commands {
    @Bindable var model: AppViewModel
    @Environment(\.openWindow) private var openWindow

    private var isBusy: Bool { model.isScanning || model.isExecuting || model.cleanup.isBusy }
    private var canReviewSelection: Bool {
        model.selectedVisibleReviewAction?.executedAt == nil && model.selectedVisibleReviewAction != nil
            && !model.isScanning && !model.isExecuting && !model.isPlanning
    }

    /// ⌘1–⌘9 go to the rows people use most.
    private static let shortcutRows: [AppDestination] = [
        .overview, .systemJunk, .developer, .largeFiles, .duplicates, .media, .applications, .explorer, .history
    ]

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "Scan")) {
                openWindow(id: "main")
                model.scanAll()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isBusy)
            Button(String(localized: "Scan Options…")) {
                openWindow(id: "main")
                if model.destination == .media || !DistributionChannel.supportsAdvanced {
                    model.cleanup.showsScope = true
                } else {
                    model.showsScanSetup = true
                }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(isBusy)
            Divider()
            Button(String(localized: "Export Report…")) { Task { await model.generateReport() } }
                .disabled(model.outcome == nil || isBusy)
        }
        CommandGroup(after: .textEditing) {
            Button(String(localized: "Find")) {
                if !model.destination.supportsSearch, DistributionChannel.supportsAdvanced { model.destination = .explorer }
                model.searchFocusRequest += 1
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu(String(localized: "Go")) {
            ForEach(AppDestination.sections.flatMap(\.rows)) { row in
                if let index = Self.shortcutRows.firstIndex(of: row) {
                    Button(row.title) { model.destination = row }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                } else {
                    Button(row.title) { model.destination = row }
                }
            }
        }
        if DistributionChannel.supportsAdvanced {
            CommandMenu(String(localized: "Review")) {
                Button(String(localized: "Ask Tidybyte…")) { model.showsPlanner = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(model.plan == nil || isBusy)
                Divider()
                Button(String(localized: "Approve Selected Action")) {
                    if let action = model.selectedVisibleReviewAction { model.approve(action) }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(
                    !canReviewSelection || model.selectedAction?.risk == .forbidden
                        || model.selectedAction.map { !AppViewModel.isSupportedOperation($0.actionType) } == true)
                Button(String(localized: "Reject Selected Action")) {
                    if let action = model.selectedVisibleReviewAction { model.reject(action) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!canReviewSelection)
            }
        }
        if let checkForUpdates = MacOSCleanerApp.checkForUpdates {
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…"), action: checkForUpdates)
            }
        }
        SidebarCommands()
        InspectorCommands()
        ToolbarCommands()
    }
}
