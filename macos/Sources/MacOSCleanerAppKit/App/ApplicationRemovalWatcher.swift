import Foundation
import MacOSCleanerCore

/// Watches /Applications and ~/Applications. When an app bundle disappears
/// and stays gone for 10 seconds (updates replace bundles in place), the
/// owner offers to review its leftovers.
@MainActor
final class ApplicationRemovalWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var known: [String: InstalledApplication] = [:]
    private var pending: Task<Void, Never>?
    private let folders: [URL]
    private let onRemoved: (InstalledApplication) -> Void

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, onRemoved: @escaping (InstalledApplication) -> Void) {
        folders = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        self.onRemoved = onRemoved
    }

    func start() {
        guard sources.isEmpty else { return }
        known = Self.installedApps(in: folders)
        // A vnode source is the native way to watch one folder's entries.
        for folder in folders {
            let descriptor = open(folder.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleCheck() } }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources = []
        pending?.cancel()
    }

    private func scheduleCheck() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            let current = Self.installedApps(in: folders)
            for (id, app) in known where current[id] == nil { onRemoved(app) }
            known = current
        }
    }

    /// Bundle ID → app for direct children of the folders. No size walk: fast.
    static func installedApps(in folders: [URL]) -> [String: InstalledApplication] {
        var apps: [String: InstalledApplication] = [:]
        for folder in folders {
            let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in entries where url.pathExtension == "app" {
                guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
                apps[id] = InstalledApplication(
                    id: id, name: url.deletingPathExtension().lastPathComponent, bundleURL: url,
                    bundleIdentifier: id, bundleSizeBytes: 0)
            }
        }
        return apps
    }
}
