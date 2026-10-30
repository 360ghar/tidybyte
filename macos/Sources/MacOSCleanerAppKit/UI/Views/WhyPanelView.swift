import MacOSCleanerCore
import SwiftUI

struct WhyPanelView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        if let action = model.selectedAction {
            Form {
                Section(String(localized: "Action")) {
                    Text(action.actionType.displayName).font(.headline)
                    RiskBadge(risk: action.risk)
                    Text(action.reason).textSelection(.enabled)
                    LabeledContent(String(localized: "Confidence"), value: "\(Int(action.confidence * 100))%")
                    Text(operationDescription(for: action)).font(.callout)
                }
                Section(String(localized: "Affected files")) {
                    ForEach(model.selectedActionFiles) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.fileName).font(.headline)
                            Text(file.displayPath).font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if !file.riskFlags.isEmpty {
                                Label(
                                    file.riskFlags.map(\.displayName).joined(separator: ", "),
                                    systemImage: "exclamationmark.triangle"
                                ).font(.caption)
                            }
                            Button(String(localized: "Show in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                        }
                    }
                }
                if action.actionType == .runPackageManagerCleanup {
                    Section(String(localized: "Command preview")) {
                        ForEach(
                            (model.outcome?.packageCandidates ?? []).filter { action.targets.contains($0.id) }, id: \.id
                        ) { candidate in
                            Text(([candidate.commandPath.path] + candidate.arguments).joined(separator: " "))
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(candidate.dryRunOutput).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                Section(String(localized: "Recovery")) {
                    Text(recoveryText(for: action)).font(.callout)
                }
                Section(String(localized: "Saved rules")) {
                    Button(String(localized: "Approve and Save Always Rule")) {
                        Task { await model.alwaysDoThis(action) }
                    }
                    .disabled(action.risk == .forbidden || !AppViewModel.isSupportedOperation(action.actionType))
                    Button(String(localized: "Reject and Save Never Rule")) {
                        Task { await model.neverDoThisHere(action) }
                    }
                }
                .disabled(model.isScanning || model.isExecuting || model.isPlanning || action.executedAt != nil)
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                String(localized: "Select an action"), systemImage: "checklist",
                description: Text(String(localized: "Its reason, affected files, and recovery details appear here.")))
        }
    }

    private func recoveryText(for action: PlannedAction) -> String {
        if action.risk == .forbidden { return String(localized: "Blocked actions cannot run.") }
        if !AppViewModel.isSupportedOperation(action.actionType) {
            return String(localized: "This action is for review only. Tidybyte cannot execute it.")
        }
        if action.actionType == .runPackageManagerCleanup {
            return String(localized: "Package-manager cleanup cannot be undone. Review the command before approval.")
        }
        return String(
            localized:
                "Restore options appear in History. Recovery needs the saved record and available files."
        )
    }

    private func operationDescription(for action: PlannedAction) -> String {
        let fileCount = action.targets.count
        let filePart =
            fileCount == 1
            ? String(localized: "1 file")
            : String(localized: "\(fileCount) files")
        switch action.actionType {
        case .moveToTrash:
            return String(
                localized: "Move \(filePart) to Trash", comment: "Operation description for moveToTrash action")
        case .move:
            return String(
                localized: "Move \(filePart) to \(action.destination?.path ?? String(localized: "destination"))",
                comment: "Operation description for move action")
        case .archive:
            return String(
                localized: "Create ZIP archive of \(filePart), then trash originals",
                comment: "Operation description for archive action")
        case .tag:
            return String(localized: "Apply Finder tag to \(filePart)", comment: "Operation description for tag action")
        case .createAlias:
            return String(
                localized: "Create Finder alias for \(filePart)",
                comment: "Operation description for createAlias action")
        case .createSymlink:
            return String(
                localized: "Create symbolic link for \(filePart)",
                comment: "Operation description for createSymlink action")
        case .runPackageManagerCleanup:
            return String(
                localized: "Run package manager cleanup command",
                comment: "Operation description for runPackageManagerCleanup action")
        case .rename:
            return String(localized: "Rename \(filePart)", comment: "Operation description for rename action")
        case .cloneDeduplicate:
            return String(
                localized: "Fold \(filePart) onto their keepers as APFS clones (nothing is deleted)",
                comment: "Operation description for cloneDeduplicate action")
        default:
            return String(localized: "\(action.actionType.displayName): \(filePart)")
        }
    }

}
