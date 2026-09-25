import SwiftUI

/// "You could free" summary at the top of the cleanup home.
///
/// Shows the app-wide `ReclaimBucketer` total, the same figure as the Storage
/// tab and the widget. It counts only items stored on this device, and Live
/// Photos and large videos at about half their size (the usual saving from
/// converting or compressing them). Duplicates, similar and blurry photos need
/// a scan, so they are not in the number.
struct ReclaimableHeroCard: View {
    let bytes: Int64
    let itemCount: Int

    private var itemLabel: String {
        "\(itemCount) \(itemCount == 1 ? "item" : "items")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("You Could Free")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Text("Up to \(bytes.formattedFileSize)")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("On this device, from \(itemLabel): screenshots, Live Photos, large videos, photos saved from apps and large files.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Live Photos and large videos count at about half their size. A scan for duplicates, similar and blurry photos usually finds more.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        // VoiceOver reading "2.4 GB" without context tells the user nothing, so
        // the card is one element with the whole sentence as its label.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You could free up to \(bytes.formattedFileSize) on this device, from \(itemLabel)")
    }
}
