import SwiftUI

struct CleanupHomeView: View {
    @Environment(AppNavigation.self) private var appNavigation
    @Environment(LibraryChangeMonitor.self) private var libraryMonitor
    @State private var viewModel = CleanupHomeViewModel()

    private let columns = ResponsiveGrid.card()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(Array(viewModel.tools.enumerated()), id: \.element.id) { index, tool in
                    Button {
                        appNavigation.showCleanup(tool: tool.tool)
                    } label: {
                        cleanupToolCard(tool)
                    }
                    .buttonStyle(.plain)
                    .scaleOnPress()
                    .fadeSlideIn(delay: Double(index) * 0.04)
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

    private func cleanupToolCard(_ tool: CleanupToolInfo) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(tool.color.gradient)
                        .frame(width: 44, height: 44)

                    Image(systemName: tool.icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Spacer()

                // Badge
                badgeView(for: tool)
            }

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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
            Text("Scan")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.cardSurface)
                .clipShape(Capsule())
        }
    }
}
