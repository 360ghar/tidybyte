import WidgetKit
import SwiftUI

struct StorageWidgetView: View {
    let entry: StorageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            // `supportedFamilies` is small + medium today, but the family the
            // system hands us is not ours to guarantee: a wider one (as iPad's
            // extraLarge did) must degrade to the medium layout rather than
            // render an empty widget.
            switch family {
            case .systemSmall:
                smallView(snapshot)
            case .systemMedium:
                mediumView(snapshot)
            default:
                // An unexpected family (a wider one than we declare today, the
                // way iPad's extraLarge arrived) degrades to the medium layout
                // instead of rendering an empty widget.
                mediumView(snapshot)
            }
        } else {
            placeholderView
        }
    }

    // MARK: - Small

    private func smallView(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            storageRing(snapshot, size: 70, lineWidth: 8)
            Spacer(minLength: 0)
            Text(headline(snapshot))
                .font(.caption2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let age = ageLabel(snapshot) {
                Text(age)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "tidybyte://storage"))
    }

    // MARK: - Medium

    private func mediumView(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            storageRing(snapshot, size: 84, lineWidth: 9)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline(snapshot))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Link(destination: URL(string: "tidybyte://cleanup/screenshots")!) {
                    statRow(icon: "camera.viewfinder",
                            text: L10n.format("%lld screenshot", snapshot.screenshotCount),
                            detail: fmt(snapshot.screenshotBytes))
                }

                Link(destination: URL(string: "tidybyte://cleanup/largeFiles")!) {
                    statRow(icon: "externaldrive",
                            text: L10n.format("%lld large file", snapshot.largeFileCount),
                            detail: fmt(snapshot.largeFileBytes))
                }

                if let freed = snapshot.lifetimeFreedBytes, freed > 0 {
                    // Tappable: opens Activity & Savings.
                    Button(intent: ShowSavingsWidgetIntent()) {
                        Text("Cleaned up \(fmt(freed)) so far")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if let age = ageLabel(snapshot) {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "tidybyte://storage"))
    }

    /// The total counts only items on this iPhone; the rows below count the
    /// whole library (what the tools list), so the headline says so.
    ///
    /// Built in code rather than as a `Text` literal, so it goes through `L10n`:
    /// the widget has no `\.locale` environment of its own to resolve a
    /// `LocalizedStringKey` against.
    private func headline(_ snapshot: WidgetSnapshot) -> String {
        snapshot.reclaimableBytes > 0
            ? L10n.format("Up to %@ to free on iPhone", fmt(snapshot.reclaimableBytes))
            : L10n.string("Nothing to free on iPhone")
    }

    /// "Updated 3d ago" once the snapshot is a day old (the app rescans only
    /// when it opens), and a nudge to open the app after a week.
    private func ageLabel(_ snapshot: WidgetSnapshot) -> String? {
        let age = entry.date.timeIntervalSince(snapshot.capturedAt)
        guard age >= 86_400 else { return nil }
        let days = Int(age / 86_400)
        return days >= 7
            ? L10n.string("Open TidyByte to refresh")
            : L10n.format("Updated %lldd ago", days)
    }

    // MARK: - Pieces

    private func storageRing(_ snapshot: WidgetSnapshot, size: CGFloat, lineWidth: CGFloat) -> some View {
        let fraction = snapshot.totalBytes > 0
            ? min(1, max(0, Double(snapshot.usedBytes) / Double(snapshot.totalBytes)))
            : 0
        return ZStack {
            Circle()
                .stroke(.gray.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.blue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                // `verbatim`: see `GroupComparisonView`. The ring's number is
                // language-independent, so it needs no catalog entry.
                Text(verbatim: "\(Int(fraction * 100))%")
                    .font(.system(size: size * 0.26, weight: .bold))
                Text("used")
                    .font(.system(size: size * 0.13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage \(Int(fraction * 100)) percent used")
    }

    private func statRow(icon: String, text: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(detail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(.blue)
            Text("Open TidyByte to scan your library")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "tidybyte://storage"))
    }

    /// Locale-aware, and shared with the app so the widget and the Storage tab
    /// never disagree about what "1.5 GB" looks like. `ByteCountFormatter` has
    /// no locale API at all, so it rendered a period as the decimal separator
    /// for every user regardless of their language.
    private func fmt(_ bytes: Int64) -> String {
        Formatters.fileSize(bytes)
    }
}
