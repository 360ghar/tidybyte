import SwiftUI

struct MediaCleanerView: View {
    @State private var viewModel: MediaCleanerViewModel
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var previewAsset: AssetSummary?
    @State private var pendingDeletion: Set<String> = []
    @State private var showAlbums = false
    @State private var draftAlbums: Set<String> = []

    init(tool: CleanupTool) {
        _viewModel = State(initialValue: MediaCleanerViewModel(tool: tool))
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    LimitedLibraryBanner()
                    if viewModel.tool == .chatMedia {
                        Text("Albums group this media; their names do not verify which app saved it. Deleting removes items from Photos, not from chat storage.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Spacing.lg)
                        Picker("Album", selection: $viewModel.activeAlbumID) {
                            Text("All albums").tag(String?.none)
                            ForEach(viewModel.selectedAlbums) { album in
                                Text(album.title).tag(Optional(album.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    let filterLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
                    filterLayout {
                        if viewModel.tool == .chatMedia {
                            Picker("Media", selection: $viewModel.mediaFilter) {
                                ForEach(LargeFileFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                        }
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        Picker("Sort", selection: $viewModel.sortOrder) {
                            ForEach(LargeFileSortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("mediaSort")
                    }
                    .padding(.horizontal, Spacing.lg)
                    Text("\(viewModel.filteredAssets.count) items · \(MediaCleanerViewModel.sizeLabel(viewModel.filteredAssets))")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.lg)
                    if let error = viewModel.errorMessage {
                        ToolErrorBanner(message: error, title: viewModel.tool.name, onDismiss: { viewModel.errorMessage = nil })
                    }
                    if viewModel.isLoading && viewModel.assets.isEmpty {
                        ProgressView("Loading media").padding(Spacing.xl)
                    } else {
                        if viewModel.filteredAssets.isEmpty {
                            EmptyStateView(icon: viewModel.tool.icon, title: "No matching media",
                                           message: viewModel.tool == .chatMedia ? "Choose albums or change your filters." : "No screen recordings were found.")
                        }
                        LazyVGrid(columns: ResponsiveGrid.photo(), spacing: Spacing.xs) {
                            ForEach(viewModel.filteredAssets) { asset in cell(asset) }
                        }
                        .padding(Spacing.xs)
                    }
                }
            }
            .pullToRefresh { await viewModel.load() }
            if !viewModel.visibleSelectedIDs.isEmpty {
                ActionBarView {
                    Text("\(viewModel.visibleSelectedIDs.count) selected")
                    Spacer()
                    if viewModel.isDeleting { ProgressView() }
                    Button("Delete", role: .destructive) { pendingDeletion = viewModel.visibleSelectedIDs }
                        .disabled(viewModel.isDeleting)
                }
            }
        }
        .navigationTitle(viewModel.tool.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SelectAllToolbarButton(allSelected: viewModel.allVisibleSelected,
                    selectAll: { viewModel.selectedIDs.formUnion(viewModel.filteredAssets.map(\.id)) },
                    deselectAll: { viewModel.selectedIDs.subtract(viewModel.filteredAssets.map(\.id)) })
                    .disabled(viewModel.isLoading || viewModel.isDeleting)
            }
            if viewModel.tool == .chatMedia {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Albums") {
                        draftAlbums = viewModel.albumIDs
                        showAlbums = true
                    }.disabled(viewModel.isLoading || viewModel.isDeleting)
                }
            }
        }
        .task(id: libraryMonitor.generation) { await viewModel.load() }
        .confirmationDialog("Delete \(pendingDeletion.count) items from Photos?", isPresented: Binding(
            get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let ids = pendingDeletion
                pendingDeletion = []
                Task { _ = await viewModel.delete(ids: ids) }
            }
        } message: { Text(CleanupDeletion.recoverableNote) }
        .fullScreenCover(item: $previewAsset) { asset in
            MediaPreviewView(assets: viewModel.filteredAssets,
                startIndex: viewModel.filteredAssets.firstIndex { $0.id == asset.id } ?? 0,
                photoService: .shared, onDelete: { await viewModel.delete(ids: [$0.id]) })
        }
        .sheet(isPresented: $showAlbums) {
            NavigationStack {
                List(viewModel.albums) { album in
                    Toggle(isOn: Binding(get: { draftAlbums.contains(album.id) }, set: { selected in
                        if selected { draftAlbums.insert(album.id) } else { draftAlbums.remove(album.id) }
                    })) {
                        Text("\(album.title) (\(album.count))")
                    }
                }
                .overlay { if viewModel.albums.isEmpty { Text("No accessible user albums.") } }
                .navigationTitle("Chat albums")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAlbums = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let ids = draftAlbums
                            showAlbums = false
                            Task { await viewModel.saveAlbums(ids) }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ asset: AssetSummary) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { previewAsset = asset } label: {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { AsyncThumbnailView(assetId: asset.id, photoService: .shared) }
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text(asset.mediaType == .video ? "\(asset.formattedDuration) · \(asset.displaySize)" : asset.displaySize)
                            .font(.caption2).foregroundStyle(.white)
                            .padding(Spacing.xs).background(.black.opacity(0.7))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(asset.filename ?? "media"), \(asset.displaySize)")
            SelectToggle(isSelected: viewModel.selectedIDs.contains(asset.id), itemName: asset.filename ?? "media") {
                viewModel.selectedIDs.toggle(asset.id)
            }
            .disabled(viewModel.isDeleting)
        }
    }
}
