import SwiftUI

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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading albums…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .navigationTitle("Select Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            albums = await photoService.fetchUserAlbums()
            isLoading = false
        }
    }
}
