import MacOSCleanerCore
import SwiftUI

struct UndoHistoryView: View {
    @Bindable var model: AppViewModel
    @State private var restoreRequest: UndoRecord?

    private var records: [UndoRecord] {
        model.undoRecords.filter {
            model.searchText.isEmpty
                || ($0.restoreURL?.path ?? $0.trashURL?.path ?? "").localizedCaseInsensitiveContains(model.searchText)
                || $0.inverseAction.displayName.localizedCaseInsensitiveContains(model.searchText)
        }
    }

    private var previousActions: [PlannedAction] {
        model.historyActions.filter {
            !model.lastExecutionActionIDs.contains($0.id) && model.actionMatchesSearch($0)
        }
    }

    var body: some View {
        List(selection: $model.selectedHistoryID) {
            if let summary = model.executionSummary {
                Section(String(localized: "Latest changes")) {
                    LabeledContent(String(localized: "Completed operations"), value: String(summary.logs.count))
                    LabeledContent(String(localized: "Failed actions"), value: String(summary.failedActionIDs.count))
                    LabeledContent(
                        String(localized: "Skipped or cancelled actions"),
                        value: model.lastExecutionActionIDs
                            .subtracting(summary.logs.map(\.plannedActionID))
                            .subtracting(summary.failedActionIDs).count.formatted())
                    LabeledContent(
                        String(localized: "Pending approved actions"),
                        value: String(model.pendingExecutableActions().count))
                    ForEach(Array(summary.failures.enumerated()), id: \.offset) { _, failure in
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(SemanticScale.error).textSelection(.enabled)
                    }
                }
            }
            if let summary = model.executionSummary {
                Section(String(localized: "Completed operations")) {
                    ForEach(
                        summary.logs.filter { log in
                            model.searchText.isEmpty
                                || log.operationType.displayName.localizedCaseInsensitiveContains(model.searchText)
                                || log.beforeState.values.contains {
                                    $0.localizedCaseInsensitiveContains(model.searchText)
                                }
                        }
                    ) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(log.operationType.displayName, systemImage: "checkmark.circle")
                            Text(log.beforeState["path"] ?? log.beforeState["command"] ?? log.result)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.tag(log.id)
                    }
                }
                Section(String(localized: "Failed or skipped actions")) {
                    ForEach(
                        (model.plan?.actions ?? []).filter {
                            model.lastExecutionActionIDs.contains($0.id)
                                && ($0.status != .completed || summary.failedActionIDs.contains($0.id))
                                && model.actionMatchesSearch($0)
                        }
                    ) { action in
                        Label(
                            action.reason,
                            systemImage: action.status == .failed ? "exclamationmark.triangle" : "pause.circle"
                        )
                        .tag(action.id)
                    }
                }
            }
            if !previousActions.isEmpty {
                Section(String(localized: "Previous actions")) {
                    ForEach(previousActions) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                action.actionType.displayName,
                                systemImage: action.status == .failed ? "exclamationmark.triangle" : "checkmark.circle")
                            Text(action.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            HStack {
                                Text(action.status.displayName)
                                if let date = action.executedAt { Text(date, format: .dateTime) }
                            }.font(.caption).foregroundStyle(.secondary)
                        }.tag(action.id)
                    }
                }
            }
            Section(String(localized: "Restore records")) {
                ForEach(records) { record in
                    HStack(spacing: Spacing.elementNormal) {
                        Image(systemName: record.status == .available ? "arrow.uturn.backward" : "checkmark.circle")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.inverseAction.displayName).font(.headline)
                            Text(
                                record.restoreURL?.path ?? record.trashURL?.path
                                    ?? String(localized: "No file path recorded")
                            )
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                        }
                        Spacer()
                        Text(record.status.displayName).font(.caption).foregroundStyle(.secondary)
                        Button(String(localized: "Restore")) { restoreRequest = record }
                            .disabled(record.status != .available || model.isScanning || model.isExecuting)
                    }
                    .padding(.vertical, Spacing.elementTight).tag(record.id)
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if records.isEmpty && previousActions.isEmpty && model.executionSummary == nil {
                if !model.searchText.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                } else {
                    ContentUnavailableView(
                        String(localized: "No history yet"), systemImage: "clock.arrow.circlepath",
                        description: Text(
                            String(localized: "Completed changes and available restore actions appear here.")))
                }
            }
        }
        .sheet(item: $restoreRequest) { record in
            VStack(alignment: .leading, spacing: Spacing.elementSection) {
                Text(String(localized: "Restore this change?")).font(.title2.bold())
                Text(record.restoreURL?.path ?? record.trashURL?.path ?? record.inverseAction.displayName)
                    .textSelection(.enabled)
                Text(String(localized: "Optional: tell Tidybyte why you want to restore it."))
                    .foregroundStyle(.secondary)
                ForEach(AppViewModel.RegretReason.allCases, id: \.self) { reason in
                    Button(reason.rawValue) {
                        model.selectedRegretReason = reason.rawValue
                        restoreRequest = nil
                        Task { await model.restoreWithReason(record) }
                    }
                }
                HStack {
                    Button(String(localized: "Cancel")) { restoreRequest = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(String(localized: "Restore without answering")) {
                        restoreRequest = nil
                        Task { await model.restore(record) }
                    }.buttonStyle(.borderedProminent)
                }
            }
            .padding(Spacing.screenEdge)
            .frame(minWidth: 460)
            .presentationSizing(.fitted)
        }
    }
}

