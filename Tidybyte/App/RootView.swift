import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appNavigation = AppNavigation()
    @State private var permissionHandler = PhotoPermissionHandler()
    @State private var libraryMonitor = LibraryChangeMonitor()
    @AppStorage(AppPreferences.Key.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    #if DEBUG
    /// Set by the UI test launch argument. Evaluated once per view instance and
    /// kept in `@State` so it cannot change mid-session.
    @State private var forceOnboardingForUITests =
        ProcessInfo.processInfo.arguments.contains("-uitest-reset-onboarding")
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(WidgetSnapshotCoordinator.self) private var widgetCoordinator

    init() {
        #if DEBUG
        // Start UI tests from a genuinely fresh first-run state. Resetting the
        // persisted flag here (rather than pinning it false via a launch
        // argument) matters: an argument-domain value would outrank the write
        // that Skip performs, so the cover could never be dismissed.
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: AppPreferences.Key.hasCompletedOnboarding)
        }
        #endif

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

            NavigationStack(path: storagePathBinding) {
                permissionGatedView { StorageDashboardView() }
                    .navigationDestination(for: StorageRoute.self) { route in
                        switch route {
                        case .activity:
                            ActivityView()
                        }
                    }
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
        .sidebarAdaptableOnPad()
        .environment(appNavigation)
        .environment(libraryMonitor)
        // Injected so any tab can react to limited access (the shared
        // `LimitedLibraryBanner`) without threading the handler through every
        // initializer.
        .environment(permissionHandler)
        .tint(.blue)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView(
                onFinish: { hasCompletedOnboarding = true },
                onRequestAccess: { await permissionHandler.requestPermission() }
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                permissionHandler.updateState()
                // A widget button tapped while the app was backgrounded queued
                // its route in the App Group; apply it on the way back up.
                applyPendingWidgetRoute()
            }
        }
        .onChange(of: permissionHandler.permissionState) { _, newState in
            // APP-02: a first-launch permission grant happens in-foreground, so
            // scenePhase never re-fires — run the daily scan on the grant. The
            // coordinator's isScanning guard dedupes against any activation
            // scan still in flight.
            if newState == .authorized || newState == .limited {
                Task { await libraryMonitor.start() }
                Task { await widgetCoordinator.runDailyScanIfNeeded(modelContext: modelContext) }
            }
        }
        .onChange(of: libraryMonitor.generation) { _, newGeneration in
            // APP-03: in-app cleanups bump the generation — refresh the widget
            // snapshot (debounced + deduped inside the coordinator) and
            // reconcile the cached lifetime savings the widget reads.
            Task {
                await widgetCoordinator.refreshAfterLibraryChange(
                    generation: newGeneration,
                    modelContext: modelContext
                )
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
            // Same for a widget button tapped while the app was not running.
            applyPendingWidgetRoute()
            // Registering the library observer before access is decided can
            // raise the one-time iOS photo prompt over onboarding. Start it
            // only once access exists (the onChange below covers a grant).
            if permissionHandler.permissionState == .authorized || permissionHandler.permissionState == .limited {
                await libraryMonitor.start()
            }
        }
    }

    /// Applies a destination queued by an interactive-widget button. The widget
    /// target's intents can't reference `DeepLink`, so they write a
    /// `WidgetRoute` into the shared App Group instead; this is the only place
    /// that turns one into navigation. `consume` clears it, so a route can't
    /// replay on every activation.
    private func applyPendingWidgetRoute() {
        guard let route = AppGroupStore.consumePendingRoute() else { return }
        switch route {
        case .swipe:
            appNavigation.handle(.swipe)
        case .screenshots:
            appNavigation.handle(.cleanupTool(.screenshots))
        case .activity:
            appNavigation.handle(.activity)
        }
    }

    /// Drives the first-run cover.
    ///
    /// The decision itself lives in `AppPreferences.shouldPresentOnboarding` so
    /// the "fresh install only" rule is unit-tested rather than duplicated here.
    /// The setter records completion, so onboarding cannot reappear even if the
    /// user dismisses it via Skip.
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: {
                #if DEBUG
                // UI tests need a deterministic first-run screen: the simulator
                // persists its photo-permission grant across runs, so
                // `shouldPresentOnboarding` would otherwise return false after
                // any test that granted access.
                //
                // The force bypasses only the *permission* half of the gate, not
                // the completion flag — returning an unconditional true here
                // would make the cover impossible to dismiss, including via Skip.
                if forceOnboardingForUITests {
                    return !hasCompletedOnboarding
                }
                #endif
                return AppPreferences.shouldPresentOnboarding(
                    hasCompleted: hasCompletedOnboarding,
                    permissionState: permissionHandler.permissionState
                )
            },
            set: { isPresented in
                if !isPresented { hasCompletedOnboarding = true }
            }
        )
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

    private var storagePathBinding: Binding<[StorageRoute]> {
        Binding(
            get: { appNavigation.storagePath },
            set: { appNavigation.storagePath = $0 }
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

private extension View {
    /// Adopts the iPad sidebar on iOS 18+, and stays a tab bar everywhere else.
    ///
    /// Deliberately NOT a `NavigationSplitView` rewrite: the four sections each
    /// carry their own `NavigationStack` with its own typed path, and rebuilding
    /// that by hand would put the iPhone navigation — deep links, App Intents,
    /// widget routes, the swipe-session deletion gate — at risk for no user
    /// benefit. `sidebarAdaptable` is the platform's own answer: the same
    /// `TabView` renders as a tab bar on iPhone and a collapsible sidebar on
    /// iPad, with keyboard navigation for free.
    ///
    /// The `#available` split exists because the style is iOS 18+ and the app
    /// targets iOS 17. On 17 an iPad keeps the tab bar, which is exactly what it
    /// shipped with — a graceful degradation rather than a reason to raise the
    /// deployment target.
    @ViewBuilder
    func sidebarAdaptableOnPad() -> some View {
        if #available(iOS 18.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}
