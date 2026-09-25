import Foundation
import Observation
import UIKit

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

    private let photoService = PhotoLibraryService.shared
    private var isObserving = false
    private var debounceTask: Task<Void, Never>?
    /// App-lifetime observer (the monitor lives as long as the app), so no
    /// removal needed.
    private var memoryWarningObserver: NSObjectProtocol?

    func start() async {
        guard !isObserving else { return }
        isObserving = true
        await photoService.startObservingChanges { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleGenerationBump()
            }
        }
        // Cache eviction on library change is owned by PhotoLibraryService
        // (selective id eviction, SHARED-08) — but a memory warning still
        // wants the whole image cache dropped, and nothing else did that.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await ImageCache.shared.removeAll() }
        }
    }

    /// Permission transitions do not always produce a PhotoKit change callback.
    func permissionDidChange() {
        debounceTask?.cancel()
        debounceTask = nil
        generation += 1
        ScanResults.permissionChanged()
        Task { await ImageCache.shared.removeAll() }
    }

    /// PHPhotoLibrary posts one change per mutation, so a bulk delete of N
    /// assets can fire N times in quick succession — coalesce into one bump.
    private func scheduleGenerationBump() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.generation += 1
            self.debounceTask = nil
            // Expire the scan cache here, where the change is observed, rather
            // than in a screen: the epoch advances once per generation no
            // matter which screens are alive, so a scan that started before
            // the change can never publish a pre-change result, and counts a
            // tool records after its own delete survive the next screen load.
            ScanResults.libraryChanged(to: self.generation)
            // Thumbnail coherence is owned by PhotoLibraryService (selective
            // id eviction alongside the change, SHARED-08) — the bump here
            // only refreshes the lists.
        }
    }
}
