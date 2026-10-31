import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Vision

enum ImageQualityAnalysis {
    static func measureImage(_ url: URL, original: MediaFacts, sensitivity: Int) throws -> ImageMeasurement {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
        else {
            throw CleanupError.message(String(localized: "This image cannot be decoded."))
        }
        var facts = original
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        facts.width = original.width ?? properties?[kCGImagePropertyPixelWidth] as? Int
        facts.height = original.height ?? properties?[kCGImagePropertyPixelHeight] as? Int
        facts.capturedAt = captureDate(properties) ?? original.capturedAt
        let apple = properties?[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        facts.contentIdentifier = apple?["17"] as? String
        let sample = luminanceSamples(image, side: 64)
        let mean = sample.reduce(0, +) / Double(max(1, sample.count))
        facts.luminance = mean
        facts.clippedHighlights = Double(sample.filter { $0 > 0.98 }.count) / Double(max(1, sample.count))
        var gradient = 0.0
        for row in 1..<63 {
            for column in 1..<63 {
                let index = row * 64 + column
                let value =
                    sample[index - 1] + sample[index + 1] + sample[index - 64] + sample[index + 64] - 4 * sample[index]
                gradient += value * value
            }
        }
        facts.sharpness = gradient / (62 * 62)
        var hash: UInt64 = 0
        let small = luminanceSamples(image, side: 8)
        let smallMean = small.reduce(0, +) / 64
        for (index, value) in small.enumerated() where value > smallMean { hash |= UInt64(1) << index }
        let classification = try classify(image, sensitivity: sensitivity)
        facts.category = classification.category
        return ImageMeasurement(facts: facts, feature: classification.feature, perceptualHash: hash)
    }

    private static func captureDate(_ properties: [CFString: Any]?) -> Date? {
        guard let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssXXXXX"
        return formatter.date(from: raw + (offset ?? ""))
    }

    private static func classify(_ image: CGImage, sensitivity: Int) throws -> (
        feature: VNFeaturePrintObservation?, category: SmartCategory
    ) {
        var category = SmartCategory.other
        let feature = VNGenerateImageFeaturePrintRequest()
        feature.revision = VNGenerateImageFeaturePrintRequestRevision2
        let classify = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([feature, classify, text])
        let threshold: Float = [0.75, 0.55, 0.35][min(2, max(0, sensitivity))]
        let labels = classify.results?.filter { $0.confidence >= threshold }.map(\.identifier) ?? []
        if labels.contains(where: { ["food", "meal", "fruit", "vegetable", "dish"].contains($0) }) {
            category = .food
        } else if labels.contains(where: { ["cat", "dog", "pet", "animal"].contains($0) }) {
            category = .pets
        } else if labels.contains(where: {
            ["landscape", "nature", "mountain", "forest", "flower", "beach"].contains($0)
        }) {
            category = .nature
        } else if labels.contains("selfie") {
            category = .selfies
        } else if (text.results?.count ?? 0) >= 6 {
            category = .documents
        } else if (text.results?.count ?? 0) >= 2 {
            category = .memes
        }
        return (feature.results?.first, category)
    }

    private static func luminanceSamples(_ image: CGImage, side: Int) -> [Double] {
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return pixels.map { Double($0) / 255 }
    }
}
