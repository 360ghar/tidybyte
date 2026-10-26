import XCTest
import Photos
import SwiftUI
@testable import Tidybyte

/// Covers the access-vs-empty resolution and the copy it produces.
///
/// The bug this pins: a library the app cannot see and a library with nothing
/// left to review both drew "All Caught Up!", so a permission problem was
/// reported to the user as a finished job. What is asserted here is that every
/// access state either explains itself or explicitly defers to another screen,
/// and that no explanation renders blank.
final class PhotoAccessRecoveryTests: XCTestCase {

    private let allStates: [PhotoPermissionState] = [
        .notDetermined, .authorized, .limited, .denied, .restricted
    ]

    override func setUp() {
        super.setUp()
        // The copy assertions pin English text, and the presentations hold
        // catalog *keys*, so English is what they hand back regardless of the
        // override. Pinned anyway by `save(.english)` and not `save(nil)`:
        // `nil` restores the *device* language, so on a non-English simulator one
        // leftover override would otherwise leak into these tests and fail them
        // for an unrelated reason.
        LanguagePreferenceStore.save(.english)
    }

    override func tearDown() {
        // Hand the device language back, so this file cannot leak an override
        // into whatever runs next.
        LanguagePreferenceStore.save(nil)
        super.tearDown()
    }

    // MARK: - Deck reason

    func testEmptyLibraryUnderLimitedAccessIsNamedAsSuch() {
        XCTAssertEqual(
            PhotoLibraryEmptyReason.resolve(status: .limited, totalAssetCount: 0),
            .limitedNoSelection
        )
    }

    func testEmptyLibraryUnderFullAccessIsAPermissionProblemNotAnEmptyLibrary() {
        XCTAssertEqual(
            PhotoLibraryEmptyReason.resolve(status: .authorized, totalAssetCount: 0),
            .accessReturnedNothing
        )
    }

    func testAReadableLibraryNeverProducesAnAccessExplanation() {
        // The filter ran out of photos: that is a finished deck, not a
        // permission problem, and the existing "All Caught Up!" copy is right.
        for state in allStates {
            XCTAssertNil(
                PhotoLibraryEmptyReason.resolve(status: state, totalAssetCount: 1),
                "\(state) with a readable library must not claim an access problem"
            )
        }
    }

    func testStatesWithoutAccessDeferToThePermissionGate() {
        for state in [PhotoPermissionState.notDetermined, .denied, .restricted] {
            XCTAssertNil(
                PhotoLibraryEmptyReason.resolve(status: state, totalAssetCount: 0),
                "\(state) has its own screen and must not also explain an empty deck"
            )
        }
    }

    // MARK: - Album reason

    func testLimitedAccessSplitsOnWhatIsActuallyMissing() {
        // Under limited access iOS hides *user* albums (they cannot be fetched
        // or created) but still returns *smart* albums filtered to the shared
        // selection, so the census decides which half of the problem this is —
        // and therefore which action can fix it. The "Add to Album" sheet asks
        // for editable albums only, which skips smart albums, so a limited user
        // with photos reaches this with a full, visible photo.
        XCTAssertEqual(
            AlbumListEmptyReason.resolve(status: .limited, totalAssetCount: 0),
            .limitedNoSelection,
            "nothing shared: sharing photos is the fix"
        )
        XCTAssertEqual(
            AlbumListEmptyReason.resolve(status: .limited, totalAssetCount: 12),
            .limitedCannotUseAlbums,
            "photos shared but editable albums missing: only Full Access fixes it"
        )
    }

    func testFullAccessWithoutAssetsReportsTheSamePermissionProblem() {
        XCTAssertEqual(
            AlbumListEmptyReason.resolve(status: .authorized, totalAssetCount: 0),
            .accessReturnedNothing
        )
    }

    func testFullAccessWithAssetsAndNoAlbumsIsGenuinelyEmpty() {
        // A library with photos and no user albums is a real answer, and the
        // sheet's existing "No Albums" copy is the right one.
        XCTAssertNil(AlbumListEmptyReason.resolve(status: .authorized, totalAssetCount: 40))
    }

