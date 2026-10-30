import CryptoKit
import Foundation
import ImageIO
@preconcurrency import os
import Photos
import UniformTypeIdentifiers

public protocol PhotoMutationService: Sendable {
    func previewURL(for item: ReviewItem) async throws -> URL
    func localURLs(for item: ReviewItem) async throws -> [URL]
    func export(_ item: ReviewItem, to folder: URL) async throws -> [URL]
    func replace(_ item: ReviewItem, with url: URL, kind: MediaKind) async throws -> String
    func delete(_ item: ReviewItem) async throws
}

public struct PhotosReplacementError: LocalizedError, Sendable {
    public let replacementID: String
    public let reason: String
    public var errorDescription: String? { reason }
}

/// A resource transfer is shared only by Photos callbacks and cancellation.
private final class PhotoTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private var hash = SHA256()
    private var bytes: Int64 = 0
    private var handle: FileHandle?
    private var failure: Error?
    private var request: PHAssetResourceDataRequestID?
    private var cancelled = false

    init(output: URL?) throws {
        if let output {
            handle = try FileHandle(forWritingTo: output)
        }
    }
    func receive(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled, failure == nil else { return }
        do {
            try handle?.write(contentsOf: data)
            hash.update(data: data)
            bytes += Int64(data.count)
        } catch { failure = error }
    }
    func setRequest(_ id: PHAssetResourceDataRequestID) {
        lock.lock()
        request = id
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let id = request
        lock.unlock()
        if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
    }
    func finish() throws -> (Int64, String) {
        lock.lock()
        defer { lock.unlock() }
        try handle?.synchronize()
        try handle?.close()
        handle = nil
        if cancelled { throw CancellationError() }
        if let failure { throw failure }
        return (bytes, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

public actor PhotoLibraryService: PhotoMutationService {
    private var exportCache: [String: [URL]] = [:]
    private let cacheRoot: URL
    public init() {
        cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CleanerPreviews-" + UUID().uuidString)
    }

    public func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw CleanupError.message(String(localized: "Photos access was not granted. You can still scan folders."))
        }
    }

    public func scan(progress: @Sendable (CleanupProgress) async -> Void) async throws -> [ReviewItem] {
        try await authorize()
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        let assets = PHAsset.fetchAssets(with: options)
        var result: [ReviewItem] = []
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            guard asset.mediaType == .image || asset.mediaType == .video else { continue }
            let resources = PHAssetResource.assetResources(for: asset)
            var item = ReviewItem(
                id: "photos:" + asset.localIdentifier, source: .photos(asset.localIdentifier),
                name: resources.first?.originalFilename ?? String(localized: "Photos asset"),
                kind: asset.mediaType == .video ? .video : .image, bytes: 0)
            item.createdAt = asset.creationDate
            item.modifiedAt = asset.modificationDate
            item.facts.width = asset.pixelWidth
            item.facts.height = asset.pixelHeight
            item.facts.duration = asset.mediaType == .video ? asset.duration : nil
            item.facts.isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            item.facts.isScreenRecording = asset.mediaSubtypes.contains(.videoScreenRecording)
            item.facts.burstIdentifier = asset.burstIdentifier
            for resource in resources {
                var descriptor = PhotoResource(
                    name: resource.originalFilename, type: resource.type.rawValue,
                    uniformType: resource.uniformTypeIdentifier)
                do {
                    let digest = try await Self.read(resource, output: nil)
                    descriptor.bytes = digest.0
                    descriptor.hash = digest.1
                    item.bytes += digest.0
                } catch is CancellationError { throw CancellationError() } catch { item.isDownloaded = false }
                item.resources.append(descriptor)
            }
            result.append(item)
            await progress(
                CleanupProgress(
                    String(localized: "Reading Photos resources"), completed: index + 1,
                    total: assets.count))
        }
        return result
    }

    public func asset(_ item: ReviewItem) throws -> PHAsset {
        guard let id = item.photoID,
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
            asset.modificationDate == item.modifiedAt
        else {
            throw CleanupError.message(String(localized: "The Photos asset changed. Scan again before making changes."))
        }
        return asset
    }

    public func localURLs(for item: ReviewItem) async throws -> [URL] {
        try Task.checkCancellation()
        _ = try asset(item)
        guard item.isDownloaded else {
            throw CleanupError.message(String(localized: "This asset is not downloaded. Download it in Photos first."))
        }
        if let urls = exportCache[item.reviewKey],
            urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            return urls
        }
        let directory = cacheRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let urls = try await export(item, to: directory)
            exportCache[item.reviewKey] = urls
            return urls
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    public func previewURL(for item: ReviewItem) async throws -> URL {
        let urls = try await localURLs(for: item)
        let desired = item.kind == .video ? [PHAssetResourceType.fullSizeVideo, .video] : [.fullSizePhoto, .photo]
        for type in desired {
            if let index = item.resources.firstIndex(where: { $0.type == type.rawValue }),
                urls.indices.contains(index) {
                return urls[index]
            }
        }
        guard let first = urls.first else { throw CleanupError.message(String(localized: "No preview is available.")) }
        return first
    }

    public func analysisPreview(_ item: ReviewItem, size: Int = 512) async throws -> URL {
        let original = try asset(item)
        // Cancellation-aware like read(): a cancelled caller must not stay
        // suspended until Photos eventually delivers a non-degraded image,
        // and a degraded-then-final double delivery must resume exactly once.
        let pending = PendingPreviewRequest()
        let image: CGImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let options = PHImageRequestOptions()
                options.isNetworkAccessAllowed = false
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .fast
                // Store the continuation BEFORE the request starts so a
                // cancellation racing the callback can always resolve it.
                pending.store(continuation)
                let requestID = PHImageManager.default().requestImage(
                    for: original, targetSize: CGSize(width: size, height: size),
                    contentMode: .aspectFit, options: options
                ) { image, information in
                    if information?[PHImageResultIsDegradedKey] as? Bool == true { return }
                    pending.deliver(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                }
                pending.setRequestID(requestID)
            }
        } onCancel: {
            pending.cancelIfPending()
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let output = cacheRoot.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        guard let writer = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            throw CleanupError.message(String(localized: "Cannot create a preview."))
        }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else {
            throw CleanupError.message(String(localized: "Cannot write preview."))
        }
        return output
    }

    public func releaseAnalysisPreview(_ url: URL) {
        guard url.deletingLastPathComponent() == cacheRoot else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public func export(_ item: ReviewItem, to folder: URL) async throws -> [URL] {
        let current = try asset(item)
        let resources = PHAssetResource.assetResources(for: current)
        guard resources.count == item.resources.count, item.isDownloaded else {
            throw CleanupError.message(String(localized: "Original Photos resources are not available."))
        }
        var urls: [URL] = []
        for (index, resource) in resources.enumerated() {
            try Task.checkCancellation()
            let descriptor = item.resources[index]
            guard descriptor.name == resource.originalFilename, descriptor.type == resource.type.rawValue else {
                throw CleanupError.message(String(localized: "The Photos resource list changed. Scan again."))
            }
            let output = try ReviewSafety.reserveOutput(in: folder, name: resource.originalFilename)
            let digest = try await Self.read(resource, output: output)
            guard digest.0 == descriptor.bytes, digest.1 == descriptor.hash,
                try FingerprintService.fullHash(for: output) == descriptor.hash
            else {
                throw CleanupError.message(
                    String(localized: "Export verification failed. The Photos original was kept."))
            }
            urls.append(output)
        }
        return urls
    }

    public func delete(_ item: ReviewItem) async throws {
        try Task.checkCancellation()
        let original = try asset(item)
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([original] as NSArray) }
    }

    public func replace(_ item: ReviewItem, with url: URL, kind: MediaKind) async throws -> String {
        try Task.checkCancellation()
        let original = try asset(item)
        let placeholder = PhotoReplacementID()
        let albums = PHAssetCollection.fetchAssetCollectionsContaining(original, with: .album, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: kind == .video ? .video : .photo, fileURL: url, options: nil)
            request.creationDate = original.creationDate
            request.location = original.location
            request.isFavorite = original.isFavorite
            request.isHidden = original.isHidden
            if let created = request.placeholderForCreatedAsset {
                placeholder.value = created.localIdentifier
                albums.enumerateObjects { album, _, _ in
                    PHAssetCollectionChangeRequest(for: album)?.addAssets([created] as NSArray)
                }
            }
        }
        guard let id = placeholder.value else {
            throw CleanupError.message(String(localized: "Cannot verify the new Photos asset. The original was kept."))
        }
        do {
            guard let replacement = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
                let resource = PHAssetResource.assetResources(for: replacement).first
            else {
                throw CleanupError.message(
                    String(localized: "Cannot verify the new Photos asset. The original was kept."))
            }
            let digest = try await Self.read(resource, output: nil)
            guard try FingerprintService.fullHash(for: url) == digest.1 else {
                throw CleanupError.message(
                    String(localized: "The Photos import did not verify. Both assets were kept."))
            }
        } catch {
            throw PhotosReplacementError(replacementID: id, reason: error.localizedDescription)
        }
        return id
    }

    public func clearPreviewCache() {
        // This directory contains only exports created by this service, never user originals.
        try? FileManager.default.removeItem(at: cacheRoot)
        exportCache.removeAll()
    }

    /// Resolves the analysisPreview continuation exactly once: the first
    /// final (non-degraded) delivery wins, and task cancellation cancels the
    /// underlying Photos request and resumes the continuation with a
    /// CancellationError instead of leaving the caller suspended forever.
    private final class PendingPreviewRequest: @unchecked Sendable {
        private struct State {
            var requestID: PHImageRequestID = PHInvalidImageRequestID
            var isCancelled = false
            var continuation: CheckedContinuation<CGImage, Error>?
        }

        private let lock = OSAllocatedUnfairLock(initialState: State())

        func store(_ continuation: CheckedContinuation<CGImage, Error>) {
            let alreadyCancelled = lock.withLock { state -> Bool in
                if state.isCancelled { return true }
                state.continuation = continuation
                return false
            }
            if alreadyCancelled {
                continuation.resume(throwing: CancellationError())
            }
        }

        func setRequestID(_ id: PHImageRequestID) {
            lock.withLock { $0.requestID = id }
        }

        func deliver(_ image: CGImage?) {
            let continuation = lock.withLock { state -> CheckedContinuation<CGImage, Error>? in
                let pending = state.continuation
                state.continuation = nil
                return pending
            }
            if let decoded = image {
                continuation?.resume(returning: decoded)
            } else {
                continuation?.resume(throwing: CleanupError.message(
                    String(localized: "Local Photos preview unavailable.")))
            }
        }

        func cancelIfPending() {
            let (requestID, continuation) = lock.withLock { state -> (PHImageRequestID, CheckedContinuation<CGImage, Error>?) in
                state.isCancelled = true
                let pending = state.continuation
                state.continuation = nil
                return (state.requestID, pending)
            }
            if requestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    private static func read(_ resource: PHAssetResource, output: URL?) async throws -> (Int64, String) {
        let transfer = try PhotoTransfer(output: output)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = false
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                    transfer.receive(data)
                } completionHandler: { error in
                    do {
                        let result = try transfer.finish()
                        if let error { throw error }
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
                transfer.setRequest(id)
            }
        } onCancel: {
            transfer.cancel()
        }
    }
}

private final class PhotoReplacementID: @unchecked Sendable {
    // Written in the Photos transaction and read only after its completion.
    var value: String?
}
