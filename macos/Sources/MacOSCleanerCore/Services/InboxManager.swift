import Foundation

public actor InboxManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func defaultInboxURL() -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(AppIdentity.inboxFolderName, isDirectory: true)
    }

    public func ensureInboxExists(at url: URL? = nil) throws -> URL {
        let resolved = url ?? defaultInboxURL()
        try fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        return resolved
    }
}
