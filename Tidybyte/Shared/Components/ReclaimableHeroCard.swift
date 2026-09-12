import SwiftUI

/// "What's worth looking at" summary at the top of the cleanup home.
///
/// The number is deliberately narrow. It measures the screenshots plus the files
/// over the threshold — both computed in the single library pass the tool badges
/// already do — and describes them as "in files worth a look", not as space the
/// user will definitely free. Duplicates, similar photos, and blurry shots need
/// a real scan, so any number claimed for them here would be invented.
struct ReclaimableHeroCard: View {
    let bytes: Int64
    let itemCount: Int
    let thresholdLabel: String

    private var itemLabel: String {
        "\(itemCount) \(itemCount == 1 ? "item" : "items")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("Worth a Look")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            Text(bytes.formattedFileSize)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("across \(itemLabel) — your screenshots and files over \(thresholdLabel).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Scanning for duplicates, similar, and blurry photos usually finds more.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        // VoiceOver reading "2.4 GB" without context tells the user nothing, so
        // the card is one element with the whole sentence as its label.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("About \(bytes.formattedFileSize) across \(itemLabel), from your screenshots and files over \(thresholdLabel)")
    }
}
