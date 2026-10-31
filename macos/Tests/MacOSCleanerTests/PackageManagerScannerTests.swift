import Foundation
@testable import MacOSCleanerCore
import XCTest

final class PackageManagerScannerTests: XCTestCase {
    func testPackageManagerScannerScanReturnsResults() async {
        let scanner = PackageManagerScanner()
        let (findings, recommendations, candidates) = await scanner.scan(sessionID: "test")

        // Should return arrays (may be empty if no package managers are installed)
        XCTAssertNotNil(findings)
        XCTAssertNotNil(recommendations)
        XCTAssertNotNil(candidates)
    }

    func testPackageManagerScannerHandlesMissingTools() async {
        let scanner = PackageManagerScanner()
        // This should handle missing tools gracefully (e.g., Homebrew not installed)
        let (findings, recommendations, candidates) = await scanner.scan(sessionID: "test")

        // Should not crash even if tools are missing
        // Results depend on what's actually installed on the system
        XCTAssertNotNil(findings)
        XCTAssertNotNil(recommendations)
        XCTAssertNotNil(candidates)
    }

    func testPackageCleanupCandidateHasRequiredFields() {
        let candidate = PackageCleanupCandidate(
            id: "test-cleanup",
            title: "Test Cleanup",
            commandPath: URL(fileURLWithPath: "/usr/bin/echo"),
            arguments: ["test"],
            dryRunOutput: "Would remove test",
            risk: .low,
            category: .packageManagerCleanup
        )

        XCTAssertEqual(candidate.id, "test-cleanup")
        XCTAssertEqual(candidate.title, "Test Cleanup")
        XCTAssertEqual(candidate.risk, .low)
        XCTAssertEqual(candidate.category, .packageManagerCleanup)
    }

    func testPackageCleanupCandidateRiskLevels() {
        let lowRisk = PackageCleanupCandidate(
            id: "low", title: "Low", commandPath: URL(fileURLWithPath: "/usr/bin/echo"),
            arguments: [], dryRunOutput: "", risk: .low, category: .packageManagerCleanup
        )
        let highRisk = PackageCleanupCandidate(
            id: "high", title: "High", commandPath: URL(fileURLWithPath: "/usr/bin/echo"),
            arguments: [], dryRunOutput: "", risk: .high, category: .packageManagerCleanup
        )

        XCTAssertTrue(lowRisk.risk < highRisk.risk)
    }
}
