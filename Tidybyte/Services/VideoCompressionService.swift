import AVFoundation
import Photos
import UIKit

struct CompressionPreset: Identifiable, Sendable {
    let id: String
    let label: String
    let preset: String
    let description: String

    static let presets: [CompressionPreset] = [
        CompressionPreset(id: "1080p", label: "1080p HD", preset: AVAssetExportPreset1920x1080, description: "Good quality, moderate savings"),
        CompressionPreset(id: "720p", label: "720p", preset: AVAssetExportPreset1280x720, description: "Decent quality, major savings"),
        CompressionPreset(id: "480p", label: "480p", preset: AVAssetExportPreset640x480, description: "Lower quality, maximum savings")
    ]

    /// Longest-edge target (in pixels) of the export preset: 1080p exports at
    /// 1920×1080, 720p at 1280×720, 480p at 640×480.
    var targetLongestEdge: Int {
        switch id {
        case "1080p": return 1920
        case "720p": return 1280
        default: return 640
        }
    }
}

struct CompressionResult: Sendable {
    let originalSize: Int64
    let compressedSize: Int64
    let replacementAssetIdentifier: String?
    /// True when compression would not have saved space, so the original was
    /// left untouched and no replacement was created.
    let skipped: Bool
}

/// Outcome counts for one compression batch, surfaced after the loop so the UI
/// can present a single summary (rather than an alert popping per failed item
/// mid-batch — COMP-11).
struct CompressionBatchSummary: Sendable, Equatable {
    let completed: Int
    let failed: Int
    let skipped: Int
    let cancelled: Bool
}

enum CompressionState: Sendable {
    case waiting
    case exporting(Float)
    case completed(savedBytes: Int64)
    /// The item was intentionally left untouched (no savings, unknown size,
    /// or already compressed previously) and stays in the list so the user
    /// can see why (COMP-04, COMP-07, COMP-16).
    case keptOriginal(reason: String)
    case failed(String)
}

/// Deterministic batch order: descending file size (matching the on-screen
/// sorted list), ties broken by local identifier. `Set` iteration alone is
/// nondeterministic, which made per-item progress flicker between runs
/// (COMP-12).
func sortedBatchIds(selected: Set<String>, fileSizes: [String: Int64]) -> [String] {
    selected.sorted { lhs, rhs in
        let lhsSize = fileSizes[lhs] ?? 0
        let rhsSize = fileSizes[rhs] ?? 0
        if lhsSize != rhsSize { return lhsSize > rhsSize }
        return lhs < rhs
    }
}

