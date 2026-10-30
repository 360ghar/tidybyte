import MacOSCleanerCore
import ServiceManagement
import SwiftUI

enum SettingsSection: Hashable { case general, scanning, media, privacy, data }

struct SettingsView: View {
    @Bindable var model: AppViewModel
    @State private var showClearConfirmation = false
    @State private var launchAtLogin = false
    @State private var apiBaseURLText = ""
    @State private var settingsError: String?
    @FocusState private var apiBaseURLFocused: Bool
    @AppStorage(AppDelegate.menuBarExtraKey) private var showsMenuBarExtra = false
    @AppStorage(AppDelegate.removalWatchKey) private var watchesAppRemovals = true

    var body: some View {
        TabView(selection: $model.settingsSection) {
            Tab(String(localized: "General"), systemImage: "gearshape", value: .general) { general }
            if DistributionChannel.supportsAdvanced {
                Tab(String(localized: "Scanning"), systemImage: "magnifyingglass", value: .scanning) { scanning }
            }
            Tab(String(localized: "Photos & Media"), systemImage: "photo.on.rectangle", value: .media) {
                CleanupSettingsView(model: model.cleanup)
            }
            if DistributionChannel.supportsAdvanced {
                Tab(String(localized: "AI & Privacy"), systemImage: "lock.shield", value: .privacy) { provider }
                Tab(String(localized: "Data"), systemImage: "externaldrive", value: .data) { data }
            }
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 420, idealHeight: 520)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            apiBaseURLText = model.providerSettings.apiBaseURL.absoluteString
        }
        .alert(String(localized: "Clear all data?"), isPresented: $showClearConfirmation) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Clear All Data"), role: .destructive) {
                Task { await model.clearAllData() }
            }
        } message: {
            Text(
                String(
                    localized:
                        "This deletes scan data, restore records, rules, and preferences. It cannot be undone."
                ))
        }
    }

    private var general: some View {
        Form {
            Section(String(localized: "Startup")) {
                Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let settingsError { Text(settingsError).foregroundStyle(SemanticScale.error) }
            }
            Section {
                Toggle(String(localized: "Show in menu bar"), isOn: $showsMenuBarExtra)
            } footer: {
                Text(String(localized: "Shows free space and quick actions. Tidybyte keeps running when its window closes."))
            }
            if DistributionChannel.supportsAdvanced {
                Section {
                    Toggle(String(localized: "Offer to clean up after I delete an app"), isOn: $watchesAppRemovals)
                        .onChange(of: watchesAppRemovals) { _, enabled in model.setRemovalWatching(enabled) }
                } footer: {
                    Text(String(localized: "Tidybyte notices apps removed from Applications while it runs."))
                }
            }
            Section(String(localized: "About")) {
                LabeledContent(
                    String(localized: "Version"),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")
                LabeledContent(
                    String(localized: "Build"),
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Development")
            }
        }.formStyle(.grouped)
    }

    private var scanning: some View {
        Form {
            Section(String(localized: "Defaults")) {
                Picker(String(localized: "Scan mode"), selection: $model.selectedMode) {
                    ForEach(ScanMode.allCases, id: \.self) { mode in Text(mode.displayName).tag(mode) }
                }.onChange(of: model.selectedMode) { model.saveSettings() }
                Picker(String(localized: "Cleanup posture"), selection: $model.cleanupPosture) {
                    Text(String(localized: "Conservative")).tag(CleanupPosture.conservative)
                    Text(String(localized: "Balanced")).tag(CleanupPosture.balanced)
                    Text(String(localized: "Aggressive")).tag(CleanupPosture.aggressive)
                }.onChange(of: model.cleanupPosture) { model.saveSettings() }
                Picker(String(localized: "Duplicate resolution"), selection: $model.duplicateStrategy) {
                    Text(String(localized: "Fold into APFS clone (nothing deleted)")).tag(DuplicateStrategy.apfsClone)
                    Text(String(localized: "Move duplicates to Trash")).tag(DuplicateStrategy.moveToTrash)
                }.onChange(of: model.duplicateStrategy) { model.saveSettings() }
            }
            Section(String(localized: "Automatic maintenance")) {
                Toggle(isOn: $model.autoscanEnabled) {
                    VStack(alignment: .leading, spacing: Spacing.elementTight) {
                        Text(String(localized: "Run daily when idle"))
                        Text(String(localized: "Waits for idle time and power (or ≥50% battery). Folds duplicate files only. Nothing is ever deleted unattended, and every fold can be undone.", comment: "Automatic maintenance explanation"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: model.autoscanEnabled) { model.saveSettings() }
                if !model.autoscanEnabled, !LaunchAgentInstaller.canInstall() {
                    Text(String(localized: "Install the app in /Applications to enable automatic maintenance.", comment: "Autoscan requires installed app hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastRun = model.lastAutoScanDate {
                    LabeledContent(String(localized: "Last automatic run")) {
                        Text(lastRun.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(String(localized: "Recommendation preferences")) {
                calibration(
                    String(localized: "Review source code carefully"),
                    rule: "Never suggest deleting source code files without manual review.")
                calibration(
                    String(localized: "Find more old downloads"),
                    rule: "Be more willing to suggest cleanup for old downloads and installers.")
                calibration(
                    String(localized: "Protect design source files"),
                    rule: "Never suggest deleting design source files (.psd, .sketch, .fig) without review.")
                calibration(
                    String(localized: "Prefer archiving"), rule: "Prefer archiving files instead of moving to trash.")
                calibration(
                    String(localized: "Review cloud files carefully"),
                    rule: "Never suggest actions on cloud-synced files without explicit review.")
            }
        }
        .formStyle(.grouped)
        .disabled(model.isScanning || model.isExecuting)
    }

    private var provider: some View {
        Form {
            Section(String(localized: "Privacy")) {
                Picker(String(localized: "Allowed data"), selection: $model.providerSettings.privacyMode) {
                    Text(String(localized: "Local Only")).tag(PrivacyMode.localOnly)
                    Text(String(localized: "Metadata Only AI")).tag(PrivacyMode.metadataOnlyAI)
                    Text(String(localized: "Snippets AI")).tag(PrivacyMode.snippetsAI)
                    Text(String(localized: "Vision AI")).tag(PrivacyMode.visionAI)
                    Text(String(localized: "Full Document AI")).tag(PrivacyMode.fullDocumentAI)
                }.onChange(of: model.providerSettings.privacyMode) { model.saveSettings() }
                Toggle(String(localized: "Enable AI during scans"), isOn: $model.includeAI)
                    .disabled(model.providerSettings.privacyMode == .localOnly)
                    .onChange(of: model.includeAI) { model.saveSettings() }
                Text(
                    String(
                        localized:
                            "Local Only sends no data. Other modes send allowed data to your provider."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Provider")) {
                TextField(String(localized: "Provider name"), text: $model.providerSettings.providerName)
                    .onChange(of: model.providerSettings.providerName) { model.saveSettings() }
                TextField(String(localized: "API base URL"), text: $apiBaseURLText)
                    .focused($apiBaseURLFocused).onSubmit { commitAPIBaseURL() }
                    .onChange(of: apiBaseURLFocused) { if !apiBaseURLFocused { commitAPIBaseURL() } }
                if let message = apiBaseURLValidationMessage { Text(message).foregroundStyle(SemanticScale.error) }
                TextField(String(localized: "Text model"), text: $model.providerSettings.textModel)
                    .onChange(of: model.providerSettings.textModel) { model.saveSettings() }
                SecureField(String(localized: "API key"), text: $model.apiKeyInput)
                Button(String(localized: "Save API Key")) {
                    Task {
                        await model.saveAPIKey()
                        settingsError = model.errorMessage
                    }
                }.disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let settingsError { Text(settingsError).foregroundStyle(SemanticScale.error) }
            }
            Section(String(localized: "Model options")) {
                Stepper(
                    String(localized: "Maximum tokens: \(model.providerSettings.maxTokens)"),
                    value: $model.providerSettings.maxTokens, in: 200...8000, step: 100
                )
                .onChange(of: model.providerSettings.maxTokens) { model.saveSettings() }
                Slider(value: $model.providerSettings.temperature, in: 0...1) {
                    Text(String(localized: "Temperature"))
                }.onChange(of: model.providerSettings.temperature) { model.saveSettings() }
            }
        }.formStyle(.grouped).disabled(model.isScanning || model.isExecuting)
    }

    private var data: some View {
        Form {
            Section(String(localized: "Local storage")) {
                Button(String(localized: "Export Database…")) { Task { await model.exportDatabase() } }
                Button(String(localized: "Clear All Data…"), role: .destructive) { showClearConfirmation = true }
                Text(String(localized: "Clearing local data removes the records needed to restore previous changes."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).disabled(model.isScanning || model.isExecuting)
    }

    private func calibration(_ title: String, rule: String) -> some View {
        Button(title) { Task { await model.applyCalibrationPreset(rule) } }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settingsError = nil
        } catch {
            settingsError = String(localized: "Could not update launch at login: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func commitAPIBaseURL() {
        guard apiBaseURLValidationMessage == nil,
            let url = URL(string: apiBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        model.providerSettings.apiBaseURL = url
        model.saveSettings()
    }

    private var apiBaseURLValidationMessage: String? {
        let text = apiBaseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        // HTTPS only: the gateway refuses cleartext endpoints at request time,
        // so accepting http here would just save a URL that always fails — and
        // credentials must never be offered over cleartext.
        guard let url = URL(string: text), url.scheme?.lowercased() == "https",
            url.host?.isEmpty == false
        else {
            return String(localized: "Enter an https provider URL such as https://api.example.com/v1.")
        }
        return nil
    }
}
