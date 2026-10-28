import SwiftUI
import MacOSCleanerCore

/// Snapshots tab: pick any two stored scan snapshots and see which folders
/// grew, ranked by byte delta. Read-only — diffing never modifies data.
struct SnapshotDiffView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        List(selection: $model.selectedSnapshotID) {
            Section(String(localized: "Saved scans")) {
                ForEach(model.storageSnapshots.filter {
                    model.searchText.isEmpty || snapshotLabel(for: $0).localizedCaseInsensitiveContains(model.searchText)
                        || $0.bytesByRootPath.keys.contains { $0.localizedCaseInsensitiveContains(model.searchText) }
                }) { snapshot in
                    Text(snapshotLabel(for: snapshot)).tag(snapshot.id)
                }
            }
            if model.isLoadingSnapshots {
                ProgressView(String(localized: "Loading snapshots…"))
            } else if model.storageSnapshots.count < 2 {
                emptyState
            } else {
                pickerCard
                diffCard
            }
        }
        .listStyle(.inset)
        .task { await model.loadSnapshotHistory() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Need at least two scans to compare."), systemImage: "square.stack.3d.up")
        } description: {
            Text(String(localized: "Each scan saves a snapshot. Start another scan to compare results."))
        } actions: {
            EmptyStateActionsView(model: model)
        }
    }

    private var pickerCard: some View {
        Section( String(localized: "Compare Scans")) {
            VStack(alignment: .leading, spacing: Spacing.elementTight) {
                Picker(String(localized: "Older snapshot"), selection: Binding(
                    get: { model.olderSnapshotID ?? "" },
                    set: { newValue in
                        model.olderSnapshotID = newValue.isEmpty ? nil : newValue
                        Task { await model.refreshSnapshotDiff() }
                    }
                )) {
                    ForEach(model.storageSnapshots.sorted { $0.createdAt < $1.createdAt }) { snapshot in
                        Text(snapshotLabel(for: snapshot)).tag(snapshot.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(String(localized: "Older snapshot"))
                Picker(String(localized: "Newer snapshot"), selection: Binding(
                    get: { model.newerSnapshotID ?? "" },
                    set: { newValue in
                        model.newerSnapshotID = newValue.isEmpty ? nil : newValue
                        Task { await model.refreshSnapshotDiff() }
                    }
                )) {
                    ForEach(model.storageSnapshots.sorted { $0.createdAt < $1.createdAt }) { snapshot in
                        Text(snapshotLabel(for: snapshot)).tag(snapshot.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(String(localized: "Newer snapshot"))
            }
        }
    }

    private func snapshotLabel(for snapshot: StorageSnapshot) -> String {
        let date = snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(date), \(snapshot.totalBytes.formattedByteCount)"
    }

    @ViewBuilder
    private var diffCard: some View {
        if let error = model.snapshotDiffError {
            Text(error)
                .appFont(.labelMedium)
                .foregroundStyle(Primary.label)
                .padding(Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SemanticScale.errorSoft, in: RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
        } else if let diff = model.snapshotDiff {
            Section( String(localized: "Snapshot Diff")) {
                VStack(alignment: .leading, spacing: Spacing.elementTight) {
                    headlineRow(for: diff)
                    if diff.folderDeltas.isEmpty {
                        Text(String(localized: "No folder changed between these snapshots."))
                            .appFont(.caption)
                            .foregroundStyle(Color.secondary)
                    } else {
                        Text(String(localized: "Grown folders"))
                            .font(.app(.h3))
                            
                            .foregroundStyle(Color.secondary)
                        ForEach(diff.folderDeltas.filter { model.searchText.isEmpty || $0.path.localizedCaseInsensitiveContains(model.searchText) }) { delta in
                            folderRow(for: delta)
                        }
                    }
                    if !diff.categoryDeltas.isEmpty {
                        Text(String(localized: "Category shifts"))
                            .font(.app(.h3))
                            
                            .foregroundStyle(Color.secondary)
                        ForEach(diff.categoryDeltas, id: \.category) { entry in
                            HStack {
                                Text(entry.category.displayName)
                                    .appFont(.labelMedium)
                                    
                                    .foregroundStyle(Color.secondary)
                                Spacer()
                                deltaChip(entry.deltaBytes)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Snapshot comparison"))
        }
    }

    private func headlineRow(for diff: SnapshotDiff) -> some View {
        HStack {
            Text(String(localized: "Total change"))
                .appFont(.h4)
                .foregroundStyle(Color.primary)
            Spacer()
            deltaChip(diff.totalDeltaBytes)
        }
    }

    private func folderRow(for delta: SnapshotFolderDelta) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(delta.path)
                    .appFont(.filePath)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(delta.olderBytes.formattedByteCount) → \(delta.newerBytes.formattedByteCount)")
                    .appFont(.filePath)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }
            Spacer()
            deltaChip(delta.deltaBytes)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(delta.path), change \(signedBytes(delta.deltaBytes))"))
    }

    private func deltaChip(_ value: Int64) -> some View {
        Text(signedBytes(value))
            .appFont(.labelMedium)
            .monospacedDigit()
            .foregroundStyle(value > 0 ? SemanticScale.warning : SemanticScale.success)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(value > 0 ? SemanticScale.warningSoft : SemanticScale.successSoft)
            .clipShape(.rect(cornerRadius: Radius.cardCompact))
    }

    private func signedBytes(_ value: Int64) -> String {
        value >= 0 ? "+\(value.formattedByteCount)" : "−\(abs(value).formattedByteCount)"
    }
}

struct SnapshotDetailsView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        if let snapshot = model.storageSnapshots.first(where: { $0.id == model.selectedSnapshotID }) {
            Form {
                Section(String(localized: "Scan snapshot")) {
                    Text(snapshot.createdAt, format: .dateTime).font(.headline)
                    LabeledContent(String(localized: "Scanned size"), value: snapshot.totalBytes.formattedByteCount)
                    LabeledContent(String(localized: "Removed through Cleaner"),
                                   value: snapshot.removedBytesThroughApp.formattedByteCount)
                }
                Section(String(localized: "Scan locations")) {
                    ForEach(snapshot.bytesByRootPath.keys.sorted(), id: \.self) { path in
                        LabeledContent(path, value: (snapshot.bytesByRootPath[path] ?? 0).formattedByteCount)
                            .textSelection(.enabled)
                    }
                }
                Section(String(localized: "Categories")) {
                    ForEach(snapshot.bytesByCategory.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                        LabeledContent(category.displayName,
                                       value: (snapshot.bytesByCategory[category] ?? 0).formattedByteCount)
                    }
                }
            }.formStyle(.grouped)
        } else {
            ContentUnavailableView(String(localized: "No snapshot selected"), systemImage: "square.stack.3d.up")
        }
    }
}
