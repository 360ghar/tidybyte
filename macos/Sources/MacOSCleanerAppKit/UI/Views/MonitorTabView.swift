import SwiftUI
import MacOSCleanerCore

/// Monitor tab: read-only storage growth and forecast surface reusing
/// SpaceForecaster and the stored snapshot timeline. No background work, no
/// auto-delete — this tab only reports.
struct MonitorTabView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        List {
            forecastCard
            timelineCard
        }
        .listStyle(.inset)
        .task {
            if model.storageSnapshots.isEmpty { await model.loadSnapshotHistory() }
            if model.spaceForecast == nil { await model.loadStorageTimeline() }
        }
    }

    @ViewBuilder
    private var forecastCard: some View {
        Section(String(localized: "Storage Forecast")) {
            VStack(alignment: .leading, spacing: Spacing.elementTight) {
                if let forecast = model.spaceForecast {
                    Text(forecast.message)
                        .appFont(.bodyMedium)
                        .foregroundStyle(Color.primary)
                    if forecast.dailyGrowthRate > 0 {
                        Text(String(localized: "Growth rate: \(forecast.dailyGrowthRate.formattedByteCount)/day"))
                            .appFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary)
                        forecastThresholdRow(for: forecast)
                    }
                } else {
                    Text(String(localized: "Not enough history yet: run at least two scans to build a forecast."))
                        .appFont(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Storage forecast"))
    }

    @ViewBuilder
    private func forecastThresholdRow(for forecast: SpaceForecaster.Forecast) -> some View {
        if let days = forecast.daysUntil95PercentFull ?? forecast.daysUntil90PercentFull ?? forecast.daysUntil80PercentFull {
            let text = days == 1
                ? String(localized: "Est. 1 day until the next threshold")
                : String(localized: "Est. \(days) days until the next threshold")
            Text(text)
                .appFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
    }

    @ViewBuilder
    private var timelineCard: some View {
        Section(String(localized: "Storage Timeline")) {
            VStack(alignment: .leading, spacing: Spacing.elementTight) {
                if model.storageSnapshots.isEmpty {
                    Text(String(localized: "No snapshots yet: each scan saves one."))
                        .appFont(.caption)
                        .foregroundStyle(Color.secondary)
                } else {
                    let ordered = model.storageSnapshots.sorted { $0.createdAt < $1.createdAt }
                    ForEach(Array(ordered.suffix(14)), id: \.id) { snapshot in
                        timelineRow(for: snapshot, previous: previousSnapshot(before: snapshot, in: ordered))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Storage timeline"))
    }

    private func previousSnapshot(before snapshot: StorageSnapshot, in ordered: [StorageSnapshot]) -> StorageSnapshot? {
        guard let index = ordered.firstIndex(where: { $0.id == snapshot.id }), index > 0 else { return nil }
        return ordered[index - 1]
    }

    private func timelineRow(for snapshot: StorageSnapshot, previous: StorageSnapshot?) -> some View {
        let delta = previous.map { snapshot.totalBytes - $0.totalBytes }
        return HStack {
            Text(snapshot.createdAt, style: .date)
                .appFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
            Spacer()
            if let delta {
                Text(signedBytes(delta))
                    .appFont(.labelMedium)
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? SemanticScale.warning : SemanticScale.success)
            }
            Text(snapshot.totalBytes.formattedByteCount)
                .appFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func signedBytes(_ value: Int64) -> String {
        value >= 0 ? "+\(value.formattedByteCount)" : "−\(abs(value).formattedByteCount)"
    }
}
