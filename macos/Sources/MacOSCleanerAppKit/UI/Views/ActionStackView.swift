import MacOSCleanerCore
import SwiftUI

struct ActionStackView: View {
    @Bindable var model: AppViewModel
    @State private var bulkRequest: BulkReviewRequest?

    /// Only this sidebar row's actions. Bulk commands never reach rows the user cannot see.
    private var actions: [PlannedAction] { model.actions(in: model.destination) }
    private var visibleActions: [PlannedAction] {
        model.visibleReviewActions
    }

    var body: some View {
        VStack(spacing: 0) {
            if !actions.isEmpty { controls }
            if actions.isEmpty {
                ContentUnavailableView {
                    Label(
                        model.outcome == nil
                            ? String(localized: "Not scanned yet") : String(localized: "Nothing to clean here"),
                        systemImage: model.destination.icon)
                } description: {
                    Text(
                        model.outcome == nil
                            ? String(localized: "Scan to find cleanup opportunities.")
                            : String(localized: "The latest scan found nothing in this area."))
                } actions: {
                    if model.outcome == nil {
                        Button(String(localized: "Scan My Mac")) { model.scanAll() }
                            .disabled(model.isScanning || model.isExecuting)
                    }
                }
            } else if visibleActions.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                List(selection: $model.selectedActionID) {
                    ForEach(visibleActions) { action in
                        ActionRow(model: model, action: action).tag(action.id)
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let action = actions.first(where: { $0.id == id }) {
                        Button(String(localized: "Show Details")) {
                            model.selectedActionID = id
                            model.showsInspector = true
                        }
                        Button(String(localized: "Approve")) { model.approve(action) }
                            .disabled(!canReview(action))
                        Button(String(localized: "Reject")) { model.reject(action) }
                            .disabled(
                                action.executedAt != nil || model.isExecuting || model.isScanning || model.isPlanning)
                    }
                } primaryAction: { ids in
                    if let id = ids.first {
                        model.selectedActionID = id
                        model.showsInspector = true
                    }
                }
            }
        }
        .sheet(item: $bulkRequest) { request in
            bulkConfirmation(request)
        }
        .onChange(of: model.plan?.id) {
            model.reviewRiskFilter = nil
            bulkRequest = nil
        }
        .onChange(of: visibleActions.map(\.id)) {
            if model.selectedVisibleReviewAction == nil { model.selectedActionID = nil }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            ViewThatFits(in: .horizontal) {
                HStack { bulkControls }
                VStack(alignment: .leading) { bulkControls }
            }
            Text(String(localized: "Select an action to inspect it. Approval is a separate step."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(Spacing.cardPadding)
        .disabled(model.isScanning || model.isExecuting || model.isPlanning)
    }

    @ViewBuilder
    private var bulkControls: some View {
        Button(String(localized: "Approve Visible…")) {
            requestBulk(visibleActions.filter { $0.userDecision == .undecided && canReview($0) }, approve: true)
        }
        .disabled(!visibleActions.contains { $0.userDecision == .undecided && canReview($0) })
        Button(String(localized: "Approve Low Risk…")) {
            requestBulk(
                visibleActions.filter { $0.risk == .low && $0.userDecision == .undecided && canReview($0) },
                approve: true)
        }
        .disabled(!visibleActions.contains { $0.risk == .low && $0.userDecision == .undecided && canReview($0) })
        Menu(String(localized: "More")) {
            Button(String(localized: "Reject Undecided…")) {
                requestBulk(
                    visibleActions.filter { $0.userDecision == .undecided && $0.executedAt == nil }, approve: false)
            }
            .disabled(!visibleActions.contains { $0.userDecision == .undecided && $0.executedAt == nil })
        }
        .fixedSize()
    }

    private func canReview(_ action: PlannedAction) -> Bool {
        action.executedAt == nil && action.risk != .forbidden
            && AppViewModel.isSupportedOperation(action.actionType)
            && !model.isScanning && !model.isExecuting && !model.isPlanning
    }

    private func requestBulk(_ actions: [PlannedAction], approve: Bool) {
        guard !actions.isEmpty else { return }
        // Revision token, not the plan's JSON signature: comparing signatures
        // per render re-encoded the whole plan on the main thread.
        bulkRequest = BulkReviewRequest(actions: actions, approve: approve, planRevision: model.planRevision)
    }

    private func bulkConfirmation(_ request: BulkReviewRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.elementSection) {
            Text(request.approve ? String(localized: "Approve Actions") : String(localized: "Reject Actions"))
                .font(.title2.bold())
            Text(
                String(
                    localized:
                        "Update decisions for \(request.actions.count) actions. No files change."
                ))
            if request.actions.contains(where: { $0.risk == .high }) {
                Label(String(localized: "This includes high-risk actions."), systemImage: "exclamationmark.triangle")
            }
            if request.planRevision != model.planRevision {
                Text(String(localized: "The plan changed. Cancel and review the current actions."))
                    .foregroundStyle(SemanticScale.error)
            }
            HStack {
                Button(String(localized: "Cancel")) { bulkRequest = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(request.approve ? String(localized: "Approve") : String(localized: "Reject")) {
                    guard request.planRevision == model.planRevision else { return }
                    for action in request.actions {
                        if request.approve { model.approve(action) } else { model.reject(action) }
                    }
                    bulkRequest = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    request.planRevision != model.planRevision
                        || model.isScanning || model.isExecuting || model.isPlanning)
            }
        }
        .padding(Spacing.screenEdge)
        .frame(minWidth: 420)
        .presentationSizing(.fitted)
    }
}

private struct BulkReviewRequest: Identifiable {
    let id = UUID()
    let actions: [PlannedAction]
    let approve: Bool
    let planRevision: Int
}

struct ActionRow: View {
    @Bindable var model: AppViewModel
    let action: PlannedAction

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.elementNormal) {
            VStack(alignment: .leading, spacing: 5) {
                Text(action.reason).font(.headline).lineLimit(2)
                Text(targetDescription).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: Spacing.elementTight) {
                    Text(action.actionType.displayName).font(.caption)
                    RiskBadge(risk: action.risk)
                    Text(stateLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: Spacing.elementTight) {
                Text(affectedBytes.formattedByteCount).monospacedDigit().font(.callout)
                    .help(String(localized: "Affected file size; reclaimable space depends on the operation"))
                HStack {
                    Button(String(localized: "Reject")) { model.reject(action) }
                        .disabled(action.executedAt != nil)
                    Button(String(localized: "Approve")) { model.approve(action) }
                        .disabled(
                            action.risk == .forbidden || action.executedAt != nil
                                || !AppViewModel.isSupportedOperation(action.actionType))
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
        .padding(.vertical, Spacing.elementTight)
        .disabled(model.isScanning || model.isExecuting || model.isPlanning)
        .accessibilityElement(children: .contain)
    }

    private var stateLabel: String {
        if action.risk == .forbidden { return String(localized: "Blocked") }
        if !AppViewModel.isSupportedOperation(action.actionType) { return String(localized: "Review only") }
        return action.status.displayName
    }
    private var targetDescription: String {
        guard let id = action.targets.first, let record = model.filesByID[id] else {
            return String(localized: "\(action.targets.count) items")
        }
        return action.targets.count > 1
            ? String(localized: "\(record.displayPath) and \(action.targets.count - 1) more") : record.displayPath
    }
    private var affectedBytes: Int64 {
        Set(action.targets).compactMap { model.filesByID[$0] }.reduce(0) { $0 + $1.sizeBytes }
    }
}
