import MacOSCleanerCore
import SwiftUI

/// The home screen, modeled on System Settings › General › Storage: one
/// capacity bar, then one recommendation row per sidebar area.
struct OverviewView: View {
    @Bindable var model: AppViewModel
    @State private var disk = DiskGaugeData.currentHomeVolume()
    @State private var trashBytes: Int64?
    @State private var confirmsEmptyTrash = false

    private static let recommendationRows: [AppDestination] = [
        .systemJunk, .developer, .largeFiles, .duplicates, .media, .leftovers
    ]

    var body: some View {
        Form {
            Section { storage }
            if model.outcome == nil && model.cleanup.result == nil {
                Section { firstScan }
            } else {
                Section(String(localized: "Recommendations")) {
                    let rows = recommendations
                    if rows.isEmpty {
                        Text(String(localized: "Nothing to clean right now. Scan again after you use your Mac for a while."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows, id: \.row) { item in recommendationRow(item.row, bytes: item.bytes) }
                }
            }
            if let outcome = model.outcome { latestScan(outcome) }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "Empty the Trash?"), isPresented: $confirmsEmptyTrash, titleVisibility: .visible
        ) {
            Button(String(localized: "Empty Trash"), role: .destructive) { emptyTrash() }
        } message: {
            Text(
                String(
                    localized: "This permanently erases \((trashBytes ?? 0).formattedByteCount). You can't undo this action."))
        }
        .task {
            disk = DiskGaugeData.currentHomeVolume()
            trashBytes = await TrashMeasure.userTrashBytes()
        }
    }

    // MARK: Storage

    @ViewBuilder private var storage: some View {
        if let total = disk.totalBytes, let free = disk.freeBytes, total > 0 {
            let used = max(0, total - free)
            VStack(alignment: .leading, spacing: Spacing.elementTight) {
                LabeledContent {
                    Text(String(localized: "\(free.formattedByteCount) available of \(total.formattedByteCount)"))
                        .monospacedDigit()
                } label: {
                    Label(volumeName, systemImage: "internaldrive").font(.headline)
                }
                ProgressView(value: Double(used), total: Double(total))
                    .tint(Double(used) / Double(total) > 0.9 ? SemanticScale.warning : nil)
                    .accessibilityLabel(String(localized: "Startup disk"))
                    .accessibilityValue(
                        String(localized: "\(used.formattedByteCount) used, \(free.formattedByteCount) available"))
                if Double(used) / Double(total) > 0.9 {
                    Label(String(localized: "Your startup disk is almost full."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(SemanticScale.warning)
                        .font(.callout)
                }
            }
        } else {
            Text(String(localized: "Disk capacity is unavailable.")).foregroundStyle(.secondary)
        }
        LabeledContent {
            HStack {
                Text(trashBytes?.formattedByteCount ?? String(localized: "Unknown")).monospacedDigit()
                Button(String(localized: "Open Trash")) {
                    if let url = URL(string: "trash:///") { NSWorkspace.shared.open(url) }
                }
                if DistributionChannel.supportsAdvanced {
                    Button(String(localized: "Empty Trash…"), role: .destructive) { confirmsEmptyTrash = true }
                        .disabled((trashBytes ?? 0) == 0)
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(String(localized: "Trash"))
                    Text(String(localized: "Space returns after you empty the Trash."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "trash")
            }
        }
    }

    private func emptyTrash() {
        do {
            try TrashBin.empty()
        } catch {
            model.setErrorMessage(error.localizedDescription)
        }
        Task {
            trashBytes = await TrashMeasure.userTrashBytes()
            disk = DiskGaugeData.currentHomeVolume()
        }
    }

    private var volumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName)
            ?? String(localized: "Startup Disk")
    }

    // MARK: First scan

    private var firstScan: some View {
        VStack(spacing: Spacing.elementNormal) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(String(localized: "Find what you can clean")).font(.title2.bold())
            Text(
                String(
                    localized: """
                        Tidybyte looks for caches, leftovers, duplicates, and large files. \
                        Nothing changes until you approve it.
                        """)
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Button(String(localized: "Scan My Mac")) { model.scanAll() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isScanning || model.cleanup.isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sectionGap)
    }

    // MARK: Recommendations

    private var recommendations: [(row: AppDestination, bytes: Int64)] {
        let pending = model.pendingBytesByDestination
        return Self.recommendationRows.compactMap { row in
            guard AppDestination.sections.flatMap(\.rows).contains(row) else { return nil }
            let bytes = row == .media ? model.cleanup.reclaimableBytes : (pending[row] ?? 0)
            return bytes > 0 ? (row, bytes) : nil
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private func recommendationRow(_ row: AppDestination, bytes: Int64) -> some View {
        LabeledContent {
            HStack(spacing: Spacing.elementNormal) {
                Text(bytes.formattedByteCount).monospacedDigit().foregroundStyle(.secondary)
                Button(String(localized: "Review…")) { model.destination = row }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                    Text(Self.summary(for: row)).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: row.icon)
            }
        }
    }

    private static func summary(for row: AppDestination) -> String {
        switch row {
        case .systemJunk: String(localized: "Caches, logs, and browser data that apps rebuild.")
        case .developer: String(localized: "Build folders, package caches, and simulator data.")
        case .largeFiles: String(localized: "Big files, old downloads, and installers.")
        case .duplicates: String(localized: "Identical copies. Fold them to save space without deleting.")
        case .media: String(localized: "Similar photos, screenshots, and large videos.")
        case .leftovers: String(localized: "Files left behind by apps you removed.")
        default: ""
        }
    }

    // MARK: Latest scan

    private func latestScan(_ outcome: ScanOutcome) -> some View {
        Section {
            LabeledContent(
                String(localized: "Items checked"),
                value: outcome.files.count.formatted())
            LabeledContent(
                String(localized: "Size checked"),
                value: outcome.session.totalBytesSeen.formattedByteCount)
            if let completed = outcome.session.completedAt {
                LabeledContent(String(localized: "Finished"), value: completed.formatted(.relative(presentation: .named)))
            }
            HStack {
                Button(String(localized: "Export Report…")) { Task { await model.generateReport() } }
                if model.generatedReportURL != nil {
                    Button(String(localized: "Open Report")) { model.openLatestReport() }
                }
            }
        } header: {
            Text(String(localized: "Latest Scan"))
        } footer: {
            Text(String(localized: "Results cover the scanned locations, not the whole disk."))
        }
    }
}

extension CleanupModel {
    /// Bytes the Photos & Media tools could reclaim, counting each item once
    /// and never selecting the best copy of a group.
    var reclaimableBytes: Int64 {
        guard result?.isFresh == true else { return 0 }
        let tools: [CleanupTool] = [.duplicates, .similar, .bursts, .blurry, .screenshots, .screenRecordings, .large]
        let keepers = Set(result?.groups.map(\.bestID) ?? [])
        var bytesByID: [String: Int64] = [:]
        for tool in tools {
            for item in items(for: tool) where item.canChange && !keepers.contains(item.id) {
                bytesByID[item.id] = item.bytes
            }
        }
        let allowed = MediaAnalysisService.safeSelection(Set(bytesByID.keys), groups: result?.groups ?? [])
        return bytesByID.filter { allowed.contains($0.key) }.values.reduce(0, +)
    }
}

/// Size of ~/.Trash. Reading it needs Full Disk Access; nil means unknown.
enum TrashMeasure {
    static func userTrashBytes() async -> Int64? {
        await Task.detached(priority: .utility) {
            let trash = ReviewSafety.userHome.appendingPathComponent(".Trash")
            // Listing fails without Full Disk Access; report unknown, not zero.
            guard (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil,
                let files = FileManager.default.enumerator(
                at: trash, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            else { return nil }
            var total: Int64 = 0
            while let file = files.nextObject() as? URL {
                if Task.isCancelled { return nil }
                guard let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                else { return nil }
                if values.isRegularFile == true { total += Int64(values.totalFileAllocatedSize ?? 0) }
            }
            return total
        }.value
    }
}