    func testAlbumReasonsAlsoDeferWhenThereIsNoAccess() {
        for state in [PhotoPermissionState.notDetermined, .denied, .restricted] {
            XCTAssertNil(AlbumListEmptyReason.resolve(status: state, totalAssetCount: 0))
        }
    }

    // MARK: - Copy

    func testEveryRecoveryPresentationHasTitleAndMessage() {
        for presentation in allPresentations {
            XCTAssertFalse(
                presentation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "a recovery card without a title is a blank screen"
            )
            XCTAssertFalse(
                presentation.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "a recovery card without a message does not explain the cause"
            )
        }
    }

    func testEveryRecoveryPresentationOffersAnAction() {
        // The card exists to get the user out of the state. A message with no
        // button is the dead end this replaced.
        for presentation in allPresentations {
            XCTAssertFalse(presentation.actions.isEmpty, "\(presentation.title) offers no action")
        }
    }

    func testOnlyTheStuckStateExplainsItselfInNumberedSteps() {
        // Steps are for the state the user cannot see a cause for. Limited
        // access gets straight actions, because "add photos" is self-evident.
        XCTAssertFalse(PhotoRecoveryPresentation.accessReturnedNothing.steps.isEmpty)
        XCTAssertTrue(PhotoRecoveryPresentation.limitedNoSelection.steps.isEmpty)
        XCTAssertTrue(PhotoRecoveryPresentation.limitedAlbums.steps.isEmpty)
        XCTAssertTrue(PhotoRecoveryPresentation.limitedAlbumsNeedFullAccess.steps.isEmpty)
    }

