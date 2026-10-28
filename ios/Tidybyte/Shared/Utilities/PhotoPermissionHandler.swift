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
///
/// The copy is resolved through `L10n` at construction rather than by making
/// the fields `LocalizedStringKey`. Two reasons: this type is `Equatable` and
/// compared in tests, which a `LocalizedStringKey` field would break; and the
/// screen renders it with `Text(presentation.title)`, which is the
/// non-localizing `StringProtocol` overload, so the text has to arrive already
/// translated.
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
    ///
    /// Computed, not stored: a `static let` would capture the launch-time
    /// language the first time the type is touched and keep serving it after
    /// the user switches.
    static var primerTitle: String { L10n.string("Allow Photo Access?") }
    static var primerMessage: String {
        L10n.string("iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.")
    }
    static var primerButtonTitle: String { L10n.string("Continue") }
    static var declineButtonTitle: String { L10n.string("Not Now") }
}

extension PhotoPermissionState {
    var presentation: PermissionPresentation {
        switch self {
        case .notDetermined:
            PermissionPresentation(
                title: L10n.string("TidyByte Needs Your Photos"),
                message: L10n.string("TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next."),
                action: .requestPermission,
                showsPrimer: true
            )
        case .authorized:
            PermissionPresentation(
                title: L10n.string("Photo Access Is On"),
                message: L10n.string("TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so."),
                action: .none,
                showsPrimer: false
            )
        case .limited:
            PermissionPresentation(
                title: L10n.string("Limited Photo Access"),
                message: L10n.string("TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library."),
                action: .none,
                showsPrimer: false
            )
        case .denied:
            PermissionPresentation(
                title: L10n.string("Photo Access Is Off"),
                message: L10n.string("iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again."),
                action: .openSettings,
                showsPrimer: false
            )
        case .restricted:
            PermissionPresentation(
                title: L10n.string("Photo Access Is Restricted"),
                message: L10n.string("A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first."),
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

    /// Opens TidyByte's own page in Settings.
    ///
    /// Static for the same reason as `presentLimitedLibraryPicker`: the
    /// recovery card offers "Open Settings" and has no handler instance, and
    /// there must be exactly one implementation of the jump.
    @MainActor
    static func openSettings() {
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
        // Logged because the call is a silent no-op when the app is no longer
        // `.limited` or a presentation is already in flight — without this a
        // "the button does nothing" report has nothing to go on.
        AppLog.photo.info(
            "Presenting limited library picker (status \(PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue, privacy: .public))"
        )
        // The topmost controller, not the root: UIKit ignores a presentation
        // requested while another one is already showing, which made the button
        // appear to do nothing when a sheet was up.
        guard let presenter = topmostViewController() else { return }
        // The completion variant, so "the picker closed" is observable without
        // waiting on a debounced change-observer delivery.
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { _ in
            // The handler is not guaranteed to arrive on main, and the observers
            // behind this notification touch view state.
            Task { @MainActor in
                NotificationCenter.default.post(name: .photoLibrarySelectionDidChange, object: nil)
            }
        }
    }

    /// True when nothing is already presented.
    ///
    /// Used to gate the automatic presentation on launch: the picker is helpful
    /// when the app opens to an empty library, but covering a sheet the user is
    /// working in is not.
    @MainActor
    static var isReadyToPresentLimitedLibraryPicker: Bool {
        guard let root = activeRootViewController() else { return false }
        return root.presentedViewController == nil
    }

    /// Waits, briefly, for any covered screen to finish dismissing.
    ///
    /// `isReadyToPresentLimitedLibraryPicker` is a snapshot, and the moment the
    /// launch offer runs is exactly the moment the snapshot is wrong: the
    /// onboarding `fullScreenCover` is still on screen for a few frames after
    /// `hasCompletedOnboarding` flips, so a single check returned false while
    /// the cover was mid-dismissal and nothing ever re-triggered the offer. The
    /// launch's one offer was lost.
    ///
    /// A bounded poll, not a fixed sleep: when the surface is already clear this
    /// returns on the first check, and the timeout keeps a stuck presentation
    /// from holding the task open.
    ///
    /// `isReady` is a parameter so the wait itself is testable without a window
    /// scene.
    @MainActor
    static func waitUntilReadyToPresent(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(50),
        isReady: () -> Bool = { PhotoPermissionHandler.isReadyToPresentLimitedLibraryPicker }
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if isReady() { return true }
            // Checked explicitly rather than relying on `Task.sleep` throwing:
            // a cancelled sleep returns immediately, and the deadline is wall
            // clock, so the loop would spin for the rest of the second.
            if Task.isCancelled || ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: pollInterval)
        }
    }

    @MainActor
    private static func activeRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow?.rootViewController
    }

    @MainActor
    private static func topmostViewController() -> UIViewController? {
        var controller = activeRootViewController()
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
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

extension Notification.Name {
    /// Posted when the system limited-library picker closes, so screens that are
    /// waiting on a widened selection can reload without depending on a debounced
    /// PHPhotoLibraryChangeObserver delivery.
    static let photoLibrarySelectionDidChange = Notification.Name("photoLibrarySelectionDidChange")
}
