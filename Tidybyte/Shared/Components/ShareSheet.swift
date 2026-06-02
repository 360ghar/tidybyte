import SwiftUI
import UIKit

/// Identifiable wrapper so a share sheet can be driven by `.sheet(item:)`. Holds
/// the temp file URLs that were exported for sharing; the hosting view deletes
/// the containing export folder when the sheet is dismissed.
struct SharePayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Thin SwiftUI bridge to `UIActivityViewController`. Used instead of `ShareLink`
/// because the items are PHAsset representations resolved asynchronously to temp
/// files before presentation.
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
