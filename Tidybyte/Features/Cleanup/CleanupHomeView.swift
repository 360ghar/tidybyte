import SwiftUI
import SwiftData

struct CleanupHomeView: View {
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CleanupHomeViewModel()

    /// Replacement-copy ids persisted by the compression flows. The badge must
    /// exclude them exactly like `PhotoCompressionViewModel.candidates` does,
    /// or the home screen shows a stale nonzero badge after compression.
    private func savedReplacementIds() -> Set<String> {
        CompressionJournal.savedCopyIds(modelContext: modelContext)
    }

    private let columns = ResponsiveGrid.card()

    /// The single tool to point at first: the biggest pile in the group the user
    /// can act on immediately. Nil until counts land, and nil when nothing in
    /// that group has anything to clean — a "Start here" badge on a zero would
    /// be worse than none.
    private var startHereTool: CleanupTool? {
        CleanupToolCategory.freeUpSpace.tools
            .compactMap { tool -> (CleanupTool, Int)? in
                guard let count = viewModel.info(for: tool)?.count, count > 0 else { return nil }
                return (tool, count)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Limited access is the state that makes every tool look broken,
                // so it is surfaced before the tools themselves.
                LimitedLibraryBanner()

                if viewModel.hasLoadedCounts, viewModel.reclaimableBytes > 0 {
                    ReclaimableHeroCard(
                        bytes: viewModel.reclaimableBytes,
                        itemCount: viewModel.reclaimableItemCount
                    )
                    .fadeSlideIn()
                }

                ForEach(CleanupToolCategory.allCases) { category in
                    section(for: category)
                }
            }
            .padding(Spacing.lg)
        }
        .navigationTitle("Cleanup")
        .pullToRefresh {
            await viewModel.refreshCounts(excludingCompressedCopies: savedReplacementIds())
        }
        .task(id: libraryMonitor.generation) {
            await viewModel.sync(to: libraryMonitor.generation, excludingCompressedCopies: savedReplacementIds)
        }
        .onAppear {
            // Back from a scan tool: show its fresh result.
            if viewModel.hasLoadedCounts { viewModel.applyScanResults() }
        }
    }

    // MARK: - Section

    private func section(for category: CleanupToolCategory) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.title3.bold())

                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(Array(category.tools.enumerated()), id: \.element) { index, tool in
                    if let info = viewModel.info(for: tool) {
                        Button {
                            appNavigation.showCleanup(tool: info.tool)
                        } label: {
                            cleanupToolCard(info, isStartHere: info.tool == startHereTool)
                        }
                        .buttonStyle(.plain)
                        .scaleOnPress()
                        .fadeSlideIn(delay: Double(index) * 0.04)
                    }
                }
            }
        }
    }

    // MARK: - Card

    private func cleanupToolCard(_ tool: CleanupToolInfo, isStartHere: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                // Bare glyph in the tool's color: no tile behind it.
                // Fixed box: SF Symbols differ in height, and a taller glyph
                // pushed one card's text below its neighbour's.
                Image(systemName: tool.icon)
                    .font(.title2)
                    .foregroundStyle(tool.color)
                    .scaledSquare(32)
                    .accessibilityHidden(true)

                Spacer()

                badgeView(for: tool)
            }

            // Pushes the text block to the bottom, so cards stretched to the
            // row height keep their chevrons on one line.
            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(tool.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .minimumScaleFactor(0.8)

                    // Always laid out, shown on one card only, so that card is
                    // not taller than its neighbour.
                    Label("Start here", systemImage: "arrow.right.circle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                        .opacity(isStartHere ? 1 : 0)
                        .accessibilityHidden(!isStartHere)
                }

                Spacer(minLength: 0)

                // Signals "this opens a tool" rather than "this starts a scan" —
                // which the "Not scanned" badge alone left ambiguous.
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
        }
        // Every card fills its grid row, so neighbours share top and bottom
        // edges even when one title wraps.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
        // One element per card: VoiceOver otherwise reads the icon, the count
        // badge, the title, the description, and "Start here" as five separate
        // stops with the badge number stripped of its meaning.
        .accessibilityElement(children: .combine)
    }

    /// Plain text, not a colored pill: the number in the primary ink, the
    /// "nothing yet" states in secondary.
    @ViewBuilder
    private func badgeView(for tool: CleanupToolInfo) -> some View {
        if tool.isLoading {
            SkeletonView(cornerRadius: CornerRadius.small)
                .frame(width: 36, height: 20)
        } else if let count = tool.count, count > 0 {
            Text("\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
        } else if tool.count == 0 {
            Text("None")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        } else {
            // These four tools cost a full scan to count, so the badge promises
            // a scan instead of implying the library contains none.
            Text("Not scanned")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
