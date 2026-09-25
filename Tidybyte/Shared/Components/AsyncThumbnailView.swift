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
            let sharpKey = ImageCache.key(for: assetId, size: targetSize)
            if let cached = await ImageCache.shared.image(for: sharpKey) {
                guard !Task.isCancelled else { return }
                image = cached
                hasLoaded = true
                loadedAssetId = assetId
                return
            }
            let degradedKey = "\(sharpKey)#degraded"
            if let cached = await ImageCache.shared.image(for: degradedKey) {
                guard !Task.isCancelled else { return }
                image = cached
                hasLoaded = true
                showingDegraded = true
                loadedAssetId = assetId
            }

            // E5: an edit of THIS asset can land while the load is in flight,
            // which moves its cache stamp. Those bytes are pre-edit, so the
            // store refuses them — and showing them while pinning
            // `loadedAssetId` would leave the edited image unseen for as long
            // as this view lives. Retry with a fresh stamp instead. The stamp is
            // per-asset, so an edit of a different asset neither refuses this
            // store nor costs a retry.
            let maxAttempts = 3
            for _ in 1...maxAttempts {
                let stamp = await ImageCache.shared.stamp(for: assetId)
                let (loaded, isDegraded) = await photoService.loadThumbnailWithQuality(for: assetId, size: targetSize)
                guard !Task.isCancelled else { return }
                guard let loaded else { break }
                if isDegraded {
                    // File the soft placeholder under the degraded key; never
                    // overwrite something sharper we're already showing. A soft
                    // preview is shown even if its store is refused: the sharp
                    // pass below supersedes it either way.
                    if !showingDegraded {
                        await ImageCache.shared.setImage(loaded, for: degradedKey, assetId: assetId, ifStamp: stamp)
                        withAnimation(.easeIn(duration: 0.2)) { image = loaded }
                        showingDegraded = true
                    }
                    break
                }
                if await ImageCache.shared.setImage(loaded, for: sharpKey, assetId: assetId, ifStamp: stamp) {
                    // The soft placeholder is superseded.
                    await ImageCache.shared.removeImage(for: degradedKey)
                    withAnimation(.easeIn(duration: 0.2)) { image = loaded }
                    break
                }
                // Refused: edited (or the cache flushed) mid-load, so these
                // bytes are stale. Loop and reload rather than displaying them,
                // unless this was the last attempt — a bound keeps a library
                // that is changing under us from spinning here.
            }
            hasLoaded = true
            loadedAssetId = assetId
        }
    }
}

/// Bare heart drawn on a photo that is a favorite, so it is never deleted by
/// accident. No tile or pill behind it: a tight dark shadow keeps it legible
/// on light photos.
struct FavoriteMark: View {
    var font: Font = .caption

    var body: some View {
        Image(systemName: "heart.fill")
            .font(font)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
            .accessibilityLabel("Favorite")
    }
}
