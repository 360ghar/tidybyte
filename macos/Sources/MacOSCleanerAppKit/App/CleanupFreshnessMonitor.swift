import CoreServices
import Foundation
import MacOSCleanerCore
@preconcurrency import Photos

/// System callback bridge; all observable state is updated on the main actor.
final class CleanupFreshnessMonitor: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let changed: @Sendable () -> Void

    @MainActor init(roots: [URL], includesPhotos: Bool, changed: @escaping @Sendable () -> Void) {
        self.changed = changed
        super.init()
        if !roots.isEmpty {
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil)
            stream = FSEventStreamCreate(
                nil,
                { _, pointer, count, paths, _, _ in
                    guard let pointer else { return }
                    let entries = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                    let relevant = (0..<count).contains { index in
                        ReviewSafety.isAllowed(URL(fileURLWithPath: String(cString: entries[index])))
                    }
                    if relevant {
                        Unmanaged<CleanupFreshnessMonitor>.fromOpaque(pointer).takeUnretainedValue().changed()
                    }
                },
                &context, roots.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
            if let stream {
                FSEventStreamSetDispatchQueue(stream, .main)
                FSEventStreamStart(stream)
            }
        }
        if includesPhotos { PHPhotoLibrary.shared().register(self) }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) { changed() }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
