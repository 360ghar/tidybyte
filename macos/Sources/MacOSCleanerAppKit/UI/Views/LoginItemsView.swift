import MacOSCleanerCore
import SwiftUI

/// Apps › Login Items: launch agents and daemons that start with the Mac.
/// Your own agents can be removed through Leftovers; system-wide items are
/// managed in System Settings, where macOS asks for an administrator.
struct LoginItemsView: View {
    @Bindable var model: AppViewModel
    @State private var items: [LaunchItem] = []
    @State private var selection: LaunchItem.ID?
    @State private var pendingRemoval: LaunchItem?

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "No login items"), systemImage: "power",
                    description: Text(String(localized: "No third-party agents or daemons start with this Mac.")))
            } else {
                table
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(String(localized: "Login Items Settings"), systemImage: "gearshape")
                }
                .help(String(localized: "Open System Settings › General › Login Items"))
            }
        }
        .task { items = LaunchItems.list() }
        .confirmationDialog(
            String(localized: "Add \(pendingRemoval?.label ?? "") to Leftovers?"),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Add to Leftovers")) {
                guard let item = pendingRemoval else { return }
                Task {
                    if await model.stageRemoval(of: item), let id = model.selectedActionID {
                        model.showReviewAction(id: id)
                    }
                }
            }
        } message: {
            Text(String(localized: "Nothing changes until you approve it in Leftovers and confirm."))
        }
    }

    private var table: some View {
        Table(items, selection: $selection) {
            TableColumn(String(localized: "Name")) { item in
                Label {
                    Text(item.appBundle?.deletingPathExtension().lastPathComponent ?? item.label)
                } icon: {
                    if let bundle = item.appBundle, FileManager.default.fileExists(atPath: bundle.path) {
                        AppIconView(url: bundle, size: 16)
                    } else {
                        Image(systemName: "gearshape.2")
                    }
                }
                .help(item.label)
            }
            TableColumn(String(localized: "Kind")) { item in Text(item.domain.displayName) }
                .width(min: 110, ideal: 130)
            TableColumn(String(localized: "Status")) { item in status(item) }
                .width(min: 100, ideal: 130)
            TableColumn(String(localized: "Program")) { item in
                Text(item.program ?? "—").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .contextMenu(forSelectionType: LaunchItem.ID.self) { ids in
            if let item = items.first(where: { ids.contains($0.id) }) {
                Button(String(localized: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Button(String(localized: "Remove…")) { pendingRemoval = item }
                    .disabled(!item.canRemove)
            }
        }
    }

    @ViewBuilder
    private func status(_ item: LaunchItem) -> some View {
        if item.isProgramMissing {
            Label(String(localized: "Program missing"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(SemanticScale.warning)
        } else if let enabled = item.isEnabled {
            Text(enabled ? String(localized: "Allowed") : String(localized: "Turned off"))
        } else {
            Text(String(localized: "Not listed")).foregroundStyle(.secondary)
        }
    }
}
