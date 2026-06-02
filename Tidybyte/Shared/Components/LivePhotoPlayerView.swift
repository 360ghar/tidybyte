import SwiftUI
import PhotosUI

/// SwiftUI bridge to `PHLivePhotoView` so callers can drop motion playback of a
/// Live Photo into any view tree. Loads the `PHLivePhoto` representation
/// asynchronously via `PhotoLibraryService.loadLivePhoto` and auto-plays once
/// the player is bound.
///
/// - Long-press to replay (the default `PHLivePhotoView` gesture).
/// - On disappear the view's live photo reference is nilled so off-screen
///   pages in a `TabView` pager do not pin memory.
struct LivePhotoPlayerView: UIViewRepresentable {
    let assetId: String
    let photoService: PhotoLibraryService
    var targetSize: CGSize = CGSize(width: 1200, height: 1200)
    var autoPlay: Bool = true
    var onPlaybackStart: (() -> Void)? = nil
    var onPlaybackEnd: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackStart: onPlaybackStart, onPlaybackEnd: onPlaybackEnd)
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        context.coordinator.onPlaybackStart = onPlaybackStart
        context.coordinator.onPlaybackEnd = onPlaybackEnd

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
                if shouldAutoPlay, livePhoto != nil, !coordinator.hasAutoPlayed {
                    coordinator.hasAutoPlayed = true
                    view.startPlayback(with: .full)
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: PHLivePhotoView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        uiView.livePhoto = nil
    }

    @MainActor
    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var loadedAssetId: String?
        var isLoading = false
        var hasAutoPlayed = false
        var loadTask: Task<Void, Never>?
        var onPlaybackStart: (() -> Void)?
        var onPlaybackEnd: (() -> Void)?

        init(
            onPlaybackStart: (() -> Void)?,
            onPlaybackEnd: (() -> Void)?
        ) {
            self.onPlaybackStart = onPlaybackStart
            self.onPlaybackEnd = onPlaybackEnd
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            onPlaybackStart?()
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            onPlaybackEnd?()
        }
    }
}
