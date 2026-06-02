import Foundation
import SwiftData

enum SwipeDecision: String, Codable {
    case deleted
    case addedToAlbum
    case skipped
}

@Model
final class SwipeRecord {
    var assetLocalIdentifier: String
    var decision: SwipeDecision
    var albumLocalIdentifier: String?
    var swipedAt: Date

    init(assetLocalIdentifier: String, decision: SwipeDecision, albumLocalIdentifier: String? = nil, swipedAt: Date = .now) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.decision = decision
        self.albumLocalIdentifier = albumLocalIdentifier
        self.swipedAt = swipedAt
    }
}
