import UserNotifications
import SwiftUI
import SwiftData
import Photos

@main
struct TidybyteApp: App {
    /// Nil only when SwiftData cannot be initialized at all — see
    /// `makeModelContainer()`. `body` then renders a degraded screen instead of
    /// trapping during launch.
    private let modelContainer: ModelContainer?
    /// Owns the once-per-day scan + widget refreshes (APP-01/02/03/04/09).
    private let widgetCoordinator = WidgetSnapshotCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Reset UI-test state before anything can read it. This lives here, not
        // in `RootView.init`, because `RootView` builds its `LanguageStore` in a
        // property initializer — and a property initializer runs before the body
        // of its own `init`. A reset performed there cleared the stored language
        // *after* `LanguageStore` had already read it, so the launch the reset
        // was added for still rendered the previous language; only the launch
        // after that saw the clear.
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset-onboarding") {
            UITestLaunchReset.perform()
        }
        #endif

        modelContainer = Self.makeModelContainer()
        // Set before launch finishes, so a tap that cold-launches the app is
        // still routed.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    /// Builds the SwiftData container, degrading instead of trapping.
    ///
    /// Three tiers, each strictly more degraded than the last:
    ///
    /// 1. On-disk store with the real schema — the normal path.
    /// 2. In-memory store with the real schema. A corrupted or
    ///    migration-incompatible on-disk store must not brick launch; history
    ///    simply doesn't persist across launches in this state, and every
    ///    `@Model` still inserts and queries normally.
    /// 3. In-memory store with an *empty* schema. An OS upgrade can change model
    ///    validation rules such that even tier 2 fails; an empty schema has no
    ///    rules to violate, so the app still launches and features degrade to
    ///    no-ops rather than crashing in a launch loop.
    ///
    /// Only if all three fail does this return nil, which no known OS state
    /// produces — but returning nil is the point: a `try!` here would turn an
    /// unprecedented failure into an unrecoverable crash on the launch path.
    private static func makeModelContainer() -> ModelContainer? {
        let schema = Schema([
            SwipeRecord.self,
            CompressionRecord.self,
            StorageSnapshot.self,
            CleanupActivityRecord.self
        ])

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
        } catch {
            AppLog.app.error("Persistent ModelContainer failed (\(error.localizedDescription, privacy: .public)); falling back to in-memory store")
            // Tier-2 fallback: the in-memory store starts EMPTY, but the
            // UserDefaults scan-date marker may still claim today's heavy scan
            // already ran — which would skip the rebuild scan and leave the
            // storage snapshot/widget empty. Invalidate it so the daily scan
            // rebuilds from the live library on activation.
            UserDefaults.standard.removeObject(forKey: AppPreferences.Key.lastStorageScanAt)
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            AppLog.app.fault("In-memory ModelContainer failed (\(error.localizedDescription, privacy: .public)); degrading to empty store")
        }

        let emptySchema = Schema([])
        do {
            return try ModelContainer(
                for: emptySchema,
                configurations: [ModelConfiguration(schema: emptySchema, isStoredInMemoryOnly: true)]
            )
        } catch {
            AppLog.app.fault("Empty-schema ModelContainer failed (\(error.localizedDescription, privacy: .public)); SwiftData is unavailable")
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                RootView()
                    .task {
                        // Wire the cleanup ledger before anything can record into it
                        // (the daily scan also reconciles its cached totals).
                        CleanupLedger.shared.attach(modelContext: modelContainer.mainContext)
                        await handleSceneActivation(modelContext: modelContainer.mainContext)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                        // Evict thumbnails under memory pressure (the cache now
                        // also has a 50MB cost ceiling; this is the backstop).
                        Task { await ImageCache.shared.removeAll() }
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        if newPhase == .active {
                            Task { await handleSceneActivation(modelContext: modelContainer.mainContext) }
                        }
                    }
                    .modelContainer(modelContainer)
                    .environment(widgetCoordinator)
            } else {
                SwiftDataUnavailableView()
            }
        }
    }

    @MainActor
    private func handleSceneActivation(modelContext: ModelContext) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            await widgetCoordinator.refreshReminder()
            return
        }

        // APP-01: the coordinator's `isScanning` guard dedupes the `.task` +
        // scenePhase double-fire on cold launch AND the APP-02 permission-grant
        // re-entry from RootView, so the once-per-day scan runs exactly once.
        // (TidybyteApp is a struct; the in-flight guard lives on the
        // coordinator rather than a stored property here.)
        await widgetCoordinator.runDailyScanIfNeeded(modelContext: modelContext)
    }
}

#if DEBUG
/// The UI-test launch reset: a genuinely fresh first-run state.
///
/// Two properties matter, and both were violated once:
///
/// 1. **It must run before anything reads the state it clears.** `RootView`
///    builds its `LanguageStore` in a property initializer, so a reset in
///    `RootView.init`'s body ran too late to affect the launch it targeted.
///    `App.init` is the earliest app-owned point, and it is before any view.
/// 2. **It must run exactly once.** `RootView.init` re-runs whenever the App
///    body re-evaluates, and the photo permission alert causes a `scenePhase`
///    change that does exactly that. A second reset deleted the first-run flag
///    `Skip` had just written and brought the onboarding cover back over a
///    running test. `App.init` already runs once; this keeps the reset
///    idempotent regardless of where it is called from.
private enum UITestLaunchReset {
    private static let didReset: Void = {
        UserDefaults.standard.removeObject(forKey: AppPreferences.Key.hasCompletedOnboarding)
        // The stored language override outranks iOS's `AppleLanguages`, which
        // the UI tests pin to English for their label lookups. A simulator left
        // in German by a previous hand-check would render German and fail every
        // English assertion, so clear it here too. Written through the store so
        // both stores (App Group and standard) are cleared by the same code that
        // writes them.
        LanguagePreferenceStore.save(nil)
        // `LanguageStore.applyToSystem` mirrors the pick into `AppleLanguages`
        // for the system-rendered UI, and `Bundle.main` follows that key.
        // Clearing only the override left the mirror behind, so the unit tests —
        // which run in this same app and pass no `-AppleLanguages` — resolved
        // `Bundle.main` against the language a previous UI test picked and
        // asserted German copy against English expectations.
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }()

    /// Runs the reset at most once per process, however often it is called.
    static func perform() { _ = didReset }
}
#endif
/// Shown when SwiftData could not be initialized in any configuration.
///
/// This screen is deliberately outside `RootView`: every feature reads
/// `@Environment(\.modelContext)`, which traps when no container was installed,
/// so the app cannot render its normal UI in this state. It is expected to be
/// unreachable in practice — it exists so the failure mode is a readable screen
/// instead of a crash on launch.
private struct SwiftDataUnavailableView: View {
    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "externaldrive.badge.xmark")
                .scaledGlyph(ScaledSize.stateGlyph, weight: .light)
                .foregroundStyle(Color.warning)

            VStack(spacing: Spacing.md) {
                Text("TidyByte Can't Start")
                    .font(.title2.bold())

                Text("The on-device database for your cleanup history couldn't be opened. This is usually temporary — force-quit TidyByte and open it again. If it keeps happening, updating iOS usually clears it.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            Spacer()

            Text("Your photos are untouched and were never uploaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.xl)
        }
    }
}
