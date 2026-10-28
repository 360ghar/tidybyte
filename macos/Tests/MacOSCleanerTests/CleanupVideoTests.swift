import AVFoundation
import CoreVideo
import VideoToolbox
import XCTest

@testable import MacOSCleanerCore

@MainActor
final class CleanupVideoTests: XCTestCase {
    func testVideoCompressionDecodesAndPreservesSizeAndDuration() async throws {
        guard ProcessInfo.processInfo.environment["CLEANER_RUN_VIDEO_INTEGRATION"] == "1" else {
            throw XCTSkip("Opt in on a host with working VideoToolbox services: CLEANER_RUN_VIDEO_INTEGRATION=1")
        }
        let root = try TestFixtures.makeTemporaryDirectory(named: "CleanupVideo-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.mov")
        try await writeVideo(source)
        let item = try XCTUnwrap(ReviewInventory.record(source, root: root))
        var settings = CleanupSettings()
        settings.videoHeight = 480
        let output = try await MediaCompressionService().compress(
            item, source: source, destination: root, settings: settings
        ) { _ in }
        let original = AVURLAsset(url: source)
        let compressed = AVURLAsset(url: output)
        let duration = try await original.load(.duration).seconds
        let actual = try await compressed.load(.duration).seconds
        let tracks = try await compressed.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 640, height: 480))
        XCTAssertEqual(duration, actual, accuracy: 0.1)
        XCTAssertLessThan(try ReviewSafety.identity(at: output).sizeBytes ?? .max, item.bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testVideoWithAlphaHDRAndStereoIsRejectedBeforeConversion() throws {
        let fixtures: [[String: Any]] = [
            [kCMFormatDescriptionExtension_ContainsAlphaChannel as String: true],
            [kCMFormatDescriptionExtension_BitsPerComponent as String: 10],
            [kCMFormatDescriptionExtension_HasLeftStereoEyeView as String: true],
            [kCMFormatDescriptionExtension_TransferFunction as String: "SMPTE_ST_2084_PQ"]
        ]
        for extensions in fixtures {
            var description: CMVideoFormatDescription?
            XCTAssertEqual(
                CMVideoFormatDescriptionCreate(
                    allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_H264,
                    width: 640, height: 480, extensions: extensions as CFDictionary,
                    formatDescriptionOut: &description), noErr)
            XCTAssertThrowsError(try MediaCompressionService.validateVideoFormat(XCTUnwrap(description)))
        }
    }

    func testLivePhotoPairUsesPairingMetadataAfterRenaming() {
        var image = ReviewItem(
            id: "still", source: .file(URL(fileURLWithPath: "/tmp/Camera/renamed.jpg")),
            name: "renamed.jpg", kind: .image, bytes: 100)
        var video = ReviewItem(
            id: "motion", source: .file(URL(fileURLWithPath: "/tmp/Camera/IMG_1234.mov")),
            name: "IMG_1234.mov", kind: .video, bytes: 200)
        image.facts.contentIdentifier = "pair-identifier"
        video.facts.contentIdentifier = "pair-identifier"
        XCTAssertEqual(MediaAnalysisService.livePhotoGroups([image, video]).count, 1)
        video.facts.contentIdentifier = "different"
        XCTAssertTrue(MediaAnalysisService.livePhotoGroups([image, video]).isEmpty)
    }

    private func writeVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 480,
                AVVideoEncoderSpecificationKey: [
                    kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: false
                ],
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 30_000_000]
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(15)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData {
                guard Date() < deadline else {
                    throw CleanupError.message("VideoToolbox did not accept the fixture frames within 15 seconds.")
                }
                if let error = writer.error { throw error }
                try await Task.sleep(for: .milliseconds(5))
            }
            let buffer = try noiseBuffer(seed: UInt64(frame + 1))
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func noiseBuffer(seed: UInt64) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 640, 480, kCVPixelFormatType_32BGRA, nil, &result), kCVReturnSuccess)
        let buffer = try XCTUnwrap(result)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let count = CVPixelBufferGetBytesPerRow(buffer) * 480
        var state = seed
        for index in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            bytes[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 32)
        }
        return buffer
    }
}
