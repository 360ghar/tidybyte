import WidgetKit
import SwiftUI

struct StorageWidgetView: View {
    let entry: StorageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            // `supportedFamilies` is fixed to small + medium, so both cases are
            // covered explicitly; the default is required only to satisfy
            // exhaustiveness over the rest of `WidgetFamily` (unreachable at
            // runtime given the declared families).
            switch family {
            case .systemSmall:
                smallView(snapshot)
            case .systemMedium:
                mediumView(snapshot)
            default:
                EmptyView()
            }
        } else {
            placeholderView
        }
    }

    // MARK: - Small

    private func smallView(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            storageRing(snapshot, size: 70, lineWidth: 8)
            Spacer(minLength: 0)
            if let freed = snapshot.lifetimeFreedBytes, freed > 0 {
                Label("Freed \(fmt(freed))", systemImage: "arrow.down.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            Label("\(snapshot.screenshotCount + snapshot.largeFileCount) to clean",
                  systemImage: "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "tidybyte://storage"))
    }

    // MARK: - Medium

    private func mediumView(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 16) {
            storageRing(snapshot, size: 84, lineWidth: 9)

            VStack(alignment: .leading, spacing: 6) {
                Text("TidyByte")
                    .font(.headline)

                Link(destination: URL(string: "tidybyte://cleanup/screenshots")!) {
                    statRow(icon: "camera.viewfinder",
                            text: "\(snapshot.screenshotCount) screenshots",
                            detail: fmt(snapshot.screenshotBytes))
                }

                Link(destination: URL(string: "tidybyte://cleanup/largeFiles")!) {
                    statRow(icon: "externaldrive",
                            text: "\(snapshot.largeFileCount) large files",
                            detail: fmt(snapshot.largeFileBytes))
                }

                if let freed = snapshot.lifetimeFreedBytes, freed > 0 {
                    // Tappable: same destination as the Activity & Savings
                    // screen, without spending any extra height in the widget.
                    Button(intent: ShowSavingsWidgetIntent()) {
                        Label("Freed \(fmt(freed)) so far", systemImage: "arrow.down.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("Reclaim ~\(fmt(snapshot.reclaimableBytes))", systemImage: "arrow.down.circle")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }

                quickActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "tidybyte://storage"))
    }

    /// Interactive row: each button runs an intent in the app's process and
    /// hands the destination over through the App Group (`WidgetRoute`).
    /// `.mini` control size keeps the row inside the medium widget's height
    /// budget alongside the ring and the stat rows.
    private var quickActions: some View {
        HStack(spacing: 8) {
            Button(intent: StartSwipeWidgetIntent()) {
                Label("Swipe", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                    .font(.caption2.bold())
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.blue)

            Button(intent: CleanScreenshotsWidgetIntent()) {
                Label("Screenshots", systemImage: "camera.viewfinder")
                    .font(.caption2.bold())
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.orange)
        }
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
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: size * 0.26, weight: .bold))
                Text("used")
                    .font(.system(size: size * 0.13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
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

    private func fmt(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
