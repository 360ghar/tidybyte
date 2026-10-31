import MacOSCleanerCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var executionRequest: ExecutionRequest?
    @AppStorage(OnboardingView.stepKey) private var onboardingStep = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: Spacing.sidebarWidth, max: 280)
        } detail: {
            searchableDetail
                .navigationTitle(model.destination.title)
                .navigationSubtitle(busyText ?? "")
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) { StatusNotices(model: model) }
                .safeAreaBar(edge: .bottom) {
                    if model.destination.isReview || model.destination == .duplicates {
                        StagedQueueBar(model: model) { executionRequest = ExecutionRequest(model: model, maximumRisk: $0) }
                    }
                }
                .inspector(isPresented: $model.showsInspector) {
                    inspectorContent.inspectorColumnWidth(min: 280, ideal: Spacing.detailPanelWidth, max: 400)
                }
                .overlay(alignment: .bottom) {
                    // The model computes a scan summary (duration, candidates,
                    // errors) and retires it after 6 seconds; this renders it.
                    if model.showScanSummaryToast, let summary = model.activeScanSummary {
                        Text(summary)
                            .font(.callout)
                            .padding(.horizontal, Spacing.elementNormal)
                            .padding(.vertical, Spacing.elementTight)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.separator))
                            .padding(.bottom, Spacing.elementNormal)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $model.showsScanSetup) { ScanSetupView(model: model) }
        .sheet(isPresented: $model.showsPlanner) { NaturalLanguagePlanView(model: model) }
        .sheet(isPresented: Bindable(model.cleanup).showsScope) { CleanupScopeView(model: model.cleanup) }
        .sheet(item: $executionRequest) { request in ExecutionConfirmView(model: model, request: request) }
        .sheet(
            isPresented: Binding(
                get: { onboardingStep < OnboardingView.doneStep },
                set: { if !$0 { onboardingStep = OnboardingView.doneStep } })
        ) {
            OnboardingView(model: model).interactiveDismissDisabled()
        }
        .onChange(of: model.searchFocusRequest) { isSearchFocused = true }
        .onChange(of: model.destination) {
            model.searchText = ""
            if !model.destination.supportsInspector { model.showsInspector = false }
        }
        .task {
            await model.cleanup.load()
            await model.loadUndoHistory()
        }
    }

    @ViewBuilder
    private var searchableDetail: some View {
        if model.destination.supportsSearch {
            detail
                .searchable(
                    text: $model.searchText, placement: .toolbar,
                    prompt: String(localized: "Search \(model.destination.title)"))
                .searchFocused($isSearchFocused)
        } else {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.destination {
        case .overview: OverviewView(model: model)
        case .systemJunk, .developer, .largeFiles, .leftovers: ActionStackView(model: model)
        case .duplicates: DuplicatesTabView(model: model)
        case .media: MediaWorkspace(model: model.cleanup)
        case .applications: ApplicationsView(model: model)
        case .loginItems: LoginItemsView(model: model)
        case .explorer: FilesView(model: model)
        case .changes: ChangesView(model: model)
        case .history: HistoryView(model: model)
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch model.destination {
        case .explorer: SelectionInspectorView(model: model)
        case .systemJunk, .developer, .largeFiles, .leftovers, .duplicates: WhyPanelView(model: model)
        case .applications: ApplicationDetailsView(model: model)
        case .history: HistoryDetailsView(model: model)
        default:
            ContentUnavailableView(
                String(localized: "No selection"), systemImage: "sidebar.trailing",
                description: Text(String(localized: "Select an item to see its details.")))
        }
    }

    private var isBusy: Bool { model.isScanning || model.isExecuting || model.cleanup.isBusy }

    private var busyText: String? {
        if model.isScanning {
            return model.scanPhaseText.isEmpty ? String(localized: "Scanning…") : model.scanPhaseText
        }
        if model.isExecuting { return String(localized: "Applying changes…") }
        if model.cleanup.isBusy { return model.cleanup.progress.phase }
        return nil
    }

    private func stop() {
        if model.isScanning { model.cancelScan() }
        if model.isExecuting { model.cancelExecution() }
        if model.cleanup.isBusy { model.cleanup.cancel() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.destination == .explorer {
            ToolbarItem {
                Menu {
                    Picker(String(localized: "View"), selection: $model.exploreViewKindRaw) {
                        ForEach(ExploreViewKind.allCases) { kind in Text(kind.title).tag(kind.rawValue) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(String(localized: "View"), systemImage: "rectangle.3.group")
                }
                .help(String(localized: "Choose how to show files"))
            }
        }
        if model.destination.isReview {
            ToolbarItem {
                Picker(String(localized: "Risk"), selection: $model.reviewRiskFilter) {
                    Text(String(localized: "All Risks")).tag(nil as RiskLevel?)
                    ForEach([RiskLevel.low, .medium, .high, .forbidden], id: \.self) { risk in
                        Text(risk.displayName).tag(Optional(risk))
                    }
                }
                .help(String(localized: "Show actions of one risk level"))
            }
            ToolbarItem {
                Button {
                    model.showsPlanner = true
                } label: {
                    Label(String(localized: "Ask Tidybyte"), systemImage: "text.bubble")
                }
                .help(String(localized: "Describe what to clean in your own words"))
                .disabled(model.plan == nil || isBusy)
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            if isBusy {
                Button(role: .cancel, action: stop) {
                    Label(String(localized: "Stop"), systemImage: "stop.fill")
                }
                .help(String(localized: "Stop the current scan or cleanup"))
            } else {
                Button(action: model.scanAll) {
                    Label(String(localized: "Scan"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassProminent)
                .help(String(localized: "Scan for cleanup opportunities"))
            }
        }
        if model.destination.supportsInspector {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showsInspector.toggle()
                } label: {
                    Label(String(localized: "Inspector"), systemImage: "sidebar.trailing")
                }
                .help(String(localized: "Show or hide details"))
            }
        }
    }
}
