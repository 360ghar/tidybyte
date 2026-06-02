import SwiftUI

struct AlbumPickerSheet: View {
    let photoService: PhotoLibraryService
    let onAlbumSelected: (String) async -> Bool
    let onSkip: () -> Void

    @State private var albums: [AlbumInfo] = []
    @State private var isLoading = true
    @State private var showNewAlbumField = false
    @State private var newAlbumName = ""
    @State private var isCreatingAlbum = false
    @State private var errorMessage: String?
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
                        albums = await photoService.fetchUserAlbums()
                    }
                }
            }
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            albums = await photoService.fetchUserAlbums()
            isLoading = false
        }
        .alert("Album Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
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
            .disabled(newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty || isCreatingAlbum)

            Button {
                showNewAlbumField = false
                newAlbumName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
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
    }

    // MARK: - Actions

    private func selectAlbum(_ album: AlbumInfo) {
        Task {
            let didSelect = await onAlbumSelected(album.id)
            guard didSelect else { return }
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
            let didSelect = await onAlbumSelected(albumId)
            guard didSelect else { return }
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

struct AsyncAlbumThumbnail: View {
    let assetId: String?
    let photoService: PhotoLibraryService
    @State private var image: UIImage?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if hasLoaded {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "photo.on.rectangle")
                            .foregroundStyle(.secondary)
                    }
            } else {
                SkeletonView(cornerRadius: 0)
            }
        }
        .task(id: assetId) {
            image = nil
            hasLoaded = false
            guard let assetId else {
                hasLoaded = true
                return
            }

            if let cached = await ImageCache.shared.image(for: assetId) {
                image = cached
                hasLoaded = true
                return
            }

            let loaded = await photoService.loadThumbnail(for: assetId, size: CGSize(width: 200, height: 200))
            guard !Task.isCancelled else { return }
            if let loaded {
                await ImageCache.shared.setImage(loaded, for: assetId)
            }
            image = loaded
            hasLoaded = true
        }
    }
}
