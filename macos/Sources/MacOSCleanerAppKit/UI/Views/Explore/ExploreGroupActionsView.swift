import MacOSCleanerCore
import SwiftUI

/// Focus + Stage actions for an Explore group selection.
/// Focus drills the Explore list into the group's largest member; Stage routes
/// that member through the existing Plan approve flow (proposed Trash-first
/// action, SafetyAuditor review at execution — never a direct delete).
/// Groups that resolve to no concrete record (e.g. the "Other" rollup) render
/// nothing so callers can drop this view into any selection footer.
struct ExploreGroupActionsView: View {
    @Bindable var model: AppViewModel
    var group: ExploreGroup
    var files: [FileRecord]
    /// Drill callback used by FoldersGridView (re-roots the grid on the record).
    var onFocus: ((FileRecord) -> Void)?

    @State private var actionMessage: String?

    private var representative: FileRecord? {
        ExploreTreeBuilder.largestMember(of: group, in: files)
    }

    var body: some View {
        if let record = representative {
            VStack(alignment: .leading, spacing: Spacing.elementTight) {
                HStack(spacing: Spacing.elementTight) {
                    SecondaryButton(
                        title: String(localized: "Focus"),
                        icon: "scope",
                        action: {
                            if let onFocus {
                                onFocus(record)
                            } else {
                                model.focusExploreRecord(id: record.id)
                                model.selectExploreRecord(id: record.id)
                            }
                            actionMessage = String(localized: "Focused \(record.fileName).")
                        }
                    )
                    if model.stagedExploreAction(matching: record) != nil {
                        SecondaryButton(
                            title: String(localized: "Approve"),
                            icon: "checkmark",
                            action: {
                                guard let staged = model.stagedExploreAction(matching: record) else {
                                    return
                                }
                                model.approve(staged)
                                actionMessage = String(localized: "Approved. Review it in Proposed Actions.")
                            }
                        )
                    } else {
                        SecondaryButton(
                            title: String(localized: "Stage"),
                            icon: "plus.circle",
                            action: {
                                if model.stageExploreRecordForCleanup(record) != nil {
                                    actionMessage = String(localized: "Added to the cleanup plan. Review it in Proposed Actions.")
                                } else {
                                    actionMessage = String(localized: "Could not stage. Run a scan first.")
                                }
                            }
                        )
                    }
                }
                Text(String(localized: "Acts on largest member: \(record.fileName) (\(record.sizeBytes.formattedByteCount))"))
                    .appFont(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let actionMessage {
                    Text(actionMessage)
                        .appFont(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Group actions for \(group.name)"))
        }
    }
}
