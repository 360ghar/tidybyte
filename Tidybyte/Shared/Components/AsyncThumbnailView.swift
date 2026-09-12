import SwiftUI

struct AsyncThumbnailView: View {
    let assetId: String
    let photoService: PhotoLibraryService
    var targetSize: CGSize = CGSize(width: 200, height: 200)

    @State private var image: UIImage?
    @State private var hasLoaded = false
    /// The id the current image state describes (E3).
    @State private var loadedAssetId: String?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else if hasLoaded {
                Rectangle()
                    .fill(Color.cardSurface)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
            } else {
                SkeletonView(cornerRadius: 0)
            }
        }
        .task(id: assetId) {
            // E3: only reset when the asset actually changed — re-running for
            // the same id used to flash the skeleton for one actor-hop before
            // the cache hit landed.
            guard assetId != loadedAssetId else { return }
            image = nil
            hasLoaded = false

            // E4: consult the sharp key first, then the degraded one. A cached
            // soft placeholder no longer blocks a sharp re-fetch for the whole
            // session (residual SHARED-05).
            var showingDegraded = false
            if let cached = await ImageCache.shared.image(for: assetId) {
                image = cached
                hasLoaded = true
                loadedAssetId = assetId
                return
            }
            let degradedKey = "\(assetId)#degraded"
            if let cached = await ImageCache.shared.image(for: degradedKey) {
                image = cached
                hasLoaded = true
                showingDegraded = true
                loadedAssetId = assetId
            }

            let (loaded, isDegraded) = await photoService.loadThumbnailWithQuality(for: assetId, size: targetSize)
            guard !Task.isCancelled else { return }
            if let loaded {
                if isDegraded {
                    // File the soft placeholder under the degraded key; never
                    // overwrite something sharper we're already showing.
                    if !showingDegraded {
                        await ImageCache.shared.setImage(loaded, for: degradedKey)
                        withAnimation(.easeIn(duration: 0.2)) { image = loaded }
                    }
                } else {
                    await ImageCache.shared.setImage(loaded, for: assetId)
                    // The soft placeholder is superseded.
                    await ImageCache.shared.removeImage(for: degradedKey)
                    withAnimation(.easeIn(duration: 0.2)) { image = loaded }
                }
            }
            hasLoaded = true
            loadedAssetId = assetId
        }
    }
}
