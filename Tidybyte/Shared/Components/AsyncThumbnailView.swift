import SwiftUI

struct AsyncThumbnailView: View {
    let assetId: String
    let photoService: PhotoLibraryService
    var targetSize: CGSize = CGSize(width: 200, height: 200)

    @State private var image: UIImage?
    @State private var hasLoaded = false

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
            image = nil
            hasLoaded = false

            if let cached = await ImageCache.shared.image(for: assetId) {
                image = cached
                hasLoaded = true
                return
            }

            let loaded = await photoService.loadThumbnail(for: assetId, size: targetSize)
            guard !Task.isCancelled else { return }
            if let loaded {
                await ImageCache.shared.setImage(loaded, for: assetId)
            }
            withAnimation(.easeIn(duration: 0.2)) {
                image = loaded
            }
            hasLoaded = true
        }
    }
}