struct HistoryDetailsView: View {
    @Bindable var model: AppViewModel
    @State private var storedLog: OperationLog?

    private var record: UndoRecord? { model.undoRecords.first { $0.id == model.selectedHistoryID } }
    private var log: OperationLog? {
        model.executionSummary?.logs.first { $0.id == model.selectedHistoryID } ?? storedLog
    }

    var body: some View {
        Form {
            if let record {
                Section(String(localized: "Restore record")) {
                    LabeledContent(String(localized: "Operation"), value: record.inverseAction.displayName)
                    LabeledContent(String(localized: "Status"), value: record.status.displayName)
                    if let path = record.restoreURL?.path { Text(path).textSelection(.enabled) }
                    if let expiry = record.validUntil {
                        LabeledContent(String(localized: "Valid until"), value: expiry.formatted())
                    }
                    Text(
                        String(
                            localized:
                                "Use Restore in the history list. Recovery depends on the files remaining available.")
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let log {
                Section(String(localized: "Operation")) {
                    Text(log.operationType.displayName).font(.headline)
                    Text(log.timestamp, format: .dateTime)
                    if let error = log.error { Text(error).foregroundStyle(SemanticScale.error) }
                }
                Section(String(localized: "Before")) { stateValues(log.beforeState) }
                Section(String(localized: "After")) { stateValues(log.afterState) }
                if log.operationType == .runPackageManagerCleanup {
                    Text(String(localized: "This command has no restore action."))
                }
            } else if let action = selectedAction {
                Section(String(localized: "Action")) {
                    Text(action.reason).textSelection(.enabled)
                    Text(action.status.displayName)
                    RiskBadge(risk: action.risk)
                    if action.actionType == .runPackageManagerCleanup {
                        Text(String(localized: "This command has no restore action."))
                    }
                    if action.status == .failed {
                        Text(String(localized: "See the latest execution errors in History for failure details."))
                    }
                }
            } else if record == nil {
                Text(String(localized: "Select a history item to see its details."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: model.selectedHistoryID) {
            storedLog = nil
            if let record { storedLog = await model.historyOperation(id: record.operationLogID) }
        }
    }

    private var selectedAction: PlannedAction? {
        model.historyActions.first { $0.id == model.selectedHistoryID }
            ?? model.plan?.actions.first { $0.id == model.selectedHistoryID }
    }

    private func stateValues(_ values: [String: String]) -> some View {
        ForEach(values.keys.sorted(), id: \.self) { key in
            LabeledContent(key, value: values[key] ?? "")
                .font(.caption).textSelection(.enabled)
        }
    }
}
