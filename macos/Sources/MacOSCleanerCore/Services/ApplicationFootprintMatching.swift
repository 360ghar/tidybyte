import Foundation
import Security

/// Matching rules for the uninstaller: names, launch jobs, and signatures,
/// plus the staging helpers that build review groups.
extension ApplicationFootprintService {
    /// Possible matches and admin-only items: one review-only finding.
    func reviewOnlyGroup(_ reviewOnly: [ApplicationFootprintItem], app: InstalledApplication, sessionID: String)
        -> StagedUninstall? {
        var files: [FileRecord] = []
        var findings: [Finding] = []
        var recommendations: [Recommendation] = []
        let reviewRecords = reviewOnly.compactMap {
            makeRecord(url: $0.url, sessionID: sessionID, sizeBytes: max(0, $0.sizeBytes))
        }
        if !reviewRecords.isEmpty {
            let findingID = UUID().uuidString
            let bytes = reviewRecords.reduce(Int64(0)) { $0 + $1.sizeBytes }
            findings.append(Finding(
                id: findingID, scanSessionID: sessionID, category: .appLeftover, severity: .high, confidence: 0.5,
                bytesReclaimable: bytes,
                summary: String(
                    localized: "Review only: \(reviewRecords.count) more items that may belong to \(app.name)",
                    comment: "Uninstall review-only finding"),
                evidence: ["bundle_id": app.bundleIdentifier ?? "", "bytes": String(bytes)],
                targetFileIDs: reviewRecords.map(\.id)))
            recommendations.append(Recommendation(
                id: UUID().uuidString, findingID: findingID, actionType: .inspectOnly,
                targetFileIDs: reviewRecords.map(\.id), confidence: 0.5, risk: .high,
                reason: String(
                    localized: """
                        These items match only by developer team or need administrator rights. \
                        Check them in Finder before you remove them.
                        """, comment: "Uninstall review-only reason"),
                expectedBytesReclaimed: 0, requiresConfirmation: true, llmTraceID: nil,
                policyTraceID: "app_uninstall_review_only"))
            files.append(contentsOf: reviewRecords)
        }
        return files.isEmpty ? nil : StagedUninstall(files: files, findings: findings, recommendations: recommendations)
    }

    /// Stages items outside an app footprint (a launch agent plist) as one
    /// Trash-first finding that flows through review like any other.
    public func stagedRemoval(
        of urls: [URL], summary: String, reason: String, sessionID: String
    ) -> StagedUninstall {
        let records = urls.compactMap { url in
            makeRecord(url: url, sessionID: sessionID, sizeBytes: Self.allocatedSize(of: url, fileManager: fileManager))
        }.filter(isAllowed)
        guard !records.isEmpty else { return StagedUninstall(files: [], findings: [], recommendations: []) }
        let bytes = records.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let findingID = UUID().uuidString
        return StagedUninstall(
            files: records,
            findings: [Finding(
                id: findingID, scanSessionID: sessionID, category: .appLeftover, severity: .medium, confidence: 0.9,
                bytesReclaimable: bytes, summary: summary, evidence: ["paths": urls.map(\.path).joined(separator: ", ")],
                targetFileIDs: records.map(\.id))],
            recommendations: [Recommendation(
                id: UUID().uuidString, findingID: findingID, actionType: .moveToTrash, targetFileIDs: records.map(\.id),
                confidence: 0.9, risk: .medium, reason: reason, expectedBytesReclaimed: bytes,
                requiresConfirmation: true, llmTraceID: nil, policyTraceID: "launch_item_removal")])
    }

