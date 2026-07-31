import SwiftUI
import SwiftData
import Photos

@main
struct TidybyteApp: App {
    let modelContainer: ModelContainer
    /// Owns the once-per-day scan + widget refreshes (APP-01/02/03/04/09).
    private let widgetCoordinator = WidgetSnapshotCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            SwipeRecord.self,
            CompressionRecord.self,
            StorageSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupted or migration-incompatible store shouldn't crash the app on
            // launch. Fall back to an in-memory store *using the real schema* so the
            // history models can still be inserted/queried (an empty schema would only
            // defer the crash to the first insert). History simply won't persist
            // across launches in that rare state. An in-memory container built from a
            // valid schema only fails for a deterministic, dev-time model error, so a
            // force-try here surfaces that loudly rather than masking it.
            AppLog.app.error("Persistent ModelContainer failed (\(error.localizedDescription, privacy: .public)); falling back to in-memory store")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            modelContainer = try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await handleSceneActivation()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await handleSceneActivation() }
                    }
                }
        }
        .modelContainer(modelContainer)
        .environment(widgetCoordinator)
    }

    @MainActor
    private func handleSceneActivation() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        // APP-01: the coordinator's `isScanning` guard dedupes the `.task` +
        // scenePhase double-fire on cold launch AND the APP-02 permission-grant
        // re-entry from RootView, so the once-per-day scan runs exactly once.
        // (TidybyteApp is a struct; the in-flight guard lives on the
        // coordinator rather than a stored property here.)
        await widgetCoordinator.runDailyScanIfNeeded(modelContext: modelContainer.mainContext)
    }
}
