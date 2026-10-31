import XCTest
@testable import Tidybyte

/// Covers the filename marker list behind origin detection.
///
/// The list feeds the "Saved from Apps" category, which is the one cleanup
/// surface whose usefulness depends entirely on recognizing a user's apps. A
/// marker that stops matching silently empties the category for everyone using
/// that app, and nothing else in the suite would notice.
final class SavedFromAppMarkersTests: XCTestCase {

    // MARK: - Region coverage

    /// The messengers dominant in the regions this app ships languages for.
    /// Each entry is a real filename shape that app produces, so the test fails
    /// if a marker is ever narrowed or dropped.
    func testMatchesAppsDominantOutsideNorthAmerica() {
        let samples: [(app: String, filename: String)] = [
            ("LINE", "LINE_ALBUM_20240101_1.jpg"),
            ("WeChat", "mmexport1704067200000.jpg"),
            ("WeChat camera", "wx_camera_1704067200000.jpg"),
            ("KakaoTalk", "KakaoTalk_20240101_120000123.jpg"),
            ("Naver", "NAVER_20240101.jpg"),
            ("Viber", "viber_image_2024-01-01_12-00-00.jpg"),
            ("ShareIt", "shareit_1704067200000.jpg"),
            ("Zalo", "zalo_1704067200000.jpg"),
            ("Weibo", "weibo_1704067200000.jpg"),
            ("Douyin", "douyin_1704067200000.jpg"),
            ("imo", "imo_1704067200000.jpg"),
        ]

        for sample in samples {
            XCTAssertTrue(
                SavedFromAppMarkers.matches(filename: sample.filename),
                "\(sample.app) filename should match: \(sample.filename)"
            )
        }
    }

    /// The apps the original list covered. These must keep working — the
    /// refactor that widened the list was not allowed to narrow it.
    func testMatchesOriginallyCoveredApps() {
        let samples = [
            "IMG-20240101-WA0001.jpg",   // WhatsApp
            "FB_IMG_1704067200000.jpg",  // Facebook
            "INSTA_1704067200000.jpg",   // Instagram
            "TELEGRAM_1704067200000.jpg",
            "SNAPCHAT_1704067200000.jpg",
            "RECEIVED_1704067200000.jpg",
            "DOWNLOAD_1704067200000.jpg",
        ]

        for filename in samples {
            XCTAssertTrue(
                SavedFromAppMarkers.matches(filename: filename),
                "should still match: \(filename)"
            )
        }
    }

    // MARK: - Case and emptiness

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(SavedFromAppMarkers.matches(filename: "line_album_1.jpg"))
        XCTAssertTrue(SavedFromAppMarkers.matches(filename: "kakaotalk_1.jpg"))
        XCTAssertTrue(SavedFromAppMarkers.matches(filename: "Viber_image_1.jpg"))
    }

    func testEmptyAndNilFilenamesDoNotMatch() {
        XCTAssertFalse(SavedFromAppMarkers.matches(filename: nil))
        XCTAssertFalse(SavedFromAppMarkers.matches(filename: ""))
    }

    // MARK: - Ambiguous markers must not over-fire

    /// Some markers are only distinctive at the start of a filename. These
    /// assertions pin that down: `LINE_` matches `TIMELINE_1.jpg` when searched
    /// for anywhere, and a bare `WA` matches `AWARD_1.jpg`. Both regressed once
    /// already, so the innocent filenames stay in the suite.
    func testOrdinaryFilenamesDoNotMatch() {
        let innocent = [
            "TIMELINE_1.jpg",     // ends in the "LINE_" marker
            "ONLINE_1.jpg",       // same
            "NEWLINE_1.jpg",      // same
            "KIMONO_1.jpg",       // would match a bare "IMO"
            "CINEMO_1.jpg",       // same
            "AWARD_1.jpg",        // would match a bare "WA"
            "WATER_1.jpg",        // same
            "IMG_1234.HEIC",      // camera: underscore, not the "IMG-" marker
            "DSC_0001.JPG",       // camera
            "PXL_20240101_120000.jpg", // camera (Pixel)
            "IMG_1234.DNG",       // camera (ProRAW)
        ]

        for filename in innocent {
            XCTAssertFalse(
                SavedFromAppMarkers.matches(filename: filename),
                "should not match: \(filename)"
            )
        }
    }

    /// The prefix list earns its place only if every entry is matched at the
    /// start. Asserting the two lists apart catches an entry moved to
    /// `substrings` for convenience, which would silently reintroduce the
    /// false positives above.
    func testPrefixMarkersMatchOnlyAtTheStart() {
        for marker in SavedFromAppMarkers.prefixes {
            XCTAssertTrue(
                SavedFromAppMarkers.matches(filename: marker + "20240101.jpg"),
                "prefix marker must match at the start: \(marker)"
            )
            XCTAssertFalse(
                SavedFromAppMarkers.matches(filename: "X" + marker + "20240101.jpg"),
                "prefix marker must not match mid-filename: \(marker)"
            )
        }
    }

    /// WhatsApp's marker is the hyphenated `-WA`, which is how its filenames
    /// actually carry it. Both shapes it produces must keep matching.
    func testWhatsAppMarkersStillMatch() {
        for filename in [
            "IMG-20240101-WA0001.jpg",
            "VID-20240101-WA0001.mp4",
            "img-20240101-wa0001.jpg",
        ] {
            XCTAssertTrue(
                SavedFromAppMarkers.matches(filename: filename),
                "WhatsApp filename should match: \(filename)"
            )
        }
    }

    // MARK: - List hygiene

    /// Every marker must be uppercase, because matching uppercases the filename
    /// before comparing. A lowercase entry would be dead code that never fires.
    func testEveryMarkerIsUppercase() {
        for marker in SavedFromAppMarkers.all {
            XCTAssertEqual(
                marker, marker.uppercased(),
                "marker must be uppercase to ever match: \(marker)"
            )
        }
    }

    /// A marker shorter than two characters would match almost any filename.
    /// The shortest intentional entry is `WA`.
    func testNoMarkerIsTooShortToBeMeaningful() {
        for marker in SavedFromAppMarkers.all {
            XCTAssertGreaterThanOrEqual(
                marker.count, 2,
                "marker is too short to be distinctive: \(marker)"
            )
        }
    }

    func testNoDuplicateMarkers() {
        let markers = SavedFromAppMarkers.all
        XCTAssertEqual(
            markers.count, Set(markers).count,
            "duplicate marker in the list: \(markers)"
        )
    }
}
