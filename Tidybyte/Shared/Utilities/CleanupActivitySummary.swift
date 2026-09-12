import Foundation

/// A single successful cleanup, flattened out of SwiftData so the summary math
/// is pure and unit-testable. The Activity view model maps
/// `CleanupActivityRecord` + `CompressionRecord` rows into these.
struct CleanupEvent: Sendable, Equatable {
    let kind: CleanupActivityKind
    let itemCount: Int
    let freedBytes: Int64
    let date: Date
}

/// Rollup of the cleanup ledger. Pure value type: every figure the Activity
/// screen and the widget's "Freed ..." line show comes from here, so the two
/// surfaces can't drift apart.
struct CleanupActivitySummary: Sendable, Equatable {
    struct DayBucket: Identifiable, Sendable, Equatable {
        let day: Date
        let bytes: Int64
        let itemCount: Int
        var id: Date { day }
    }

    struct ToolBreakdown: Identifiable, Sendable, Equatable {
        let kind: CleanupActivityKind
        let count: Int
        let bytes: Int64
        var id: String { kind.rawValue }
    }

    /// How many days of history the chart covers (today inclusive).
    static let chartWindowDays = 30

    var lifetimeFreedBytes: Int64 = 0
    var lifetimeItemCount: Int = 0
    var monthFreedBytes: Int64 = 0
    /// Oldest → newest, exactly `chartWindowDays` entries, zero-filled for days
    /// with no cleanup so the chart never has gaps.
    var daily: [DayBucket] = []
    /// Kinds with at least one event, most reclaimed first.
    var byTool: [ToolBreakdown] = []
    /// Newest first.
    var recent: [CleanupEvent] = []

    var isEmpty: Bool { lifetimeItemCount == 0 }

    /// Days on which something was actually cleaned — used by the "N days
    /// active" line and to decide whether the chart is worth drawing.
    var activeDayCount: Int {
        daily.filter { $0.itemCount > 0 }.count
    }

    static func build(
        events: [CleanupEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CleanupActivitySummary {
        var summary = CleanupActivitySummary()

        for event in events {
            summary.lifetimeFreedBytes += event.freedBytes
            summary.lifetimeItemCount += event.itemCount
            if calendar.isDate(event.date, equalTo: now, toGranularity: .month) {
                summary.monthFreedBytes += event.freedBytes
            }
        }

        summary.daily = dailyBuckets(events: events, now: now, calendar: calendar)
        summary.byTool = toolBreakdowns(events: events)
        summary.recent = events.sorted { $0.date > $1.date }

        return summary
    }

    /// Last `chartWindowDays` days, oldest first, one bucket per calendar day.
    /// Days with no events are present with zero bytes so `BarMark` renders a
    /// continuous axis.
    static func dailyBuckets(
        events: [CleanupEvent],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DayBucket] {
        let today = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(byAdding: .day, value: -(chartWindowDays - 1), to: today) else {
            return []
        }

        var bytesByDay: [Date: (bytes: Int64, items: Int)] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            guard day >= firstDay, day <= today else { continue }
            var entry = bytesByDay[day] ?? (0, 0)
            entry.bytes += event.freedBytes
            entry.items += event.itemCount
            bytesByDay[day] = entry
        }

        return (0..<chartWindowDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            let entry = bytesByDay[day] ?? (0, 0)
            return DayBucket(day: day, bytes: entry.bytes, itemCount: entry.items)
        }
    }

    static func toolBreakdowns(events: [CleanupEvent]) -> [ToolBreakdown] {
        var byKind: [CleanupActivityKind: (count: Int, bytes: Int64)] = [:]
        for event in events {
            var entry = byKind[event.kind] ?? (0, 0)
            entry.count += event.itemCount
            entry.bytes += event.freedBytes
            byKind[event.kind] = entry
        }
        return byKind
            .map { ToolBreakdown(kind: $0.key, count: $0.value.count, bytes: $0.value.bytes) }
            // Bytes desc, then raw value asc so ties order deterministically
            // (dictionary iteration order is not stable).
            .sorted {
                $0.bytes == $1.bytes
                    ? $0.kind.rawValue < $1.kind.rawValue
                    : $0.bytes > $1.bytes
            }
    }
}
