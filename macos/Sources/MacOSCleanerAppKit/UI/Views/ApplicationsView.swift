import MacOSCleanerCore
import SwiftUI

struct ApplicationsView: View {
    @Bindable var model: AppViewModel

    private var applications: [InstalledApplication] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.installedApplications.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List(selection: $model.selectedApplicationID) {
            ForEach(applications) { app in
                HStack(spacing: Spacing.elementNormal) {
                    AppIconView(url: app.bundleURL, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.headline)
                        Text(app.bundleURL.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if model.stagedUninstallAppIDs.contains(app.id) {
                        Label(String(localized: "Staged"), systemImage: "checkmark.circle").font(.caption)
                    }
                    Text(app.bundleSizeBytes.formattedByteCount).monospacedDigit()
                }
                .padding(.vertical, Spacing.elementTight).tag(app.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.isLoadingApplications {
                ProgressView(String(localized: "Loading applications…"))
            } else if applications.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No applications found"), systemImage: "app",
                        description: Text(String(localized: "Tidybyte checks /Applications and ~/Applications.")))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first {
                Button(String(localized: "Show Details")) {
                    model.selectedApplicationID = id
                    model.showsInspector = true
                }
            }
        } primaryAction: { ids in
            model.selectedApplicationID = ids.first
            model.showsInspector = true
        }
        .task { if model.installedApplications.isEmpty { await model.loadInstalledApplications() } }
    }
}

struct ApplicationDetailsView: View {
    @Bindable var model: AppViewModel
    @State private var showsStagingConfirmation = false

    private var app: InstalledApplication? {
        model.installedApplications.first { $0.id == model.selectedApplicationID }
    }

    var body: some View {
        Group {
            if let app {
                Form {
                    Section {
                        Label {
                            Text(app.name).font(.headline)
                        } icon: {
                            AppIconView(url: app.bundleURL, size: 20)
                        }
                        Text(app.bundleURL.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        LabeledContent(String(localized: "Bundle size"), value: app.bundleSizeBytes.formattedByteCount)
                        if let identifier = app.bundleIdentifier {
                            LabeledContent(String(localized: "Identifier"), value: identifier)
                        }
                        Button(String(localized: "Show in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
                        }
                    }
                    footprint(app)
                    Section(String(localized: "Uninstall")) {
                        Button(String(localized: "Uninstall…")) { showsStagingConfirmation = true }
                            .disabled(
                                model.footprintItemsByAppID[app.id] == nil
                                    || model.stagedUninstallAppIDs.contains(app.id))
                        Text(
                            String(
                                localized: """
                                    Adds the app and its sure matches to Leftovers. Nothing changes until you \
                                    approve and confirm.
                                    """))
                        .font(.caption).foregroundStyle(.secondary)
                    }.disabled(model.isScanning || model.isExecuting || model.isPlanning)
                }.formStyle(.grouped)
                    .confirmationDialog(
                        String(localized: "Stage uninstall for \(app.name)?"),
                        isPresented: $showsStagingConfirmation, titleVisibility: .visible
                    ) {
                        Button(String(localized: "Add to Leftovers")) {
                            Task {
                                await model.stageUninstall(for: app)
                                if model.stagedUninstallAppIDs.contains(app.id), let id = model.selectedActionID {
                                    model.showReviewAction(id: id)
                                }
                            }
                        }
                        Button(String(localized: "Cancel"), role: .cancel) {}
                    } message: {
                        Text(
                            String(
                                localized:
                                    "Add the app and its data to Review. Files change only after approval and confirmation."
                            ))
                    }
            } else {
                ContentUnavailableView(String(localized: "No application selected"), systemImage: "app")
            }
        }
        .task(id: model.selectedApplicationID) { if let app { await model.loadFootprint(for: app) } }
    }

    private func footprint(_ app: InstalledApplication) -> some View {
        Section(String(localized: "Associated data")) {
            if let items = model.footprintItemsByAppID[app.id] {
                if items.isEmpty { Text(String(localized: "No associated data found.")).foregroundStyle(.secondary) }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(item.location.displayName, value: item.sizeBytes.formattedByteCount)
                        Text(item.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Label {
                            Text("\(item.confidence.displayName) · \(item.reason)")
                        } icon: {
                            Image(systemName: item.confidence == .certain ? "checkmark.seal" : "questionmark.circle")
                                .foregroundStyle(item.confidence == .certain ? SemanticScale.success : SemanticScale.warning)
                        }
                        .font(.caption)
                        if item.location.isSystemWide {
                            Label(String(localized: "Shared system location"), systemImage: "exclamationmark.shield")
                                .font(.caption).foregroundStyle(SemanticScale.warning)
                        }
                    }
                }
            } else {
                ProgressView(String(localized: "Measuring associated data…"))
            }
        }
    }
}

/// The app's own Finder icon, as Finder and System Settings show it.
struct AppIconView: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
