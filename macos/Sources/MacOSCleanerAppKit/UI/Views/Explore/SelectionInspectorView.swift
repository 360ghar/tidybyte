import AppKit
import MacOSCleanerCore
import QuickLook
import SwiftUI

/// File metadata and navigation. Staging is separate from approval in Review.
struct SelectionInspectorView: View {
    @Bindable var model: AppViewModel
    @State private var previewURL: URL?
    @State private var didCopyPath = false

    private var record: FileRecord? { model.selectedExploreRecord ?? model.focusedExploreRecord }
    private var files: [FileRecord] { model.outcome?.files ?? [] }

    var body: some View {
        Group {
            if let record {
                Form {
                    Section {
                        Label(record.fileName, systemImage: record.kind == .directory ? "folder" : "doc")
                            .font(.headline).textSelection(.enabled)
                        Text(record.displayPath).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary).textSelection(.enabled)
                        LabeledContent(String(localized: "Kind"), value: record.kind.displayName)
                    }
                    sizeDetails(record)
                    dateDetails(record)
                    riskDetails(record)
                    children(record)
                    fileActions(record)
                    reviewActions(record)
                }.formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    String(localized: "No file selected"), systemImage: "doc.text.magnifyingglass",
                    description: Text(String(localized: "Select a file to see its details.")))
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: model.selectedExploreRecordID) { didCopyPath = false }
    }

    private func sizeDetails(_ record: FileRecord) -> some View {
        let totals = ExploreSubtreeIndex.totals(files: files)
        let total = ExploreSubtreeIndex.subtreeBytes(for: record, totals: totals)
        let sizes = FileSizeProbe.sizes(for: record.url)
        let logical = record.kind == .directory ? total : sizes.logical ?? total
        let allocated = record.kind == .directory ? nil : sizes.allocated
        let parent = ExploreSubtreeIndex.parentPath(of: record.displayPath)
        let parentBytes = totals[parent] ?? files.filter { $0.kind != .directory }.reduce(0) { $0 + $1.sizeBytes }
        return Section(String(localized: "Size")) {
            LabeledContent(String(localized: "Logical size"), value: logical.formattedByteCount)
            if let allocated {
                LabeledContent(String(localized: "Size on disk"), value: allocated.formattedByteCount)
                if logical > allocated {
                    LabeledContent(
                        String(localized: "Compression savings"),
                        value: (logical - allocated).formattedByteCount)
                }
            }
            if parentBytes > 0 {
                LabeledContent(
                    String(localized: "Share of parent"),
                    value: min(1, Double(total) / Double(parentBytes)).formatted(.percent.precision(.fractionLength(1)))
                )
            }
            if let items = record.rolledUpItemCount {
                // A summarized folder has no scanned children to count.
                LabeledContent(String(localized: "Items inside"), value: items.formatted())
            } else if record.kind == .directory || record.kind == .package {
                let descendants = ExploreSubtreeIndex.descendants(ofParentPath: record.displayPath, in: files)
                LabeledContent(
                    String(localized: "Scanned files"),
                    value: descendants.filter { $0.kind == .regularFile }.count.formatted())
                LabeledContent(
                    String(localized: "Scanned folders"),
                    value: descendants.filter { $0.kind == .directory }.count.formatted())
            }
        }
    }

    private func dateDetails(_ record: FileRecord) -> some View {
        Section(String(localized: "Information")) {
            if let date = record.createdAt {
                LabeledContent(
                    String(localized: "Created"), value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let date = record.modifiedAt {
                LabeledContent(
                    String(localized: "Modified"), value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let date = record.lastOpenedAt {
                LabeledContent(
                    String(localized: "Last opened"), value: date.formatted(date: .abbreviated, time: .shortened))
            }
            // Owner and tags are read live for the selected item only; the scan skips them for speed.
            if let owner = (try? FileManager.default.attributesOfItem(atPath: record.url.path))?[.ownerAccountName]
                as? String {
                LabeledContent(String(localized: "Owner"), value: owner)
            }
            if let tags = (try? URL(fileURLWithPath: record.url.path).resourceValues(forKeys: [.tagNamesKey]))?.tagNames,
                !tags.isEmpty {
                LabeledContent(String(localized: "Tags"), value: tags.joined(separator: ", "))
            }
            if let target = record.symlinkTarget {
                LabeledContent(String(localized: "Link target"), value: target.path)
            }
        }
    }

    @ViewBuilder
    private func riskDetails(_ record: FileRecord) -> some View {
        if !record.riskFlags.isEmpty || record.cloudProvider != nil {
            Section(String(localized: "Risk information")) {
                ForEach(Array(record.riskFlags).sorted { $0.rawValue < $1.rawValue }, id: \.self) { flag in
                    Label(flag.displayName, systemImage: "exclamationmark.shield")
                        .foregroundStyle(SemanticScale.warning)
                }
                if let provider = record.cloudProvider {
                    LabeledContent(String(localized: "Cloud provider"), value: provider)
                }
            }
        }
    }

    @ViewBuilder
    private func children(_ record: FileRecord) -> some View {
        if record.kind == .directory || record.kind == .package {
            let totals = ExploreSubtreeIndex.totals(files: files)
            let children = ExploreSubtreeIndex.directChildren(ofParentPath: record.displayPath, in: files)
                .sorted {
                    ExploreSubtreeIndex.subtreeBytes(for: $0, totals: totals)
                        > ExploreSubtreeIndex.subtreeBytes(for: $1, totals: totals)
                }
            Section(String(localized: "Largest inside")) {
                if children.isEmpty { Text(String(localized: "No scanned children.")).foregroundStyle(.secondary) }
                ForEach(children.prefix(10)) { child in
                    Button {
                        model.selectedExploreRecordID = child.id
                    } label: {
                        LabeledContent(
                            child.fileName,
                            value: ExploreSubtreeIndex.subtreeBytes(for: child, totals: totals).formattedByteCount)
                    }.buttonStyle(.borderless)
                }
            }
        }
    }

    private func fileActions(_ record: FileRecord) -> some View {
        Section(String(localized: "File actions")) {
            Button(String(localized: "Show in Finder"), systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([record.url])
            }
            Button(String(localized: "Quick Look"), systemImage: "eye") { previewURL = record.url }
            if record.kind == .directory {
                Button(String(localized: "Open Folder"), systemImage: "folder.badge.plus") {
                    model.focusExploreRecord(id: record.id)
                }
            }
            Button(
                didCopyPath ? String(localized: "Copied") : String(localized: "Copy Path"),
                systemImage: "doc.on.doc"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.url.path, forType: .string)
                didCopyPath = true
            }
        }
    }

    private func reviewActions(_ record: FileRecord) -> some View {
        Section(String(localized: "Cleanup")) {
            if let action = model.stagedExploreAction(matching: record) {
                Button(String(localized: "Review Action")) {
                    model.showReviewAction(id: action.id)
                }
                Button(String(localized: "Remove from Plan")) { model.unstageExploreAction(matching: record) }
                    .disabled(action.executedAt != nil)
            } else {
                Button(String(localized: "Add to Review")) { model.stageExploreRecordForCleanup(record) }
                    .disabled(model.plan == nil)
            }
            Text(String(localized: "Review and approve proposed changes before applying them."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(model.isScanning || model.isExecuting || model.isPlanning)
    }
}
