import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appNavigation = AppNavigation()
    @State private var permissionHandler = PhotoPermissionHandler()
    @State private var libraryMonitor = LibraryChangeMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSnapshotCoordinator.self) private var widgetCoordinator

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: tabSelectionBinding) {
            NavigationStack {
                permissionGatedView { SwipeHomeView() }
            }
            .tabItem {
                Label("Swipe", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
            }
            .tag(AppTab.swipe)

            NavigationStack(path: cleanupPathBinding) {
                permissionGatedView { CleanupHomeView() }
                    .navigationDestination(for: CleanupTool.self) { tool in
                        cleanupDestinationView(for: tool)
                    }
            }
            .tabItem {
                Label("Cleanup", systemImage: "sparkles")
            }
            .tag(AppTab.cleanup)

            NavigationStack {
                permissionGatedView { StorageDashboardView() }
            }
            .tabItem {
                Label("Storage", systemImage: "chart.pie")
            }
            .tag(AppTab.storage)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(AppTab.settings)
        }
        .environment(appNavigation)
        .environment(libraryMonitor)
        .tint(.blue)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                permissionHandler.updateState()
            }
        }
        .onChange(of: permissionHandler.permissionState) { _, newState in
            // APP-02: a first-launch permission grant happens in-foreground, so
            // scenePhase never re-fires — run the daily scan on the grant. The
            // coordinator's isScanning guard dedupes against any activation
            // scan still in flight.
            if newState == .authorized || newState == .limited {
                Task { await widgetCoordinator.runDailyScanIfNeeded(modelContext: modelContext) }
            }
        }
        .onChange(of: libraryMonitor.generation) { _, newGeneration in
            // APP-03: in-app cleanups bump the generation — refresh the widget
            // snapshot (debounced + deduped inside the coordinator).
            Task { await widgetCoordinator.refreshAfterLibraryChange(generation: newGeneration) }
        }
        .onChange(of: PendingRoute.shared.link) { _, newLink in
            // An App Intent set a route while the app is alive (warm launch /
            // foreground). Apply and clear it.
            if newLink != nil, let link = PendingRoute.shared.consume() {
                appNavigation.handle(link)
            }
        }
        .onOpenURL { url in
            if let link = DeepLink.from(url: url) {
                appNavigation.handle(link)
            }
        }
        .task {
            // Cold launch where the intent's perform() ran before the view
            // appeared (so .onChange never fired): drain any pending route.
            if let link = PendingRoute.shared.consume() {
                appNavigation.handle(link)
            }
            await libraryMonitor.start()
        }
    }

    /// Custom binding whose setter is only invoked by user taps on a tab, so
    /// programmatic switches (deep links / App Intents) don't fire the
    /// selection haptic (APP-05).
    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { appNavigation.selectedTab },
            set: { newTab in
                appNavigation.selectedTab = newTab
                HapticHelper.selection()
            }
        )
    }

    private var cleanupPathBinding: Binding<[CleanupTool]> {
        Binding(
            get: { appNavigation.cleanupPath },
            set: { appNavigation.cleanupPath = $0 }
        )
    }

    @ViewBuilder
    private func permissionGatedView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        switch permissionHandler.permissionState {
        case .authorized, .limited:
            content()
        default:
            PhotoPermissionView(permissionHandler: permissionHandler)
        }
    }
}

enum AppTab: Hashable {
    case swipe
    case cleanup
    case storage
    case settings
}
