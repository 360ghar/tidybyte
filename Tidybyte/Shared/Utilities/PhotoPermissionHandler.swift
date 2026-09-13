import SwiftUI
import Photos

enum PhotoPermissionState: Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
}

// MARK: - Presentation

/// What the UI should show and offer for a given permission state. Pure so the
/// state -> copy/action mapping is unit-tested instead of duplicated across
/// three screens.
struct PermissionPresentation: Equatable {
    enum Action: Equatable { case requestPermission, openSettings, none }

    let title: String
    let message: String
    let action: Action
    /// True when the app should show its own explanation before firing the
    /// one-shot system prompt.
    let showsPrimer: Bool

    // MARK: Pre-prompt explainer

    /// iOS shows the photo prompt exactly once per install, so the ask is
    /// never fired cold. The primer also tells the user why a second tap can
    /// no longer produce a dialog — that is what sends them to Settings.
    static let primerTitle = "Allow Photo Access?"
    static let primerMessage = "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review."
    static let primerButtonTitle = "Continue"
    static let declineButtonTitle = "Not Now"
}

extension PhotoPermissionState {
    var presentation: PermissionPresentation {
        switch self {
        case .notDetermined:
            PermissionPresentation(
                title: "TidyByte Needs Your Photos",
                message: "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.",
                action: .requestPermission,
                showsPrimer: true
            )
        case .authorized:
            PermissionPresentation(
                title: "Photo Access Is On",
                message: "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.",
                action: .none,
                showsPrimer: false
            )
        case .limited:
            PermissionPresentation(
                title: "Limited Photo Access",
                message: "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.",
                action: .none,
                showsPrimer: false
            )
        case .denied:
            PermissionPresentation(
                title: "Photo Access Is Off",
                message: "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.",
                action: .openSettings,
                showsPrimer: false
            )
        case .restricted:
            PermissionPresentation(
                title: "Photo Access Is Restricted",
                message: "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.",
                action: .none,
                showsPrimer: false
            )
        }
    }
}

// MARK: - Handler

@Observable
@MainActor
final class PhotoPermissionHandler {
    var permissionState: PhotoPermissionState = .notDetermined

    init() {
        updateState()
    }

    func updateState() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        permissionState = PhotoPermissionState(authorizationStatus: status)
    }

    func requestPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        permissionState = PhotoPermissionState(authorizationStatus: status)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Presents the system picker that lets the user widen a limited selection.
    ///
    /// Static so callers that only track the raw `PHAuthorizationStatus`
    /// (`SettingsView`) can offer the same action without owning a handler
    /// instance — there is exactly one implementation of "ask for more photos".
    @MainActor
    static func presentLimitedLibraryPicker() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = scene?.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
}

extension PhotoPermissionState {
    /// The single place a raw PhotoKit status becomes a UI state. Kept out of
    /// the `@MainActor` handler so the mapping stays unit-testable.
    init(authorizationStatus status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .limited: self = .limited
        @unknown default: self = .denied
        }
    }
}
