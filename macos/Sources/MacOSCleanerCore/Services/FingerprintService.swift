import AVFoundation
import AppKit
import CryptoKit
import Foundation
import ImageIO
@preconcurrency import Vision

/// Stateless fingerprinting. All methods are `nonisolated` (the type is a
/// stateless enum-style namespace) so callers can run many hashes concurrently
/// without serializing through an actor — hashing is the scan's hot path.
public enum FingerprintService {
    private static let chunkSize = 64 * 1024

    public static func quickHash(for url: URL, sizeBytes: Int64) throws -> String {
        guard sizeBytes > 0 else {
            return "empty"
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        let offsets = offsetsForQuickHash(sizeBytes: sizeBytes)
        for offset in offsets {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            hasher.update(data: data)
        }
        hasher.update(data: Data(String(sizeBytes).utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func fullHash(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            // Cooperative cancellation: stop reading promptly when the scan is cancelled.
            if Task.isCancelled {
                throw CancellationError()
            }
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func offsetsForQuickHash(sizeBytes: Int64) -> [Int64] {
        if sizeBytes <= Int64(chunkSize * 3) {
            return [0]
        }
        let middle = max(0, (sizeBytes / 2) - Int64(chunkSize / 2))
        let end = max(0, sizeBytes - Int64(chunkSize))
        return [0, middle, end]
    }

    public static func perceptualHash(for url: URL) async -> String? {
        guard let cgImage = await decodeCGImage(from: url) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard error == nil,
                      let result = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(returning: nil)
                    return
                }
                // Use the raw feature print data, not the NSKeyedArchiver encoding.
                // The archiver output includes a variable-length plist header, making the
                // first N bytes depend on encoding metadata rather than the image content.
                let data = result.data
                let hash = SHA256.hash(data: data)
                continuation.resume(returning: hash.map { String(format: "%02x", $0) }.joined())
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Decodes a CGImage from a file URL on the cooperative thread pool
    /// (CGImageSource operations are thread-safe).
    private static func decodeCGImage(from url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Feature print of an image, for DISTANCE comparison between two images
    /// (near-duplicate detection). `nil` when the image cannot be decoded or
    /// Vision cannot produce a print.
    public static func featurePrint(for url: URL) async -> ImageFeaturePrint? {
        guard let cgImage = await decodeCGImage(from: url) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard error == nil,
                      let result = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ImageFeaturePrint(observation: result))
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