    func testStuckCopyFitsBothAnEmptyPhoneAndAStuckPermission() {
        // The app cannot tell a brand-new iPhone with no photos from a stuck
        // permission: both are `.authorized` with a zero census. So the copy may
        // state the fact (full access, nothing returned) and point at the Photos
        // app to decide which case this is — it may not accuse the device of a
        // permissions problem.
        let message = PhotoRecoveryPresentation.accessReturnedNothing.message
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("full photo access"),
            "The state under test is full access with nothing to read: \(message)"
        )
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("Photos app"),
            "Only the Photos app can tell the user whether photos exist: \(message)"
        )
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("permissions problem"),
            "When photos do exist, the cause is the permission and the copy must still say so: \(message)"
        )
        XCTAssertFalse(
            message.localizedCaseInsensitiveContains("not an empty library"),
            "A genuinely empty phone is not a permissions problem: \(message)"
        )
        XCTAssertEqual(
            PhotoRecoveryPresentation.accessReturnedNothing.steps.count,
            3,
            "The numbered steps are valid in both cases and have to stay"
        )
    }

    func testLimitedCopyOffersBothWaysOut() {
        XCTAssertEqual(
            PhotoRecoveryPresentation.limitedNoSelection.actions,
            [.addPhotos, .openSettings, .retry],
            "Widening the selection and switching to Full Access are both valid; either alone strands a user, and the retry is the only manual reload when the change notification is missed"
        )
    }

    func testStuckCopyOffersSettingsFirstAndThenARetry() {
        XCTAssertEqual(
            PhotoRecoveryPresentation.accessReturnedNothing.actions,
            [.openSettings, .retry],
            "Settings fixes it; retry proves it, so both are needed and in that order"
        )
    }

    func testAlbumCopyOffersTheSameTwoWaysOutAsTheDeck() {
        // The empty-album card is only reachable when the app can see zero
        // assets, which "Add More Photos" fixes — the same state as an empty
        // deck. Settings-first-only made it a dead end for a user who simply
        // had not picked anything yet.
        XCTAssertEqual(
            PhotoRecoveryPresentation.limitedAlbums.actions,
            [.addPhotos, .openSettings],
            "both actions recover an empty album list; neither is offered first by accident"
        )
    }

    func testEmptySelectionAlbumCopyDoesNotClaimFullAccessIsRequiredForAlbums() {
        // WWDC20 "Handle the Limited Photos Library": user albums are hidden from
        // a limited app, but smart albums are still returned, filtered to the
        // selection. A limited user with one shared photo therefore sees a
        // populated album list, so telling a user with *nothing* shared that
        // albums need full access would send them to Settings when sharing one
        // photo is enough.
        let presentation = PhotoRecoveryPresentation.limitedAlbums
        XCTAssertFalse(
            presentation.title.localizedCaseInsensitiveContains("full access"),
            "the no-selection card must not claim full access is required: \(presentation.title)"
        )
        XCTAssertTrue(
            presentation.message.localizedCaseInsensitiveContains("none are shared"),
            "it must name the real cause — no visible photos: \(presentation.message)"
        )
        XCTAssertTrue(
            presentation.actions.contains(.addPhotos),
            "sharing a photo is the cheapest fix and has to be offered"
        )
    }

    func testUnusableAlbumsCopyNamesAlbumsAndOffersOnlySettings() {
        // The mirror case, and the one the "Add to Album" sheet actually hits:
        // photos ARE visible (editable-only mode excludes the smart albums that
        // would otherwise populate the list), so "share more photos" would be a
        // lie and a retry cannot change a permission. Settings is the only exit.
        let presentation = PhotoRecoveryPresentation.limitedAlbumsNeedFullAccess
        XCTAssertTrue(
            presentation.message.localizedCaseInsensitiveContains("albums"),
            "it has to name the missing thing: \(presentation.message)"
        )
        XCTAssertFalse(
            presentation.message.localizedCaseInsensitiveContains("none are shared"),
            "photos are shared in this state; saying otherwise contradicts the photo the user is looking at: \(presentation.message)"
        )
        XCTAssertEqual(
            presentation.actions,
            [.openSettings],
            "only Full Access makes user albums readable, so nothing else belongs on this card"
        )
        XCTAssertFalse(
            presentation.actions.contains(.retry),
            "a retry cannot change a permission"
        )
    }

    func testActionTitlesAreCatalogKeysNotTranslatedText() {
        // Same words as the existing banner and empty state, so "Open Settings"
        // means one thing across the app.
        //
        // These are catalog *keys*, which is why they are asserted as English
        // literals under a non-English override: the value has to be
        // language-independent, because the card hands it back to `Text` as a
        // `LocalizedStringKey` and SwiftUI does the resolving against the live
        // locale. Resolving here (`L10n.string`) would return the translated
        // text, which is not a key in any language but English — a second lookup
        // would then be a no-op and the card would freeze at the language it was
        // built in.
        LanguagePreferenceStore.save(.german)
        XCTAssertEqual(PhotoRecoveryPresentation.Action.addPhotos.title, "Add More Photos")
        XCTAssertEqual(PhotoRecoveryPresentation.Action.openSettings.title, "Open Settings")
        XCTAssertEqual(PhotoRecoveryPresentation.Action.retry.title, "Try Again")
        XCTAssertEqual(
            PhotoRecoveryPresentation.limitedNoSelection.title,
            "No Photos Shared Yet",
            "the title must be the key too, not the German value"
        )
    }

    func testLiveLanguageBundlesResolveEveryRecoveryKey() {
        // The recovery copy is built with `L10n`, which a language change does
        // not re-run on its own; the views re-key it. What this pins is that
        // every key exists in every shipped translation at all — a missing key
        // falls back to the English text and looks translated in the base
        // language. Pure bundle lookups, so the whole sweep is instant.
        let languages = AppLanguage.concreteLanguages.filter { $0 != .english }
        // The same 20 non-English languages `scripts/localization/check.mjs`
        // validates the catalog for.
        XCTAssertEqual(languages.count, 20, "the shipped set is English plus 20")

        for key in Self.recoveryKeys {
            let resolved = languages.map { L10n.string(key, language: $0) }
            for (language, value) in zip(languages, resolved) {
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(language.rawValue) resolves \(key) to an empty string"
                )
            }

            let translated = zip(languages, resolved).filter { $0.1 != key }.map { $0.0 }
            if Self.awaitingTranslation.contains(key) {
                // This key's English text changed after the translation pass for
                // the release ran. Translated in *no* language is pending work;
                // translated in *some* is a shipped English string on part of the
                // store. Delete the entry from `awaitingTranslation` once its
                // translations exist — the branch below is then strict forever.
                XCTAssertTrue(
                    translated.isEmpty || translated.count == languages.count,
                    "\(key.prefix(40))… is translated in \(translated.count) of \(languages.count) languages"
                )
            } else {
                let missing = languages.filter { !translated.contains($0) }
                XCTAssertTrue(
                    missing.isEmpty,
                    "\(key.prefix(40))… has no translation in \(missing.map(\.rawValue))"
                )
            }
        }
    }

    func testRecoveryKeyListMatchesWhatThePresentationsRender() {
        // Keeps the sweep above honest: a new string in a presentation that is
        // not in `recoveryKeys` would silently never be checked for translation.
        LanguagePreferenceStore.save(.english)
        var rendered: [String] = []
        for presentation in allPresentations {
            rendered.append(presentation.title)
            rendered.append(presentation.message)
            rendered += presentation.steps
            for action in presentation.actions { rendered.append(action.title) }
        }
        for string in rendered {
            XCTAssertTrue(Self.recoveryKeys.contains(string), "not swept for translation: \(string)")
            XCTAssertFalse(string.contains("%"), "a format specifier in a copy key breaks placeholder parity: \(string)")
        }
    }

    func testCopyIsAKeyPerLanguageSoTheCardCanReResolveIt() {
        // The card hands each line to `Text(LocalizedStringKey(…))`, which is
        // what lets a live language change re-render it. That only works if the
        // presentation holds the *key*: a resolved value is not a catalog key in
        // any language but English, so the second lookup would be a no-op and
        // the copy would stay in the language it was built in.
        //
        // The presentation has no language input at all, which is the property
        // that makes this true. Asserted structurally and by resolution.
        LanguagePreferenceStore.save(.german)
        let card = PhotoRecoveryPresentation.limitedNoSelection
        XCTAssertEqual(card.title, "No Photos Shared Yet", "the card froze at the override language")

        // And the key really does resolve to a different, non-empty value in the
        // override language — so the assertion above is not passing because the
        // German translation happens to match the English.
        let germanTitle = L10n.string(card.title, language: .german)
        XCTAssertNotEqual(germanTitle, card.title, "German must differ from the key, or this proves nothing")
        XCTAssertFalse(germanTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        // Every line, not just the title: a step left resolved would read English
        // under VoiceOver and in the body.
        for step in PhotoRecoveryPresentation.accessReturnedNothing.steps {
            XCTAssertTrue(
                Self.recoveryKeys.contains(step),
                "a step is not an English key, so it cannot re-resolve: \(step)"
            )
        }
    }

    // MARK: - Helpers

    /// Every English copy key the card can render — titles, messages, steps, and
    /// action titles. Hardcoded because the English text *is* the catalog key.
    private static let recoveryKeys: [String] = [
        "No Photos Shared Yet",
        "TidyByte has permission to see some of your photos, but none are shared with it right now, so there is nothing to review. Pick the photos it can see, or switch it to Full Access in Settings.",
        "No Photos Found",
        "TidyByte has full photo access, but the library returned no photos. If the Photos app on this iPhone shows photos, that is a permissions problem, and the steps below reset it.",
        "Open the Photos app and check that your photos are still there.",
        "In Settings, turn TidyByte's Photos access off, then on again, and choose Full Access.",
        "Come back here and tap Try Again.",
        "No Albums Yet",
        "TidyByte has access to some of your photos, but none are shared with it yet, so there are no albums to list. Pick the photos it can see, or switch it to Full Access in Settings.",
        "Albums Need Full Access",
        "TidyByte can see your photos, but not your albums. With limited access, iOS does not let an app read or create albums, so choose Full Access in Settings to file photos into an album.",
        "Add More Photos",
        "Open Settings",
        "Try Again"
    ]

    /// Copy that does not exist in the catalog yet, so it is allowed to be
    /// untranslated — in *every* language at once, never partially. The
    /// translation pass emptied this set, so the branch above is strict for
    /// every key: a reworded English string now turns this sweep red instead of
    /// shipping English to part of the store.
    private static let awaitingTranslation: Set<String> = []

    private var allPresentations: [PhotoRecoveryPresentation] {
        [
            PhotoRecoveryPresentation.limitedNoSelection,
            PhotoRecoveryPresentation.accessReturnedNothing,
            PhotoRecoveryPresentation.limitedAlbums,
            PhotoRecoveryPresentation.limitedAlbumsNeedFullAccess
        ]
    }
}
