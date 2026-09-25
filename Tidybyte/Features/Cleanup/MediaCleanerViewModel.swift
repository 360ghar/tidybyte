import SwiftUI

enum ChatAlbumSelection {
    static func isRecognized(_ title: String) -> Bool {
        let normalized = title.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return ["whatsapp", "whatsapp business", "telegram", "signal", "messenger", "viber", "line", "wechat"].contains(normalized)
    }

    static func selectedIDs(in albums: [AlbumInfo], defaults: UserDefaults = .standard) -> Set<String> {
        let available = albums.filter { $0.type == .userAlbum }
        let ids = defaults.stringArray(forKey: AppPreferences.Key.chatAlbumIDs)
            .map(Set.init) ?? Set(available.filter { isRecognized($0.title) }.map(\.id))
        return ids.intersection(available.map(\.id))
    }
}

@Observable
@MainActor
final class MediaCleanerViewModel {
    let tool: CleanupTool
    var assets: [AssetSummary] = [] { didSet { refreshFilter() } }
    var albums: [AlbumInfo] = []
    var albumIDs: Set<String> = []
    var activeAlbumID: String? { didSet { refreshFilter() } }
    var mediaFilter = LargeFileFilter.all { didSet { refreshFilter() } }
    var sortOrder = LargeFileSortOrder.largest { didSet { refreshFilter() } }
    var selectedIDs: Set<String> = [] { didSet { refreshSelection() } }
    var isLoading = false
    var isDeleting = false
    var errorMessage: String?
    private var loadGeneration = 0
    private var membership: [String: Set<String>] = [:] { didSet { refreshFilter() } }
    private(set) var filteredAssets: [AssetSummary] = []
    private var visibleIDs: Set<String> = []
    private(set) var visibleSelectedIDs: Set<String> = []
    private(set) var filteredSizeLabel = Int64(0).formattedFileSize
    private let photoService: PhotoLibraryService

    init(tool: CleanupTool, photoService: PhotoLibraryService = .shared) {
        self.tool = tool
        self.photoService = photoService
    }

    private func refreshFilter() {
        let visible = activeAlbumID.map { id in assets.filter { membership[id, default: []].contains($0.id) } } ?? assets
        filteredAssets = LargeFilesViewModel.computeFilteredAssets(from: visible, threshold: 0, mediaFilter: mediaFilter, sortOrder: sortOrder)
        visibleIDs = Set(filteredAssets.map(\.id))
        filteredSizeLabel = Self.sizeLabel(filteredAssets)
        refreshSelection()
    }

    private func refreshSelection() { visibleSelectedIDs = selectedIDs.intersection(visibleIDs) }
    var allVisibleSelected: Bool { !filteredAssets.isEmpty && visibleSelectedIDs.count == filteredAssets.count }
    var selectedAlbums: [AlbumInfo] { albums.filter { albumIDs.contains($0.id) } }

    static func sizeLabel(_ assets: [AssetSummary]) -> String {
        let bytes = assets.reduce(Int64(0)) { $0 + max(0, $1.fileSize) }
        let unknown = assets.filter { $0.fileSize <= 0 }.count
        if unknown == assets.count && unknown > 0 { return "Sizes unavailable" }
        return bytes.formattedFileSize + (unknown > 0 ? " known · \(unknown) sizes unavailable" : "")
    }

    func load() async {
        loadGeneration += 1
        let token = loadGeneration
        isLoading = true
        defer { if token == loadGeneration { isLoading = false } }
        var newAssets: [AssetSummary] = []
        var newMembership: [String: Set<String>] = [:]
        var newAlbums: [AlbumInfo] = []
        var newAlbumIDs = Set<String>()
        if tool == .screenRecordings {
            newAssets = await photoService.fetchAssetsByMediaType(.video).filter(\.isScreenRecording)
        } else {
            newAlbums = await photoService.fetchUserAlbums().filter { $0.type == .userAlbum }
            newAlbumIDs = ChatAlbumSelection.selectedIDs(in: newAlbums)
            var byID: [String: AssetSummary] = [:]
            for id in newAlbumIDs.sorted() {
                guard !Task.isCancelled, token == loadGeneration else { return }
                let items = await photoService.fetchAssets(filter: .specificAlbum(id: id))
                    .filter { $0.mediaType == .photo || $0.mediaType == .video }
                newMembership[id] = Set(items.map(\.id))
                for asset in items { byID[asset.id] = asset }
                await Task.yield()
            }
            newAssets = Array(byID.values)
        }
        guard !Task.isCancelled, token == loadGeneration else { return }
        assets = newAssets
        membership = newMembership
        albums = newAlbums
        albumIDs = newAlbumIDs
        selectedIDs.formIntersection(newAssets.map(\.id))
        if let activeAlbumID, !albumIDs.contains(activeAlbumID) { self.activeAlbumID = nil }
        ScanResults.record(tool, count: assets.count)
    }

    func saveAlbums(_ ids: Set<String>) async {
        UserDefaults.standard.set(ids.sorted(), forKey: AppPreferences.Key.chatAlbumIDs)
        activeAlbumID = nil
        selectedIDs.removeAll()
        await load()
    }

    func delete(ids: Set<String>) async -> Bool {
        guard !isDeleting, !ids.isEmpty else { return false }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        let sizes = Dictionary(assets.map { ($0.id, $0.fileSize) }, uniquingKeysWith: { a, _ in a })
        let result = await CleanupDeletion.delete(
            requestedIds: ids, kind: tool == .screenRecordings ? .screenRecordings : .chatMedia,
            sizeById: sizes,
            apply: { removed in
                self.assets.removeAll { removed.contains($0.id) }
                self.selectedIDs.subtract(removed)
                ScanResults.record(self.tool, count: self.assets.count)
            }
        )
        errorMessage = result.errorMessage
        return ids.isSubset(of: result.removed)
    }
}
