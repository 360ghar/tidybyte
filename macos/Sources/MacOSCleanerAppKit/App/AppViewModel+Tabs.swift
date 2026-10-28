import Foundation
import MacOSCleanerCore

// MARK: - Top-level tabs (Agent 6)

/// Tab, uninstall-staging, and snapshot-diff behavior for AppViewModel.
/// Stored tab/snapshot state lives on the main type (the `@Observable` macro
/// cannot observe extension stored properties); everything here is behavior.
/// Uninstall staging never touches the filesystem: it builds Trash-first
/// recommendations that flow through user approval, SafetyAuditor, and
/// ActionExecutor like any other plan action.
@MainActor
extension AppViewModel {

    var duplicateFindings: [Finding] {
        (outcome?.findings ?? []).filter { $0.category == .duplicate }
    }

    func loadInstalledApplications() async {
        guard !isLoadingApplications else { return }
        isLoadingApplications = true
        defer { isLoadingApplications = false }
        let service = ApplicationFootprintService()
        installedApplications = await service.enumerateInstalledApplications()
        if installedApplications.isEmpty {
            statusMessage = String(localized: "No applications found in /Applications or ~/Applications.")
        }
    }

    func loadFootprint(for app: InstalledApplication) async {
        guard footprintItemsByAppID[app.id] == nil else { return }
        let service = ApplicationFootprintService()
        let items = await service.footprintItems(for: app)
        footprintItemsByAppID[app.id] = items
    }

    /// Stages a complete uninstall for an app into the review plan as
    /// Trash-first recommendations. The caller must already hold user approval
    /// intent (button + confirmation dialog); staged actions still pass
    /// SafetyAuditor and ActionExecutor before anything touches the disk.
    func stageUninstall(for app: InstalledApplication) async {
        guard !isScanning, !isExecuting, !isPlanning, !stagedUninstallAppIDs.contains(app.id) else { return }
        let staged = await stage(name: app.name) { service, sessionID in
            try await service.stagedUninstall(for: app, sessionID: sessionID)
        }
        if staged { stagedUninstallAppIDs.insert(app.id) }
    }

    /// Adds a user launch agent's plist to Leftovers. It stops at next login.
    /// - Returns: true when the item is now in Leftovers.
    @discardableResult
    func stageRemoval(of item: LaunchItem) async -> Bool {
        guard item.canRemove, !isScanning, !isExecuting, !isPlanning else { return false }
        return await stage(name: item.label) { service, sessionID in
            await service.stagedRemoval(
                of: [item.url],
                summary: String(localized: "Login item \(item.label)", comment: "Launch item removal finding"),
                reason: String(
                    localized: "Moves the launch agent to Trash. It stops running at your next login. Restore it from History.",
                    comment: "Launch item removal reason"),
                sessionID: sessionID)
        }
    }