    /// Bundle IDs (lowercased) and locations of the other installed apps.
    func otherApps(than app: InstalledApplication, home: URL) -> [(id: String, url: URL)] {
        let own = app.bundleIdentifier?.lowercased()
        return (installedBundlesOverride ?? InstalledAppIndex.standardBundles(home: home)).compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier?.lowercased(), id != own,
                url.standardizedFileURL != app.bundleURL.standardizedFileURL else { return nil }
            return (id, url)
        }
    }

    /// App groups from the code signature are certain unless another installed
    /// app of the same vendor declares the group too; other containers of the
    /// same developer team are only possible matches.
    func groupContainers(
        for app: InstalledApplication, in directory: URL, others: [(id: String, url: URL)]
    ) -> [ApplicationFootprintItem] {
        let signing = Self.signingInfo(for: app.bundleURL)
        let groups = Set(signing.appGroups.map { $0.lowercased() })
        // Only same-vendor apps are read: a signature check costs a few milliseconds each.
        let vendor = app.bundleIdentifier.map { Self.vendor(of: $0.lowercased()) }
        let sharedGroups = groups.isEmpty ? [] : Set(others.filter { Self.vendor(of: $0.id) == vendor }
            .flatMap { Self.signingInfo(for: $0.url).appGroups.map { $0.lowercased() } })
        return children(of: directory).compactMap { child in
            let name = child.lastPathComponent.lowercased()
            if groups.contains(name) {
                return sharedGroups.contains(name)
                    ? item(child, .groupContainers, (.possible, String(localized: "App group shared with another installed app")))
                    : item(child, .groupContainers, (.certain, String(localized: "Shared app group of this app")))
            }
            if let match = Self.footprintMatch(entryName: child.lastPathComponent, app: app) {
                guard !Self.belongsToOtherApp(child.lastPathComponent, app: app, others: others.map(\.id)) else { return nil }
                return item(child, .groupContainers, match)
            }
            if let team = signing.teamID?.lowercased(), name.hasPrefix(team + ".") {
                return item(
                    child, .groupContainers, (.possible, String(localized: "Belongs to the same developer team")))
            }
            return nil
        }
    }

    /// Conservative footprint match for a direct child entry name. Never
    /// substring-matches: a folder merely containing the app's name belongs to
    /// someone else until proven otherwise.
    public static func matchesFootprint(entryName: String, app: InstalledApplication) -> Bool {
        footprintMatch(entryName: entryName, app: app) != nil
    }

    /// Exact bundle-ID names are certain; bundle-ID prefixes and the exact
    /// normalized app name are likely.
    static func footprintMatch(entryName: String, app: InstalledApplication) -> (FootprintConfidence, String)? {
        let lowered = entryName.lowercased()
        if let bundleID = app.bundleIdentifier?.lowercased(), !bundleID.isEmpty {
            let exact = ["", ".plist", ".savedstate", ".binarycookies"].map { bundleID + $0 }
            if exact.contains(lowered) {
                return (.certain, String(localized: "Named after the app's bundle ID"))
            }
            if lowered.hasPrefix(bundleID + ".") || lowered.hasPrefix(bundleID + "-") {
                return (.likely, String(localized: "Starts with the app's bundle ID"))
            }
        }
        let stripped = entryName.hasSuffix(".plist")
            ? String(entryName.dropLast(".plist".count))
            : (entryName as NSString).deletingPathExtension
        guard !Self.normalized(app.name).isEmpty, Self.normalized(stripped) == Self.normalized(app.name) else {
            return nil
        }
        return (.likely, String(localized: "Named after the app"))
    }

    /// Lowercase with spaces, dashes, and underscores removed, so "Google
    /// Chrome" matches "GoogleChrome" but never merely contains it.
    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0 != " " && $0 != "-" && $0 != "_" }
    }

    static func launchJob(_ job: [String: Any], belongsTo app: InstalledApplication) -> Bool {
        if let id = app.bundleIdentifier?.lowercased(), !id.isEmpty {
            let label = (job["Label"] as? String)?.lowercased() ?? ""
            if label == id || label.hasPrefix(id + ".") { return true }
            let associated = (job["AssociatedBundleIdentifiers"] as? [String])
                ?? (job["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
            if associated.contains(where: { $0.lowercased() == id }) { return true }
        }
        guard let program = program(of: job) else { return false }
        return program.hasPrefix(app.bundleURL.standardizedFileURL.path + "/")
    }

    /// True when another installed app owns the entry by a longer bundle ID:
    /// `com.google.chrome.canary` belongs to Chrome Canary, not Chrome.
    static func belongsToOtherApp(_ entryName: String, app: InstalledApplication, others: [String]) -> Bool {
        let name = entryName.lowercased()
        let own = app.bundleIdentifier?.lowercased() ?? ""
        return others.contains { other in
            other.count > own.count && (name == other || name.hasPrefix(other + ".") || name.hasPrefix(other + "-"))
        }
    }

    /// A job another installed app also names (label or associated bundle IDs)
    /// keeps running for that app, so it is never a sure match.
    static func launchJob(_ job: [String: Any], app: InstalledApplication, isSharedWith others: [String]) -> Bool {
        let label = (job["Label"] as? String) ?? ""
        let associated = ((job["AssociatedBundleIdentifiers"] as? [String])
            ?? (job["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []).map { $0.lowercased() }
        return others.contains { associated.contains($0) } || belongsToOtherApp(label, app: app, others: others)
    }

    /// First two labels: `com.microsoft` for `com.microsoft.word`.
    static func vendor(of bundleID: String) -> String {
        bundleID.split(separator: ".").prefix(2).joined(separator: ".")
    }

    static func program(of job: [String: Any]) -> String? {
        (job["Program"] as? String) ?? (job["ProgramArguments"] as? [String])?.first
    }

    static func isUUID(_ name: String) -> Bool { UUID(uuidString: name) != nil }

    /// Team ID and app groups from the bundle's code signature.
    static func signingInfo(for bundleURL: URL) -> (teamID: String?, appGroups: [String]) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode else { return (nil, []) }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
            let info = information as? [String: Any] else { return (nil, []) }
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (
            info[kSecCodeInfoTeamIdentifier as String] as? String,
            entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        )
    }
}
