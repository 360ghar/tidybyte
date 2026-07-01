import Foundation
import Observation

/// App-level monitor that turns PhotoKit change notifications into an
/// observable `generation` counter. Views re-run their load/refresh task via
/// `.task(id: monitor.generation)`, so returning to a tab after the library
/// changed (in-app deletion, compression, or edits made in the Photos app)
/// shows fresh data without a manual pull-to-refresh.
@Observable
@MainActor
final class LibraryChangeMonitor {
    /// Monotonically increasing token bumped (debounced) on every photo
    /// library change. `Int.min` is reserved by consumers as "never synced".
    private(set) var generation = 0

    private let photoService = PhotoLibraryService()
    private var isObserving = false
    private var debounceTask: Task<Void, Never>?

    func start() async {
        guard !isObserving else { return }
        isObserving = true
        await photoService.startObservingChanges { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleGenerationBump()
            }
        }
    }

    /// PHPhotoLibrary posts one change per mutation, so a bulk delete of N
    /// assets can fire N times in quick succession — coalesce into one bump.
    private func scheduleGenerationBump() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.generation += 1
            self?.debounceTask = nil
        }
    }
}
