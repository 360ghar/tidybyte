import Foundation
import SwiftData

@Model
final class StorageSnapshot {
    var capturedAt: Date
    var photoBytes: Int64
    var videoBytes: Int64
    var screenshotBytes: Int64
    // Default keeps SwiftData lightweight migration automatic for stores created
    // before Live Photos were tracked separately (they were previously folded
    // into photoBytes).
    var livePhotoBytes: Int64 = 0
    var otherBytes: Int64

    var totalBytes: Int64 {
        photoBytes + videoBytes + screenshotBytes + livePhotoBytes + otherBytes
    }

    init(
        capturedAt: Date = .now,
        photoBytes: Int64,
        videoBytes: Int64,
        screenshotBytes: Int64,
        livePhotoBytes: Int64 = 0,
        otherBytes: Int64
    ) {
        self.capturedAt = capturedAt
        self.photoBytes = photoBytes
        self.videoBytes = videoBytes
        self.screenshotBytes = screenshotBytes
        self.livePhotoBytes = livePhotoBytes
        self.otherBytes = otherBytes
    }
}
