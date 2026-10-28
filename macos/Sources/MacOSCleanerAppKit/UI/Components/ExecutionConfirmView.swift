import MacOSCleanerCore
import SwiftUI

struct ExecutionConfirmView: View {
    @Bindable var model: AppViewModel
    let request: ExecutionRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementSection) {
            Label(String(localized: "Review Changes"), systemImage: "checklist")
                .font(.title2.bold())
            Text(
                String(
                    localized: "\(request.actions.count) approved actions · \(request.fileCount) known unique items")
            )
            if !request.areaCounts.isEmpty {
                Text(request.areaCounts.map { "\($0.area.title) \($0.count)" }.formatted(.list(type: .and)))
                    .foregroundStyle(.secondary)
            }
            ForEach(request.operationTypes) { type in
                LabeledContent(type.displayName) {
                    Text(request.actions.filter { $0.actionType == type }.count, format: .number)
                }
            }
            if request.hasPackageCommands {
                Text(
                    String(
                        localized:
                            "Command targets are measured when they run. Their size and file count are excluded."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if request.unresolvedTargetCount > 0 {
                Label(
                    String(
                        localized: "Missing records: \(request.unresolvedTargetCount). Rescan to include these items."),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption).foregroundStyle(SemanticScale.warning)
            }
            if request.estimatedBytes > 0 {
                LabeledContent(
                    String(localized: "Estimated file space"), value: request.estimatedBytes.formattedByteCount)
            }
            Text(
                request.isTrashOnly
                    ? String(
                        localized: "Files will move to Trash. Restore them from History while they remain available.")
                    : String(
                        localized:
                            "Restore options appear in History. Package-manager cleanup cannot be undone."
                    )
            )
            .font(.callout).foregroundStyle(.secondary)
            Text(
                String(
                    localized:
                        "Safety checks run again before any files change. Blocked and review-only actions are excluded."
                )
            )
            .font(.caption).foregroundStyle(.secondary)
            if !request.isCurrent(in: model) {
                Label(
                    String(localized: "The plan changed. Close this sheet and review it again."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(SemanticScale.error)
            }
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(request.confirmTitle, role: request.isTrashOnly ? .destructive : nil) {
                    dismiss()
                    Task { await model.executeConfirmedRequest(request) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!request.isCurrent(in: model))
            }
        }
        .padding(Spacing.screenEdge)
        .frame(minWidth: 440)
        .presentationSizing(.fitted)
    }
}
