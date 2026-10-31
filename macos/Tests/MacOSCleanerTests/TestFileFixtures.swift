import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared file-fixture helpers for tests that need real files (sparse files,
/// PDFs, images) without allocating large disk or memory buffers.
enum TestFileFixtures {
    /// Creates a sparse file with the given logical size using `truncate(2)`.
    /// The file reports the full logical size through its attributes while
    /// occupying ~0 real disk blocks on APFS.
    static func makeSparseFile(at url: URL, logicalSize: UInt64) throws {
        try Data("x".utf8).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: logicalSize)
    }

    /// Writes a minimal one-page PDF containing `text` via CoreGraphics +
    /// CoreText. The text is extractable by PDFKit (`PDFDocument.page(at:)?.string`).
    static func makePDF(at url: URL, text: String) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw TestFileFixtureError.couldNotCreatePDFContext
        }
        context.beginPDFPage(nil)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
    }

    /// Writes a small solid-color PNG (width x height) readable by ImageIO.
    static func makePNG(at url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw TestFileFixtureError.couldNotCreatePNG
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestFileFixtureError.couldNotCreatePNG
        }
    }
}

enum TestFileFixtureError: Error {
    case couldNotCreatePDFContext
    case couldNotCreatePNG
}
