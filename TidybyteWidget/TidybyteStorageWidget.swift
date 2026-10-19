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
        // E2: the snapshot completion renders in the real widget (not just the
        // gallery) — fabricated "92 GB used / 214 screenshots" must not show as
        // if it were the user's data. Real snapshot when one exists; the
        // placeholder view handles nil. Gallery previews keep `.sample`.
        let snapshot = context.isPreview ? WidgetSnapshot.sample : AppGroupStore.loadSnapshot()
        completion(StorageEntry(date: Date(), snapshot: snapshot))
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
                // The widget is its own process with its own bundle, so a
                // `Text` literal here resolves against the *extension's*
                // language rather than the app's. When the user overrides the
                // language in TidyByte's Settings, the app writes
                // `AppleLanguages` into the app's preferences domain, which the
                // extension does not read — so the app would be German and the
                // widget English.
                //
                // Injecting the stored choice explicitly closes that gap, and
                // matches what `RootView` does for the app. Both read the same
                // App Group value, so the two can never disagree.
                .environment(\.locale, Self.widgetLocale)
                .environment(\.layoutDirection, Self.widgetLayoutDirection)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Storage & Cleanup")
        .description("See storage used and how much you can clean up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    /// The stored language as a `Locale`, or the device locale when the user
    /// left the choice on Automatic. Region always comes from the device, so a
    /// US user who picks German still sees US date and number conventions —
    /// the same rule `Formatters.locale(for:)` applies.
    private static var widgetLocale: Locale {
        Formatters.locale(for: LanguagePreferenceStore.stored())
    }

    /// Arabic and Hebrew mirror the widget's layout; every other language reads
    /// left to right. Without this the widget stays LTR in those languages
    /// while the app mirrors.
    private static var widgetLayoutDirection: LayoutDirection {
        let resolved = LanguagePreferenceStore.stored() ?? AppLanguage.matchingDeviceLanguage()
        return resolved?.isRightToLeft == true ? .rightToLeft : .leftToRight
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
            reclaimableBytes: 7_600_000_000,
            lifetimeFreedBytes: 4_300_000_000,
            lifetimeItemCount: 612
        )
    }
}
