import SwiftUI

/// Why a photo-library read came back empty.
///
/// Two very different situations produce zero assets, and the app used to draw
/// the same "All Caught Up!" empty state for both (SWIPE-09):
///
/// - the filter genuinely ran out of photos, or
/// - the app has access on paper but no photos to read.
///
/// The second one is what a fresh install with a stuck permission looks like:
/// the Photos switch shows a value, `authorizationStatus(for: .readWrite)`
/// returns `.limited` or `.authorized`, every fetch returns nothing, and the app
/// blames the library. This type names that state so the UI can offer the two
/// actions that actually recover it.
enum PhotoLibraryEmptyReason: Equatable, Sendable {
    /// Limited access with nothing shared. iOS shows a limited app only the
    /// photos the user picked, so an empty selection reads as an empty library.
    case limitedNoSelection

    /// iOS reports full access and the library still returns nothing.
    ///
    /// The app cannot tell the two causes apart from here: a brand-new device
    /// with no photos looks exactly like a stuck permission. So the copy must be
    /// true in both — it states the fact (full access, zero assets) and points at
    /// the Photos app to decide which case this is.
    case accessReturnedNothing

    /// The reason an empty deck should be explained by access, or `nil` when it
    /// must not be.
    ///
    /// - Parameter totalAssetCount: how many assets the app can see, unfiltered.
    ///   Any non-zero count means the deck is empty because of the filter, which
    ///   is the existing "All Caught Up!" copy.
    static func resolve(status: PhotoPermissionState, totalAssetCount: Int) -> PhotoLibraryEmptyReason? {
        guard totalAssetCount == 0 else { return nil }
        switch status {
        case .limited: return .limitedNoSelection
        case .authorized: return .accessReturnedNothing
        // No access at all is the permission gate's job, not an empty-state
        // explanation — it has its own screen and its own ask.
        case .notDetermined, .denied, .restricted: return nil
        }
    }

    var recovery: PhotoRecoveryPresentation {
        switch self {
        case .limitedNoSelection: .limitedNoSelection
        case .accessReturnedNothing: .accessReturnedNothing
        }
    }
}

/// Why an album list came back empty.
///
/// Separate from `PhotoLibraryEmptyReason` because limited access splits into
/// two different answers, and only the census tells them apart. Under limited
/// access iOS hides *user* albums entirely — they cannot be fetched or created —
/// but *smart* albums stay fetchable, filtered to the shared selection (WWDC20,
/// "Handle the Limited Photos Library"). So:
///
/// - nothing shared → both lists are empty, and sharing photos fixes it;
/// - photos shared, but the sheet only asks for editable albums (the "Add to
///   Album" sheet passes `editableOnly: true`, which skips smart albums) → the
///   list is empty because the user albums are missing, and only Full Access
///   fixes it. "Share more photos" would be a lie there: the user is looking at
///   a shared photo while being told nothing is shared.
enum AlbumListEmptyReason: Equatable, Sendable {
    /// Limited access with nothing shared. Smart albums exist but contain no
    /// visible assets, and user albums are unavailable, so the list is empty.
    case limitedNoSelection

    /// Limited access with photos visible, but no user albums. Every smart album
    /// already contributed what it could, so what is missing is the user albums
    /// an app may only read, create, and file into with full access.
    case limitedCannotUseAlbums

    /// Full access and no assets at all — the same device-side permission
    /// problem the deck reports.
    case accessReturnedNothing

    static func resolve(status: PhotoPermissionState, totalAssetCount: Int) -> AlbumListEmptyReason? {
        switch status {
        case .limited: return totalAssetCount == 0 ? .limitedNoSelection : .limitedCannotUseAlbums
        case .authorized: return totalAssetCount == 0 ? .accessReturnedNothing : nil
        case .notDetermined, .denied, .restricted: return nil
        }
    }

