import Darwin
import Foundation

/// Space that moving an item to Trash (and emptying it) actually returns.
/// A hard link with other names frees nothing, and an APFS clone frees only
/// the blocks it does not share.
public enum ReclaimableBytes {
    /// - Parameter checkClones: asks the file system for shared blocks (one
    ///   call per large file). Off for views that redraw often.
    public static func size(of record: FileRecord, checkClones: Bool = true) -> Int64 {
        guard record.kind == .regularFile else { return max(0, record.sizeBytes) }
        if let links = record.linkCount, links > 1 { return 0 }
        guard checkClones, record.sizeBytes >= 1_048_576, let unshared = privateSize(of: record.url) else {
            return max(0, record.sizeBytes)
        }
        return min(max(0, record.sizeBytes), unshared)
    }

    /// Bytes not shared with any clone (`ATTR_CMNEXT_PRIVATESIZE`), or nil
    /// when the volume does not report it.
    static func privateSize(of url: URL) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(bitPattern: Int32(bitPattern: UInt32(ATTR_CMN_RETURNED_ATTRS)))
        // Extended common attributes go in the fork bitmap with FSOPT_ATTR_CMN_EXTENDED.
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        struct Reply {
            var length: UInt32 = 0
            var returned = attribute_set_t()
            var privateSize: off_t = 0
        }
        var reply = Reply()
        let options = UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED)
        let status = withUnsafeMutableBytes(of: &reply) { buffer in
            getattrlist(url.path, &request, buffer.baseAddress, buffer.count, options)
        }
        guard status == 0, reply.returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
        return Int64(reply.privateSize)
    }
}
