import Vision
import UIKit
import CoreImage
import Metal

struct BlurAnalysisResult: Sendable {
    let blurScore: Float      // Higher = more blurry. 0-1 scale
    let isBlurry: Bool
}

struct ExposureAnalysisResult: Sendable {
    let meanLuminance: Float  // 0-1 scale
    let isTooDark: Bool
    let isOverexposed: Bool
}

/// Sendable wrapper around a `VNFeaturePrintObservation`. The observation is
/// immutable after generation and safe to read from any thread, but the SDK type
/// isn't marked `Sendable`; this lets feature prints cross actor boundaries
/// (generator → comparison) without strict-concurrency warnings.
struct FeaturePrint: @unchecked Sendable {
    let observation: VNFeaturePrintObservation
}

enum BlurSensitivity: String, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    /// A photo is flagged blurry when its Laplacian variance (computed on a
    /// fixed 512px grayscale working image, 0–255 luminance) falls below this.
    /// Higher sensitivity ⇒ higher threshold ⇒ more photos flagged blurry.
    /// Conservative defaults bias against false positives; tune on-device using
    /// the per-photo variance emitted to `AppLog.vision` (see `analyzeBlurriness`).
    var varianceThreshold: Float {
        switch self {
        case .low: 40
        case .medium: 70
        case .high: 120
        }
    }
}

/// Controls how aggressively the Smart Categories tool buckets a photo: the
/// confidence floor for Vision scene/object labels and how much of the frame
/// must be text before a photo counts as a document/meme.
enum CategorySensitivity: String, CaseIterable, Sendable {
    case strict = "Strict"
    case balanced = "Balanced"
    case broad = "Broad"

    var confidenceFloor: Float {
        switch self {
        case .strict: 0.30
        case .balanced: 0.20
        case .broad: 0.10
        }
    }

    var textCoverageThreshold: Float {
        switch self {
        case .strict: 0.18
        case .balanced: 0.12
        case .broad: 0.08
        }
    }
}

/// Raw Vision signals for a single image, produced by `classifyImageContent`.
/// Deliberately UI-agnostic: the mapping from Vision identifiers to user-facing
/// categories lives in `PhotoCategorizationService` so this stays a thin Vision
/// wrapper (mirrors how `BlurAnalysisResult` carries scores, not UI tabs).
struct ContentClassificationResult: Sendable {
    /// Scene/object identifiers (above the sensitivity floor) → confidence.
    let labels: [String: Float]
    /// Fraction of the frame covered by recognized text (0–1).
    let textCoverage: Float
    /// Area of the largest detected face as a fraction of the frame (0–1).
    let faceCoverage: Float
    var succeeded = true
}

struct AestheticsResult: Sendable, Equatable {
    let score: Float
    let isUtility: Bool
    var isLowQuality: Bool { score.isFinite && score < 0 && !isUtility }
}

struct LensSmudgeResult: Sendable, Equatable {
    let confidence: Float
    var isSmudged: Bool { confidence.isFinite && confidence >= 0.8 }
}

