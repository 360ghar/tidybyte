import SwiftUI
import PhotosUI

/// SwiftUI bridge to `PHLivePhotoView` so callers can drop motion playback of a
/// Live Photo into any view tree. Loads the `PHLivePhoto` representation
/// asynchronously via `PhotoLibraryService.loadLivePhoto` and auto-plays once
/// the player is bound.
///
/// - Long-press to replay (the default `PHLivePhotoView` gesture).
/// - Pass `isActive: false` when the page is not the visible one in a pager:
///   the player unloads (nils its live photo, cancels in-flight loads) so
///   off-screen pages do not pin memory (COMP-14). `dismantleUIView` alone
///   never fires for off-screen pages in a `TabView`.
struct LivePhotoPlayerView: UIViewRepresentable {
    let assetId: String
    let photoService: PhotoLibraryService
    var targetSize: CGSize = CGSize(width: 1200, height: 1200)
    var autoPlay: Bool = true
    var isActive: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        // COMP-14: the page went inactive — tear down immediately (a pager
        // keeps adjacent pages alive, so dismantleUIView is never called).
        guard isActive else {
            unload(uiView, coordinator: context.coordinator)
            return
        }

        if context.coordinator.loadedAssetId != assetId {
            context.coordinator.loadedAssetId = assetId
            uiView.livePhoto = nil
            context.coordinator.hasAutoPlayed = false
            context.coordinator.isLoading = true

            let coordinator = context.coordinator
            let service = photoService
            let size = targetSize
            let shouldAutoPlay = autoPlay
            let view = uiView

            coordinator.loadTask?.cancel()
            coordinator.loadTask = Task { @MainActor in
                let livePhoto = await service.loadLivePhoto(for: assetId, targetSize: size)
                guard !Task.isCancelled else { return }
                guard coordinator.loadedAssetId == assetId else { return }
                coordinator.isLoading = false
                view.livePhoto = livePhoto
                if let livePhoto {
                    coordinator.loadedAssetId = assetId
                    if shouldAutoPlay, !coordinator.hasAutoPlayed {
                        coordinator.hasAutoPlayed = true
                        view.startPlayback(with: .full)
                    }
                } else {
                    // Load failed (e.g. iCloud hiccup): clear the marker so the
                    // next update re-tries instead of staying blank (SHARED-06).
                    coordinator.loadedAssetId = nil
                }
            }
        }
    }

    /// Tears down the player: cancels any in-flight load, stops playback, and
    /// nils the `PHLivePhoto` so the page stops pinning the Live Photo's
    /// buffers. Idempotent.
    func unload(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        coordinator.loadTask = nil
        coordinator.loadedAssetId = nil
        coordinator.isLoading = false
        coordinator.hasAutoPlayed = false
        uiView.stopPlayback()
        uiView.livePhoto = nil
    }

    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        uiView.livePhoto = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var loadedAssetId: String?
        var isLoading = false
        var hasAutoPlayed = false
        var loadTask: Task<Void, Never>?
    }
}
