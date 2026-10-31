import Foundation
@testable import MacOSCleanerCore
import XCTest

/// Unattended maintenance gating: the run conditions fail closed, the
/// LaunchAgent plist has exactly the expected shape, and installation is
/// refused for binaries outside /Applications.
final class AutoScanTests: XCTestCase {
    // MARK: - Conditions

    func testRunIsNotDueWithinInterval() {
        let conditions = AutoScanConditions(interval: 24 * 3600, idleThreshold: 600, minimumBatteryPercent: 50)
        let recent = Date().addingTimeInterval(-3600)
        XCTAssertFalse(conditions.isDue(lastRun: recent, idleSeconds: 3600, onACPower: true, batteryPercent: 100))
    }

    func testRunIsDueWhenIdleAndPowered() {
        let conditions = AutoScanConditions(interval: 24 * 3600, idleThreshold: 600, minimumBatteryPercent: 50)
        let yesterday = Date().addingTimeInterval(-25 * 3600)
        XCTAssertTrue(conditions.isDue(lastRun: yesterday, idleSeconds: 900, onACPower: true, batteryPercent: 20))
        // Battery-only: 50% or better also qualifies.
        XCTAssertTrue(conditions.isDue(lastRun: yesterday, idleSeconds: 900, onACPower: false, batteryPercent: 50))
        XCTAssertTrue(conditions.isDue(lastRun: nil, idleSeconds: 900, onACPower: false, batteryPercent: 80))
    }

    func testRunFailsClosedOnBusyOrUnknownInputs() {
        let conditions = AutoScanConditions(interval: 24 * 3600, idleThreshold: 600, minimumBatteryPercent: 50)
        // User is actively using the Mac.
        XCTAssertFalse(conditions.isDue(lastRun: nil, idleSeconds: 30, onACPower: true, batteryPercent: 100))
        // Idle time unmeasurable — skip, never guess.
        XCTAssertFalse(conditions.isDue(lastRun: nil, idleSeconds: nil, onACPower: true, batteryPercent: 100))
        // Power unmeasurable and battery unknown.
        XCTAssertFalse(conditions.isDue(lastRun: nil, idleSeconds: 900, onACPower: nil, batteryPercent: nil))
        // Below the battery floor without AC.
        XCTAssertFalse(conditions.isDue(lastRun: nil, idleSeconds: 900, onACPower: false, batteryPercent: 49))
    }

    // MARK: - LaunchAgent plist

    func testBundledAgentPlistShape() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Configuration/\(LaunchAgentInstaller.plistName)")
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["Label"] as? String, LaunchAgentInstaller.label)
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/MacOS/Tidybyte")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["Tidybyte", "--autoscan"])
        XCTAssertEqual(plist["AssociatedBundleIdentifiers"] as? [String], [AppIdentity.bundleIdentifier])
        XCTAssertEqual(plist["StartInterval"] as? Int, 3600)
        XCTAssertEqual(plist["ProcessType"] as? String, "Background")
        XCTAssertEqual(plist["LowPriorityIO"] as? Bool, true)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
    }

    // MARK: - Unattended action filter

    func testUnattendedFilterApprovesOnlyCloneFoldActions() {
        // The headless pass must never self-approve destructive work: trash,
        // moves, tags, package-manager commands all wait for a human.
        var clone = PlannedAction(
            id: "clone-1", planID: "plan", actionType: .cloneDeduplicate, targets: ["f1"],
            destination: nil, status: .proposed, risk: .low, confidence: 0.9,
            reason: "fold", userDecision: .undecided, executedAt: nil, findingID: nil)
        var trash = clone
        trash.id = "trash-1"
        trash.actionType = .moveToTrash
        var package = clone
        package.id = "pkg-1"
        package.actionType = .runPackageManagerCleanup
        var executedClone = clone
        executedClone.id = "clone-done"
        executedClone.executedAt = Date()
        var decidedClone = clone
        decidedClone.id = "clone-decided"
        decidedClone.userDecision = .approved

        var plan = Plan.empty(sessionID: "s")
        plan.actions = [clone, trash, package, executedClone, decidedClone]

        let filtered = AutoScanRunner.unattendedActionFilter(plan)
        XCTAssertEqual(filtered.map(\.id), ["clone-1"], "Only the pending clone-fold action may run unattended")
        _ = clone // silence unused-var lint when mutable copies shadow it
    }

    func testInstallLocationGuard() {
        // Installed apps may schedule unattended work.
        XCTAssertTrue(LaunchAgentInstaller.canInstall(
            executablePath: "/Applications/Tidybyte.app/Contents/MacOS/Tidybyte"
        ))
        let home = NSHomeDirectory()
        XCTAssertTrue(LaunchAgentInstaller.canInstall(
            executablePath: home + "/Applications/Tidybyte.app/Contents/MacOS/Tidybyte"
        ))
        // A build-tree or translocated binary must never be scheduled: it
        // would vanish on the next rebuild or app move.
        XCTAssertFalse(LaunchAgentInstaller.canInstall(
            executablePath: "/Users/dev/project/.build/debug/Tidybyte"
        ))
        XCTAssertFalse(LaunchAgentInstaller.canInstall(
            executablePath: "/private/var/folders/x/AppTranslocation/.../Tidybyte"
        ))
    }
}
