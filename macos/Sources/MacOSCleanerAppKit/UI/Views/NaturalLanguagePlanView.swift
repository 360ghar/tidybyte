import SwiftUI

struct NaturalLanguagePlanView: View {
    @Bindable var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var planningTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementSection) {
            Label(String(localized: "Ask Tidybyte"), systemImage: "sparkle.magnifyingglass").font(.title2.bold())
            Text(String(localized: "Describe the cleanup you want to review. This changes the plan, not your files."))
                .foregroundStyle(.secondary)
            TextField(String(localized: "For example, find old installers"), text: $model.naturalLanguageCommand)
                .textFieldStyle(.roundedBorder).focused($isFocused)
                .onSubmit { submit() }
                .disabled(model.isPlanning)
            FlowSuggestions(model: model)
                .disabled(model.isPlanning)
            if model.isPlanning { ProgressView(String(localized: "Preparing your plan…")) }
            if let error = model.errorMessage { Text(error).foregroundStyle(SemanticScale.error) }
            HStack {
                Button(String(localized: "Cancel")) {
                    planningTask?.cancel()
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Update Plan")) { submit() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(
                        model.naturalLanguageCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.plan == nil || model.isPlanning || model.isScanning || model.isExecuting)
            }
        }
        .padding(Spacing.screenEdge)
        .frame(minWidth: 480)
        .presentationSizing(.fitted)
        .onAppear { isFocused = true }
        .onDisappear { planningTask?.cancel() }
    }

    private func submit() {
        guard !model.isPlanning, !model.isScanning, !model.isExecuting, model.plan != nil,
            !model.naturalLanguageCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        planningTask = Task {
            if await model.applyNaturalLanguageCommand(), !Task.isCancelled {
                model.reviewRiskFilter = nil
                model.searchText = ""
                if !model.destination.isReview { model.destination = .systemJunk }
                dismiss()
            }
        }
    }
}

private struct FlowSuggestions: View {
    @Bindable var model: AppViewModel
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(AppViewModel.suggestionCommands, id: \.self) { command in
                    Button(command) { model.naturalLanguageCommand = command }
                }
            }
        }
    }
}