actor VideoCompressionService {
    private let photoService: PhotoLibraryService

    init(photoService: PhotoLibraryService) {
        self.photoService = photoService
    }

    // MARK: - Preset Selection

    /// Picks the export preset for an asset without ever upscaling (COMP-10):
    /// when the source's longest edge is smaller than the selected preset's
    /// target, falls back to the largest preset that still fits — down to the
    /// smallest (480p) for sub-640p sources. Exporting with a preset larger
    /// than the source both wastes space and can fail outright on sub-1080p
    /// sources, which was the default first-run experience.
    static func effectivePreset(for asset: AssetSummary, selected: CompressionPreset) -> CompressionPreset {
        let longestEdge = max(asset.pixelWidth, asset.pixelHeight)
        guard let selectedRank = CompressionPreset.presets.firstIndex(where: { $0.id == selected.id }) else {
            // Unknown/custom preset — the caller chose it explicitly.
            return selected
        }
        // `presets` is ordered largest → smallest; walk from the selected one
        // downward in size until a target fits the source.
        for rank in selectedRank..<CompressionPreset.presets.count {
            let candidate = CompressionPreset.presets[rank]
            if longestEdge >= candidate.targetLongestEdge {
                return candidate
            }
        }
        // Source smaller than every preset (or dimensions unknown): fall back
        // to the smallest preset rather than failing the export.
        return CompressionPreset.presets[CompressionPreset.presets.count - 1]
    }

    // MARK: - Compress Video

    func compressVideo(
        assetId: String,
        preset: CompressionPreset,
        onSaveWillCommit: (@MainActor @Sendable () -> Void)? = nil,
        onReplacementSaved: (@MainActor @Sendable (String, Int64) -> Void)? = nil,
        onProgress: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws -> CompressionResult {
        guard let phAsset = photoService.getPHAsset(for: assetId) else {
            throw CompressionError.assetNotFound
        }

        let originalSize = getFileSize(for: phAsset)
        guard originalSize > 0 else {
            // iCloud-only (or KVC-unreadable) assets report 0 bytes. Compressing
            // them would make the "does this save space?" check meaningless and
            // could delete a large original in exchange for a 0-byte history
            // record — skip instead (COMP-07).
            throw CompressionError.sizeUnknown
        }

        guard let avAsset = try await loadAVAsset(from: phAsset)?.value else {
            throw CompressionError.videoLoadTimedOut
        }

        // Export to a temp file; guarantee it is removed on every exit path.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset.preset) else {
            throw CompressionError.exportSessionCreationFailed
        }

        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Poll progress on a background-priority task that is always cancelled on scope exit.
        // AVAssetExportSession isn't Sendable, but reading `.progress` while the export
        // runs is the documented, thread-safe polling pattern (pre-iOS 18). Box it so the
        // capture across the isolation boundary is explicit rather than an unchecked leak.
        let sessionBox = UncheckedSendableBox(exportSession)
        let progressTask = Task(priority: .utility) {
            var lastSent: Float = -1
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let p = sessionBox.value.progress
                // Guard: only hop to the main actor when progress moved
                // meaningfully (or finished) — every tick used to do a
                // firstIndex + @Observable publish, churning the main thread
                // for minutes during long encodes.
                if abs(p - lastSent) >= 0.02 || p >= 1.0 {
                    lastSent = p
                    await onProgress(p)
                }
            }
        }
        defer { progressTask.cancel() }

        // D4: task cancellation now actually stops the in-flight encode —
        // previously `cancelExport()` was never called, so "Cancel" let the
        // export run to completion (minutes for long videos) before the batch
        // loop noticed. `cancelExport` is documented thread-safe and is the
        // intended cross-thread stop.
        try await withTaskCancellationHandler {
            await exportSession.export()
        } onCancel: {
            exportSession.cancelExport()
        }

        guard exportSession.status == .completed else {
            // A cancelled export surfaces as a failed status with no error —
            // map it to the typed cancelled case so the batch summary counts
            // it correctly instead of reporting an export failure (D4).
            if Task.isCancelled || exportSession.status == .cancelled {
                throw CompressionError.cancelled
            }
            throw CompressionError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        }

        // Verify the exported file exists and is non-empty before trusting it.
        let compressedSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            compressedSize = (attrs[.size] as? Int64) ?? 0
        } catch {
            throw CompressionError.fileSizeReadFailed
        }
        guard compressedSize > 0 else {
            throw CompressionError.exportFailed("Exported file was empty.")
        }

        // Respect batch cancellation: once the user cancels, stop before
        // replacing anything so no half-finished swap happens (COMP-08).
        guard !Task.isCancelled else {
            throw CompressionError.cancelled
        }

        // If compression wouldn't actually save space, keep the original untouched.
        guard compressedSize < originalSize else {
            AppLog.compression.info("No savings compressing \(assetId, privacy: .public); keeping original")
            return CompressionResult(
                originalSize: originalSize,
                compressedSize: originalSize,
                replacementAssetIdentifier: nil,
                skipped: true
            )
        }

        // Capture album membership before deleting the original so we can restore it.
        let albumIdentifiers = await photoService.userAlbumIdentifiers(containing: assetId)

        // Save the compressed video, preserving the original's
        // date/location/favorite/hidden state. Burst membership cannot be
        // carried over — there is no creation-request API for it (COMP-17).
        //
        // D1: tell the journal a library write is about to begin. This is the
        // last moment the row can be written before a copy could exist without
        // its id being recorded — reconcile needs it to tell a crash here apart
        // from a crash during the export (which strands nothing).
        await onSaveWillCommit?()
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            request?.creationDate = phAsset.creationDate
            request?.location = phAsset.location
            request?.isFavorite = phAsset.isFavorite
            request?.isHidden = phAsset.isHidden
            placeholder = request?.placeholderForCreatedAsset
        }

        guard let replacementId = placeholder?.localIdentifier else {
            throw CompressionError.exportFailed("Failed to save compressed video to library.")
        }
        // D1: report the durable new copy to the journal immediately, with the
        // real exported size so the journal never has to guess at 0.
        await onReplacementSaved?(replacementId, compressedSize)

        // A cancel that landed after the replacement commit must not strand a
        // duplicate: roll the just-saved copy back and report cancellation so
        // the batch loop resets the row instead of recording a failure. The
        // pending journal row still names the replacement, so if this rollback
        // fails reconcile retries the removal on the next load.
        if Task.isCancelled {
            _ = try? await photoService.deleteAssets(identifiers: [replacementId])
            throw CompressionError.cancelled
        }

        // Restore album membership on the replacement (best effort).
        for albumId in albumIdentifiers {
            do {
                try await photoService.addToAlbum(assetIdentifiers: [replacementId], albumIdentifier: albumId)
            } catch {
                AppLog.photo.error("Failed to restore album \(albumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Delete the original only after confirming the replacement exists. If
        // deletion fails, roll the replacement back so we don't leave a
        // duplicate behind (COMP-02).
        var originalDeleteUnconfirmed = false
        do {
            let deleted = try await photoService.deleteAssets(identifiers: [assetId])
            // SHARED-01: deleteAssets reports success as a SUBSET of its input —
            // the per-identifier fallback returns a partial (or empty) set
            // without throwing when it is cancelled mid-retry. An unconfirmed
            // delete means the original is still in the library, so the swap
            // must not be reported as done (that would credit savings for a
            // duplicate and hide the leftover from the journal).
            originalDeleteUnconfirmed = !deleted.contains(assetId)
        } catch {
            originalDeleteUnconfirmed = true
        }
        if originalDeleteUnconfirmed {
            var rollbackSucceeded = false
            do {
                let rolledBack = try await photoService.deleteAssets(identifiers: [replacementId])
                rollbackSucceeded = rolledBack.contains(replacementId)
            } catch {
                rollbackSucceeded = false
            }
            // A cancelled delete left the library as we found it — report a
            // cancellation so the batch loop can reset the row instead of
            // claiming a failure the user did not cause.
            if Task.isCancelled {
                throw CompressionError.cancelled
            }
            throw CompressionError.originalDeletionFailed(rollbackSucceeded: rollbackSucceeded)
        }

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: compressedSize,
            replacementAssetIdentifier: replacementId,
            skipped: false
        )
    }

    // MARK: - Helpers

    /// Loads the asset's `AVAsset`, bounded by the same 20s timeout +
    /// cancellation pattern as `PhotoLibraryService.requestPlayerItem` so a
    /// stalled iCloud download cannot hang the batch in `.exporting(0)`
    /// forever (COMP-03). Returns `nil` on timeout or request failure; the
    /// caller turns that into a clear error message.
    private func loadAVAsset(from phAsset: PHAsset) async -> UncheckedSendableBox<AVAsset>? {
        await withCheckedContinuation { continuation in
            let resumer = ContinuationResumer<UncheckedSendableBox<AVAsset>?>(continuation)

            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            // Wire the timeout + cleanup hook BEFORE issuing the request so a
            // synchronously-delivered callback still cancels the timeout Task
            // (otherwise it lingers, orphaned, for the full timeout).
            let manager = PHImageManager.default()
            var requestID: PHImageRequestID = PHInvalidImageRequestID
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(20))
                resumer.resume(nil)
            }
            resumer.onResume = {
                manager.cancelImageRequest(requestID)
                timeoutTask.cancel()
            }

            requestID = manager.requestAVAsset(
                forVideo: phAsset,
                options: options
            ) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] {
                    AppLog.compression.error("Video load request failed: \(String(describing: error), privacy: .public)")
                }
                resumer.resume(avAsset.map(UncheckedSendableBox.init))
            }
        }
    }

    private func getFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        var total: Int64 = 0
        for resource in resources {
            if resource.responds(to: NSSelectorFromString("fileSize")),
               let size = resource.value(forKey: "fileSize") as? Int64 {
                total += size
            }
        }
        return total
    }
}

enum CompressionError: LocalizedError {
    case assetNotFound
    case videoLoadTimedOut
    case sizeUnknown
    case cancelled
    case exportSessionCreationFailed
    case exportFailed(String)
    case fileSizeReadFailed
    case originalDeletionFailed(rollbackSucceeded: Bool)

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Video not found."
        case .videoLoadTimedOut: "Couldn't load the video (it may still be in iCloud). Please try again."
        case .sizeUnknown: "Video size unknown (iCloud-only) — skipped."
        case .cancelled: "Cancelled."
        case .exportSessionCreationFailed: "Failed to create export session."
        case .exportFailed(let msg): "Export failed: \(msg)"
        case .fileSizeReadFailed: "Failed to read file size."
        case .originalDeletionFailed(let rollbackSucceeded):
            if rollbackSucceeded {
                "Compressed copy saved, but the original couldn't be deleted. We removed the new copy to avoid a duplicate."
            } else {
                "Compressed copy saved, but the original couldn't be deleted, and the new copy couldn't be removed either. Check your library for a duplicate."
            }
        }
    }
}
