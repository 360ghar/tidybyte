import Darwin
import Foundation
import os

/// Outcome of a single fold attempt. Every non-success case carries a reason
/// suitable for surfacing in the Why Panel and execution logs.
public enum FoldOutcome: Sendable, Equatable {
    /// The duplicate now shares the keeper's storage blocks. `freedBytes` is
    /// the allocated size the duplicate stopped paying for (st_blocks × 512).
    case folded(freedBytes: Int64)
    /// The two paths already point at the same storage (hard link, pre-existing
    /// clone): nothing to do, and not an error.
    case alreadyShared
    /// A guard declined the fold; the file is untouched.
    case skipped(String)
    /// The file changed since the scan (contents, stat) — the stale plan lost
    /// the race, so the fold was aborted with the file untouched.
    case changed(String)
    /// An operation failed mid-fold (clone, rename, metadata). The file may
    /// still be its original self or the fold may have completed partially —
    /// always re-verify before retrying.
    case failed(String)
}

/// APFS clone-based deduplication. Stateless helpers around `clonefile(2)` and
/// `copyfile(3)` that fold two byte-identical files into one shared storage
/// (copy-on-write clone) without deleting, moving or renaming anything the
/// user can see, and unfold a folded clone back into a real private copy.
///
/// The fold chain follows a strict safety order: both files must be ordinary,
/// owned by the current user, quiet, closed and still byte-identical at swap
/// time; the clone is built in the duplicate's own directory (so it can never
/// cross a volume), given the duplicate's exact metadata, re-verified, and
/// only then swapped in with an atomic `rename(2)`.
public enum APFSCloneService {
    static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "APFSCloneService")

    /// Files modified within this window are considered in active use and are
    /// never folded. Configurable for tests; production code uses the default.
    public static let defaultQuietPeriod: TimeInterval = 300

    /// Prefix of the hidden temp files a fold/unfold creates in the target's
    /// own directory.
    static let tempFilePrefix = ".apfsclone-"

    /// xattrs the system manages and nothing else may rewrite. Clones inherit
    /// the cloning process's `com.apple.provenance`, which cannot be cleared —
    /// excluding it here keeps metadata sync from failing outright.
    private static let systemManagedXattrs: Set<String> = ["com.apple.provenance"]

    /// File attributes captured in a single `lstat` call.
    struct FileStat: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        let nlink: UInt64
        let uid: UInt32
        let gid: UInt32
        let mode: UInt32
        let flags: UInt32
        let size: Int64
        let allocatedBytes: Int64
        let mtime: TimeInterval
        let birthtime: TimeInterval
    }

    /// Snapshot of the user-visible metadata a fold must preserve exactly.
    struct MetadataSnapshot: Equatable, Sendable {
        let mode: UInt32
        let uid: UInt32
        let gid: UInt32
        let size: Int64
        let mtime: TimeInterval
        let birthtime: TimeInterval
        let xattrs: [String: Data]
    }

    /// User-visible flags that make a file untouchable: compressed (its data
    /// is not plain content), immutable, append-only, system-restricted,
    /// change-tracked, or a dataless cloud placeholder.
    private static let untouchableFlags: UInt32 =
        UInt32(UF_COMPRESSED) | UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)
        | UInt32(UF_APPEND) | UInt32(SF_APPEND) | UInt32(SF_RESTRICTED)
        | UInt32(UF_TRACKED) | UInt32(SF_DATALESS)

    // MARK: - Fold

    /// Folds `duplicate` onto `keeper`: after a successful fold both paths
    /// exist unchanged for the user, but the duplicate shares the keeper's
    /// storage blocks. Every failure mode leaves the duplicate byte-for-byte
    /// as it was.
    /// - Parameters:
    ///   - duplicate: the copy that will stop paying for its own storage.
    ///   - keeper: the copy whose blocks will be shared.
    ///   - quietPeriod: minimum age of the last modification for the fold to
    ///     proceed. Pass 0 in tests that create fresh fixtures.
    public static func fold(
        duplicate: URL,
        keeper: URL,
        quietPeriod: TimeInterval = APFSCloneService.defaultQuietPeriod
    ) -> FoldOutcome {
        let duplicatePath = duplicate.path
        let keeperPath = keeper.path
        guard let before = lstatInfo(duplicatePath), let keeperStat = lstatInfo(keeperPath) else {
            return .failed("file is missing")
        }
        if let blocked = foldPreflight(
            before: before, keeperStat: keeperStat,
            duplicatePath: duplicatePath, keeperPath: keeperPath, quietPeriod: quietPeriod
        ) {
            return blocked
        }
        return swapInClone(duplicatePath: duplicatePath, keeperPath: keeperPath, before: before)
    }

    /// The guard chain that declines unsafe folds. Returns the outcome to
    /// report, or nil when the swap may proceed.
    private static func foldPreflight(
        before: FileStat,
        keeperStat: FileStat,
        duplicatePath: String,
        keeperPath: String,
        quietPeriod: TimeInterval
    ) -> FoldOutcome? {
        // A clone can only share blocks within one APFS volume.
        guard before.device == keeperStat.device else {
            return .skipped("different volume")
        }
        guard before.inode != keeperStat.inode else {
            return .alreadyShared
        }
        // Hard links, foreign-owned files and special-flag files are left
        // alone: folding them either buys nothing or risks breaking something
        // outside this file's own identity.
        guard before.nlink == 1, keeperStat.nlink == 1,
              before.uid == getuid(), keeperStat.uid == getuid(),
              before.flags & untouchableFlags == 0,
              keeperStat.flags & untouchableFlags == 0 else {
            return .skipped("protected file")
        }
        guard Date().timeIntervalSince1970 - before.mtime >= quietPeriod else {
            return .skipped("modified in the last few minutes")
        }
        guard !isOpenForWriting(duplicatePath), !isOpenForWriting(keeperPath) else {
            return .skipped("open in another app")
        }
        // The scan's hash is stale by definition; prove identity live at swap time.
        guard contentsEqual(duplicatePath, keeperPath) else {
            return .changed("contents differ")
        }
        return nil
    }

    /// Builds the clone in the duplicate's own directory, dresses it in the
    /// duplicate's exact metadata, re-verifies everything, and swaps it in
    /// with one atomic rename.
    private static func swapInClone(duplicatePath: String, keeperPath: String, before: FileStat) -> FoldOutcome {
        let directory = (duplicatePath as NSString).deletingLastPathComponent
        let temp = directory + "/" + tempFilePrefix + String(UUID().uuidString.prefix(8))
        var keepTemp = false
        defer {
            if !keepTemp {
                unlink(temp)
            }
        }

        // CLONE_NOFOLLOW: never clone through a symlink swapped in mid-fold.
        // CLONE_NOOWNERCOPY: ownership comes from our explicit metadata copy.
        guard clonefile(keeperPath, temp, UInt32(CLONE_NOFOLLOW | CLONE_NOOWNERCOPY)) == 0 else {
            let reason = String(cString: strerror(errno))
            logger.error("clonefile failed for \(duplicatePath, privacy: .public): \(reason, privacy: .public)")
            return .failed("clone failed: \(reason)")
        }
        // The user-visible file keeps ITS metadata, not the keeper's.
        guard copyMetadata(from: duplicatePath, to: temp) else {
            return .failed("could not copy metadata")
        }
        guard let cloned = metadataSnapshot(temp), let original = metadataSnapshot(duplicatePath),
              cloned == original else {
            return .failed("metadata could not be kept exactly")
        }
        guard contentsEqual(temp, duplicatePath) else {
            return .changed("contents differ")
        }
        guard lstatInfo(duplicatePath) == before else {
            return .changed("file changed during fold")
        }
        guard rename(temp, duplicatePath) == 0 else {
            let reason = String(cString: strerror(errno))
            logger.error("rename failed for \(duplicatePath, privacy: .public): \(reason, privacy: .public)")
            return .failed("rename failed: \(reason)")
        }
        keepTemp = true
        logger.info("Folded \(duplicatePath, privacy: .public) onto \(keeperPath, privacy: .public)")
        return .folded(freedBytes: before.allocatedBytes)
    }

    // MARK: - Unfold

    /// Reverses a fold: replaces the shared clone at `path` with a real,
    /// private copy of the same bytes. Returns false (touching nothing) when
    /// identity, free space or any filesystem step fails, so the caller can
    /// leave the undo record available for a retry.
    public static func unfold(
        path: URL,
        expectedDevice: UInt64? = nil,
        expectedInode: UInt64? = nil,
        freeSpaceReserve: Int64 = 200_000_000
    ) -> Bool {
        let target = path.path
        guard let before = lstatInfo(target) else { return false }
        if let expectedDevice, let expectedInode,
           before.device != expectedDevice || before.inode != expectedInode {
            return false
        }
        guard freeBytes(target) > before.size + freeSpaceReserve else {
            logger.info("Undo declined for \(target, privacy: .public): not enough free space")
            return false
        }
        guard !isOpenForWriting(target) else { return false }

        let directory = (target as NSString).deletingLastPathComponent
        let temp = directory + "/" + tempFilePrefix + String(UUID().uuidString.prefix(8))
        var keepTemp = false
        defer {
            if !keepTemp {
                unlink(temp)
            }
        }
        // COPYFILE_DATA without COPYFILE_CLONE writes real, unshared blocks.
        guard copyfile(target, temp, nil, copyfile_flags_t(COPYFILE_DATA | COPYFILE_NOFOLLOW)) == 0 else {
            return false
        }
        guard copyMetadata(from: target, to: temp),
              metadataSnapshot(temp) == metadataSnapshot(target),
              contentsEqual(temp, target),
              lstatInfo(target) == before,
              rename(temp, target) == 0 else {
            return false
        }
        keepTemp = true
        logger.info("Unfolded \(target, privacy: .public) into a private copy")
        return true
    }

    // MARK: - Volume / free space

    /// True when the file's volume is APFS and therefore supports `clonefile`.
    public static func volumeSupportsClones(at url: URL) -> Bool {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return false }
        return cString(of: fs.f_fstypename) == "apfs"
    }

    /// Free bytes on the volume containing `path`; 0 when statfs fails.
    static func freeBytes(_ path: String) -> Int64 {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return 0 }
        return Int64(fs.f_bavail) * Int64(fs.f_bsize)
    }

    // MARK: - Stats and metadata

    private static func lstatInfo(_ path: String) -> FileStat? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return FileStat(
            device: UInt64(st.st_dev),
            inode: st.st_ino,
            nlink: UInt64(st.st_nlink),
            uid: st.st_uid,
            gid: st.st_gid,
            mode: UInt32(st.st_mode),
            flags: st.st_flags,
            size: Int64(st.st_size),
            allocatedBytes: Int64(st.st_blocks) * 512,
            mtime: TimeInterval(st.st_mtimespec.tv_sec),
            birthtime: TimeInterval(st.st_birthtimespec.tv_sec)
        )
    }

    private static func metadataSnapshot(_ path: String) -> MetadataSnapshot? {
        guard let st = lstatInfo(path) else { return nil }
        var xattrs: [String: Data] = [:]
        for name in xattrNames(path) where !systemManagedXattrs.contains(name) {
            if let value = xattrValue(path, name: name) {
                xattrs[name] = value
            }
        }
        return MetadataSnapshot(
            mode: st.mode,
            uid: st.uid,
            gid: st.gid,
            size: st.size,
            mtime: st.mtime,
            birthtime: st.birthtime,
            xattrs: xattrs
        )
    }

    /// Copies mode, ownership, times and ACLs with `copyfile`, then syncs
    /// xattrs manually (skipping the system-managed ones `copyfile` cannot set).
    private static func copyMetadata(from source: String, to destination: String) -> Bool {
        let flags = copyfile_flags_t(COPYFILE_STAT | COPYFILE_ACL | COPYFILE_NOFOLLOW)
        guard copyfile(source, destination, nil, flags) == 0 else { return false }
        return copyXattrs(from: source, to: destination)
    }

    private static func copyXattrs(from source: String, to destination: String) -> Bool {
        let sourceNames = Set(xattrNames(source))
        // The clone starts with the keeper's xattrs; anything the original
        // file does not have must go (except what the system owns).
        for name in xattrNames(destination)
        where !sourceNames.contains(name) && !systemManagedXattrs.contains(name) {
            removexattr(destination, name, 0)
        }
        for name in sourceNames where !systemManagedXattrs.contains(name) {
            guard let value = xattrValue(source, name: name) else { continue }
            let result = value.withUnsafeBytes { raw in
                setxattr(destination, name, raw.baseAddress, raw.count, 0, 0)
            }
            if result != 0 {
                logger.warning("xattr \(name, privacy: .public) could not be copied")
            }
        }
        return true
    }

    private static func xattrNames(_ path: String) -> [String] {
        let size = listxattr(path, nil, 0, 0)
        guard size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        let written = listxattr(path, &buffer, size, 0)
        guard written > 0 else { return [] }
        var names: [String] = []
        var nameStart = buffer.startIndex
        for index in buffer.startIndex..<(buffer.startIndex + written) where buffer[index] == 0 {
            names.append(String(cString: Array(buffer[nameStart..<index]) + [0]))
            nameStart = index + 1
        }
        return names
    }

    private static func xattrValue(_ path: String, name: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = Data(count: size)
        let read = buffer.withUnsafeMutableBytes { raw in
            getxattr(path, name, raw.baseAddress, size, 0, 0)
        }
        guard read >= 0 else { return nil }
        return buffer.prefix(read)
    }

    /// Reads a NUL-terminated C string out of a fixed-size C char array
    /// without force-unwrapping the buffer pointer.
    fileprivate static func cString<T>(of value: T) -> String {
        var value = value
        return withUnsafeBytes(of: &value) { buffer in
            let bytes = buffer.prefix { $0 != 0 }.map { CChar(bitPattern: $0) }
            return String(cString: bytes + [0])
        }
    }

    // MARK: - Byte comparison

    /// Byte-for-byte comparison with uncached reads, so the check reflects
    /// what is on disk rather than what the page cache remembers.
    static func contentsEqual(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = lstatInfo(lhs), let right = lstatInfo(rhs), left.size == right.size else {
            return false
        }
        let leftFD = open(lhs, O_RDONLY | O_NOFOLLOW)
        let rightFD = open(rhs, O_RDONLY | O_NOFOLLOW)
        defer {
            if leftFD >= 0 { close(leftFD) }
            if rightFD >= 0 { close(rightFD) }
        }
        guard leftFD >= 0, rightFD >= 0 else { return false }
        fcntl(leftFD, F_NOCACHE, 1)
        fcntl(rightFD, F_NOCACHE, 1)
        let bufferSize = 1 << 20
        let leftBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize, alignment: MemoryLayout<UInt8>.alignment
        )
        let rightBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize, alignment: MemoryLayout<UInt8>.alignment
        )
        defer {
            leftBuffer.deallocate()
            rightBuffer.deallocate()
        }
        var offset: Int64 = 0
        while offset < left.size {
            let chunk = min(Int64(bufferSize), left.size - offset)
            let leftRead = read(leftFD, leftBuffer, Int(chunk))
            let rightRead = read(rightFD, rightBuffer, Int(chunk))
            guard leftRead == Int(chunk), rightRead == Int(chunk) else { return false }
            if memcmp(leftBuffer, rightBuffer, Int(chunk)) != 0 { return false }
            offset += chunk
        }
        return true
    }

    // MARK: - Open-for-writing detection

    /// True when any process currently holds `path` open for writing. Folding
    /// a file another app is writing would silently discard the app's writes.
    static func isOpenForWriting(_ path: String) -> Bool {
        OpenFilesSnapshot.shared.contains(path)
    }

    /// Invalidates the open-files cache. Tests call this to force a fresh scan.
    public static func invalidateOpenFilesCache() {
        OpenFilesSnapshot.shared.invalidate()
    }
}