    /// Merges staged files, findings, and actions into the review plan. Without
    /// a scan it starts an empty one, so staging never depends on scanning.
    @discardableResult
    private func stage(
        name: String,
        _ build: (ApplicationFootprintService, String) async throws -> StagedUninstall
    ) async -> Bool {
        if outcome == nil || plan == nil {
            let session = ScanSession(
                scanType: .selectedFolders, rootURLs: [], permissionsSnapshot: "staged", status: .completed)
            try? await store.saveScanSession(session)
            outcome = .standalone(session: session)
            plan = .empty(sessionID: session.id)
        }
        guard let scan = outcome, var currentPlan = plan else { return false }
        let signature = executionPlanSignature
        do {
            let staged = try await build(ApplicationFootprintService(), scan.session.id)
            guard !Task.isCancelled, !isScanning, !isExecuting, !isPlanning,
                signature == executionPlanSignature else { return false }
            guard !staged.files.isEmpty else {
                errorMessage = String(localized: "Nothing removable found for \(name). It may be missing or protected.")
                return false
            }
            var mergedFilesByID = filesByID
            for file in staged.files { mergedFilesByID[file.id] = file }
            let appended = await planner.appendRecommendations(
                staged.recommendations, to: currentPlan, filesByID: mergedFilesByID)
            guard !Task.isCancelled, !isScanning, !isExecuting, !isPlanning,
                signature == executionPlanSignature else { return false }
            guard !appended.isEmpty else {
                statusMessage = String(localized: "\(name) is already in Leftovers.")
                return false
            }
            // Commit files and actions together only while the plan is current.
            var updatedScan = scan
            updatedScan.files.append(contentsOf: staged.files)
            updatedScan.findings.append(contentsOf: staged.findings)
            currentPlan.actions.append(contentsOf: appended)
            currentPlan.originalActions?.append(contentsOf: appended)
            refreshPlanEstimates(plan: &currentPlan, filesByID: mergedFilesByID)
            outcome = updatedScan
            plan = currentPlan
            selectedActionID = appended.last?.id
            statusMessage = String(localized: "Added \(name) to Leftovers for review.")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Starts or stops watching /Applications for removed apps.
    func setRemovalWatching(_ enabled: Bool) {
        guard DistributionChannel.supportsAdvanced, enabled else {
            removalWatcher?.stop()
            removalWatcher = nil
            return
        }
        guard removalWatcher == nil else { return }
        let watcher = ApplicationRemovalWatcher { [weak self] app in
            guard let self else { return }
            removedApplications[app.id] = app
            Task { await self.notifyRemoval(of: app) }
        }
        watcher.start()
        removalWatcher = watcher
    }

    private func notifyRemoval(of app: InstalledApplication) async {
        let service = ApplicationFootprintService()
        guard await service.footprintItems(for: app).contains(where: { $0.confidence == .certain }) else { return }
        await notifications.scheduleLeftoversNotification(
            appName: app.name, bundleID: app.id, bundlePath: app.bundleURL.path)
    }

    /// Notification tap: stage what the removed app left behind and show it.
    /// Works after a relaunch: the notification carries the app's name and path.
    func reviewLeftovers(ofRemovedApp bundleID: String, name: String, bundlePath: String) async {
        let app = removedApplications[bundleID] ?? InstalledApplication(
            id: bundleID, name: name, bundleURL: URL(fileURLWithPath: bundlePath),
            bundleIdentifier: bundleID, bundleSizeBytes: 0)
        await stageUninstall(for: app)
        if let id = selectedActionID { showReviewAction(id: id) } else { destination = .leftovers }
    }

    func refreshPlanEstimates(plan: inout Plan, filesByID: [String: FileRecord]? = nil) {
        let resolved = filesByID ?? self.filesByID
        plan.estimatedReclaimableBytes = Set(plan.actions.flatMap(\.targets))
            .compactMap { resolved[$0].map { ReclaimableBytes.size(of: $0) } }
            .reduce(Int64(0), +)
        plan.estimatedFilesAffected = Set(plan.actions.flatMap(\.targets)).count
        plan.riskBreakdown = Dictionary(grouping: plan.actions, by: \.risk).mapValues(\.count)
    }

    // MARK: - Snapshots tab

    func loadSnapshotHistory() async {
        guard !isLoadingSnapshots else { return }
        isLoadingSnapshots = true
        defer { isLoadingSnapshots = false }
        do {
            storageSnapshots = try await store.recentSnapshots(limit: 30)
            if olderSnapshotID == nil || newerSnapshotID == nil {
                olderSnapshotID = storageSnapshots.dropFirst().first?.id
                newerSnapshotID = storageSnapshots.first?.id
            }
            await refreshSnapshotDiff()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSnapshotDiff() async {
        snapshotDiffError = nil
        guard let olderID = olderSnapshotID, let newerID = newerSnapshotID else {
            snapshotDiff = nil
            return
        }
        do {
            let service = SnapshotService(store: store)
            snapshotDiff = try await service.diffSnapshot(olderID: olderID, newerID: newerID)
        } catch {
            snapshotDiff = nil
            snapshotDiffError = error.localizedDescription
        }
    }
}
