import MacOSCleanerCore
import QuickLook
import SwiftUI

struct FilesView: View {
    @Bindable var model: AppViewModel
    @State private var sortOrder = [KeyPathComparator(\FileRecord.sizeBytes, order: .reverse)]
    @State private var previewURL: URL?
    @State private var showsRelationships = false

    private var files: [FileRecord] { model.outcome?.files ?? [] }
    private var visibleFiles: [FileRecord] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { record in
            let inFolder =
                model.focusedExploreRecord.map {
                    record.url.deletingLastPathComponent().standardizedFileURL == $0.url.standardizedFileURL
                } ?? true
            return inFolder && (query.isEmpty || record.displayPath.localizedCaseInsensitiveContains(query))
        }.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.outcome == nil {
                ContentUnavailableView(
                    String(localized: "No scanned files"), systemImage: "folder",
                    description: Text(String(localized: "Start a scan to browse files and storage.")))
            } else {
                browserControls
                if model.exploreViewKindRaw == ExploreViewKind.list.rawValue {
                    fileTable
                } else {
                    ScrollView {
                        ExploreViewSwitcher(model: model, files: files, categorySections: model.dashboardSections)
                            .padding(Spacing.cardPadding)
                    }
                }
                if showsRelationships {
                    Divider()
                    RelationshipGraphView(model: model, edges: model.outcome?.edges ?? [], filesByID: model.filesByID)
                        .frame(height: 200).padding(Spacing.cardPadding)
                }
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: model.exploreViewKindRaw) { model.saveSettings() }
    }

    private var browserControls: some View {
        HStack(spacing: Spacing.elementNormal) {
            Button {
                model.focusExploreRecord(id: nil)
            } label: {
                Label(String(localized: "All Scanned Files"), systemImage: "folder")
            }
            .buttonStyle(.borderless)
            if let focused = model.focusedExploreRecord {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                Text(focused.fileName).lineLimit(1).help(focused.displayPath)
            }
            Spacer()
            Toggle(String(localized: "Relationships"), isOn: $showsRelationships).toggleStyle(.button)
            Menu {
                Button(String(localized: "Create Inbox Folder")) { Task { await model.createInbox() } }
                    .disabled(model.isScanning || model.isExecuting)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help(String(localized: "File actions"))
        }
        .controlSize(.small)
        .padding(Spacing.cardPadding)
    }

    private var fileTable: some View {
        Table(visibleFiles, selection: $model.selectedExploreRecordID, sortOrder: $sortOrder) {
            TableColumn(String(localized: "Name"), value: \.fileName) { record in
                Label(record.fileName, systemImage: record.kind == .directory ? "folder.fill" : "doc")
                    .help(record.displayPath)
            }
            .width(min: 180, ideal: 300)
            TableColumn(String(localized: "Size"), value: \.sizeBytes) { record in
                Text(record.sizeBytes.formattedByteCount).monospacedDigit()
            }.width(min: 70, ideal: 90)
            TableColumn(String(localized: "Kind"), value: \.kind.rawValue) { record in
                Text(record.kind.displayName)
            }.width(min: 70, ideal: 100)
            TableColumn(String(localized: "Modified"), value: \.sortableModifiedDate) { record in
                if let date = record.modifiedAt { Text(date, style: .date) } else { Text("—") }
            }.width(min: 85, ideal: 110)
        }
        .overlay {
            if visibleFiles.isEmpty {
                if !model.searchText.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                } else {
                    ContentUnavailableView(
                        String(localized: "No files in this view"), systemImage: "folder",
                        description: Text(String(localized: "This folder has no scanned files.")))
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let record = model.filesByID[id] {
                Button(String(localized: "Show Details")) {
                    model.selectedExploreRecordID = id
                    model.showsInspector = true
                }
                Button(String(localized: "Quick Look")) { previewURL = record.url }
                Button(String(localized: "Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([record.url])
                }
                Button(String(localized: "Add to Review")) { model.stageExploreRecordForCleanup(record) }
                    .disabled(model.isScanning || model.isExecuting || model.plan == nil)
            }
        } primaryAction: { ids in
            guard let id = ids.first, let record = model.filesByID[id] else { return }
            if record.kind == .directory { model.focusExploreRecord(id: id) } else { previewURL = record.url }
        }
        .onKeyPress(.space) {
            guard let record = model.selectedExploreRecord else { return .ignored }
            previewURL = record.url
            return .handled
        }
    }
}

extension FileRecord {
    fileprivate var sortableModifiedDate: Date { modifiedAt ?? .distantPast }
}
