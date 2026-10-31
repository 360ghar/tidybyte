import MacOSCleanerCore
import SwiftUI
import UniformTypeIdentifiers

struct ScanSetupView: View {
    @Bindable var model: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var showsFolderPicker = false
    @State private var folderError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(String(localized: "Scan"), selection: $model.selectedMode) {
                        ForEach(ScanMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    if model.selectedMode == .selectedFolders { folders }
                } header: {
                    Text(String(localized: "Choose what to scan"))
                } footer: {
                    Text(
                        String(
                            localized:
                                "Scanning does not change your files. Review proposed actions before applying them."))
                }
                Section(String(localized: "Options")) {
                    Picker(String(localized: "Cleanup posture"), selection: $model.cleanupPosture) {
                        Text(String(localized: "Conservative")).tag(CleanupPosture.conservative)
                        Text(String(localized: "Balanced")).tag(CleanupPosture.balanced)
                        Text(String(localized: "Aggressive")).tag(CleanupPosture.aggressive)
                    }
                    Toggle(String(localized: "Use configured AI provider"), isOn: $model.includeAI)
                        .disabled(model.providerSettings.privacyMode == .localOnly)
                    Text(
                        model.includeAI
                            ? String(
                                localized: "The AI & Privacy settings control which data is sent to your provider.")
                            : String(localized: "This scan uses local rules. File data is not sent to an AI provider.")
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Button(String(localized: "AI & Privacy Settings…")) {
                        model.settingsSection = .privacy
                        openSettings()
                    }
                }
            }
            .formStyle(.grouped)
            if let folderError {
                Label(folderError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SemanticScale.error).padding(Spacing.cardPadding)
            }
            Divider()
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Start Scan")) {
                    model.saveSettings()
                    model.destination = .overview
                    model.runScan()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canScan)
            }
            .padding(Spacing.cardPadding)
        }
        .frame(minWidth: 520, minHeight: 440)
        .presentationSizing(.form)
        .fileImporter(
            isPresented: $showsFolderPicker, allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                urls.forEach { model.addScanFolder($0) }
                folderError = nil
            case .failure(let error):
                folderError = error.localizedDescription
            }
        }
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            ForEach(model.selectedFolders, id: \.path) { url in
                HStack {
                    Label(url.lastPathComponent, systemImage: "folder")
                        .help(url.path)
                    Spacer()
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button {
                        model.removeSelectedFolder(url)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Remove \(url.lastPathComponent)"))
                }
            }
            HStack {
                Button(String(localized: "Choose Folders…")) { showsFolderPicker = true }
                Button(String(localized: "Add Downloads")) { model.addDownloadFolderToSelection() }
            }
        }
    }

    private var canScan: Bool {
        !model.isScanning && !model.isExecuting
            && (model.selectedMode != .selectedFolders || !model.selectedFolders.isEmpty)
    }
}
