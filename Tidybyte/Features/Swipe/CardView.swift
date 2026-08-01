import SwiftUI
import AVFoundation
import AVKit

struct CardView: View {
    let asset: AssetSummary
    let photoService: PhotoLibraryService
    let isTopCard: Bool

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    /// The in-flight player-item load, tracked so `stopPlayback` can cancel it:
    /// without cancellation, a load started on the top card would still create
    /// a playing player after the card was swiped away (SWIPE-07).
    @State private var loadTask: Task<Void, Never>?

    var dragOffset: CGSize = .zero

    private var deleteOpacity: Double {
        guard isTopCard else { return 0 }
        return min(max(-Double(dragOffset.width) / 150.0, 0), 1.0)
    }

    private var keepOpacity: Double {
        guard isTopCard else { return 0 }
        return min(max(Double(dragOffset.width) / 150.0, 0), 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .transition(.opacity)
                } else {
                    SkeletonView(cornerRadius: 0)
                }

                // Video playback (SWIPE-07): a play affordance on the top card
                // loads the player item and plays inline; playback stops when the
                // card is dragged or leaves the deck.
                if asset.mediaType == .video, isTopCard {
                    if let player {
                        VideoPlayer(player: player)
                            .accessibilityLabel("Video preview playing")
                    } else {
                        Button {
                            startPlayback()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.4), radius: 6)
                        }
                        .accessibilityLabel("Play video")
                    }
                }

                // Gradient overlay at bottom
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }

                // Metadata overlay
                VStack {
                    // Top badges
                    HStack(spacing: Spacing.sm) {
                        if asset.isLivePhoto {
                            BadgeView(text: "LIVE", icon: "livephoto", color: .yellow)
                        }
                        if !asset.isLocallyAvailable {
                            BadgeView(text: "iCloud", icon: "icloud.and.arrow.down", color: .blue)
                        }
                        Spacer()
                    }
                    .padding(.top, Spacing.lg)
                    .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Bottom info
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            if asset.mediaType == .video {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                    Text(asset.formattedDuration)
                                        .font(.caption.monospacedDigit())
                                }
                                .foregroundStyle(.white)
                            }

                            if let date = asset.creationDate {
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }

                        Spacer()

                        Text(asset.formattedFileSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }

                // Swipe indicators
                if isTopCard {
                    VStack {
                        HStack {
                            Spacer()
                            Label("DELETE", systemImage: "trash.fill")
                                .font(.title.bold())
                                .foregroundStyle(.red)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.small)
                                        .stroke(.red, lineWidth: 3)
                                )
                                .rotationEffect(.degrees(15))
                                .padding(.trailing, Spacing.xxl)
                                .padding(.top, 40)
                        }
                        Spacer()
                    }
                    .opacity(deleteOpacity)

                    VStack {
                        HStack {
                            Label("KEEP", systemImage: "checkmark")
                                .font(.title.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.small)
                                        .stroke(.green, lineWidth: 3)
                                )
                                .rotationEffect(.degrees(-15))
                                .padding(.leading, Spacing.xxl)
                                .padding(.top, 40)
                            Spacer()
                        }
                        Spacer()
                    }
                    .opacity(keepOpacity)

                    Rectangle()
                        .fill(.red.opacity(deleteOpacity * 0.15))
                    Rectangle()
                        .fill(.green.opacity(keepOpacity * 0.15))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .cardShadow()
        }
        .task {
            await loadImage()
        }
        .onDisappear {
            // The card left the deck — tear down playback so the player item
            // and its buffers aren't retained (SWIPE-07).
            stopPlayback()
        }
        .onChange(of: isTopCard) { _, newValue in
            // The card stopped leading the deck (swiped or advanced) — tear
            // down playback AND cancel any in-flight load so a load started on
            // the top card can't finish into a playing player on an off-top
            // card (SWIPE-07).
            if !newValue {
                stopPlayback()
            }
        }
        .onChange(of: dragOffset) { _, newValue in
            // The user started dragging the card — stop playback so the video
            // doesn't keep playing under the swipe (SWIPE-07).
            if newValue != .zero {
                stopPlayback()
            }
        }
    }

    private func loadImage() async {
        // Full-screen pixel size matches the swipe session's prefetch target so the
        // cached image is reused instead of re-fetched. Avoids deprecated UIScreen.main.
        let loaded = await photoService.loadImage(for: asset.id, targetSize: ScreenMetrics.pixelSize)
        withAnimation(.easeIn(duration: 0.3)) {
            image = loaded
        }
    }

    private func startPlayback() {
        guard player == nil, isTopCard else { return }
        loadTask?.cancel()
        loadTask = Task {
            guard let box = await photoService.loadPlayerItem(for: asset.id) else { return }
            // The card may have been swiped away while the item was loading;
            // the isTopCard/drag/disappear teardowns above cancel this task —
            // respect that instead of creating a playing player off-screen.
            guard !Task.isCancelled else { return }
            let newPlayer = AVPlayer(playerItem: box.value)
            player = newPlayer
            newPlayer.play()
        }
    }

    private func stopPlayback() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player = nil
    }
}

struct BadgeView: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.7))
        .clipShape(Capsule())
    }
}
