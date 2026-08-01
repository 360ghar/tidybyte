import SwiftUI
import SwiftData

struct CompressionHistoryView: View {
    @Query(sort: \CompressionRecord.compressedAt, order: .reverse) private var records: [CompressionRecord]

    /// COMP-01: failed records carry `compressedSizeBytes == 0`; summing them
    /// would inflate the total with fake savings. Only completed rows count.
    var totalSaved: Int64 {
        records.reduce(0) { $0 + $1.savedBytes }
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
                                Text("\(records.count) compressions")
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
                            Image(systemName: record.mediaType == "photo" ? "photo" : "video")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(record.compressedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)

                                Text(record.exportPreset)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(record.outcome.capitalized)
                                    .font(.caption2.bold())
                                    // Three-state, matching the savings badge:
                                    // completed → green, failed → red, skipped
                                    // (intentional) → neutral.
                                    .foregroundStyle(record.isFailed ? .red : record.succeeded ? .green : .secondary)

                                if record.replacementAssetLocalIdentifier != nil {
                                    Text("Replacement saved to library")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.xs) {
                                    Text(record.originalSizeBytes.formattedFileSize)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(record.compressedSizeBytes.formattedFileSize)
                                        .foregroundStyle(.primary)
                                }
                                .font(.caption.monospacedDigit())

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
                .pullToRefresh {
                    // `@Query` is live and auto-updates from SwiftData, so there is no
                    // manual fetch to re-run. Yield to keep the gesture/haptic affordance
                    // consistent app-wide without faking work.
                    await Task.yield()
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
