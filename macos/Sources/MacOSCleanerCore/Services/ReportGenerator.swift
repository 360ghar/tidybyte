import AppKit
import CoreGraphics
import Foundation
import os

public enum ReportGeneratorError: Error, LocalizedError, Sendable {
    case cannotCreatePDF

    public var errorDescription: String? {
        switch self {
        case .cannotCreatePDF: String(localized: "Unable to create PDF report.", comment: "Error when PDF creation fails")
        }
    }
}

public actor ReportGenerator {
    private let store: SQLiteStore
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "ReportGenerator")

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func generateCleanupReport(outcome: ScanOutcome, plan: Plan, destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let reportURL = destination.appendingPathComponent("Cleanup Report \(Self.timestamp()).pdf", isDirectory: false)
        let text = reportText(outcome: outcome, plan: plan)
        try writePDF(text: text, to: reportURL)
        return reportURL
    }

    private func reportText(outcome: ScanOutcome, plan: Plan) -> String {
        // Break the grouped dictionary chain into steps — the compiler cannot
        // type-check the fully chained expression in reasonable time.
        let grouped = Dictionary(grouping: outcome.findings, by: \.category)
        let totals = grouped.mapValues { findings in findings.reduce(Int64(0)) { $0 + $1.bytesReclaimable } }
        let topCategories = totals
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { "\($0.key.displayName): \($0.value.formattedByteCount)" }
            .joined(separator: "\n")

        let riskyRejected = plan.actions.filter { $0.risk >= .high }.count
        let status = reportStatusLines(outcome: outcome)
        return String(localized: """
        Tidybyte Cleanup Session Report

        Scan started: \(outcome.session.startedAt.formatted())
        \(status.completion)
        Files reviewed: \(outcome.session.totalFilesSeen)
        Bytes scanned: \(outcome.session.totalBytesSeen.formattedByteCount)
        Proposed actions: \(plan.actions.count)
        Estimated reviewable space: \(plan.estimatedReclaimableBytes.formattedByteCount)
        Duplicate findings: \(outcome.findings.filter { $0.category == .duplicate }.count)
        Developer artifact findings: \(outcome.findings.filter { $0.category == .developerArtifact }.count)
        High-risk recommendations (require explicit confirmation before execution): \(riskyRejected)
        \(status.unreadable)

        Top categories
        \(topCategories)

        \(status.notices)

        Summary
        \(plan.summary)

        Safety posture
        Files are moved to Trash or organized with reversible records where possible. Package-manager and Docker actions are marked not fully undoable.
        """, comment: "Cleanup session report body")
    }

    /// Report header lines: completion state, unreadable count, and notices.
    private struct ReportStatus {
        let completion: String
        let unreadable: String
        let notices: String
    }

    /// Completion state and diagnostics for the report. Split out of
    /// `reportText` to keep its body under the function-length limit.
    private func reportStatusLines(outcome: ScanOutcome) -> ReportStatus {
        let completedAt = outcome.session.completedAt?.formatted()
            ?? String(localized: "Not completed", comment: "Placeholder for missing completion time")
        let completion = outcome.wasCancelled || outcome.session.status == .cancelled
            ? String(
                localized: "Scan stopped early: \(completedAt). These results cover only the locations scanned before the stop.",
                comment: "Report line for a scan the person stopped before it finished")
            : String(
                localized: "Scan completed: \(completedAt)",
                comment: "Report line for a completed scan")
        // An empty report section reads as "clean"; say what the scan could not
        // see instead, matching the notices the app shows in Review.
        let unreadable = outcome.session.errorsCount > 0
            ? String(
                localized: "Locations that could not be read: \(outcome.session.errorsCount)",
                comment: "Report line counting locations the scan could not read")
            : ""
        let notices = outcome.notices.isEmpty
            ? ""
            : String(
                localized: "Scan notices\n\(outcome.notices.map(\.message).joined(separator: "\n"))",
                comment: "Report section listing diagnostics for a scan")
        return ReportStatus(completion: completion, unreadable: unreadable, notices: notices)
    }

    private func writePDF(text: String, to url: URL) throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ReportGeneratorError.cannotCreatePDF
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        let pageRect = CGRect(x: 54, y: 54, width: 504, height: 684)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let totalStringRange = CFRangeMake(0, attributed.length)
        var currentRange = totalStringRange

        while currentRange.location < totalStringRange.length {
            context.beginPDFPage(nil)

            let path = CGPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)

            // Get the visible range to advance
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            // Zero-glyph pages (path too small for even one line) never advance
            // the range and would loop forever.
            guard visibleRange.length > 0 else {
                break
            }

            context.saveGState()
            // Translate to the bottom-left of the text area.  Core Graphics origin is
            // bottom-left, and CTFrame draws text from high-y (top) to low-y (bottom)
            // within its path rect.  Using pageRect.minY places the frame so its top
            // sits at pageRect.maxY (near the page top) and its bottom at pageRect.minY.
            context.translateBy(x: pageRect.minX, y: pageRect.minY)
            CTFrameDraw(frame, context)
            context.restoreGState()

            context.endPDFPage()

            currentRange = CFRangeMake(currentRange.location + visibleRange.length, currentRange.length - visibleRange.length)
        }

        context.closePDF()
        try data.write(to: url, options: .atomic)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter.string(from: Date())
    }
}