/// Process-wide snapshot of every file descriptor open for writing, refreshed
/// at most every 2 seconds. Mutable state lives behind a lock in one final
/// class so the enum above stays concurrency-safe under Swift 6.
private final class OpenFilesSnapshot: @unchecked Sendable {
    static let shared = OpenFilesSnapshot()

    private let lock = NSLock()
    private var paths: Set<String> = []
    private var refreshedAt: Date = .distantPast

    func contains(_ path: String) -> Bool {
        lock.lock()
        let needsRefresh = Date().timeIntervalSince(refreshedAt) > 2
        lock.unlock()
        if needsRefresh { refresh() }
        lock.lock()
        defer { lock.unlock() }
        return paths.contains(path)
    }

    func invalidate() {
        lock.lock()
        refreshedAt = .distantPast
        lock.unlock()
    }

    private func refresh() {
        var writing: Set<String> = []
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(pidCount))
        let stored = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard stored > 0 else { return }
        for pid in pids.prefix(Int(stored)) {
            let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard listSize > 0 else { continue }
            let fdCount = Int(listSize) / MemoryLayout<proc_fdinfo>.size
            var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
            let storedFDs = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, listSize)
            guard storedFDs > 0 else { continue }
            for fdInfo in fdInfos.prefix(Int(storedFDs) / MemoryLayout<proc_fdinfo>.size)
            where fdInfo.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
                // One call yields both the open flags and the path.
                var info = vnode_fdinfowithpath()
                let infoSize = proc_pidinfo(
                    pid, PROC_PIDFDVNODEPATHINFO, UInt64(fdInfo.proc_fd), &info,
                    Int32(MemoryLayout<vnode_fdinfowithpath>.size)
                )
                guard infoSize > 0, info.pfi.fi_openflags & UInt32(FWRITE) != 0 else { continue }
                writing.insert(APFSCloneService.cString(of: info.pvip.vip_path))
            }
        }
        lock.lock()
        paths = writing
        refreshedAt = Date()
        lock.unlock()
    }
}
