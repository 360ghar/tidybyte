import XCTest
import Photos
@testable import Tidybyte

/// Covers the pure `PhotoPermissionState -> PermissionPresentation` mapping.
///
/// The system dialog itself cannot be asserted from a unit test, so what is
/// pinned here is that every state offers the right action and never renders a
/// blank title or message — the two ways the Settings row and the full-screen
/// gate drifted apart before (a fresh install offered "Open Settings" with
/// nothing to turn on).
final class PhotoPermissionPresentationTests: XCTestCase {

    private let allStates: [PhotoPermissionState] = [
        .notDetermined, .authorized, .limited, .denied, .restricted
    ]

    // MARK: - State -> action

    func testNotDeterminedAsksAndShowsThePrimer() {
        let presentation = PhotoPermissionState.notDetermined.presentation
        XCTAssertEqual(presentation.action, .requestPermission)
        XCTAssertTrue(presentation.showsPrimer)
    }

    func testDeniedSendsTheUserToSettings() {
        let presentation = PhotoPermissionState.denied.presentation
        XCTAssertEqual(presentation.action, .openSettings)
        XCTAssertFalse(presentation.showsPrimer)
    }

    func testRestrictedOffersNoAction() {
        let presentation = PhotoPermissionState.restricted.presentation
        XCTAssertEqual(presentation.action, PermissionPresentation.Action.none)
        XCTAssertFalse(presentation.showsPrimer)
    }

    func testLimitedOffersNoActionBecauseWideningIsASeparateAffordance() {
        let presentation = PhotoPermissionState.limited.presentation
        XCTAssertEqual(presentation.action, PermissionPresentation.Action.none)
        XCTAssertFalse(presentation.showsPrimer)
    }

    func testAuthorizedOffersNoAction() {
        let presentation = PhotoPermissionState.authorized.presentation
        XCTAssertEqual(presentation.action, PermissionPresentation.Action.none)
        XCTAssertFalse(presentation.showsPrimer)
    }

    func testOnlyNotDeterminedShowsThePrimer() {
        for state in allStates {
            XCTAssertEqual(
                state.presentation.showsPrimer,
                state == .notDetermined,
                "\(state) shows the primer only when the system prompt is still available"
            )
        }
    }

    // MARK: - Copy

    func testEveryStateHasTitleAndMessage() {
        for state in allStates {
            let presentation = state.presentation
            XCTAssertFalse(
                presentation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(state) needs a title"
            )
            XCTAssertFalse(
                presentation.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(state) needs a message"
            )
        }
    }

    func testRestrictedCopyNamesTheBlockAndSaysSettingsCannotFixIt() {
        let message = PhotoPermissionState.restricted.presentation.message
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("restriction"),
            "Must name the Screen Time / device-management restriction: \(message)"
        )
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("Settings"),
            "Must say the Photos switch cannot change it: \(message)"
        )
    }

    func testNotDeterminedCopySaysTheAskIsStillComing() {
        let message = PhotoPermissionState.notDetermined.presentation.message
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("ask"),
            "Must say iOS will ask next, so the button's behaviour is not a surprise: \(message)"
        )
    }

    func testDeniedCopyPointsAtSettings() {
        let message = PhotoPermissionState.denied.presentation.message
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("Settings"),
            "The only route back is Settings: \(message)"
        )
    }

    // MARK: - Primer

    func testPrimerCopyIsComplete() {
        XCTAssertFalse(PermissionPresentation.primerTitle.isEmpty)
        XCTAssertFalse(PermissionPresentation.primerMessage.isEmpty)
        XCTAssertEqual(PermissionPresentation.primerButtonTitle, "Continue")
        XCTAssertEqual(PermissionPresentation.declineButtonTitle, "Not Now")
    }

    // MARK: - PhotoKit mapping (unchanged by the refactor)

    func testAuthorizationStatusMapping() {
        XCTAssertEqual(PhotoPermissionState(authorizationStatus: .notDetermined), .notDetermined)
        XCTAssertEqual(PhotoPermissionState(authorizationStatus: .restricted), .restricted)
        XCTAssertEqual(PhotoPermissionState(authorizationStatus: .denied), .denied)
        XCTAssertEqual(PhotoPermissionState(authorizationStatus: .authorized), .authorized)
        XCTAssertEqual(PhotoPermissionState(authorizationStatus: .limited), .limited)
    }
}
