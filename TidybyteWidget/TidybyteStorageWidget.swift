import WidgetKit
import SwiftUI

struct StorageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Renders only the last `WidgetSnapshot` the app wrote to the App Group — never
/// touches PhotoKit. The app pushes refreshes via
/// `WidgetCenter.shared.reloadAllTimelines()`; the hourly `.after` policy is a
/// passive fallback so relative timestamps don't go stale.
struct StorageProvider: TimelineProvider {
    func placeholder(in context: Context) -> StorageEntry {
        StorageEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        completion(StorageEntry(date: Date(), snapshot: AppGroupStore.loadSnapshot() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        let entry = StorageEntry(date: Date(), snapshot: AppGroupStore.loadSnapshot())
        let next = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TidybyteStorageWidget: Widget {
    let kind = "TidybyteStorageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StorageProvider()) { entry in
            StorageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Storage & Cleanup")
        .description("See storage used and how much you can clean up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension WidgetSnapshot {
    /// Placeholder data for the widget gallery / redacted states.
    static var sample: WidgetSnapshot {
        WidgetSnapshot(
            capturedAt: Date(),
            usedBytes: 92_000_000_000,
            totalBytes: 128_000_000_000,
            screenshotCount: 214,
            screenshotBytes: 1_400_000_000,
            largeFileCount: 18,
            largeFileBytes: 6_200_000_000,
            reclaimableBytes: 7_600_000_000
        )
    }
}
