import MacOSCleanerCore
import SwiftUI
import UniformTypeIdentifiers

struct CleanupToolView: View {
    @Bindable var model: CleanupModel
    let tool: CleanupTool
    @State private var sort = 0
    @State private var kind: MediaKind?
    @State private var category: SmartCategory?
    @State private var quality = 0
    @State private var showsChatFolder = false
    @State private var confirmation: CleanupBatch?
    @State private var resourceChoice: ResourceChoice?
    private struct ResourceChoice: Identifiable {
        let item: ReviewItem
        let index: Int
        var id: String { item.id + "\(index)" }
    }

    private var items: [ReviewItem] {
        model.items(for: tool).filter { item in
            (kind == nil || item.kind == kind || (kind == .document && item.kind == .pdf))
                && (category == nil || item.facts.category == category)
                && (tool != .blurry
                    || MediaAnalysisService.qualityIssues(item, sensitivity: model.settings.blurSensitivity)
                        .contains(qualityTitle))
        }.sorted {
            if sort == 2 || tool == .large { return $0.bytes > $1.bytes }
            let lhs = $0.modifiedAt ?? .distantPast
            let rhs = $1.modifiedAt ?? .distantPast
            return sort == 0 ? lhs > rhs : lhs < rhs
        }
    }
    private var groups: [AnalysisGroup] { model.result?.groups.filter { $0.tool == tool } ?? [] }
    private var selected: [ReviewItem] {
        let safe =
            tool.isCompression
            ? model.selection
            : MediaAnalysisService.safeSelection(model.selection, groups: model.result?.groups ?? [])
        return items.filter { safe.contains($0.id) && $0.canChange }
    }
    private var qualityTitle: String {
        switch quality {
        case 0: String(localized: "Out of focus")
        case 1: String(localized: "Too dark")
        default: String(localized: "Overexposed")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            if tool == .downloads {
                Button(String(localized: "Choose exported chat folder…")) { showsChatFolder = true }
                    .disabled(model.isBusy)
                Text(
                    String(
                        localized: """
                            Removing these files removes the local exported or downloaded copy \
                            only. It does not remove the copy inside a chat app.
                            """
                    )
                )
                .font(.callout)
            }
            if model.result?.isFresh != true {
                ContentUnavailableView(
                    String(localized: "Not scanned"), systemImage: "arrow.clockwise",
                    description: Text(String(localized: "Run a scan to refresh this tool.")))
            } else if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "No matching items"), systemImage: "checkmark.circle",
                    description: Text(String(localized: "No files in this scope match the current filters.")))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.elementSection) {
                        ForEach(groups) { group in groupView(group) }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 160), spacing: Spacing.elementNormal)],
                            spacing: Spacing.elementNormal
                        ) {
                            ForEach(items) { item in itemCard(item) }
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .onCommand(#selector(NSResponder.selectAll(_:))) {
                    model.selection = Set(items.filter(\.canChange).map(\.id))
                }
                .onDeleteCommand { requestTrash() }
            }
            if !model.jobs.isEmpty {
                ScrollView {
                    LazyVStack {
                        ForEach(model.jobs) { job in
                            HStack {
                                Text(job.item.name).lineLimit(1)
                                ProgressView(value: job.progress).frame(maxWidth: 180)
                                Text(
                                    job.event?.error ?? job.event?.state.title
                                        ?? (model.isBusy
                                            ? String(localized: "Queued") : String(localized: "Unprocessed"))
                                )
                                .font(.caption).lineLimit(2)
                            }
                        }
                    }
                }.frame(maxHeight: 160)
            }
        }
        .padding(Spacing.cardPadding)
        .navigationTitle(tool.title)
        .navigationSubtitle(String(localized: "\(items.count) items", comment: "Tool item count"))
        .toolbar { ToolbarItemGroup { controls } }
        .safeAreaBar(edge: .bottom) { actions }
            .fileImporter(isPresented: $showsChatFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { Task { await model.scanChatFolder(url) } }
            }
            .sheet(item: $model.selectedItem) { item in
                VStack {
                    Text(item.name).font(.headline)
                    ReviewPreview(item: item, model: model)
                    Button(String(localized: "Done")) { model.selectedItem = nil }.keyboardShortcut(.cancelAction)
                }
                .padding(Spacing.cardPadding)
                .frame(minWidth: 640, minHeight: 520)
                .presentationSizing(.page)
            }
            .sheet(item: $confirmation) { batch in
                if batch.tool.isCompression {
                    compressionConfirmation(batch)
                } else {
                    VStack {
                        ReviewBatchSummary(
                            decisions: batch.items.map { ReviewDecision(item: $0, choice: .trash) }, model: model,
                            retained: batch.retained)
                        HStack {
                            Button(String(localized: "Cancel")) { confirmation = nil }
                            Spacer()
                            Button(String(localized: "Move to Trash"), role: .destructive) {
                                confirmation = nil
                                model.trashSelection(batch)
                            }
                        }
                    }
                    .padding(Spacing.cardPadding)
                    .frame(minWidth: 600, minHeight: 480)
                    .presentationSizing(.form)
                }
            }
            .sheet(item: $resourceChoice) { choice in
                VStack(spacing: Spacing.elementNormal) {
                    ReviewPreview(item: choice.item, model: model).frame(height: 280)
                    Text(String(localized: "Keep \(choice.item.resources[choice.index].name)?")).font(.headline)
                    Text(
                        String(
                            localized: """
                                A verified replacement asset will be created. The original goes to \
                                Recently Deleted and this can sync to iCloud. RAW editing data, motion, \
                                and previous edit history that are not in the selected component will \
                                be lost from the replacement.
                                """
                        ))
                    let reduction = (choice.item.bytes - choice.item.resources[choice.index].bytes).formattedByteCount
                    Text(
                        String(
                            localized:
                                "Estimated reduction: \(reduction)"
                        ))
                    HStack {
                        Button(String(localized: "Cancel")) { resourceChoice = nil }
                        Spacer()
                        Button(String(localized: "Keep this component"), role: .destructive) {
                            resourceChoice = nil
                            model.keepResource(choice.item, index: choice.index)
                        }
                    }
                }
                .padding(Spacing.cardPadding)
                .frame(minWidth: 560)
                .presentationSizing(.form)
            }
    }

    @ViewBuilder private var controls: some View {
        Group {
            Picker(String(localized: "Sort"), selection: $sort) {
                Text(String(localized: "Newest")).tag(0)
                Text(String(localized: "Oldest")).tag(1)
                Text(String(localized: "Largest")).tag(2)
            }
            if tool == .large {
                Picker(String(localized: "Kind"), selection: $kind) {
                    Text(String(localized: "All")).tag(Optional<MediaKind>.none)
                    ForEach([MediaKind.image, .video, .document], id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                Picker(String(localized: "Minimum Size"), selection: $model.settings.largeMegabytes) {
                    // Includes the saved value, which Settings can set to any 5 MB step.
                    let sizes = Set([5.0, 10, 25, 50, 100, 250, 500, model.settings.largeMegabytes]).sorted()
                    ForEach(sizes, id: \.self) { megabytes in
                        Text(String(localized: "\(Int(megabytes)) MB or larger")).tag(megabytes)
                    }
                }
            }
            if tool == .categories {
                Picker(String(localized: "Category"), selection: $category) {
                    Text(String(localized: "All")).tag(Optional<SmartCategory>.none)
                    ForEach(SmartCategory.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
            }
            if tool == .blurry {
                Picker(String(localized: "Quality issue"), selection: $quality) {
                    Text(String(localized: "Out of focus")).tag(0)
                    Text(String(localized: "Too dark")).tag(1)
                    Text(String(localized: "Overexposed")).tag(2)
                }.pickerStyle(.segmented)
            }
        }.onChange(of: model.settings.largeMegabytes) {
            model.result?.settings.largeMegabytes = model.settings.largeMegabytes
            Task { await model.saveSettings() }
        }
    }

    private func itemCard(_ item: ReviewItem) -> some View {
        let isSelected = model.selection.contains(item.id)
        return VStack(alignment: .leading, spacing: 4) {
            thumbnail(item, isSelected: isSelected)
            Text(item.name).lineLimit(1).truncationMode(.middle)
            Text(item.bytes.formattedByteCount).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let seconds = item.facts.duration, seconds.isFinite {
                Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))).font(.caption)
            }
            if tool == .blurry, let score = item.facts.sharpness {
                Text(String(localized: "Sharpness \(score.formatted(.number.precision(.fractionLength(3))))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !item.isDownloaded { Text(String(localized: "Not downloaded")).font(.caption) }
            if item.isCloudSynced { Text(String(localized: "Cloud-synced file. Read only")).font(.caption) }
            if tool == .formatPairs, MediaAnalysisService.isCompoundPhoto(item) {
                Menu(String(localized: "Keep one component…")) {
                    ForEach(Array(item.resources.enumerated()), id: \.offset) { index, resource in
                        if [1, 2, 4, 9].contains(resource.type) {
                            Button(resource.name) { resourceChoice = ResourceChoice(item: item, index: index) }
                        }
                    }
                }.disabled(!item.canChange || model.isBusy)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.selectedItem = item }
        .onTapGesture { toggle(item) }
        .contextMenu {
            Button(String(localized: "Quick Look")) { model.selectedItem = item }
            Button(isSelected ? String(localized: "Deselect") : String(localized: "Select")) { toggle(item) }
                .disabled(!item.canChange)
            if let url = item.url {
                Button(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.name), \(item.bytes.formattedByteCount)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { toggle(item) }
        .accessibilityAction(named: Text(String(localized: "Quick Look"))) { model.selectedItem = item }
    }

    /// Photos-style thumbnail: an accent ring and a check badge mark the selection.
    private func thumbnail(_ item: ReviewItem, isSelected: Bool) -> some View {
        ReviewPreview(item: item, model: model, thumbnail: true)
            .frame(height: 120).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.cardCompact, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                        .font(.title2)
                        .padding(6)
                }
            }
    }

    private func toggle(_ item: ReviewItem) {
        guard item.canChange, !model.isBusy else { return }
        if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
    }

    private func requestTrash() {
        guard !tool.isCompression, !model.isBusy else { return }
        model.selection = MediaAnalysisService.safeSelection(model.selection, groups: model.result?.groups ?? [])
        guard !selected.isEmpty else { return }
        confirmation = model.makeBatch(items: selected, tool: tool)
    }
}

extension CleanupToolView {
    private func groupView(_ group: AnalysisGroup) -> some View {
        GroupBox {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(items.filter { group.memberIDs.contains($0.id) }) { item in
                        VStack {
                            ReviewPreview(item: item, model: model, thumbnail: true).frame(width: 100, height: 75)
                            Text(item.name).font(.caption).lineLimit(1)
                            let label =
                                group.bestID == item.id ? String(localized: "Best") : String(localized: "Keep this")
                            Button(label) {
                                if let index = model.result?.groups.firstIndex(where: { $0.id == group.id }) {
                                    model.result?.groups[index].bestID = item.id
                                    model.selection.remove(item.id)
                                }
                            }
                        }.frame(width: 120)
                    }
                }
            }
            HStack {
                Text(group.explanation).font(.caption)
                Spacer()
                Button(String(localized: "Move Others to Trash…"), role: .destructive) {
                    model.selection = Set(group.memberIDs.filter { $0 != group.bestID })
                    confirmation = model.makeBatch(items: selected, tool: tool)
                }.disabled(model.isBusy)
            }
        }
    }

    private var actions: some View {
        let selectedBytes = selected.reduce(0) { $0 + $1.bytes }.formattedByteCount
        return GlassEffectContainer {
            HStack(spacing: Spacing.elementNormal) {
                Button(String(localized: "Review One by One")) {
                    Task {
                        await model.startSession(items: items, tool: tool)
                        model.selectedTool = .swipe
                    }
                }
                .buttonStyle(.glass)
                .disabled(model.session != nil)
                if !groups.isEmpty {
                    Button(String(localized: "Select Extras in All Groups")) {
                        model.selection = MediaAnalysisService.safeSelection(
                            Set(groups.flatMap { group in group.memberIDs.filter { $0 != group.bestID } }),
                            groups: model.result?.groups ?? [])
                    }
                    .buttonStyle(.glass)
                }
                if tool.isCompression {
                    Button(String(localized: "Compress \(selected.count) Items…")) {
                        confirmation = model.makeBatch(items: selected, tool: tool)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(selected.isEmpty)
                } else {
                    Button(String(localized: "Move \(selected.count) to Trash · \(selectedBytes)…"), role: .destructive) {
                        requestTrash()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(selected.isEmpty)
                }
            }
            .padding(Spacing.elementTight)
            .glassEffect(in: .capsule)
        }
        .padding(.bottom, Spacing.elementNormal)
        .disabled(model.isBusy || model.result?.isFresh != true)
    }
}

extension CleanupToolView {
    private func compressionConfirmation(_ batch: CleanupBatch) -> some View {
        VStack(alignment: .leading, spacing: Spacing.elementNormal) {
            Text(String(localized: "Confirm compression")).font(.title2)
            List(batch.items) { item in
                let estimate = MediaCompressionService.estimate(item, settings: batch.settings).formattedByteCount
                HStack {
                    ReviewPreview(item: item, model: model, thumbnail: true).frame(width: 64, height: 48)
                    Text(item.name)
                    Spacer()
                    Text(
                        String(
                            localized:
                                "\(item.bytes.formattedByteCount) → about \(estimate)"
                        ))
                }
            }
            Text(
                String(
                    localized: """
                        Estimates can differ from the result. Compression can reduce quality. \
                        Each original is removed only after its smaller replacement verifies. \
                        Photos replacements can lose edit history or compound-media data; \
                        deletion can sync to iCloud. Originals remain recoverable in Trash \
                        or Recently Deleted.
                        """
                ))
            HStack {
                Button(String(localized: "Cancel")) { confirmation = nil }
                Spacer()
                Button(String(localized: "Compress and replace")) {
                    confirmation = nil
                    model.compressSelection(batch)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(minWidth: 620, minHeight: 440)
        .presentationSizing(.form)
    }
}