actor VisionAnalysisService {
    private var smudgeUnsupported = false

    func supportsLensSmudge() -> Bool {
        if #available(iOS 26, *) {
            // Apple GPU family 7 starts at A14/M1, the request's hardware floor.
            return !smudgeUnsupported && MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) == true
        }
        return false
    }

    func analyzeAesthetics(image: CGImage) async -> AestheticsResult? {
        guard #available(iOS 18, *), !Task.isCancelled else { return nil }
        do {
            let result = try await CalculateImageAestheticsScoresRequest().perform(on: image)
            guard !Task.isCancelled, result.overallScore.isFinite else { return nil }
            return AestheticsResult(score: result.overallScore, isUtility: result.isUtility)
        } catch {
            return nil
        }
    }

    func analyzeLensSmudge(image: CGImage) async -> LensSmudgeResult? {
        guard #available(iOS 26, *), supportsLensSmudge(), !Task.isCancelled else { return nil }
        do {
            let result = try await DetectLensSmudgeRequest().perform(on: image)
            guard !Task.isCancelled, result.confidence.isFinite else { return nil }
            return LensSmudgeResult(confidence: result.confidence)
        } catch {
            let error = error as NSError
            if error.domain == VNErrorDomain,
               [VNErrorCode.unsupportedRequest.rawValue, VNErrorCode.unsupportedComputeDevice.rawValue].contains(error.code) {
                smudgeUnsupported = true
            }
            return nil
        }
    }


    /// Reused across all Core Image operations. Creating a `CIContext` per call
    /// (as the previous implementation did) allocates a fresh render pipeline each
    /// time, which is expensive when scanning thousands of photos for blur/exposure.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Blur Detection

    /// Longest edge (px) of the grayscale working image used for blur analysis.
    /// Measuring at a fixed resolution keeps the variance — and therefore the
    /// threshold — comparable across photos regardless of their native size.
    private static let blurWorkingEdge = 512

    /// Laplacian variance comfortably exceeded by a genuinely sharp photo. Used
    /// only to map variance → the 0–1 `blurScore` the UI displays; the blurry
    /// decision uses `BlurSensitivity.varianceThreshold`.
    private static let referenceSharpVariance: Float = 300

    func analyzeBlurriness(image: CGImage, assetId: String, sensitivity: BlurSensitivity = .medium) -> BlurAnalysisResult {
        let variance = laplacianVariance(of: image)
        // 0 (sharp) → 1 (blurry), purely for UI (score bar / quality chips).
        let blurScore = max(0, min(1, 1 - variance / Self.referenceSharpVariance))
        let isBlurry = variance < sensitivity.varianceThreshold

        AppLog.vision.debug("Blur \(assetId, privacy: .public): variance=\(variance, privacy: .public), blurry=\(isBlurry ? "yes" : "no", privacy: .public)")

        return BlurAnalysisResult(
            blurScore: blurScore,
            isBlurry: isBlurry
        )
    }

    /// Variance of the Laplacian — the standard focus/sharpness measure. A sharp
    /// image has strong, varied edge responses (high variance); a blurry one has
    /// muted, uniform responses (low variance). Computed on an 8-bit grayscale
    /// downsample at `blurWorkingEdge` so the value is resolution-independent.
    ///
    /// (The previous implementation took the *mean* of a `CIEdges` map, which is
    /// intrinsically near-zero for any photo — flat regions dominate — and after
    /// inversion flagged nearly everything as blurry.)
    private func laplacianVariance(of image: CGImage) -> Float {
        guard let buffer = grayscaleBuffer(from: image, maxEdge: Self.blurWorkingEdge),
              buffer.width >= 3, buffer.height >= 3 else {
            // Can't measure → treat as sharp so we never flag on a failure.
            return Self.referenceSharpVariance
        }

        let width = buffer.width
        let height = buffer.height
        var sum: Double = 0
        var sumSquares: Double = 0
        var count: Double = 0

        buffer.pixels.withUnsafeBufferPointer { p in
            for y in 1..<(height - 1) {
                let row = y * width
                let above = (y - 1) * width
                let below = (y + 1) * width
                for x in 1..<(width - 1) {
                    // 4-neighbour discrete Laplacian on luminance (0–255).
                    let lap = Int(p[above + x]) + Int(p[below + x])
                            + Int(p[row + x - 1]) + Int(p[row + x + 1])
                            - 4 * Int(p[row + x])
                    let l = Double(lap)
                    sum += l
                    sumSquares += l * l
                    count += 1
                }
            }
        }

        guard count > 0 else { return Self.referenceSharpVariance }
        let mean = sum / count
        let variance = sumSquares / count - mean * mean
        return Float(max(0, variance))
    }

    private struct GrayBuffer {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    /// Renders `image` into a tightly-packed 8-bit grayscale buffer, downscaling
    /// (never upscaling) so its longest edge is at most `maxEdge`.
    private func grayscaleBuffer(from image: CGImage, maxEdge: Int) -> GrayBuffer? {
        let srcW = image.width
        let srcH = image.height
        guard srcW > 0, srcH > 0 else { return nil }

        let longest = max(srcW, srcH)
        let scale = longest > maxEdge ? Double(maxEdge) / Double(longest) : 1.0
        let width = max(1, Int((Double(srcW) * scale).rounded()))
        let height = max(1, Int((Double(srcH) * scale).rounded()))

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return GrayBuffer(pixels: pixels, width: width, height: height)
    }

    // MARK: - Exposure Analysis

    func analyzeExposure(image: CGImage) -> ExposureAnalysisResult {
        let ciImage = CIImage(cgImage: image)
        let luminance = computeMeanLuminance(ciImage: ciImage)

        return ExposureAnalysisResult(
            meanLuminance: luminance,
            isTooDark: luminance < 0.12,
            isOverexposed: luminance > 0.88
        )
    }

    private func computeMeanLuminance(ciImage: CIImage) -> Float {
        let extent = ciImage.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return 0.5 }

        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        avgFilter.setValue(ciImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let avgOutput = avgFilter.outputImage else { return 0.5 }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(avgOutput,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        // Luminance: 0.299R + 0.587G + 0.114B
        let luminance = (0.299 * Float(pixel[0]) + 0.587 * Float(pixel[1]) + 0.114 * Float(pixel[2])) / 255.0
        return luminance
    }

    // MARK: - Feature Print (for duplicate/similar detection)

    func generateFeaturePrint(image: CGImage) -> FeaturePrint? {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()

        do {
            try requestHandler.perform([request])
            guard let observation = request.results?.first else { return nil }
            return FeaturePrint(observation: observation)
        } catch {
            AppLog.vision.error("Feature print generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func computeDistance(between fp1: FeaturePrint, and fp2: FeaturePrint) -> Float {
        var distance: Float = 0
        do {
            try fp1.observation.computeDistance(&distance, to: fp2.observation)
        } catch {
            AppLog.vision.error("Feature print distance failed: \(error.localizedDescription, privacy: .public)")
            return Float.greatestFiniteMagnitude
        }
        return distance
    }

    // MARK: - Content Classification (for Smart Categories)

    /// Runs scene/object classification, text recognition, and face detection on
    /// a single image in one `VNImageRequestHandler` pass (Vision shares the
    /// decoded image across requests, far cheaper than separate handlers). The
    /// SDK observation types never escape this method — only the `Sendable`
    /// `ContentClassificationResult` crosses the actor boundary.
    func classifyImageContent(
        image: CGImage,
        sensitivity: CategorySensitivity = .balanced
    ) -> ContentClassificationResult {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let classify = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        let faces = VNDetectFaceRectanglesRequest()

        do {
            try handler.perform([classify, text, faces])
        } catch {
            AppLog.vision.error("Content classification failed: \(error.localizedDescription, privacy: .public)")
            return ContentClassificationResult(labels: [:], textCoverage: 0, faceCoverage: 0, succeeded: false)
        }

        var labels: [String: Float] = [:]
        if let observations = classify.results {
            for observation in observations where observation.confidence > sensitivity.confidenceFloor {
                labels[observation.identifier] = observation.confidence
            }
        }

        var textArea: Float = 0
        if let textResults = text.results {
            for observation in textResults {
                textArea += Float(observation.boundingBox.width * observation.boundingBox.height)
            }
        }

        var faceCoverage: Float = 0
        if let faceResults = faces.results {
            for observation in faceResults {
                faceCoverage = max(faceCoverage, Float(observation.boundingBox.width * observation.boundingBox.height))
            }
        }

        return ContentClassificationResult(
            labels: labels,
            textCoverage: min(textArea, 1.0),
            faceCoverage: faceCoverage
        )
    }
}
