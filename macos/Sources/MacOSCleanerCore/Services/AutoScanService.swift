import CoreGraphics
import Foundation
import IOKit.ps
import os
import ServiceManagement

/// Conditions that must hold before unattended maintenance may run: the daily
/// interval has elapsed, the user has been idle for a while, and the Mac is
/// plugged in or reasonably charged. Every input is injectable so tests can
/// exercise the gate without touching real hardware or clocks.
public struct AutoScanConditions: Sendable {
    public let interval: TimeInterval
    public let idleThreshold: TimeInterval
    public let minimumBatteryPercent: Int

    public init(
        interval: TimeInterval = 24 * 3600,
        idleThreshold: TimeInterval = 600,
        minimumBatteryPercent: Int = 50
    ) {
        self.interval = interval
        self.idleThreshold = idleThreshold
        self.minimumBatteryPercent = minimumBatteryPercent
    }

    /// The production gate. Test overrides flow in through `Environment`.
    public static let standard = AutoScanConditions()

    /// True when an automatic run may start. Deliberately fail-closed: when
    /// idle time or the power source cannot be measured, the run is skipped —
    /// unattended work never happens on incomplete information.
    public func isDue(
        lastRun: Date?,
        now: Date = Date(),
        idleSeconds: TimeInterval?,
        onACPower: Bool?,
        batteryPercent: Int?
    ) -> Bool {
        if let lastRun, now.timeIntervalSince(lastRun) < interval {
            return false
        }
        guard let idleSeconds, idleSeconds >= idleThreshold else {
            return false
        }
        if onACPower == true {
            return true
        }
        if let batteryPercent, batteryPercent >= minimumBatteryPercent {
            return true
        }
        return false
    }
}

/// Environment probes feeding `AutoScanConditions.isDue`, with overrides so
/// tests (and debugging) can pin inputs:
/// `TIDYBYTE_IDLE_SECONDS`, `TIDYBYTE_ON_POWER`, `TIDYBYTE_BATTERY_PERCENT`.
public enum AutoScanEnvironment {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Seconds since the last user input on the console session.
    public static func idleSeconds() -> TimeInterval? {
        if let override = environment["TIDYBYTE_IDLE_SECONDS"], let seconds = TimeInterval(override) {
            return seconds
        }
        // kCGAnyInputEventType is not exposed to Swift; ~0 selects "any event".
        guard let anyInput = CGEventType(rawValue: ~UInt32(0)) else {
            return nil
        }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    /// `(onACPower, batteryPercent)`; nil values mean "unknown" and the
    /// conditions gate treats that as not suitable.
    public static func powerStatus() -> (onACPower: Bool, batteryPercent: Int?)? {
        if let override = environment["TIDYBYTE_ON_POWER"] {
            return (override == "1", Int(environment["TIDYBYTE_BATTERY_PERCENT"] ?? ""))
        }
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        var onACPower = false
        var batteryPercent: Int?
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue {
                onACPower = true
            }
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                batteryPercent = Int((Double(current) / Double(maximum) * 100).rounded())
            }
        }
        return (onACPower, batteryPercent)
    }
}

/// Registers the hourly LaunchAgent bundled at
/// `Contents/Library/LaunchAgents/<label>.plist` (copied by Scripts/build-app.sh
/// from Configuration/). The agent launches the app binary with `--autoscan`.
/// Registration is refused when the binary does not live in /Applications or
/// ~/Applications: a translocated or developer build would schedule a
/// temporary binary that vanishes on rebuild.
public enum LaunchAgentInstaller {
    public static let label = AppIdentity.autoscanLabel
    public static let plistName = "\(AppIdentity.autoscanLabel).plist"

    private static var service: SMAppService { .agent(plistName: plistName) }

    static var executablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }

    /// Only installed apps may schedule unattended work. Set
    /// `TIDYBYTE_ALLOW_INSTALL=1` to override (development).
    public static func canInstall(executablePath: String? = nil) -> Bool {
        if ProcessInfo.processInfo.environment["TIDYBYTE_ALLOW_INSTALL"] == "1" {
            return true
        }
        let binary = executablePath ?? Self.executablePath
        let homeApplications = NSString(string: "~/Applications").expandingTildeInPath + "/"
        let applications: Set<String> = ["/Applications/", homeApplications]
        return applications.contains { binary.hasPrefix($0) }
    }

    public static func isInstalled() -> Bool {
        service.status == .enabled
    }

    /// - Throws: when the binary location is not installable or registration fails.
    public static func install() throws {
        let executable = executablePath
        guard canInstall(executablePath: executable) else {
            throw AutoScanError.notInstallable(executable)
        }
        try service.register()
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        logger.info("Registered autoscan agent, status \(service.status.rawValue, privacy: .public)")
    }

    public static func remove() {
        try? service.unregister()
    }

    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "LaunchAgentInstaller")
}

public enum AutoScanError: Error, LocalizedError {
    case notInstallable(String)
    /// Conditions not met (interval, idle, power) — a silent skip, not a failure.
    case conditionsNotMet
    case notAllowed

