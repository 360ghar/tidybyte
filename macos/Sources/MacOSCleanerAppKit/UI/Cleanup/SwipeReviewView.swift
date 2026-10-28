import MacOSCleanerCore
import SwiftUI
import UniformTypeIdentifiers

struct SwipeReviewView: View {
    @Bindable var model: CleanupModel
    @State private var offset = CGSize.zero
    @State private var showsMovePicker = false
    @State private var showsSubfolderPicker = false
    @State private var confirms = false
    @State private var confirmsDiscard = false
    @FocusState private var cardFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: Spacing.elementNormal) {
            if let session = model.session {
                if !model.sessionResults.isEmpty {
                    let processed = model.sessionResults.count
                    let successful = model.sessionResults.filter { $0.state == .complete }.count
                    let remaining = max(0, session.pendingChanges.count - processed)
                    Text(
                        String(
                            localized: """
                                \(successful) successful · \(processed - successful) failed \
                                · \(remaining) unprocessed
                                """))
                }
                HStack {
                    Text(String(localized: "\(session.decisions.count) of \(session.items.count) reviewed"))
                    Spacer()
                    Button(String(localized: "Undo last decision")) { Task { await model.undoDecision() } }
                        .disabled(
                            session.decisions.isEmpty || session.applicationStartedAt != nil || model.isBusy
                                || model.isSaving
                        ).help(String(localized: "Edit ▸ Undo also reverts the last decision."))
                    Button(
                        session.applicationStartedAt == nil
                            ? String(localized: "Discard draft") : String(localized: "Close session")
                    ) {
                        confirmsDiscard = true
                    }.disabled(model.isBusy || model.isSaving)
                }
                if let item = session.current {
                    card(item).id(item.id)
                } else {
                    ReviewBatchSummary(decisions: session.decisions, model: model)
                    Button(String(localized: "Confirm session")) { confirms = true }
                        .buttonStyle(.borderedProminent).disabled(model.isBusy || model.isSaving)
                }
            } else if let completed = model.completedSession {
                Image(systemName: "checklist").font(.largeTitle)
                Text(String(localized: "Session results")).font(.title2)
                let decisions = completed.decisions
                let trashed = model.sessionResults.filter { $0.action == "trash" && $0.state == .complete }
                Text(
                    String(
                        localized: "\(trashed.count) removed · \(decisions.filter { $0.choice == .keep }.count) kept"))
                let moved = decisions.filter { $0.choice == .move }.count
                let skipped = decisions.filter { $0.choice == .skip }.count
                Text(String(localized: "\(moved) moved · \(skipped) skipped"))
                let removedBytes = trashed.reduce(0) { $0 + $1.bytes }.formattedByteCount
                Text(String(localized: "\(removedBytes) sent to Trash or Recently Deleted"))
                completionActions
            } else {
                setup
            }
        }
        .padding(Spacing.cardPadding)
        .navigationTitle(CleanupTool.swipe.title)
            .sheet(isPresented: $confirms) {
                VStack {
                    if let session = model.session { ReviewBatchSummary(decisions: session.decisions, model: model) }
                    HStack {
                        Button(String(localized: "Cancel")) { confirms = false }
                        Spacer()
                        Button(String(localized: "Apply these changes"), role: .destructive) {
                            confirms = false
                            Task { await model.commitSession() }
                        }
                    }
                }
                .padding(Spacing.cardPadding)
                .frame(minWidth: 600, minHeight: 480)
                .presentationSizing(.form)
            }
            .confirmationDialog(
                String(localized: "Discard pending decisions? Completed changes stay in Activity."),
                isPresented: $confirmsDiscard
            ) {
                Button(String(localized: "Discard draft"), role: .destructive) { Task { await model.discardSession() } }
            }
            .fileImporter(isPresented: $showsMovePicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { choose(.move, destination: url) }
            }
            .fileImporter(isPresented: $showsSubfolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.filterFolder = url }
            }
    }

    private var setup: some View {
        VStack(spacing: Spacing.elementSection) {
            Image(systemName: "rectangle.stack").font(.largeTitle)
            Text(String(localized: "Review one file at a time")).font(.title2)
            Picker(String(localized: "Session filter"), selection: $model.filter) {
                ForEach(ReviewFilter.allCases, id: \.self) { Text($0.title).tag($0) }
            }.frame(maxWidth: 360)
            if model.filter == .beforeDate {
                DatePicker(
                    String(localized: "Modified on or before"), selection: $model.filterDate, displayedComponents: .date
                )
            }
            if model.filter == .subfolder {
                Button(model.filterFolder?.lastPathComponent ?? String(localized: "Choose nested folder…")) {
                    showsSubfolderPicker = true
                }
            }
            Text(String(localized: "\(model.filteredItems().count) files match this session"))
            Button(String(localized: "Start session")) { Task { await model.startSession() } }
                .buttonStyle(.borderedProminent).disabled(
                    model.result?.isFresh != true || model.filteredItems().isEmpty)
            if model.result?.isFresh != true { Text(String(localized: "Run a scan to start reviewing.")) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ item: ReviewItem) -> some View {
        VStack {
            Text(item.name).font(.title2).lineLimit(2)
            Text(item.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            ReviewPreview(item: item, model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            GlassEffectContainer {
                HStack(spacing: Spacing.elementNormal) {
                    Button(String(localized: "Move to Trash"), systemImage: "trash", role: .destructive) {
                        choose(.trash)
                    }
                    .disabled(!item.canChange)
                    .help(String(localized: "Delete key"))
                    Button(String(localized: "Keep"), systemImage: "checkmark") { choose(.keep) }
                        .help(String(localized: "Right Arrow key"))
                    Button(String(localized: "Move…"), systemImage: "folder") { showsMovePicker = true }
                        .disabled(!item.canChange)
                        .help(String(localized: "Up Arrow key"))
                    Button(String(localized: "Skip"), systemImage: "forward.end") { choose(.skip) }
                        .help(String(localized: "Space bar"))
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            Text(String(localized: "Changes wait for the session confirmation."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(Spacing.cardPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: Radius.card))
        .offset(offset)
        .focusable().focused($cardFocused)
        .onAppear { cardFocused = true }
        .onKeyPress(keys: [.delete, .deleteForward, .rightArrow, .upArrow, .space]) { key in
            handleKey(key, item: item)
        }
        .gesture(
            DragGesture(minimumDistance: 25).onChanged { offset = $0.translation }.onEnded { value in
                if value.translation.height < -100, abs(value.translation.height) > abs(value.translation.width),
                    item.canChange {
                    showsMovePicker = true
                } else if value.translation.width < -100, item.canChange {
                    choose(.trash)
                } else if value.translation.width > 100 {
                    choose(.keep)
                }
                withAnimation(reduceMotion ? nil : .appSelection) { offset = .zero }
            }
        )
        .disabled(model.isBusy || model.isSaving)
        .accessibilityLabel(String(localized: "Review card for \(item.name), \(item.bytes.formattedByteCount)"))
    }

    private func handleKey(_ key: KeyPress, item: ReviewItem) -> KeyPress.Result {
        guard cardFocused, !model.isBusy, !model.isSaving else { return .ignored }
        switch key.key {
        case .delete, .deleteForward: if item.canChange { choose(.trash) }
        case .rightArrow: choose(.keep)
        case .upArrow: if item.canChange { showsMovePicker = true }
        case .space: choose(.skip)
        default: return .ignored
        }
        return .handled
    }

    /// Records the decision and registers it with Edit ▸ Undo.
    private func choose(_ choice: ReviewChoice, destination: URL? = nil) {
        Task {
            guard await model.decide(choice, destination: destination) else { return }
            undoManager?.registerUndo(withTarget: model) { model in
                Task { await model.undoDecision() }
            }
            undoManager?.setActionName(String(localized: "Swipe Decision"))
        }
    }
    private var completionActions: some View {
        HStack {
            Button(String(localized: "Start Another Session")) {
                model.sessionResults = []
                model.completedSession = nil
                model.scan()
            }
            Button(String(localized: "Back to Photos & Media")) { model.selectedTool = nil }
        }
    }
}

struct ReviewBatchSummary: View {
    let decisions: [ReviewDecision]
    let model: CleanupModel
    var retained: [ReviewItem] = []
    var body: some View {
        let trashBytes = decisions.filter { $0.choice == .trash }.reduce(0) { $0 + $1.item.bytes }.formattedByteCount
        return VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            Text(String(localized: "Review these changes")).font(.title2)
            Text(
                String(
                    localized: """
                        \(count(.trash)) Trash · \(count(.keep)) kept · \(count(.move)) moved \
                        · \(count(.skip)) skipped
                        """
                ))
            Text(
                String(
                    localized: """
                        \(trashBytes) \
                        selected for removal
                        """
                ))
            List {
                ForEach(decisions, id: \.item.id) { decision in
                    HStack {
                        ReviewPreview(item: decision.item, model: model, thumbnail: true).frame(width: 64, height: 48)
                        VStack(alignment: .leading) {
                            Text(decision.item.name)
                            Text(decision.destination?.path ?? decision.choice.title).font(.caption).foregroundStyle(
                                .secondary)
                        }
                        Spacer()
                        Text(decision.item.bytes.formattedByteCount)
                    }
                }
                if !retained.isEmpty {
                    Section(String(localized: "Retained components")) {
                        ForEach(retained) { item in
                            Label(item.name, systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            if !retained.isEmpty {
                Text(
                    String(
                        localized: """
                            Removed RAW components contain editing data. Removed paired videos contain motion. \
                            These capabilities will not be preserved in the retained components.
                            """)
                ).font(.caption)
            }
            Text(
                String(
                    localized: """
                        Files move to Trash. Photos assets move to Recently Deleted and deletion \
                        can sync to iCloud. Photos moves first export and verify every original \
                        resource. No Trash or Recently Deleted items are permanently deleted \
                        by Cleanup. Photos recovery is normally available for 30 days.
                        """
                )
            )
            .font(.caption)
        }
    }
    private func count(_ choice: ReviewChoice) -> Int { decisions.filter { $0.choice == choice }.count }
}
