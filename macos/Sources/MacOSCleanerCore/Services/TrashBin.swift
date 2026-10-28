import Foundation

public enum TrashBinError: Error, LocalizedError, Sendable {
    case notATrashFolder(URL)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .notATrashFolder(let url):
            String(localized: "\(url.path) is not a Trash folder.", comment: "Empty Trash refusal")
        case .unreadable:
            String(
                localized: "Tidybyte needs Full Disk Access to empty the Trash. You can also empty it in Finder.",
                comment: "Empty Trash without access")
        }
    }
}

/// Permanently erases the contents of a Trash folder. This is the one
/// irreversible command in the app; callers confirm it explicitly first.
public enum TrashBin {
    public static var userTrash: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    }

    /// Removes every item inside `trashURL`, never the folder itself.
    /// Refuses anything that is not a real folder named `.Trash`.
    /// - Returns: the number of items removed.
    @discardableResult
    public static func empty(trashURL: URL = userTrash) throws -> Int {
        let values = try? trashURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard trashURL.lastPathComponent == ".Trash", values?.isSymbolicLink == false, values?.isDirectory == true else {
            throw TrashBinError.notATrashFolder(trashURL)
        }
        guard let items = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
        else { throw TrashBinError.unreadable }
        for item in items { try FileManager.default.removeItem(at: item) }
        return items.count
    }
}
