import AVKit
import ImageIO
import MacOSCleanerCore
import PDFKit
import Quartz
import QuickLookThumbnailing
import SwiftUI

struct ReviewPreview: View {
    let item: ReviewItem
    let model: CleanupModel
    var thumbnail = false
    @State private var url: URL?
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var grant: URL?
    @State private var error: String?
    @State private var zoom = 1.0
    @State private var page = 0
    @State private var requestID = UUID()

    var body: some View {
        VStack(spacing: Spacing.elementTight) {
            Group {
                if item.isLink {
                    ContentUnavailableView(
                        String(localized: "Link"), systemImage: "link",
                        description: Text(item.linkTarget?.path ?? String(localized: "Target unavailable")))
                } else if !item.isDownloaded {
                    ContentUnavailableView(String(localized: "Not downloaded"), systemImage: "icloud.slash")
                } else if let error {
                    ContentUnavailableView(
                        String(localized: "Preview unavailable"), systemImage: "doc.questionmark",
                        description: Text(error))
                } else if thumbnail, let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else if let url {
                    media(url)
                } else {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .fill(.quaternary).overlay {
                            ProgressView().accessibilityLabel(String(localized: "Loading preview"))
                        }
                }
            }
            if !thumbnail {
                Text(metadata).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .accessibilityLabel(String(localized: "File information: \(metadata)"))
            }
        }
        .task(id: item.reviewKey + (item.url?.path ?? "") + "\(thumbnail)") { await load() }
        .onDisappear {
            requestID = UUID()
            player?.pause()
            grant?.stopAccessingSecurityScopedResource()
            grant = nil
        }
    }

    @ViewBuilder private func media(_ url: URL) -> some View {
        switch item.kind {
        case .image:
            if let image {
                VStack {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: max(200, min(image.size.width, 640)) * zoom)
                    }
                    Slider(value: $zoom, in: 0.5...4) { Text(String(localized: "Image zoom")) }
                }
            } else {
                NativeQuickLook(url: url)
            }
        case .video, .audio:
            if let player {
                VideoPlayer(player: player).accessibilityLabel(String(localized: "Media playback controls"))
            }
        case .pdf:
            VStack {
                NativePDFPreview(url: url, page: page)
                HStack {
                    Button(String(localized: "Previous page")) { page = max(0, page - 1) }.disabled(page == 0)
                    Text(String(localized: "Page \(page + 1) of \(item.facts.pageCount ?? 1)"))
                    Button(String(localized: "Next page")) { page += 1 }.disabled(
                        page + 1 >= (item.facts.pageCount ?? 1))
                }
            }
        default: NativeQuickLook(url: url)
        }
    }

    private var metadata: String {
        var parts = [item.bytes.formattedByteCount, item.kind.title, item.sourceName]
        if let width = item.facts.width, let height = item.facts.height { parts.append("\(width) × \(height)") }
        if let seconds = item.facts.duration, seconds.isFinite {
            parts.append(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
        }
        if let pages = item.facts.pageCount { parts.append(String(localized: "\(pages) pages")) }
        if let date = item.modifiedAt { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        player?.pause()
        player = nil
        image = nil
        url = nil
        error = nil
        zoom = 1
        page = 0
        grant?.stopAccessingSecurityScopedResource()
        grant = nil
        let request = UUID()
        requestID = request
        guard !item.isLink else { return }
        guard item.isDownloaded else {
            error = String(localized: "Not downloaded. Download this item in its source app to preview it.")
            return
        }
        var acquiredGrant: URL?
        var keepsGrant = false
        defer { if !keepsGrant { acquiredGrant?.stopAccessingSecurityScopedResource() } }
        do {
            if let root = item.root { acquiredGrant = try await model.access.acquire(root) }
            try Task.checkCancellation()
            let temporaryPreview = item.photoID != nil && (thumbnail || item.kind == .image)
            let local: URL
            if temporaryPreview {
                local = try await model.photos.analysisPreview(item, size: thumbnail ? 512 : 1600)
            } else {
                local = try await model.localURL(item)
            }
            defer {
                if temporaryPreview { Task { await model.photos.releaseAnalysisPreview(local) } }
            }
            try Task.checkCancellation()
            let loadedImage = try await loadContent(local)
            try Task.checkCancellation()
            guard requestID == request else { return }
            url = local
            image = loadedImage
            player = !thumbnail && [.video, .audio].contains(item.kind) ? AVPlayer(url: local) : nil
            grant = acquiredGrant
            keepsGrant = true
        } catch is CancellationError {} catch {
            if requestID == request { self.error = error.localizedDescription }
        }
    }
    private func loadContent(_ local: URL) async throws -> NSImage? {
        if thumbnail || item.kind == .image {
            return try await PreviewThumbnailCache.image(
                for: local, key: item.reviewKey + (thumbnail ? "thumbnail" : "full"), size: thumbnail ? 320 : 1600)
        }
        if item.kind == .video || item.kind == .audio {
            try await verifyPlayback(local)
        } else if item.kind == .pdf, PDFDocument(url: local) == nil {
            throw CleanupError.message(String(localized: "This PDF cannot be opened."))
        }
        return nil
    }

    private func verifyPlayback(_ local: URL) async throws {
        guard try await AVURLAsset(url: local).load(.isPlayable) else {
            throw CleanupError.message(String(localized: "This media file cannot be played."))
        }
    }

}

@MainActor private enum PreviewThumbnailCache {
    static let cache: NSCache<NSString, NSImage> = {
        let value = NSCache<NSString, NSImage>()
        value.totalCostLimit = 64 * 1024 * 1024
        return value
    }()
    static func image(for url: URL, key: String, size: CGFloat = 320) async throws -> NSImage {
        if let image = cache.object(forKey: key as NSString) { return image }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: 1, representationTypes: .thumbnail)
        let result = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        try Task.checkCancellation()
        let image = result.nsImage
        cache.setObject(image, forKey: key as NSString, cost: Int(size * size) * 4)
        return image
    }
}

private struct NativePDFPreview: NSViewRepresentable {
    let url: URL
    let page: Int
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        if let target = view.document?.page(at: page) { view.go(to: target) }
    }
}

private struct NativeQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal) }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
        view.autostarts = false
    }
}
