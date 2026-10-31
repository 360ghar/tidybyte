import MacOSCleanerCore
import SwiftUI

struct DuplicatesTabView: View {
    @Bindable var model: AppViewModel
    @State private var selection: String?

    private var findings: [Finding] {
        model.duplicateFindings.filter { finding in
            model.searchText.isEmpty || finding.summary.localizedCaseInsensitiveContains(model.searchText)
                || finding.targetFileIDs.contains {
                    model.filesByID[$0]?.displayPath.localizedCaseInsensitiveContains(model.searchText) == true
                }
        }
    }

    /// The strategy the pending action for this finding currently uses.
    private func resolutionStrategy(for finding: Finding) -> DuplicateStrategy {
        let action = model.plan?.actions.first { $0.findingID == finding.id }
        return action?.actionType == .cloneDeduplicate ? .apfsClone : .moveToTrash
    }

    /// A strategy swap is only offered while every action for the finding is
    /// still undecided; an approval or rejection is never reinterpreted.
    private func canSwitchResolution(for finding: Finding) -> Bool {
        !(model.plan?.actions.contains {
            $0.findingID == finding.id && ($0.userDecision != .undecided || $0.executedAt != nil)
        } ?? false)
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(findings) { finding in
                VStack(alignment: .leading, spacing: Spacing.elementTight) {
                    HStack {
                        Image(systemName: "square.on.square").foregroundStyle(.secondary)
                        Text(finding.summary).font(.headline)
                        Spacer()
                        Text(finding.bytesReclaimable.formattedByteCount).monospacedDigit()
                    }
                    HStack {
                        RiskBadge(risk: finding.severity)
                        Text(String(localized: "\(finding.targetFileIDs.count) files"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        resolutionMenu(for: finding)
                        decisionButtons(for: finding)
                    }
                    if resolutionStrategy(for: finding) == .apfsClone,
                       let action = model.plan?.actions.first(where: { $0.findingID == finding.id }),
                       action.actionType == .cloneDeduplicate {
                        cloneHint(for: action)
                    }
                    DisclosureGroup(String(localized: "Files in this group")) {
                        ForEach(finding.targetFileIDs, id: \.self) { id in
                            if let record = model.filesByID[id] {
                                HStack {
                                    Text(record.displayPath).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button(String(localized: "Show in Finder")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([record.url])
                                    }.buttonStyle(.borderless)
                                }.font(.caption)
                            }
                        }
                        if let kept = finding.evidence["kept_file"] {
                            Text(String(localized: "Kept file: \(kept)")).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, Spacing.elementTight).tag(finding.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if findings.isEmpty {
                ContentUnavailableView {
                    Label(
                        model.searchText.isEmpty
                            ? String(localized: "No duplicates found")
                            : String(localized: "No matching duplicates"), systemImage: "doc.on.doc")
                } description: {
                    Text(
                        model.outcome == nil
                            ? String(localized: "Scan folders to compare files.")
                            : String(localized: "Results come from the latest scan."))
                } actions: {
                    if model.outcome == nil {
                        Button(String(localized: "New Scan…")) { model.showsScanSetup = true }
                    }
                }
            }
        }
        .onChange(of: selection) {
            model.selectedActionID = model.plan?.actions.first { $0.findingID == selection }?.id
        }
    }

    /// Caption shown under a group whose pending action is a clone fold.
    private func cloneHint(for action: PlannedAction) -> some View {
        let bytes = action.targets
            .compactMap { model.filesByID[$0]?.sizeBytes }
            .reduce(Int64(0), +)
            .formattedByteCount
        return Label(
            String(localized: "Reclaims \(bytes) without deleting anything. Every file keeps its name and metadata. Undoable.", comment: "Clone-fold hint under a duplicate group"),
            systemImage: "square.on.square.dashed"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Per-group resolution switch: fold onto the keeper (default) or trash.
    private func resolutionMenu(for finding: Finding) -> some View {
        let current = resolutionStrategy(for: finding)
        let canSwitch = canSwitchResolution(for: finding)
        return Menu {
            Button {
                model.switchDuplicateResolution(forFinding: finding.id, to: .apfsClone)
            } label: {
                if current == .apfsClone {
                    Label(
                        String(localized: "Fold into APFS clone (nothing deleted)", comment: "Duplicate resolution option"),
                        systemImage: "checkmark")
                } else {
                    Text(String(localized: "Fold into APFS clone (nothing deleted)", comment: "Duplicate resolution option"))
                }
            }
            .disabled(!canSwitch)
            Button {
                model.switchDuplicateResolution(forFinding: finding.id, to: .moveToTrash)
            } label: {
                if current == .moveToTrash {
                    Label(
                        String(localized: "Move duplicates to Trash", comment: "Duplicate resolution option"),
                        systemImage: "checkmark")
                } else {
                    Text(String(localized: "Move duplicates to Trash", comment: "Duplicate resolution option"))
                }
            }
            .disabled(!canSwitch)
        } label: {
            Label(String(localized: "Resolve", comment: "Duplicate resolution menu label"), systemImage: "arrow.triangle.branch")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!canSwitch)
    }

    /// Approve or reject every action of one group in place. Execution still
    /// goes through the single confirmation sheet.
    @ViewBuilder
    private func decisionButtons(for finding: Finding) -> some View {
        let actions = (model.plan?.actions ?? []).filter { $0.findingID == finding.id && $0.executedAt == nil }
        if !actions.isEmpty {
            let approved = actions.allSatisfy { $0.userDecision == .approved }
            let canApprove = actions.allSatisfy {
                $0.risk != .forbidden && AppViewModel.isSupportedOperation($0.actionType)
            }
            HStack {
                if approved {
                    Label(String(localized: "Approved"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(SemanticScale.success)
                }
                Button(String(localized: "Reject")) { actions.forEach(model.reject) }
                Button(String(localized: "Approve")) { actions.forEach(model.approve) }
                    .disabled(approved || !canApprove)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(model.isScanning || model.isExecuting || model.isPlanning)
        }
    }

}
