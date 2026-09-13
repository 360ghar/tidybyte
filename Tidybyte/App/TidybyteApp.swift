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
        modelContainer = Self.makeModelContainer()
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
        guard status == .authorized || status == .limited else { return }

        // APP-01: the coordinator's `isScanning` guard dedupes the `.task` +
        // scenePhase double-fire on cold launch AND the APP-02 permission-grant
        // re-entry from RootView, so the once-per-day scan runs exactly once.
        // (TidybyteApp is a struct; the in-flight guard lives on the
        // coordinator rather than a stored property here.)
        await widgetCoordinator.runDailyScanIfNeeded(modelContext: modelContext)
    }
}

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