    var recovery: PhotoRecoveryPresentation {
        switch self {
        case .limitedNoSelection: .limitedAlbums
        case .limitedCannotUseAlbums: .limitedAlbumsNeedFullAccess
        case .accessReturnedNothing: .accessReturnedNothing
        }
    }
}

/// What the recovery card draws: a title, an explanation, optional numbered
/// steps, and the actions that can fix it.
///
/// Copy is resolved through `L10n` at construction rather than stored as
/// `LocalizedStringKey` fields, for the same reason `PermissionPresentation`
/// does it: this type is `Equatable` and compared in tests, and the view wraps
/// each line back into a `LocalizedStringKey` so a live language change still
/// re-renders it. Computed properties, not `static let` — a static would keep
/// serving the launch-time language after the user switches (see `L10n`).
struct PhotoRecoveryPresentation: Equatable {
    enum Action: Equatable { case addPhotos, openSettings, retry }

    let title: String
    let message: String
    /// Numbered recovery steps, in order. Empty when the copy needs none.
    let steps: [String]
    /// Offered in order; the first is drawn as the primary button.
    let actions: [Action]

    /// The resolved English text handed back as a key, so `Text` looks it up
    /// against the live `\.locale` instead of rendering the string verbatim.
    /// The Catalog's keys *are* the English text, so this re-resolves to the
    /// chosen language — and re-resolves again if the user switches while this
    /// screen is up.
    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }
    var messageKey: LocalizedStringKey { LocalizedStringKey(message) }

    // MARK: - Copy

    static var limitedNoSelection: PhotoRecoveryPresentation {
        PhotoRecoveryPresentation(
            title: L10n.string("No Photos Shared Yet"),
            message: L10n.string("TidyByte has permission to see some of your photos, but none are shared with it right now, so there is nothing to review. Pick the photos it can see, or switch it to Full Access in Settings."),
            steps: [],
            // `.retry` is here because the picker's reload normally rides on a
            // debounced change notification; if that is missed, this is the only
            // way back without relaunching the app.
            actions: [.addPhotos, .openSettings, .retry]
        )
    }

    static var accessReturnedNothing: PhotoRecoveryPresentation {
        PhotoRecoveryPresentation(
            title: L10n.string("No Photos Found"),
            message: L10n.string("TidyByte has full photo access, but the library returned no photos. If the Photos app on this iPhone shows photos, that is a permissions problem, and the steps below reset it."),
            steps: [
                L10n.string("Open the Photos app and check that your photos are still there."),
                L10n.string("In Settings, turn TidyByte's Photos access off, then on again, and choose Full Access."),
                L10n.string("Come back here and tap Try Again.")
            ],
            actions: [.openSettings, .retry]
        )
    }

    static var limitedAlbums: PhotoRecoveryPresentation {
        PhotoRecoveryPresentation(
            title: L10n.string("No Albums Yet"),
            message: L10n.string("TidyByte has access to some of your photos, but none are shared with it yet, so there are no albums to list. Pick the photos it can see, or switch it to Full Access in Settings."),
            steps: [],
            actions: [.addPhotos, .openSettings]
        )
    }

    /// Limited access with photos visible: the user albums are the missing part,
    /// and sharing more photos cannot bring them back. Only Full Access can, so
    /// this card offers that alone rather than a re-read or a picker that would
    /// change nothing.
    static var limitedAlbumsNeedFullAccess: PhotoRecoveryPresentation {
        PhotoRecoveryPresentation(
            title: L10n.string("Albums Need Full Access"),
            message: L10n.string("TidyByte can see your photos, but not your albums. With limited access, iOS does not let an app read or create albums, so choose Full Access in Settings to file photos into an album."),
            steps: [],
            actions: [.openSettings]
        )
    }
}

extension PhotoRecoveryPresentation.Action {
    /// Button title for the action. Resolved here rather than in the view so
    /// every screen offers the same words for the same action.
    var title: String {
        switch self {
        case .addPhotos: L10n.string("Add More Photos")
        case .openSettings: L10n.string("Open Settings")
        case .retry: L10n.string("Try Again")
        }
    }
}
