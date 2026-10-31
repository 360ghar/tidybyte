import MacOSCleanerCore
import SwiftUI

/// Shared empty state for the Explore visualizations.
struct ExploreEmptyState: View {

    var body: some View {
        VStack(spacing: Spacing.elementTight) {
            Image(systemName: "folder")
                .appFont(.h3, color: Color.secondary)
            Text(String(localized: "Nothing to visualize yet.", comment: "Explore empty state title"))
                .appFont(.bodyMedium)
                .foregroundStyle(Color.secondary)
            Text(String(localized: "Run a scan or clear the name filter to fill this view.", comment: "Explore empty state hint"))
                .appFont(.caption)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Nothing to visualize yet. Run a scan or clear the name filter."))
    }
}

/// Which visualization the Explore switcher shows.
enum ExploreViewKind: String, CaseIterable, Identifiable, Sendable {
    case list
    case folders
    case sunburst
    case flame
    case bubbles
    case mindMap
    case topSizes
    case ageMap
    case treemap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:
            String(localized: "List")
        case .folders:
            String(localized: "Folders", comment: "Explore view title")
        case .sunburst:
            String(localized: "Sunburst", comment: "Explore view title")
        case .flame:
            String(localized: "Flame", comment: "Explore view title")
        case .bubbles:
            String(localized: "Bubbles", comment: "Explore view title")
        case .mindMap:
            String(localized: "Mind Map", comment: "Explore view title")
        case .topSizes:
            String(localized: "Top Sizes", comment: "Explore view title")
        case .ageMap:
            String(localized: "Age Map", comment: "Explore view title")
        case .treemap:
            String(localized: "Treemap", comment: "Explore view title")
        }
    }

    /// DiskBuddy-style one-line explainer shown under the picker.
    var tagline: String {
        switch self {
        case .list:
            String(localized: "Browse scanned files.")
        case .folders:
            String(localized: "Browse groups as cards, then drill in.", comment: "Explore view tagline")
        case .sunburst:
            String(localized: "The whole scan as concentric rings.", comment: "Explore view tagline")
        case .flame:
            String(localized: "Depth as stacked bars, top group first.", comment: "Explore view tagline")
        case .bubbles:
            String(localized: "Every group as a bubble, sized by bytes.", comment: "Explore view tagline")
        case .mindMap:
            String(localized: "Branches fanning out from your scan.", comment: "Explore view tagline")
        case .topSizes:
            String(localized: "Biggest groups first, ranked.", comment: "Explore view tagline")
        case .ageMap:
            String(localized: "When files were touched, plus big untouched ones.", comment: "Explore view tagline")
        case .treemap:
            String(localized: "Every file as a rectangle, sized by bytes.", comment: "Explore view title")
        }
    }
}

/// Segmented switcher hosting all Explore visualizations.
/// View/grouping/depth persist across launches via AppViewModel (backed by
/// UserDefaults SettingsKeys); name-filter stays transient. Child views render
/// from the already-scanned `outcome.files` — no new scanning logic.
struct ExploreViewSwitcher: View {
    @Bindable var model: AppViewModel
    var files: [FileRecord]
    var categorySections: [(FindingCategory, Int64)]

    private var nameFilter: String { model.searchText }
    @FocusState private var isFilterFocused: Bool

    private var selectedView: ExploreViewKind {
        ExploreViewKind(rawValue: model.exploreViewKindRaw) ?? .folders
    }

    private var grouping: ExploreGrouping {
        ExploreGrouping(rawValue: model.exploreGroupingRaw) ?? .byFolder
    }

    private var depth: Double {
        Double(max(1, min(10, model.exploreDepth)))
    }

    private var depthInt: Int {
        max(1, min(10, Int(depth)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            controls
            activeView
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selectedView.title)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.elementNormal) {
                groupingPicker
                depthControl
            }
            VStack(alignment: .leading, spacing: Spacing.elementTight) {
                groupingPicker
                depthControl
            }
        }
    }

    private var groupingPicker: some View {
        Picker(
            String(localized: "Group", comment: "Explore grouping picker label"),
            selection: Binding(
                get: { grouping },
                set: {
                    model.exploreGroupingRaw = $0.rawValue
                    model.saveSettings()
                }
            )
        ) {
            ForEach(ExploreGrouping.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
        .accessibilityLabel(String(localized: "Group files by"))
        .disabled(selectedView == .ageMap)
    }

    private var depthControl: some View {
        HStack(spacing: Spacing.elementTight) {
            Text(String(localized: "Depth", comment: "Explore depth slider label"))
                .appFont(.caption)
                .foregroundStyle(Color.secondary)
            Slider(
                value: Binding(
                    get: { depth },
                    set: {
                        model.exploreDepth = max(1, min(10, Int($0)))
                        model.saveSettings()
                    }
                ),
                in: 1...10,
                step: 1
            )
                .frame(maxWidth: 140)
                .accessibilityLabel(String(localized: "Folder depth"))
                .accessibilityValue(String(localized: "\(depthInt) levels"))
            Text("\(depthInt)")
                .appFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
        .disabled(selectedView == .topSizes || selectedView == .ageMap || selectedView == .treemap)
    }

    @ViewBuilder
    private var activeView: some View {
        switch selectedView {
        case .list:
            EmptyView()
        case .folders:
            FoldersGridView(model: model, files: files, grouping: grouping, maxDepth: depthInt, nameFilter: nameFilter)
        case .sunburst:
            SunburstView(model: model, files: files, grouping: grouping, maxDepth: depthInt, nameFilter: nameFilter)
        case .flame:
            FlameView(model: model, files: files, grouping: grouping, maxDepth: depthInt, nameFilter: nameFilter)
        case .bubbles:
            BubblesView(model: model, files: files, grouping: grouping, maxDepth: depthInt, nameFilter: nameFilter)
        case .mindMap:
            MindMapView(model: model, files: files, grouping: grouping, maxDepth: depthInt, nameFilter: nameFilter)
        case .topSizes:
            TopSizesView(model: model, files: files, grouping: grouping, maxDepth: depthInt, nameFilter: nameFilter)
        case .ageMap:
            AgeMapView(model: model, files: files, nameFilter: nameFilter)
        case .treemap:
            TreemapView(sections: categorySections)
                .frame(height: 170)
        }
    }
}
