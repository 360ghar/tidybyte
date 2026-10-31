import AVFoundation
import Foundation
import ImageIO
import NaturalLanguage
import PDFKit
import Vision

public actor ContentExtractor {
    private let policy: PathSafetyPolicy
    private let maxPreviewBytes = 32 * 1024

    public init(policy: PathSafetyPolicy = PathSafetyPolicy()) {
        self.policy = policy
    }

    public func summarize(files: [FileRecord], privacyMode: PrivacyMode) async -> [ContentSummary] {
        // PRIVACY: localOnly mode never extracts or produces content summaries.
        // The orchestrator also gates the call site, but this guard keeps any
        // future caller from leaking file contents or persisting summaries.
        guard privacyMode != .localOnly else {
            return []
        }
        let effectiveMode: PrivacyMode = privacyMode == .fullDocumentAI ? .snippetsAI : privacyMode
        var results: [ContentSummary] = []
        let maxConcurrentWorkers = 4
        // Bounded-concurrency parallel extraction: independent per-file work
        // (OCR, PDF text, Office decoding) is CPU/IO heavy, so a small worker
        // pool keeps a large scan from serializing minutes of work while
        // avoiding a task explosion. Results are collected by index so the
        // output order matches the input.
        await withTaskGroup(of: (Int, ContentSummary?).self) { group in
            var summariesByIndex: [Int: ContentSummary] = [:]
            var iterator = files.makeIterator()
            var nextIndex = 0
            // Windowed scheduling: keep at most `maxConcurrentWorkers` child
            // tasks in flight by adding one only as each result drains. The
            // previous add-4-drain-1 loop grew the group by 3 tasks per file —
            // for a large scan that materialized hundreds of thousands of live
            // child tasks (and their captured records) at once.
            func addNext() -> Bool {
                guard let file = iterator.next() else { return false }
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    if Task.isCancelled {
                        return (index, nil)
                    }
                    let summary = await self.summarizeOne(file, privacyMode: effectiveMode)
                    return (index, summary)
                }
                return true
            }
            for _ in 0..<maxConcurrentWorkers where addNext() {}
            while let (index, summary) = await group.next() {
                if let summary {
                    summariesByIndex[index] = summary
                }
                _ = addNext()
            }
            results = files.indices.compactMap { summariesByIndex[$0] }
        }
        return results
    }

    private func summarizeOne(_ file: FileRecord, privacyMode: PrivacyMode) async -> ContentSummary? {
        guard file.kind == .regularFile || file.kind == .package else {
            return nil
        }
        let detected = await detectLocalContent(file: file, privacyMode: privacyMode)
        guard detected.textPreview != nil || detected.ocrText != nil || !detected.imageLabels.isEmpty || !detected.videoLabels.isEmpty || detected.language != nil else {
            return nil
        }
        return ContentSummary(
            fileID: file.id,
            textPreview: detected.textPreview,
            ocrText: detected.ocrText,
            language: detected.language,
            detectedTopics: detected.topics,
            imageLabels: detected.imageLabels,
            videoLabels: detected.videoLabels,
            privacyLevel: privacyMode
        )
    }

    private func detectLocalContent(
        file: FileRecord,
        privacyMode: PrivacyMode
    ) async -> (textPreview: String?, ocrText: String?, language: String?, topics: [String], imageLabels: [String], videoLabels: [String]) {
        guard case .allow = policy.decide(target: file.url, isDirectory: file.kind == .directory) else {
            return (nil, nil, nil, ["protected"], [], [])
        }

        if let fileExtension = file.fileExtension, textExtensions.contains(fileExtension), privacyMode != .metadataOnlyAI {
            let preview = readTextPreview(file.url)
            return (preview, nil, preview.flatMap(detectLanguage), topicHints(from: preview ?? "", filePath: file.displayPath), [], [])
        }

        if file.fileExtension == "pdf", privacyMode != .metadataOnlyAI {
            let preview = await readPDFPreview(file.url)
            return (preview, nil, preview.flatMap(detectLanguage), topicHints(from: preview ?? "", filePath: file.displayPath), [], [])
        }

        if let fileExtension = file.fileExtension {
            let officeExtensions: Set<String> = ["docx", "pptx", "xlsx"]
            // Office documents are decoded through textutil (file contents), so they
            // are only read when the mode permits content extraction.
            if officeExtensions.contains(fileExtension), privacyMode != .metadataOnlyAI {
                let text = await readOfficePreview(file.url)
                var labels: [String] = ["office", fileExtension]
                if let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path) {
                    if let size = attrs[.size] as? Int64 {
                        labels.append("size: \(size.formattedByteCount)")
                    }
                    if let modDate = attrs[.modificationDate] as? Date {
                        labels.append("modified: \(modDate.formatted())")
                    }
                }
                let metadataLine = labels.joined(separator: ", ")
                let preview = [text, metadataLine].compactMap { $0 }.joined(separator: "\n")
                return (preview.isEmpty ? nil : preview, nil, text.flatMap(detectLanguage), topicHints(from: text ?? "", filePath: file.displayPath), [], [])
            }
        }

        if let fileExtension = file.fileExtension, imageExtensions.contains(fileExtension) {
            let labels = imageMetadataLabels(for: file.url)
            let ocr = privacyMode == .localOnly || privacyMode == .snippetsAI || privacyMode == .visionAI ? recognizeText(in: file.url) : nil
            return (nil, ocr, ocr.flatMap(detectLanguage), topicHints(from: ocr ?? "", filePath: file.displayPath), labels, [])
        }

        if let fileExtension = file.fileExtension, videoExtensions.contains(fileExtension) {
            let labels = readVideoPreview(file.url)
            let metadataPreview = labels.joined(separator: ", ")
            return (metadataPreview.isEmpty ? nil : metadataPreview, nil, nil, [], [], labels)
        }

        return (nil, nil, nil, [], [], [])
    }

    private var textExtensions: Set<String> {
        ["txt", "md", "markdown", "csv", "json", "yaml", "yml", "toml", "xml", "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "java", "kt", "rb", "php", "sql", "log"]
    }

    private var imageExtensions: Set<String> {
        ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"]
    }

    private var videoExtensions: Set<String> {
        ["mov", "mp4", "m4v", "avi", "mkv"]
    }

    private func readTextPreview(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        guard let data = try? handle.read(upToCount: maxPreviewBytes), !data.isEmpty else {
            return nil
        }
        // A fixed-size read can split a multibyte UTF-8 sequence; decoding the raw
        // buffer would then fail and drop an otherwise-valid preview. Trim any
        // trailing incomplete sequence before decoding.
        var validLength = data.count
        while validLength > 0 {
            if let _ = try? String(data: data.prefix(validLength), encoding: .utf8) { break }
            validLength -= 1
        }
        return String(data: data.prefix(validLength), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readPDFPreview(_ url: URL) async -> String? {
        // PDFKit is safe to use off the main actor for read-only operations.
        // Removed MainActor.run hop that serialized PDF extraction and blocked the UI.
        guard let document = PDFDocument(url: url) else {
            return nil
        }
        let pageLimit = min(document.pageCount, 3)
        let text = (0..<pageLimit)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        return String(text.prefix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readOfficePreview(_ url: URL) async -> String? {
        let result = await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/textutil"),
            arguments: ["-convert", "txt", "-stdout", url.path],
            timeout: 10
        )
        guard result.exitCode == 0 else { return nil }
        let text = result.stdout
        return String(text.prefix(4096)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readVideoPreview(_ url: URL) -> [String] {
        var labels: [String] = ["video"]
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        if duration.isFinite && duration > 0 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            labels.append("duration: \(minutes)m \(seconds)s")
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            labels.append("size: \(size.formattedByteCount)")
        }
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize
            labels.append("\(Int(size.width))x\(Int(size.height))")
        }
        return labels
    }

    private func imageMetadataLabels(for url: URL) -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return []
        }
        var labels: [String] = ["image"]
        if let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            labels.append("\(width.intValue)x\(height.intValue)")
        }
        if properties[kCGImagePropertyExifDictionary] != nil {
            labels.append("exif")
        }
        return labels
    }

    private func recognizeText(in url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let text = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private func topicHints(from text: String, filePath: String? = nil) -> [String] {
        let lowered = text.lowercased()
        var topics: [String] = []
        if lowered.contains("invoice") || lowered.contains("receipt") {
            topics.append("finance")
        }
        if lowered.contains("resume") || lowered.contains("cv") {
            topics.append("career")
        }
        if lowered.contains("api_key") || lowered.contains("secret") || lowered.contains("password") {
            let pathLower = filePath?.lowercased() ?? ""
            let secretPathHints = pathLower.contains("secret")
                || pathLower.contains("credential")
                || pathLower.contains(".env")
                || pathLower.contains("key")
                || pathLower.contains("token")
                || pathLower.contains("config")
                || pathLower.contains("auth")
            if secretPathHints || lowered.contains("api_key") {
                topics.append("possible_secret")
            }
        }
        return topics
    }
}
