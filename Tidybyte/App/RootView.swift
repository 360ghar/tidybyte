import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appNavigation = AppNavigation()
    @State private var permissionHandler = PhotoPermissionHandler()
    @State private var libraryMonitor = LibraryChangeMonitor()
    /// Owned here rather than in `TidybyteApp` so the SwiftUI environment can
    /// carry it; the app's `init` cannot publish an observable into the view
    /// tree. Read by Settings to change the language, and by nothing else —
    /// every other view gets the language through the environment below.
    @State private var languageStore = LanguageStore()
    @AppStorage(AppPreferences.Key.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(AppPreferences.Key.largeFileThresholdMB) private var largeFileThreshold = 10.0
    /// Set once the limited-library picker has been offered automatically this
    /// launch, so a user who declines is not asked again on every foreground.
    /// Deliberately not persisted: a new launch with an empty selection is worth
    /// one more offer, and the system picker is dismissible.
    @State private var hasOfferedLimitedLibraryPicker = false
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
                        permissionGatedView { cleanupDestinationView(for: tool) }
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
        .safeAreaInset(edge: .bottom) {
            if !appNavigation.isShowingSwipeCompletion {
                RecentlyDeletedNotice()
            }
        }
        .adaptiveSidebarStyle()
        .environment(appNavigation)
        .environment(libraryMonitor)
        // Injected so any tab can react to limited access (the shared
        // `LimitedLibraryBanner`) without threading the handler through every
        // initializer.
        .environment(permissionHandler)
        .environment(languageStore)
        // Localization, applied at the one place every screen is below.
        //
        // `\.locale` is what makes `Text("Some key")` resolve against the
        // chosen language; verified in the simulator that a child view which
        // never reads the environment still re-renders when this changes.
        //
        // Text that is built in code (`Text(tool.name)`, where `name` is a
        // computed `String`) is passed to `Text` as a `LocalizedStringKey` at
        // its own call site, so it reads the same environment value instead of
        // selecting the verbatim `String` overload. That is the whole
        // mechanism: an environment change re-renders the text.
        //
        // Deliberately NOT `.id(languageStore.effectiveLanguage)`. Keying the
        // tree on the language forced a full rebuild of everything below this
        // point, and that rebuild destroyed child `@State` rather than just
        // re-rendering it: a live Swipe session's `SwipeSessionViewModel` (and
        // the deletions it had marked but not committed) was thrown away, and
        // `SwipeSessionView.onDisappear` never calls `endSession()`, so the
        // completion review that every other exit path guards was skipped and
        // the marked photos silently came back as "Not Swiped Yet". The state
        // above this point (`appNavigation`, `permissionHandler`,
        // `libraryMonitor`, `languageStore`) was never at risk; the state below
        // it is what the rebuild cost.
        .environment(\.locale, languageStore.locale)
        .environment(\.layoutDirection, languageStore.layoutDirection)
        // `nil` for the default: SwiftUI then keeps following the device's
        // light/dark setting and any automatic schedule, which is the behavior
        // the app had before this setting existed.
        .preferredColorScheme(languageStore.appearance.colorScheme?.swiftUI)
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
                Task { await offerLimitedLibraryPickerIfNeeded() }
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, _ in
            // Onboarding owns the screen until it is dismissed; the offer waits
            // rather than stacking on the cover (iOS ignores the second
            // presentation anyway, which would waste the one offer).
            Task { await offerLimitedLibraryPickerIfNeeded() }
        }
        .onChange(of: permissionHandler.permissionState) { _, newState in
            Task { await offerLimitedLibraryPickerIfNeeded() }
            libraryMonitor.permissionDidChange()
            // APP-02: a first-launch permission grant happens in-foreground, so
            // scenePhase never re-fires — run the daily scan on the grant. The
            // coordinator's isScanning guard dedupes against any activation
            // scan still in flight.
            if newState == .authorized || newState == .limited {
                Task { await libraryMonitor.start() }
                Task { await widgetCoordinator.runDailyScanIfNeeded(modelContext: modelContext) }
            } else {
                Task { await widgetCoordinator.refreshReminder() }
            }
        }
        .onChange(of: libraryMonitor.generation) { _, _ in
            // APP-03: in-app cleanups bump the generation — refresh the widget
            // snapshot (debounced + deduped inside the coordinator) and
            // reconcile the cached lifetime savings the widget reads.
            Task {
                await widgetCoordinator.refreshAfterLibraryChange(modelContext: modelContext)
            }
        }
        .onChange(of: largeFileThreshold) { _, _ in
            // Covers the threshold controls in both Settings and Large Files.
            Task {
                await widgetCoordinator.refreshAfterLibraryChange(modelContext: modelContext)
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
            await offerLimitedLibraryPickerIfNeeded()
        }
    }

    /// Offers the system "which photos can this app see" picker when the app
    /// opens to an empty library under limited access.
    ///
    /// This is the state that reads as a broken app: permission is granted, so
    /// no gate appears, but every fetch returns nothing and every tool is empty.
    /// The in-app banner's "Add More Photos" needs the user to find it; opening
    /// the picker once per launch puts the fix in front of them instead.
    ///
    /// Once per launch, only when there is genuinely nothing to read, and never
    /// on top of onboarding or a sheet.
    @MainActor
    private func offerLimitedLibraryPickerIfNeeded() async {
        guard !hasOfferedLimitedLibraryPicker else { return }
        guard permissionHandler.permissionState == .limited else { return }
        guard hasCompletedOnboarding, scenePhase == .active else { return }
        guard PhotoPermissionHandler.isReadyToPresentLimitedLibraryPicker else { return }
        // Claimed before the first `await`: two launch-triggered calls otherwise
        // both pass the guard while the census is in flight, and the loser's
        // post-sleep failure used to clear the flag, so the picker came back on
        // a later foreground.
        hasOfferedLimitedLibraryPicker = true

        guard await PhotoLibraryService.shared.totalAssetCount() == 0 else {
            // Nothing to recover: hand the offer back.
            hasOfferedLimitedLibraryPicker = false
            return
        }
        // Let the launch frame land first: presenting during the same update as
        // the first tab render is what UIKit ignores.
        try? await Task.sleep(for: .milliseconds(400))
        // The live app state, not `scenePhase`: that environment value was
        // captured in this Task's copy of the view before the sleep, so it still
        // reports the old phase and would present the picker over a backgrounded
        // app.
        guard UIApplication.shared.applicationState == .active else {
            // Skipped, not offered: hand it back rather than burn it.
            hasOfferedLimitedLibraryPicker = false
            return
        }
        guard permissionHandler.permissionState == .limited,
              PhotoPermissionHandler.isReadyToPresentLimitedLibraryPicker else {
            hasOfferedLimitedLibraryPicker = false
            return
        }
        PhotoPermissionHandler.presentLimitedLibraryPicker()
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
    /// Adopts the platform's own adaptive tab style on iOS 18+, and stays a
    /// plain tab bar everywhere else.
    ///
    /// Deliberately NOT a `NavigationSplitView` rewrite: the four sections each
    /// carry their own `NavigationStack` with its own typed path, and rebuilding
    /// that by hand would put the iPhone navigation — deep links, App Intents,
    /// widget routes, the swipe-session deletion gate — at risk for no user
    /// benefit. `sidebarAdaptable` is the platform's own answer: the same
    /// `TabView` renders as a tab bar on iPhone and a collapsible sidebar where
    /// there is room for one, with keyboard navigation for free. Which pose that
    /// is follows the available space, not the device, so a foldable resizing
    /// into or out of a sidebar pose is handled by the style itself.
    ///
    /// The `#available` split exists because the style is iOS 18+ and the app
    /// targets iOS 17. On 17 the tab bar stays, which is exactly what it shipped
    /// with — a graceful degradation rather than a reason to raise the
    /// deployment target.
    @ViewBuilder
    func adaptiveSidebarStyle() -> some View {
        if #available(iOS 18.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}
