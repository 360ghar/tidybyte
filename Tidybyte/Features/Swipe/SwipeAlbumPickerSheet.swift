import SwiftUI
import UIKit

/// Album picker for the Swipe tab's "Specific Album" filter.
///
/// Loads its album list inside the sheet (`.task`) rather than relying on
/// parent state set just before presentation — a `.sheet(isPresented:)` content
/// closure isn't a dependency of the parent body, so pre-set parent state isn't
/// reliably reflected and the list rendered empty. Owning the data here (the
/// same pattern as `AlbumPickerSheet`) fixes that and lets us show explicit
/// loading and empty states.
struct SwipeAlbumPickerSheet: View {
    let photoService: PhotoLibraryService
    /// Called with the chosen album's local identifier. The sheet dismisses
    /// itself after; the caller starts the swipe session on dismissal so the
    /// navigation push isn't dropped by the simultaneous sheet dismissal.
    let onSelect: (String) -> Void

    @State private var albums: [AlbumInfo] = []
    @State private var isLoading = true
    /// Why `albums` is empty, when the cause is photo access rather than "this
    /// library has no user albums". This sheet includes smart albums, which stay
    /// readable under limited access and are filtered to the shared selection, so
    /// a limited user with photos normally gets a non-empty list. When it is
    /// still empty the reason resolves by census: nothing shared at all, or —
    /// if the visible photos contributed nothing — the missing user albums.
    @State private var emptyReason: AlbumListEmptyReason?
    @Environment(\.dismiss) private var dismiss
    /// Drives the reload on a library change. The sheet is presented from inside
    /// the app's hierarchy, so it inherits this monitor; reading `generation` in
    /// `.task(id:)` is what makes an edit made elsewhere (a delete in another
    /// tab, an edit in Photos) refresh the list while the sheet is up.
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading albums…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let reason = emptyReason {
                    ScrollView {
                        PhotoRecoveryCard(presentation: reason.recovery) { action in
                            switch action {
                            case .retry:
                                Task { await loadAlbums() }
                            case .addPhotos, .openSettings:
                                PhotoRecoveryPresentation.Action.perform(action)
                            }
                        }
                        .padding(.vertical, Spacing.xl)
                    }
                } else if albums.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.stack",
                        title: "No Albums",
                        message: "No albums with photos were found.",
                        iconColor: .teal
                    )
                } else {
                    List(albums) { album in
                        Button {
                            onSelect(album.id)
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.md) {
                                AsyncAlbumThumbnail(assetId: album.thumbnailAssetId, photoService: photoService)
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(album.title)
                                        .font(.body)
                                    Text("\(album.count) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .localizedNavigationTitle("Select Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: libraryMonitor.generation) { await loadAlbums() }
        // Not the scene-phase environment value: SwiftUI freezes a sheet's
        // environment at presentation time, so later phase changes never reach
        // this content and "go to Settings, then come back" left the card
        // untouched. The UIKit activation notification does arrive.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard emptyReason != nil else { return }
            Task { await loadAlbums() }
        }
        // Fires when the system limited-library picker closes, which is the other
        // way out of the card and not tied to a scene activation.
        .onReceive(NotificationCenter.default.publisher(for: .photoLibrarySelectionDidChange)) { _ in
            guard emptyReason != nil else { return }
            Task { await loadAlbums() }
        }
    }

    /// One fetch + one census, shared by the initial load, the card's Try Again,
    /// and the two automatic reloads.
    private func loadAlbums() async {
        // Only the first load gets the full-screen spinner: `isLoading` starts
        // `true` and is cleared below, and nothing re-arms it. Re-arming it on
        // "the list is empty" would blank the empty state ("No Albums") on every
        // foreground, which is the state this sheet exists to show.
        let loaded = await AlbumSheetLoader.load(photoService: photoService, editableOnly: false)
        albums = loaded.albums
        emptyReason = loaded.emptyReason
        isLoading = false
    }
}
