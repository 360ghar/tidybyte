import SwiftUI
import SwiftData

struct CompressionHistoryView: View {
    @Query(sort: \CompressionRecord.compressedAt, order: .reverse) private var records: [CompressionRecord]

    /// COMP-01: failed records carry `compressedSizeBytes == 0`; summing them
    /// would inflate the total with fake savings. Only completed rows count.
    var totalSaved: Int64 {
        records.reduce(0) { $0 + $1.savedBytes }
    }

    /// D15: "N compressions" means completed swaps — skipped (no savings) and
    /// failed attempts are not compressions.
    var completedCount: Int {
        records.filter(\.succeeded).count
    }

    static func icon(for mediaType: String) -> String {
        switch mediaType {
        case "photo": "photo"
        case "livePhoto": "livephoto"
        default: "video"
        }
    }

    /// Readable preset names instead of raw ids ("balanced", "still").
    static func presetLabel(_ id: String) -> String {
        if id == "still" { return "Still image" }
        if let video = CompressionPreset.presets.first(where: { $0.id == id }) { return video.label }
        if let photo = PhotoCompressionPreset.presets.first(where: { $0.id == id }) { return photo.label }
        return id
    }

    var body: some View {
        Group {
            if records.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No History",
                    message: "Compressed photos and videos will appear here.",
                    iconColor: .indigo
                )
            } else {
                List {
                    // Summary
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("\(completedCount) compressions")
                                    .font(.headline)
                                Text("Total saved: \(totalSaved.formattedFileSize)")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title)
                                .foregroundStyle(.green)
                        }
                        .glassCard()
                        .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    // Records
                    ForEach(records) { record in
                        HStack(spacing: Spacing.md) {
                            Image(systemName: Self.icon(for: record.mediaType))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(record.compressedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)

                                Text(Self.presetLabel(record.exportPreset))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if record.replacementAssetLocalIdentifier != nil {
                                    Text("Replacement saved to library")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: Spacing.xs) {
                                // The arrow only when a copy exists: a failed or
                                // skipped row showing "12 MB → Zero KB" read as
                                // a 100% saving.
                                if record.succeeded || record.replacementAssetLocalIdentifier != nil {
                                    HStack(spacing: Spacing.xs) {
                                        Text(record.originalSizeBytes.formattedFileSize)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("to")
                                        Text(record.compressedSizeBytes.formattedFileSize)
                                            .foregroundStyle(.primary)
                                    }
                                    .font(.caption.monospacedDigit())
                                } else {
                                    Text(record.originalSizeBytes.formattedFileSize)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                // COMP-01: failed rows show a "Failed" badge with
                                // zero savings instead of a misleading green
                                // "-X" (compressedSizeBytes == 0 would compute
                                // savings equal to the whole original). Skipped
                                // records (no savings / kept original) are NOT
                                // failures — they render the neutral "No
                                // savings" label instead of a red badge.
                                if record.isFailed {
                                    Text("Failed")
                                        .font(.caption.bold())
                                        .foregroundStyle(.red)
                                } else if record.savedBytes > 0 {
                                    Text("-\(record.savedBytes.formattedFileSize)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                } else {
                                    Text("No savings")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                // No pull-to-refresh: `@Query` is live and auto-updates from
                // SwiftData, so a manual refresh gesture could only fake work.
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
