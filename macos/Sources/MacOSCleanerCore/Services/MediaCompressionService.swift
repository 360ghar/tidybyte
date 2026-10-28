import AVFoundation
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor MediaCompressionService {
    public init() {}

    public static func estimate(_ item: ReviewItem, settings: CleanupSettings) -> Int64 {
        if item.kind == .image { return Int64(Double(item.bytes) * settings.imageQuality.quality * 0.8) }
        let height = max(1, item.facts.height ?? settings.videoHeight)
        let scale = min(1, Double(settings.videoHeight) / Double(height))
        return Int64(Double(item.bytes) * scale * scale * 0.65)
    }

    public func compress(
        _ item: ReviewItem, source: URL, destination: URL, settings: CleanupSettings,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let ext = item.kind == .video ? "mp4" : source.pathExtension.lowercased()
        let name = source.deletingPathExtension().lastPathComponent + "-compressed." + ext
        let staging = destination.appendingPathComponent(".cleaner-compression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let output = staging.appendingPathComponent(name)
        do {
            if item.kind == .image {
                try await Task.detached(priority: .utility) {
                    try Self.compressImage(source, output: output, quality: settings.imageQuality.quality)
                }.value
            } else if item.kind == .video {
                try await Self.compressVideo(source, output: output, height: settings.videoHeight, progress: progress)
            } else {
                throw CleanupError.message(String(localized: "This file does not support compression."))
            }
            try Task.checkCancellation()
            let before = try ReviewSafety.identity(at: source).sizeBytes ?? 0
            let after = try ReviewSafety.identity(at: output).sizeBytes ?? 0
            guard after > 0, after < before else {
                throw CleanupError.message(
                    String(localized: "The compressed copy is not smaller. The original was kept."))
            }
            await progress(1)
            for _ in 0..<100 {
                let published = ReviewSafety.uniqueOutput(in: destination, name: name)
                if renamex_np(output.path, published.path, UInt32(RENAME_EXCL)) == 0 { return published }
                if errno != EEXIST { break }
            }
            throw CleanupError.message(String(localized: "Cannot save the verified output. The original was kept."))
        } catch {
            // Only remove the new, uncommitted output owned by this job.
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func compressImage(_ sourceURL: URL, output: URL, quality: Double) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil), CGImageSourceGetCount(source) == 1,
            let type = CGImageSourceGetType(source),
            [UTType.jpeg.identifier, UTType.heic.identifier, UTType.png.identifier].contains(type as String),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.bitsPerComponent <= 8,
            let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw CleanupError.message(
                String(localized: "Compression does not support this image's format, animation, or HDR data."))
        }
        let auxiliary = [
            kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
            kCGImageAuxiliaryDataTypePortraitEffectsMatte, kCGImageAuxiliaryDataTypeHDRGainMap,
            kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte
        ]
        guard !auxiliary.contains(where: { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }) else {
            throw CleanupError.message(
                String(localized: "This image has depth, HDR, or portrait data that must be retained."))
        }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil) else {
            throw CleanupError.message(String(localized: "Cannot create the compressed image."))
        }
        var properties = metadata
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination),
            let verification = CGImageSourceCreateWithURL(output as CFURL, nil),
            CGImageSourceGetCount(verification) == 1,
            let decoded = CGImageSourceCreateImageAtIndex(verification, 0, nil),
            decoded.width == image.width, decoded.height == image.height,
            decoded.alphaInfo == image.alphaInfo || !hasAlpha(image)
        else {
            throw CleanupError.message(String(localized: "The compressed image did not pass verification."))
        }
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        [.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(image.alphaInfo)
    }

    @MainActor private static func compressVideo(
        _ source: URL, output: URL, height: Int,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let allTracks = try await asset.load(.tracks)
        guard videoTracks.count == 1, audioTracks.count <= 1,
            allTracks.count == videoTracks.count + audioTracks.count, let track = videoTracks.first
        else {
            throw CleanupError.message(String(localized: "This video's track layout is not supported for compression."))
        }
        let descriptions = try await track.load(.formatDescriptions)
        for description in descriptions { try validateVideoFormat(description) }
        let size = try await track.load(.naturalSize)
        let maximum = min(height, Int(min(abs(size.width), abs(size.height))))
        let preset: String
        if maximum >= 1080 {
            preset = AVAssetExportPreset1920x1080
        } else if maximum >= 720 {
            preset = AVAssetExportPreset1280x720
        } else if maximum >= 480 {
            preset = AVAssetExportPreset640x480
        } else {
            throw CleanupError.message(String(localized: "This video is below 480p and will not be upscaled."))
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CleanupError.message(String(localized: "This video format cannot be exported."))
        }
        exporter.metadata = try await asset.load(.metadata)
        let observation = Task {
            for await state in exporter.states(updateInterval: 0.2) {
                if case .exporting(let status) = state { await progress(status.fractionCompleted) }
            }
        }
        defer { observation.cancel() }
        try await exporter.export(to: output, as: .mp4)
        try Task.checkCancellation()
        try await verifyVideo(asset, output: output, videoCount: videoTracks.count, audioCount: audioTracks.count)
    }

    static func validateVideoFormat(_ description: CMFormatDescription) throws {
        let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String ?? ""
        let hasAlpha = extensions[kCMFormatDescriptionExtension_ContainsAlphaChannel as String] as? Bool == true
        let depth = extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? Int ?? 8
        let unsupportedKeys = [
            kCMFormatDescriptionExtension_AlphaChannelMode, kCMFormatDescriptionExtension_LogTransferFunction,
            kCMFormatDescriptionExtension_MasteringDisplayColorVolume,
            kCMFormatDescriptionExtension_ContentLightLevelInfo,
            kCMFormatDescriptionExtension_AlternativeTransferCharacteristics,
            kCMFormatDescriptionExtension_ProjectionKind,
            kCMFormatDescriptionExtension_StereoCameraBaseline
        ]
        let hasStereo = [
            kCMFormatDescriptionExtension_HasLeftStereoEyeView, kCMFormatDescriptionExtension_HasRightStereoEyeView
        ].contains { extensions[$0 as String] as? Bool == true }
        guard !hasAlpha, !hasStereo, depth <= 8,
            !unsupportedKeys.contains(where: { extensions[$0 as String] != nil }),
            !["2084", "HLG", "2100"].contains(where: transfer.contains)
        else {
            throw CleanupError.message(
                String(localized: "This video has HDR, transparency, or spatial data that must be retained."))
        }
    }

    @MainActor private static func verifyVideo(_ asset: AVURLAsset, output: URL, videoCount: Int, audioCount: Int)
        async throws {
        let result = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        let actual = try await result.load(.duration).seconds
        let newVideo = try await result.loadTracks(withMediaType: .video)
        let newAudio = try await result.loadTracks(withMediaType: .audio)
        guard actual.isFinite, abs(duration - actual) < max(0.1, duration * 0.001),
            newVideo.count == videoCount, newAudio.count == audioCount
        else {
            throw CleanupError.message(String(localized: "The exported video did not pass verification."))
        }
        let reader = try AVAssetReader(asset: result)
        guard let verifiedTrack = newVideo.first else {
            throw CleanupError.message(String(localized: "Video track missing."))
        }
        if let originalTrack = try await asset.loadTracks(withMediaType: .video).first {
            let before = try await originalTrack.load(.naturalSize)
            let after = try await verifiedTrack.load(.naturalSize)
            guard after.width <= before.width + 1, after.height <= before.height + 1,
                abs(after.width / after.height - before.width / before.height) < 0.01
            else {
                throw CleanupError.message(
                    String(localized: "The export changed aspect ratio or increased dimensions."))
            }
        }
        let readerOutput = AVAssetReaderTrackOutput(
            track: verifiedTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(readerOutput)
        guard reader.startReading(), readerOutput.copyNextSampleBuffer() != nil else {
            throw CleanupError.message(String(localized: "The exported video could not be decoded."))
        }
        reader.cancelReading()
        if let audioTrack = newAudio.first {
            let audioReader = try AVAssetReader(asset: result)
            let audioOutput = AVAssetReaderTrackOutput(
                track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            audioReader.add(audioOutput)
            guard audioReader.startReading(), audioOutput.copyNextSampleBuffer() != nil else {
                throw CleanupError.message(String(localized: "The exported audio could not be decoded."))
            }
            audioReader.cancelReading()
        }
    }
}
