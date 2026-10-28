import AppKit
import Charts
import MacOSCleanerCore
import SwiftUI

struct CleanupActivityView: View {
    @Bindable var model: CleanupModel
    private var completed: [ActivityEvent] { model.activity.filter { $0.state == .complete && !$0.restored } }
    private func total(where matches: (ActivityEvent) -> Bool) -> String {
        completed.filter(matches).reduce(0) { $0 + $1.savings }.formattedByteCount
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.elementSection) {
                Text(completed.reduce(0) { $0 + $1.savings }.formattedByteCount).font(.largeTitle).monospacedDigit()
                Text(String(localized: "\(completed.count) items processed"))
                Text(
                    String(
                        localized: """
                            Space returns when Trash or Recently Deleted is emptied. These totals \
                            record logical bytes removed or reduced, not measured free disk space.
                            """
                    )
                )
                .foregroundStyle(.secondary)
                LabeledContent(
                    String(localized: "Sent to Trash"), value: total { $0.action == "trash" && $0.item.url != nil })
                LabeledContent(
                    String(localized: "Sent to Recently Deleted"),
                    value: total { $0.action == "trash" && $0.item.photoID != nil })
                LabeledContent(
                    String(localized: "Verified compression and format reductions"),
                    value: total { $0.action == "compress" || $0.action == "keepComponent" })
                Chart {
                    ForEach(model.activity.filter { $0.state == .complete }) { event in
                        if event.date > Date().addingTimeInterval(-30 * 86_400) {
                            BarMark(
                                x: .value(String(localized: "Date"), event.date, unit: .day),
                                y: .value(String(localized: "Bytes"), event.completedReduction))
                        }
                        if let restored = event.restoredAt, restored > Date().addingTimeInterval(-30 * 86_400) {
                            BarMark(
                                x: .value(String(localized: "Date"), restored, unit: .day),
                                y: .value(String(localized: "Restore adjustment"), -event.completedReduction))
                        }
                    }
                }.frame(height: 180).accessibilityLabel(
                    String(localized: "Logical bytes processed in the last 30 days"))
                GroupBox(String(localized: "By tool")) {
                    ForEach(CleanupTool.allCases) { tool in
                        let values = completed.filter { $0.tool == tool }
                        if !values.isEmpty {
                            LabeledContent(tool.title, value: values.reduce(0) { $0 + $1.savings }.formattedByteCount)
                        }
                    }
                }
                Text(String(localized: "Recent 25 events")).font(.headline)
                if model.activity.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No activity yet"), systemImage: "clock",
                        description: Text(
                            String(localized: "Completed changes and interrupted operations appear here.")))
                }
                ForEach(Array(model.activity.prefix(25))) { event in
                    GroupBox {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(event.item.name).font(.headline)
                                Text(
                                    String(
                                        localized: """
                                            \(event.tool.title) · 1 item · \(event.bytes.formattedByteCount) · \
                                            \(event.date.formatted())
                                            """
                                    )
                                )
                                .font(.caption)
                                Text(event.restored ? String(localized: "Restored") : event.state.title)
                                if let date = event.restoredAt {
                                    Text(String(localized: "Restore adjustment: \(date.formatted())"))
                                } else if event.restoreStartedAt != nil {
                                    Text(String(localized: "Restore interrupted. Check the original folder and Trash."))
                                }
                                if event.action == "compress" {
                                    Text(String(localized: "After: \(event.outputBytes.formattedByteCount)"))
                                }
                                if let output = event.replacementURL ?? event.outputURL {
                                    Text(output.path).font(.caption).textSelection(.enabled)
                                }
                                if let asset = event.replacementPhotoID {
                                    Text(String(localized: "Replacement Photos asset: \(asset)"))
                                        .font(.caption).textSelection(.enabled)
                                }
                                if let error = event.error { Text(error).foregroundStyle(SemanticScale.error) }
                            }
                            Spacer()
                            if event.item.photoID != nil {
                                Text(String(localized: "Recover in Photos → Recently Deleted (normally 30 days)")).font(
                                    .caption)
                            } else if event.state == .complete, !event.restored, event.restoreStartedAt == nil,
                                event.outputURL != nil {
                                Button(String(localized: "Restore")) { Task { await model.restore(event) } }.disabled(
                                    model.isBusy)
                            }
                        }
                    }
                }
            }.padding(Spacing.cardPadding)
        }
    }
}
