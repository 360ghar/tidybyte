import Foundation

/// Shared scan lifecycle for the cleanup tools (C1/C2/C16).
enum ScanState: Equatable {
    case idle
    case scanning(Float)
    case completed
}

/// Owns a cancellable scan task plus a generation token, so the two races that
/// plagued the per-VM `scanTask` pattern are structurally impossible:
///
/// - **Clobber (C1):** a cancelled scan's completion wrapper used to stomp
///   `scanState` and nil the *new* scan's task handle, leaving an
///   uncancellable background scan. Here the wrapper can only clear the handle
///   if its token is still current.
/// - **Resurrection (C2):** a queued progress update used to flip the state
///   back to `.scanning` after cancel. Here every write is dropped once the
///   token is stale.
///
/// VMs route ALL scan-state writes through `update(_:_)` and guard final
/// result assignment with `isCurrent(_:)`.
@MainActor
final class ScanRunner {
    private var task: Task<Void, Never>?
    private var generation = 0

    /// True while a scan is in flight — re-entry guard and cancel visibility.
    var isRunning: Bool { task != nil }

    /// Starts `work` unless a scan is already running. `work` receives a token
    /// that identifies this run.
    func start(_ work: @escaping @MainActor (_ token: Int) async -> Void) {
        guard task == nil else { return }
        generation += 1
        let token = generation
        task = Task { [weak self] in
            await work(token)
            // Only the current run may release the slot — a cancelled run
            // finishing late must not erase a newer run's handle (C1).
            guard let self, self.generation == token else { return }
            self.task = nil
        }
    }

    /// Runs `work` as a runner-owned run and awaits its completion, so callers
    /// like pull-to-refresh get the same generation token + `cancel()`
    /// coverage as `start` while suspending until the results land. Serializes
    /// behind an in-flight run instead of overlapping it; no-op when cancelled
    /// or when a newer run started while waiting.
    func run(_ work: @escaping @MainActor (_ token: Int) async -> Void) async {
        if let current = task {
            await current.value
        }
        guard !Task.isCancelled, task == nil else { return }
        generation += 1
        let token = generation
        let current = Task { [weak self] in
            await work(token)
            // Same C1 guard as `start`: only the current run releases the slot.
            guard let self, self.generation == token else { return }
            self.task = nil
        }
        task = current
        await current.value
    }

    /// Cancels the in-flight scan, if any. Callers set their own visible state
    /// (e.g. `scanState = .idle`) right after. Cancellation propagates to
    /// structured children of the run — keep scan work structured (cf.
    /// `AlbumMembershipLoader`); detached tasks would not observe it.
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// True when `token` still names the live scan.
    func isCurrent(_ token: Int) -> Bool {
        generation == token && task != nil
    }

    /// Applies `apply` only while `token` names the live scan. Progress updates
    /// that land after `cancel()` are dropped instead of resurrecting the
    /// scanning state with no scan behind it (C2).
    func update(_ token: Int, _ apply: @MainActor () -> Void) {
        guard isCurrent(token) else { return }
        apply()
    }
}
