import Foundation

public actor ReviewExecutor {
    private let store: SQLiteStore
    private let access: FolderAccess
    private let photos: any PhotoMutationService
    private let trash: any TrashService
    private var activeOperations = Set<String>()
    public init(
        store: SQLiteStore, access: FolderAccess, photos: any PhotoMutationService,
        trash: any TrashService = FileSystemTrashProvider()
    ) {
        self.store = store
        self.access = access
        self.photos = photos
        self.trash = trash
    }

    public func apply(_ decision: ReviewDecision, tool: CleanupTool, operationID: String) async -> ActivityEvent {
        var event = ActivityEvent(id: operationID, tool: tool, item: decision.item, action: decision.choice.rawValue)
        guard activeOperations.insert(operationID).inserted else {
            event.state = .failed
            event.error = String(localized: "This operation is already running. Check Activity for its result.")
            return event
        }
        defer { activeOperations.remove(operationID) }
        do {
            if let previous = try await store.cleanupActivity(id: operationID),
                previous.state != .failed {
                return previous
            }
            try Task.checkCancellation()
            guard decision.item.canChange else {
                throw CleanupError.message(String(localized: "This item is not available for changes."))
            }
            try await store.saveActivity(event)
            if decision.item.photoID != nil {
                try await applyPhoto(decision, event: &event)
            } else {
                try await applyFile(decision, event: &event)
            }
            event.state = .complete
            try await store.saveActivity(event)
        } catch {
            event.error = error.localizedDescription
            if let failure = error as? PhotosReplacementError { event.replacementPhotoID = failure.replacementID }
            if event.state != .complete { event.state = event.outputURL == nil ? .failed : .interrupted }
            try? await store.saveActivity(event)
        }
        return event
    }

    private func applyFile(_ decision: ReviewDecision, event: inout ActivityEvent) async throws {
        guard let root = decision.item.root, let source = decision.item.url else {
            throw CleanupError.message(String(localized: "The file has no approved folder."))
        }
        let granted = try await access.acquire(root)
        defer { granted.stopAccessingSecurityScopedResource() }
        try Task.checkCancellation()
        try ReviewSafety.verify(decision.item)
        if decision.choice == .trash {
            event.outputURL = try trash.trashItem(at: source)
        } else if decision.choice == .move, let requested = decision.destination {
            let destination = try await access.acquire(requested)
            defer { destination.stopAccessingSecurityScopedResource() }
            try ReviewSafety.validateDestination(destination)
            let output = ReviewSafety.uniqueOutput(in: destination, name: source.lastPathComponent)
            event.outputURL = output
            try await store.saveActivity(event)
            try Task.checkCancellation()
            try ReviewSafety.verify(decision.item)
            try ReviewSafety.validateDestination(destination)
            try FileManager.default.moveItem(at: source, to: output)
        } else {
            throw CleanupError.message(String(localized: "The action is missing a move destination."))
        }
        if let output = event.outputURL {
            event.outputIdentity = try? ReviewSafety.identity(at: output)
            event.recoveryBookmark = try? output.bookmarkData(options: .withSecurityScope)
        }
    }

    private func applyPhoto(_ decision: ReviewDecision, event: inout ActivityEvent) async throws {
        if decision.choice == .move, let requested = decision.destination {
            let folder = try await access.acquire(requested)
            defer { folder.stopAccessingSecurityScopedResource() }
            try ReviewSafety.validateDestination(folder)
            // Keep an asset's resources together so export collisions cannot mix two assets.
            let directory = ReviewSafety.uniqueOutput(in: folder, name: decision.item.name + "-resources")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            event.outputURL = directory
            try await store.saveActivity(event)
            _ = try await photos.export(decision.item, to: directory)
            event.state = .outputReady
            try await store.saveActivity(event)
            try Task.checkCancellation()
        } else if decision.choice != .trash {
            throw CleanupError.message(String(localized: "Choose an export destination."))
        }
        try Task.checkCancellation()
        try await photos.delete(decision.item)
    }

    public func compress(
        _ item: ReviewItem, settings: CleanupSettings,
        progress: @escaping @Sendable (Double) async -> Void
    ) async -> ActivityEvent {
        var event = ActivityEvent(
            tool: item.kind == .video ? .videoCompression : .imageCompression,
            item: item, action: "compress")
        var grant: URL?
        do {
            try Task.checkCancellation()
            guard item.canChange, item.canAnalyze else {
                throw CleanupError.message(String(localized: "This item cannot be compressed."))
            }
            if let root = item.root {
                grant = try await access.acquire(root)
                try ReviewSafety.verify(item)
            }
            defer { grant?.stopAccessingSecurityScopedResource() }
            try await store.saveActivity(event)
            let source: URL
            if let url = item.url { source = url } else { source = try await photos.previewURL(for: item) }
            let output = try await MediaCompressionService().compress(
                item, source: source,
                destination: source.deletingLastPathComponent(), settings: settings, progress: progress)
            event.outputURL = output
            event.outputBytes = try ReviewSafety.identity(at: output).sizeBytes ?? 0
            event.replacementURL = output
            event.outputIdentity = try ReviewSafety.identity(at: output)
            event.state = .outputReady
            try await store.saveActivity(event)
            try Task.checkCancellation()
            guard try ReviewSafety.identity(at: output) == event.outputIdentity else {
                throw CleanupError.message(String(localized: "The compressed output changed. The original was kept."))
            }
            try await removeCompressedOriginal(item, output: output, event: &event)
            event.state = .complete
            try await store.saveActivity(event)
        } catch {
            event.error = error.localizedDescription
            if let failure = error as? PhotosReplacementError { event.replacementPhotoID = failure.replacementID }
            if event.state != .complete { event.state = event.outputURL == nil ? .failed : .interrupted }
            try? await store.saveActivity(event)
        }
        return event
    }

    private func removeCompressedOriginal(_ item: ReviewItem, output: URL, event: inout ActivityEvent) async throws {
        if item.photoID != nil {
            event.replacementPhotoID = try await photos.replace(item, with: output, kind: item.kind)
            try await store.saveActivity(event)
            try Task.checkCancellation()
            try await photos.delete(item)
        } else {
            try ReviewSafety.verify(item)
            guard let url = item.url else {
                throw CleanupError.message(String(localized: "Original file missing."))
            }
            let originalTrashURL = try trash.trashItem(at: url)
            // The recovery record keeps the original, not the compressed output.
            event.outputURL = originalTrashURL
            if let originalTrashURL {
                event.outputIdentity = try ReviewSafety.identity(at: originalTrashURL)
                event.recoveryBookmark = try? originalTrashURL.bookmarkData(options: .withSecurityScope)
            }
        }
    }

    public func keepPhotoResource(_ item: ReviewItem, index: Int) async -> ActivityEvent {
        var event = ActivityEvent(tool: .formatPairs, item: item, action: "keepComponent")
        do {
            try Task.checkCancellation()
            guard item.canChange, item.photoID != nil else {
                throw CleanupError.message(String(localized: "This Photos item is not available for changes."))
            }
            try await store.saveActivity(event)
            let urls = try await photos.localURLs(for: item)
            guard urls.indices.contains(index), item.resources.indices.contains(index) else {
                throw CleanupError.message(String(localized: "The selected resource is unavailable."))
            }
            let url = urls[index]
            let kind = ReviewInventory.mediaKind(url) ?? .image
            event.outputBytes = item.resources[index].bytes
            try Task.checkCancellation()
            event.replacementPhotoID = try await photos.replace(item, with: url, kind: kind)
            event.state = .outputReady
            try await store.saveActivity(event)
            try Task.checkCancellation()
            try await photos.delete(item)
            event.state = .complete
            try await store.saveActivity(event)
        } catch {
            event.error = error.localizedDescription
            if let failure = error as? PhotosReplacementError { event.replacementPhotoID = failure.replacementID }
            if event.state != .complete { event.state = .interrupted }
            try? await store.saveActivity(event)
        }
        return event
    }

    public func restore(_ event: ActivityEvent) async throws {
        let operationID = "restore:" + event.id
        guard activeOperations.insert(operationID).inserted else {
            throw CleanupError.message(String(localized: "This restore is already running."))
        }
        defer { activeOperations.remove(operationID) }
        guard let event = try await store.cleanupActivity(id: event.id),
            event.restoreStartedAt == nil, event.state == .complete, !event.restored, let original = event.item.url,
            let root = event.item.root, let output = event.outputURL, let identity = event.outputIdentity,
            ReviewSafety.isAllowed(original),
            ReviewSafety.contains(original, in: root),
            ReviewSafety.contains(
                original.deletingLastPathComponent().resolvingSymlinksInPath(), in: root.resolvingSymlinksInPath()),
            !FileManager.default.fileExists(atPath: original.path)
        else {
            throw CleanupError.message(
                String(localized: "This item cannot be restored here. Check Trash or Recently Deleted."))
        }
        let granted = try await access.acquire(root)
        defer { granted.stopAccessingSecurityScopedResource() }
        let recovery = try recoveryURL(output, bookmark: event.recoveryBookmark)
        defer { recovery.stopAccessingSecurityScopedResource() }
        var updated = event
        updated.restoreStartedAt = Date()
        try await store.saveActivity(updated)
        do {
            try Task.checkCancellation()
            try ReviewSafety.validateDestination(root)
            guard ReviewSafety.isAllowed(original),
                ReviewSafety.contains(
                    original.deletingLastPathComponent().resolvingSymlinksInPath(), in: root.resolvingSymlinksInPath()),
                (try? ReviewSafety.identity(at: original)) == nil,
                try ReviewSafety.identity(at: recovery) == identity
            else {
                throw CleanupError.message(String(localized: "The recovery path changed. Check Trash in Finder."))
            }
            try FileManager.default.moveItem(at: recovery, to: original)
            updated.restored = true
            updated.restoredAt = Date()
            try await store.saveActivity(updated)
        } catch {
            updated.error = error.localizedDescription
            if !updated.restored { updated.restoreStartedAt = nil }
            try? await store.saveActivity(updated)
            throw error
        }
    }
    private func recoveryURL(_ output: URL, bookmark: Data?) throws -> URL {
        guard let bookmark else { return output }
        var stale = false
        let recovery = try URL(
            resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        _ = recovery.startAccessingSecurityScopedResource()
        return recovery
    }

}

/// The only path to the user's real Trash. Test processes must inject a
/// fixture trash; this refuses to run when XCTest is loaded.
public struct FileSystemTrashProvider: TrashService {
    public init() {}
    public func trashItem(at url: URL) throws -> URL? {
        guard NSClassFromString("XCTestCase") == nil else {
            throw CocoaError(.featureUnsupported, userInfo: [NSFilePathErrorKey: url.path])
        }
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
}
