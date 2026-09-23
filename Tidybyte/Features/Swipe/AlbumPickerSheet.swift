import SwiftUI

struct AlbumPickerSheet: View {
    let photoService: PhotoLibraryService
    /// Returns nil on success, or a user-facing error message. Failures are
    /// surfaced HERE, inside the sheet — the session view's error alert sits
    /// behind this presentation and would never be seen (B4).
    let onAlbumSelected: (String) async -> String?
    let onSkip: () -> Void

    @State private var albums: [AlbumInfo] = []
    @State private var isLoading = true
    @State private var showNewAlbumField = false
    @State private var newAlbumName = ""
    @State private var isCreatingAlbum = false
    @State private var errorMessage: String?
    /// True while an album add is in flight: album selection stays disabled so
    /// a second tap can't stack another add behind it (the view model's guard
    /// reports this as a failure message instead of a silent success).
    @State private var isAddingToAlbum = false
    @Environment(\.dismiss) private var dismiss

    private var recentAlbumIds: [String] {
        AppPreferences.recentAlbumIds()
    }

    var recentAlbums: [AlbumInfo] {
        let recentIds = Array(recentAlbumIds.prefix(5))
        return recentIds.compactMap { id in albums.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading albums...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // New Album
                            if showNewAlbumField {
                                newAlbumSection
                            } else {
                                Button {
                                    showNewAlbumField = true
                                } label: {
                                    Label("New Album", systemImage: "plus.rectangle.on.folder")
                                        .font(.headline)
                                }
                                .padding(.horizontal)
                            }

                            // Recent Albums
                            if !recentAlbums.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recent")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(recentAlbums) { album in
                                                albumCard(album)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }

                            // All Albums
                            VStack(alignment: .leading, spacing: 8) {
                                Text("All Albums")
                                    .font(.headline)
                                    .padding(.horizontal)

                                LazyVGrid(columns: ResponsiveGrid.photo(spacing: Spacing.md), spacing: Spacing.md) {
                                    ForEach(albums) { album in
                                        albumGridItem(album)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                    .pullToRefresh {
                        albums = await photoService.fetchUserAlbums(editableOnly: true)
                    }
                }
            }
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel puts the card back on the deck (the sheet's onDismiss
                // cancels the pending keep).
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    // A running add would still file the photo after Cancel.
                    .disabled(isAddingToAlbum || isCreatingAlbum)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Keep Without Album") {
                        onSkip()
                        dismiss()
                    }
                    .disabled(isAddingToAlbum || isCreatingAlbum)
                }
            }
        }
        .task {
            albums = await photoService.fetchUserAlbums(editableOnly: true)
            isLoading = false
        }
        // Non-modal error surface inside the sheet (B4): the session view sits
        // behind this presentation, so the failure must surface here — as a
        // banner rather than a modal, so the album list stays usable.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = errorMessage {
                ToolErrorBanner(
                    message: message,
                    title: "Add to Album",
                    onDismiss: { errorMessage = nil }
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    // MARK: - New Album Section

    private var newAlbumSection: some View {
        HStack {
            TextField("Album name", text: $newAlbumName)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await createAlbum() }
            } label: {
                if isCreatingAlbum {
                    ProgressView()
                } else {
                    Text("Create")
                        .bold()
                }
            }
            .disabled(newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty || isCreatingAlbum || isAddingToAlbum)

            Button {
                showNewAlbumField = false
                newAlbumName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Cancel new album")
        }
        .padding(.horizontal)
    }

    // MARK: - Album Card (Horizontal Recent)

    private func albumCard(_ album: AlbumInfo) -> some View {
        Button {
            selectAlbum(album)
        } label: {
            VStack(spacing: 6) {
                AsyncAlbumThumbnail(assetId: album.thumbnailAssetId, photoService: photoService)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(album.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(width: 112)
            .contentShape(Rectangle())
        }
        .disabled(isAddingToAlbum)
    }

    // MARK: - Album Grid Item

    private func albumGridItem(_ album: AlbumInfo) -> some View {
        Button {
            selectAlbum(album)
        } label: {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        AsyncAlbumThumbnail(assetId: album.thumbnailAssetId, photoService: photoService)
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 2) {
                    Text(album.title)
                        .font(.caption)
                        .lineLimit(1)
                    Text("\(album.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
        .disabled(isAddingToAlbum)
    }

    // MARK: - Actions

    private func selectAlbum(_ album: AlbumInfo) {
        guard !isAddingToAlbum else { return }
        Task {
            isAddingToAlbum = true
            defer { isAddingToAlbum = false }
            if let failure = await onAlbumSelected(album.id) {
                errorMessage = failure
                return
            }
            saveRecentAlbum(album.id)
            dismiss()
        }
    }

    private func createAlbum() async {
        let name = newAlbumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreatingAlbum = true
        defer { isCreatingAlbum = false }

        do {
            let albumId = try await photoService.createAlbum(name: name)
            if let failure = await onAlbumSelected(albumId) {
                errorMessage = failure
                return
            }
            saveRecentAlbum(albumId)
            dismiss()
        } catch {
            errorMessage = "Failed to create album: \(error.localizedDescription)"
        }
    }

    private func saveRecentAlbum(_ id: String) {
        var recents = AppPreferences.recentAlbumIds()
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(5))
        AppPreferences.saveRecentAlbumIds(recents)
    }
}

// MARK: - Async Album Thumbnail

/// Thin wrapper over the shared `AsyncThumbnailView` (same cache, same 200px
/// target) that tolerates a missing thumbnail asset with an album-specific
/// placeholder. Replaces the private copy of the loading logic (de-slop).
struct AsyncAlbumThumbnail: View {
    let assetId: String?
    let photoService: PhotoLibraryService

    var body: some View {
        if let assetId {
            AsyncThumbnailView(assetId: assetId, photoService: photoService)
        } else {
            Rectangle()
                .fill(Color(.systemGray5))
                .overlay {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
