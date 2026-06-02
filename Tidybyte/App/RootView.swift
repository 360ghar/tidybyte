import SwiftUI

struct RootView: View {
    @State private var appNavigation = AppNavigation()
    @State private var permissionHandler = PhotoPermissionHandler()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $appNavigation.selectedTab) {
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
        .tint(.blue)
        .onChange(of: appNavigation.selectedTab) { _, _ in
            HapticHelper.selection()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                permissionHandler.updateState()
            }
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
        }
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
