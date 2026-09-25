import SwiftUI
import Charts

/// Lifetime cleanup history: what was freed, when, and by which tool.
///
/// Reached by a push inside the Storage tab (and `tidybyte://activity`). Reads
/// only from the ledger — it never scans the library, so it opens instantly.
struct ActivityView: View {
    @State private var viewModel = ActivityViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                skeleton
            } else if viewModel.summary.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Savings Yet",
                    message: "Space you free up with any cleanup tool shows up here.",
                    iconColor: .green
                )
                .padding(.top, Spacing.xxxl)
            } else {
                VStack(spacing: Spacing.xl) {
                    heroSection
                        .fadeSlideIn(delay: 0.0)

                    if viewModel.summary.activeDayCount > 0 {
                        chartSection
                            .fadeSlideIn(delay: 0.05)
                    }

                    breakdownSection
                        .fadeSlideIn(delay: 0.1)

                    recentSection
                        .fadeSlideIn(delay: 0.15)
                }
                .padding(Spacing.lg)
                .readableWidth()
            }
        }
        .navigationTitle("Activity & Savings")
        .navigationBarTitleDisplayMode(.inline)
        .pullToRefresh {
            viewModel.refresh(modelContext: modelContext)
        }
        .task(id: libraryMonitor.generation) {
            viewModel.sync(to: libraryMonitor.generation, modelContext: modelContext)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        GlassCard {
            VStack(spacing: Spacing.md) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)

                VStack(spacing: Spacing.xs) {
                    // A library made up entirely of iCloud-only assets reports
                    // 0 bytes for every item, so a literal "Zero KB" hero would
                    // be both ugly and misleading — the items WERE cleaned, the
                    // sizes just weren't readable on this device.
                    Text(heroValue)
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .monospacedDigit()
                    Text(heroCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if viewModel.summary.lifetimeFreedBytes > 0 {
                        // Deleted items sit in Recently Deleted for 30 days, so
                        // iPhone Storage in Settings does not drop right away.
                        Text("Space comes back after Photos empties Recently Deleted (up to 30 days).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                HStack(spacing: Spacing.xl) {
                    statPill(
                        value: "\(viewModel.summary.lifetimeItemCount)",
                        label: "items, all time"
                    )
                    statPill(
                        value: "\(viewModel.summary.activeDayCount)",
                        label: viewModel.summary.activeDayCount == 1 ? "active day, 30 days" : "active days, 30 days"
                    )
                    statPill(
                        value: bytesLabel(viewModel.summary.monthFreedBytes),
                        label: "this month"
                    )
                }
            }
        }
    }

    private var heroValue: String {
        viewModel.summary.lifetimeFreedBytes > 0
            ? viewModel.summary.lifetimeFreedBytes.formattedFileSize
            : "Size unknown"
    }

    private var heroCaption: String {
        viewModel.summary.lifetimeFreedBytes > 0
            ? "cleaned up since you started using TidyByte"
            : "Nothing measurable yet. Items stored only in iCloud don't report a size."
    }

    /// Byte label that never renders a bare "Zero KB" for a real cleanup.
    private func bytesLabel(_ bytes: Int64) -> String {
        bytes > 0 ? bytes.formattedFileSize : "—"
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 30-day chart

    private var chartSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Last 30 Days")
                    .font(.headline)

                Chart(viewModel.summary.daily) { bucket in
                    BarMark(
                        x: .value("Day", bucket.day, unit: .day),
                        y: .value("Freed", bucket.bytes)
                    )
                    .foregroundStyle(Color.green.gradient)
                    .cornerRadius(CornerRadius.small)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            // Skip the zero tick: a cleanup of iCloud-only items
                            // has 0 bytes but real items, and "Zero KB" on the
                            // axis would read like nothing happened.
                            if let bytes = value.as(Int64.self), bytes > 0 {
                                Text(bytes.formattedFileSize)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 140)
                // A Chart is one opaque accessibility element by default, so a
                // VoiceOver user hears "chart" and nothing else. Summarize the
                // data instead.
                .accessibilityElement()
                .accessibilityLabel("Space cleaned up per day over the last 30 days")
                .accessibilityValue(
                    viewModel.summary.daily.isEmpty
                    ? "No activity"
                    : "\(bytesLabel(viewModel.summary.last30DaysFreedBytes)) cleaned up in the last 30 days"
                )

                Text("\(bytesLabel(viewModel.summary.last30DaysFreedBytes)) cleaned up in the last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Per-tool breakdown

    private var breakdownSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Where It Came From")
                    .font(.headline)

                ForEach(viewModel.summary.byTool) { entry in
                    breakdownRow(entry)
                }
            }
        }
    }

    private func breakdownRow(_ entry: CleanupActivitySummary.ToolBreakdown) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: entry.kind.icon)
                .foregroundStyle(color(for: entry.kind))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.kind.title)
                    .font(.subheadline.bold())
                Text("\(entry.count) item\(entry.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(bytesLabel(entry.bytes))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(entry.bytes > 0 ? .green : .secondary)
        }
        .padding(.vertical, Spacing.xs)
    }

    private func color(for kind: CleanupActivityKind) -> Color {
        kind.tool?.color ?? .blue
    }

    // MARK: - Recent activity

    private var recentSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Recent Cleanups")
                    .font(.headline)

                ForEach(Array(viewModel.summary.recent.prefix(25).enumerated()), id: \.offset) { _, event in
                    recentRow(event)
                }

                Text("Only the first 25 are listed. Space freed by cleaning items stored only in iCloud may not be counted.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    private func recentRow(_ event: CleanupEvent) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: event.kind.icon)
                .font(.caption)
                .foregroundStyle(color(for: event.kind))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(event.kind.title)
                    .font(.subheadline)
                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(event.itemCount == 1 ? "1 item" : "\(event.itemCount) items")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if event.freedBytes > 0 {
                    Text("-\(event.freedBytes.formattedFileSize)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Skeleton

    private var skeleton: some View {
        VStack(spacing: Spacing.xl) {
            SkeletonView(cornerRadius: CornerRadius.large)
                .frame(height: 200)
            SkeletonView(cornerRadius: CornerRadius.large)
                .frame(height: 220)
            SkeletonView(cornerRadius: CornerRadius.large)
                .frame(height: 160)
        }
        .padding(Spacing.lg)
    }
}
