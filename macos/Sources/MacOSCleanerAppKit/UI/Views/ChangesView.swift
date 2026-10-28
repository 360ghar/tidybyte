import Charts
import MacOSCleanerCore
import SwiftUI

/// Insights › Changes: how storage moved over time. A toolbar segmented
/// control switches between the forecast, a two-scan comparison, and the
/// Photos & Media trend.
struct ChangesView: View {
    @Bindable var model: AppViewModel
    @SceneStorage("changesMode") private var mode = Mode.forecast

    enum Mode: String, CaseIterable, Identifiable {
        case forecast, compare, media
        var id: String { rawValue }
        var title: String {
            switch self {
            case .forecast: String(localized: "Forecast")
            case .compare: String(localized: "Compare Scans")
            case .media: String(localized: "Photos & Media")
            }
        }
    }

    var body: some View {
        Group {
            switch mode {
            case .forecast: MonitorTabView(model: model)
            case .compare: SnapshotDiffView(model: model)
            case .media: MediaTrendView(model: model.cleanup)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "View"), selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}

private struct MediaTrendView: View {
    @Bindable var model: CleanupModel

    var body: some View {
        if model.snapshots.count >= 2, let first = model.snapshots.first, let last = model.snapshots.last {
            Form {
                Section {
                    Chart(model.snapshots) {
                        LineMark(
                            x: .value(String(localized: "Date"), $0.date),
                            y: .value(String(localized: "Size"), $0.bytes))
                        .interpolationMethod(.monotone)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel { Text(Int64(value.as(Double.self) ?? 0).formattedByteCount) }
                        }
                    }
                    .frame(minHeight: 220)
                    .accessibilityLabel(trendLabel(first, last))
                } footer: {
                    Text(trendLabel(first, last))
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                String(localized: "No trend yet"), systemImage: "chart.line.uptrend.xyaxis",
                description: Text(String(localized: "Scan on two different days to see how this scope changes.")))
        }
    }

    private func trendLabel(_ first: CleanupSnapshot, _ last: CleanupSnapshot) -> String {
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        let delta = last.bytes - first.bytes
        return delta < 0
            ? String(localized: "Shrank by \((-delta).formattedByteCount) in \(days) days")
            : String(localized: "Grew by \(delta.formattedByteCount) in \(days) days")
    }
}
