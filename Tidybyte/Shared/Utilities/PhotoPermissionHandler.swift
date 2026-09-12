import SwiftUI
import Photos

enum PhotoPermissionState: Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted
}

@Observable
@MainActor
final class PhotoPermissionHandler {
    var permissionState: PhotoPermissionState = .notDetermined

    init() {
        updateState()
    }

    func updateState() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        permissionState = mapStatus(status)
    }

    func requestPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        permissionState = mapStatus(status)
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

    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotoPermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        case .limited: .limited
        @unknown default: .denied
        }
    }
}