    public var errorDescription: String? {
        switch self {
        case .notInstallable(let path):
            return String(
                localized: "Automatic maintenance needs the app installed in /Applications (found \(path)).",
                comment: "Autoscan install location error"
            )
        case .conditionsNotMet:
            return String(
                localized: "Skipped: the Mac is in use, not charged enough, or maintenance ran recently.",
                comment: "Autoscan conditions skip"
            )
        case .notAllowed:
            return String(localized: "Automatic maintenance is not enabled.", comment: "Autoscan disabled error")
        }
    }
}

/// Headless `--autoscan` entry point. Runs at most one unattended pass:
/// gate → scan → execute ONLY clone-fold actions (nothing is ever deleted
/// unattended; trashing needs a human in the app) → notify → stamp → exit.
public enum AutoScanRunner {
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "AutoScanRunner")
    public static let lastRunKey = "lastAutoScanDate"
    public static let enabledKey = "autoscanEnabled"

    /// Returns when the run finished (exit code conveys success). Top-level
    /// `--autoscan` handling in the executable exits the process afterwards.
    @discardableResult
    public static func run() async -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else {
            logger.info("Auto-scan disabled; exiting")
            return false
        }
        guard isDue(defaults: defaults) else {
            return false
        }
        do {
            let summary = try await runMaintenancePass()
            defaults.set(Date(), forKey: lastRunKey)
            await NotificationScheduler().scheduleScanCompletedNotification(
                reclaimedBytes: summary.freedBytes
            )
            logger.info("Auto-scan finished: \(summary.foldCount) folds, \(summary.failureCount) failures")
            return true
        } catch {
            logger.error("Auto-scan failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The gate, kept separate so `run` stays readable: interval, idle and
    /// power must all say yes before any unattended work happens.
    private static func isDue(defaults: UserDefaults) -> Bool {
        let idle = AutoScanEnvironment.idleSeconds()
        let power = AutoScanEnvironment.powerStatus()
        let lastRun = defaults.object(forKey: lastRunKey) as? Date
        let due = AutoScanConditions.standard.isDue(
            lastRun: lastRun,
            idleSeconds: idle,
            onACPower: power?.onACPower,
            batteryPercent: power?.batteryPercent
        )
        if !due {
            let idleText = idle.map { String($0) } ?? "?"
            let acText = String(power?.onACPower ?? false)
            logger.info(
                "Auto-scan conditions not met (idle: \(idleText, privacy: .public), AC: \(acText, privacy: .public))"
            )
        }
        return due
    }

    private struct MaintenanceSummary {
        let foldCount: Int
        let failureCount: Int
        let freedBytes: Int64
    }

    /// The unattended safety filter, as its own function so the invariant is
    /// directly testable: headless runs may approve ONLY pending clone-fold
    /// actions — they delete, move and rename nothing — and everything else
    /// waits for a human in the app.
    static func unattendedActionFilter(_ plan: Plan) -> [PlannedAction] {
        plan.actions.filter {
            $0.actionType == .cloneDeduplicate && $0.userDecision == .undecided && $0.executedAt == nil
        }
    }

    /// One unattended pass: scan, then approve and execute ONLY clone-fold
    /// actions. They never delete, move or rename anything, and every fold is
    /// undoable afterwards — trashing always needs a human in the app.
    private static func runMaintenancePass() async throws -> MaintenanceSummary {
        let store: SQLiteStore
        do {
            store = try SQLiteStore()
        } catch {
            // Same bootstrap rule as the app: a temporary database beats
            // refusing to run.
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("tidybyte-autoscan-\(UUID().uuidString).sqlite")
            store = try SQLiteStore(databaseURL: temporary)
        }
        let memory = MemoryEngine(store: store)
        let orchestrator = ScanOrchestrator(store: store, memory: memory)
        let executor = ActionExecutor(store: store)

        // The user's chosen folders, mirroring the app's saved settings.
        let folderPaths = UserDefaults.standard.stringArray(forKey: "selectedFolderPaths") ?? []
        let folders = folderPaths.map { URL(fileURLWithPath: $0) }

        let (outcome, plan) = try await orchestrator.scan(
            mode: folders.isEmpty ? .homeFolder : .selectedFolders,
            selectedFolders: folders,
            providerSettings: ProviderSettings(),
            includeAI: false,
            posture: .conservative,
            duplicateStrategy: .apfsClone
        )
        var filesByID: [String: FileRecord] = [:]
        for record in outcome.files {
            filesByID[record.id] = record
        }

        var foldActions = Self.unattendedActionFilter(plan)
        for index in foldActions.indices {
            foldActions[index].userDecision = .approved
            foldActions[index].status = .approved
        }
        let summary = await executor.execute(actions: foldActions, filesByID: filesByID)
        let freedBytes = summary.logs.reduce(Int64(0)) { total, log in
            total + (Int64(log.afterState["freed_bytes"] ?? "") ?? 0)
        }
        return MaintenanceSummary(
            foldCount: summary.undoRecords.count,
            failureCount: summary.failures.count,
            freedBytes: freedBytes
        )
    }
}
