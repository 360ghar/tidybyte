import Foundation
import MacOSCleanerCore

extension ActionType {
    var displayName: String {
        switch self {
        case .moveToTrash: String(localized: "Move to Trash")
        case .restore: String(localized: "Restore")
        case .move: String(localized: "Move")
        case .rename: String(localized: "Rename")
        case .tag: String(localized: "Tag")
        case .offloadLocalCopy: String(localized: "Offload Local Copy")
        case .createAlias: String(localized: "Create Alias")
        case .createSymlink: String(localized: "Create Symlink")
        case .archive: String(localized: "Archive")
        case .runProviderCleanup: String(localized: "Run Provider Cleanup")
        case .runPackageManagerCleanup: String(localized: "Run Package Cleanup")
        case .inspectOnly: String(localized: "Inspect Only")
        case .cloneDeduplicate: String(localized: "Fold into APFS Clone")
        case .unfoldClone: String(localized: "Unfold Clone")
        }
    }
}

// NOTE: `FindingCategory.displayName` lives in MacOSCleanerCore (public) so
// the report generator can use it; the UI resolves to that implementation.

extension PlannedActionStatus {
    var displayName: String {
        switch self {
        case .proposed: String(localized: "Proposed")
        case .approved: String(localized: "Approved")
        case .rejected: String(localized: "Rejected")
        case .executing: String(localized: "Executing")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .skipped: String(localized: "Skipped")
        }
    }
}

extension RiskLevel {
    var displayName: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .forbidden: String(localized: "Forbidden")
        }
    }
}

extension UndoStatus {
    var displayName: String {
        switch self {
        case .pending: String(localized: "In Progress")
        case .available: String(localized: "Available")
        case .restored: String(localized: "Restored")
        case .expired: String(localized: "Expired")
        case .notUndoable: String(localized: "Not Undoable")
        case .partiallyUndoable: String(localized: "Partially Undoable")
        case .reinstallable: String(localized: "Reinstallable")
        case .failed: String(localized: "Failed")
        }
    }
}

extension ScanMode {
    var displayName: String {
        switch self {
        case .selectedFolders: String(localized: "Selected Folders")
        case .homeFolder: String(localized: "Home Folder")
        case .developerCleanup: String(localized: "Developer Cleanup")
        case .deepSystem: String(localized: "Deep System")
        case .userEssentials: String(localized: "User Essentials")
        case .finderMetadata: String(localized: "Finder Metadata")
        case .macOSSystemCaches: String(localized: "macOS System Caches")
        case .sandboxedAppCaches: String(localized: "Sandboxed App Caches")
        case .browsers: String(localized: "Browsers")
        case .cloudStorage: String(localized: "Cloud Storage")
        case .officeApps: String(localized: "Office Applications")
        case .developerTools: String(localized: "Developer Tools")
        case .devApplications: String(localized: "Development Applications")
        case .vmTools: String(localized: "Virtual Machine Tools")
        case .applicationSupport: String(localized: "Application Support")
        case .uninstalledAppData: String(localized: "Uninstalled App Data")
        case .appleSiliconUpdates: String(localized: "Apple Silicon Updates")
        case .iosBackups: String(localized: "iOS Device Backups")
        case .timeMachineBackups: String(localized: "Time Machine Backups")
        case .largeFiles: String(localized: "Large Files")
        }
    }
}

extension RiskFlag {
    var displayName: String {
        switch self {
        case .sipProtectedSystemPath: String(localized: "SIP-protected system path")
        case .protectedDirectory: String(localized: "Protected directory")
        case .protectedFile: String(localized: "Protected file")
        case .secretOrCertificate: String(localized: "Secret or certificate")
        case .projectManifest: String(localized: "Project manifest")
        case .sourceOrConfig: String(localized: "Source or config")
        case .cloudSyncedLocalPath: String(localized: "Cloud-synced path")
        case .codingAgentMemoryOrConfig: String(localized: "Coding agent memory or config")
        case .insideTrash: String(localized: "Already in Trash")
        case .reviewOnly: String(localized: "Review only")
        }
    }
}

extension FileKind {
    var displayName: String {
        switch self {
        case .regularFile: String(localized: "File")
        case .directory: String(localized: "Folder")
        case .symlink: String(localized: "Symbolic Link")
        case .package: String(localized: "Package")
        case .other: String(localized: "Other")
        }
    }
}
