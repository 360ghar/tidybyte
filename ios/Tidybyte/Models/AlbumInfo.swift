import Foundation

enum AlbumType: String, Sendable {
    case smartAlbum
    case userAlbum
}

struct AlbumInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let count: Int
    let type: AlbumType
    var thumbnailAssetId: String?
}
