import Darwin
import Foundation

public enum TrashBinError: Error, LocalizedError, Sendable {
    case notATrashFolder(URL)
    case unreadable
    case removalFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notATrashFolder(let url):
            String(localized: "\(url.path) is not a Trash folder.", comment: "Empty Trash refusal")
        case .unreadable:
            String(
                localized: "Tidybyte needs Full Disk Access to empty the Trash. You can also empty it in Finder.",
                comment: "Empty Trash without access")
        case .removalFailed(let name):
            String(
                localized: "Could not remove “\(name)” from the Trash.",
                comment: "Empty Trash item removal failure")
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
    ///
    /// The folder is opened once and every deletion afterwards works relative
    /// to that open descriptor (`unlinkat`), never by re-resolving the path:
    /// a symlink swapped in at the validated path mid-operation cannot
    /// redirect this irreversible removal.
    /// - Returns: the number of items removed.
    @discardableResult
    public static func empty(trashURL: URL = userTrash) throws -> Int {
        let values = try? trashURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard trashURL.lastPathComponent == ".Trash", values?.isSymbolicLink == false, values?.isDirectory == true else {
            throw TrashBinError.notATrashFolder(trashURL)
        }
        let fd = open(trashURL.path, O_RDONLY | O_NOFOLLOW | O_DIRECTORY)
        guard fd >= 0 else { throw TrashBinError.unreadable }
        // fdopendir adopts the descriptor on success; it stays open (for the
        // unlinkat calls) until closedir and must be closed here on failure.
        guard let dir = fdopendir(fd) else {
            close(fd)
            throw TrashBinError.unreadable
        }
        defer { closedir(dir) }
        var stats = stat()
        guard fstat(fd, &stats) == 0, (stats.st_mode & S_IFMT) == S_IFDIR else {
            throw TrashBinError.notATrashFolder(trashURL)
        }
        let dirFD = dirfd(dir)
        // Collect first, then delete: mutating the directory while readdir
        // iterates it is undefined behavior.
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = entryName(entry)
            if name != "." && name != ".." { names.append(name) }
        }
        for name in names {
            try removeEntry(named: name, directoryFD: dirFD)
        }
        return names.count
    }

    /// Deletes one entry relative to an open directory descriptor, recursing
    /// into subdirectories through their own descriptors. Symlinks are
    /// unlinked, never followed.
    private static func removeEntry(named name: String, directoryFD: Int32) throws {
        try name.withCString { cName in
            var stats = stat()
            guard fstatat(directoryFD, cName, &stats, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw TrashBinError.removalFailed(name)
            }
            if (stats.st_mode & S_IFMT) == S_IFDIR {
                let childFD = openat(directoryFD, cName, O_RDONLY | O_NOFOLLOW | O_DIRECTORY)
                guard childFD >= 0 else { throw TrashBinError.removalFailed(name) }
                guard let childDir = fdopendir(childFD) else {
                    close(childFD)
                    throw TrashBinError.removalFailed(name)
                }
                let childDirFD = dirfd(childDir)
                var childNames: [String] = []
                while let entry = readdir(childDir) {
                    let childName = entryName(entry)
                    if childName != "." && childName != ".." { childNames.append(childName) }
                }
                // childDirFD is only valid until closedir, so recurse first.
                for childName in childNames {
                    try removeEntry(named: childName, directoryFD: childDirFD)
                }
                closedir(childDir)
                guard unlinkat(directoryFD, cName, AT_REMOVEDIR) == 0 else {
                    throw TrashBinError.removalFailed(name)
                }
            } else {
                guard unlinkat(directoryFD, cName, 0) == 0 else {
                    throw TrashBinError.removalFailed(name)
                }
            }
        }
    }

    private static func entryName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafeBytes(of: entry.pointee.d_name) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
