import SwiftUI

struct CleanupHomeView: View {
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @State private var viewModel = CleanupHomeViewModel()

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
                        itemCount: viewModel.reclaimableItemCount,
                        thresholdLabel: viewModel.largeFileThresholdLabel
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
            await viewModel.refreshCounts()
        }
        .task(id: libraryMonitor.generation) {
            await viewModel.sync(to: libraryMonitor.generation)
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
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(tool.color.gradient)
                        .scaledSquare(ScaledSize.toolCardIcon)

                    Image(systemName: tool.icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Spacer()

                badgeView(for: tool)
            }

            HStack(alignment: .bottom, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(tool.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.8)

                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if isStartHere {
                        Label("Start here", systemImage: "arrow.right.circle.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                            .padding(.top, 2)
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        // One element per card: VoiceOver otherwise reads the icon, the count
        // badge, the title, the description, and "Start here" as five separate
        // stops with the badge number stripped of its meaning.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func badgeView(for tool: CleanupToolInfo) -> some View {
        if tool.isLoading {
            SkeletonView(cornerRadius: CornerRadius.full)
                .frame(width: 36, height: 20)
        } else if let count = tool.count {
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(count > 0 ? tool.color : Color.gray)
                .clipShape(Capsule())
        } else {
            // These four tools cost a full scan to count, so the badge promises
            // a scan instead of implying the library contains none.
            Text("Not scanned")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.cardSurface)
                .clipShape(Capsule())
        }
    }
}
