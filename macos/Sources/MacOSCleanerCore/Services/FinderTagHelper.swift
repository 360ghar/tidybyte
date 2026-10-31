import Darwin
import Foundation

struct FinderTagHelper {
    static func write(_ tags: [String], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        let result: Int32 = data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return setxattr(url.path, "com.apple.metadata:_kMDItemUserTags", baseAddress, buffer.count, 0, 0)
        }
        if result != 0 {
            let err = Darwin.errno
            switch err {
            case EACCES:
                throw CocoaError(.fileWriteNoPermission)
            case ENOENT:
                throw CocoaError(.fileNoSuchFile)
            case ENOSPC:
                throw CocoaError(.fileWriteOutOfSpace)
            default:
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "setxattr failed with errno \(err): \(String(cString: strerror(err)))"])
            }
        }
    }
}
