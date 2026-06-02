import SwiftUI
import Photos

enum PhotoPermissionState {
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
