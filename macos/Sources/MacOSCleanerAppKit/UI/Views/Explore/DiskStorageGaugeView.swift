import MacOSCleanerCore
import SwiftUI

struct DiskStorageGaugeView: View {
    @State private var snapshot = DiskGaugeData.currentHomeVolume()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            HStack {
                Label(String(localized: "Mac storage"), systemImage: "internaldrive")
                    .font(.title2.bold())
                Spacer()
                Button {
                    snapshot = DiskGaugeData.currentHomeVolume()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Refresh disk capacity"))
                .accessibilityLabel(String(localized: "Refresh disk capacity"))
            }
            if let total = snapshot.totalBytes, let free = snapshot.freeBytes, total > 0 {
                let used = max(0, total - free)
                Text(String(localized: "\(free.formattedByteCount) available of \(total.formattedByteCount)"))
                    .font(.title3).monospacedDigit()
                ProgressView(value: Double(used), total: Double(total))
                    .accessibilityLabel(String(localized: "Whole-disk storage"))
                    .accessibilityValue(
                        String(localized: "\(used.formattedByteCount) used, \(free.formattedByteCount) available"))
                Text(String(localized: "Whole-disk capacity · \(used.formattedByteCount) used"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Disk capacity is unavailable. Refresh to try again."))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.elementNormal)
    }
}
