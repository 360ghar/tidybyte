import SwiftUI

enum CleanupTool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case duplicates
    case similar
    case screenshots
    case blurry
    case smartCategories
    case largeFiles
    case bursts
    case livePhotos
    case videoCompression
    case photoCompression

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duplicates: "Duplicates"
        case .similar: "Similar Photos"
        case .screenshots: "Screenshots"
        case .blurry: "Blurry Photos"
        case .smartCategories: "Smart Categories"
        case .largeFiles: "Large Files"
        case .bursts: "Burst Photos"
        case .livePhotos: "Live Photos"
        case .videoCompression: "Video Compression"
        case .photoCompression: "Photo Compression"
        }
    }

    var description: String {
        switch self {
        case .duplicates: "Find exact & visual duplicates"
        case .similar: "Photos taken close together"
        case .screenshots: "Review & clean up screenshots"
        case .blurry: "Out-of-focus & poorly lit"
        case .smartCategories: "Sort photos by content type"
        case .largeFiles: "Biggest files in your library"
        case .bursts: "Clean up burst sequences"
        case .livePhotos: "Convert to stills & save space"
        case .videoCompression: "Compress videos to save space"
        case .photoCompression: "Re-encode photos to save space"
        }
    }

    var icon: String {
        switch self {
        case .duplicates: "doc.on.doc"
        case .similar: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .blurry: "camera.metering.unknown"
        case .smartCategories: "sparkles.rectangle.stack"
        case .largeFiles: "externaldrive"
        case .bursts: "square.stack.3d.up"
        case .livePhotos: "livephoto"
        case .videoCompression: "video.badge.waveform"
        case .photoCompression: "photo.badge.arrow.down"
        }
    }

    var color: Color {
        switch self {
        case .duplicates: .red
        case .similar: .orange
        case .screenshots: .yellow
        case .blurry: .purple
        case .smartCategories: .pink
        case .largeFiles: .blue
        case .bursts: .teal
        case .livePhotos: .green
        case .videoCompression: .indigo
        case .photoCompression: .mint
        }
    }
}

@MainActor
@ViewBuilder
func cleanupDestinationView(for tool: CleanupTool) -> some View {
    switch tool {
    case .duplicates:
        DuplicateFinderView()
    case .similar:
        SimilarPhotosView()
    case .screenshots:
        ScreenshotCleanerView()
    case .blurry:
        BlurryPhotosView()
    case .smartCategories:
        SmartCategoriesView()
    case .largeFiles:
        LargeFilesView()
    case .bursts:
        BurstCleanerView()
    case .livePhotos:
        LivePhotosConverterView()
    case .videoCompression:
        VideoCompressionView()
    case .photoCompression:
        PhotoCompressionView()
    }
}
