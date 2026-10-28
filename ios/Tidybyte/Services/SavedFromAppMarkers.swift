import Foundation

/// Filename markers that identify media saved from a messaging or social app.
///
/// Split out of `PhotoLibraryService.detectOrigin` so the list can be unit
/// tested directly. It is a pure string-matching rule with no PhotoKit
/// dependency, which makes it the one part of origin detection that is cheap to
/// verify — and the part most likely to need adjusting as apps change their
/// naming.
///
/// ## Why this is broad
///
/// The category these markers feed ("Saved from Apps") is deliberately
/// recall-leaning: `detectOrigin` also treats any image that matches neither a
/// camera nor a screenshot signature as saved from an app. A false positive
/// costs the user a glance in a review list, while a false negative hides a
/// file they were trying to find. The markers exist to raise confidence on the
/// obvious cases, not to gate the category.
///
/// ## Why this covers more than the US
///
/// The original list held only the apps dominant in North America and Western
/// Europe — WhatsApp, Facebook, Instagram, Telegram, Snapchat. Someone in Tokyo
/// saves photos from LINE, in Seoul from KakaoTalk, in Shanghai from WeChat, in
/// Kyiv from Viber, in Mumbai from ShareIt. For those users the marker list
/// matched almost nothing, so the category fell back to its generic rule and
/// surfaced a noisier set. Adding the region-dominant apps makes the feature
/// behave the same everywhere.
///
/// Matching is not filtered by the device's region. A user's library can
/// contain exports from an app they used while travelling, and a marker that
/// matches costs nothing when it does not appear. One list, no region lookup.
///
/// ## Why the list is split in two
///
/// Some markers are only distinctive at the **start** of a filename, and some
/// are distinctive anywhere. `LINE_` is the clearest case: matching it anywhere
/// also matches `TIMELINE_1.jpg`, `ONLINE_1.jpg` and `NEWLINE_1.jpg`, because
/// all three happen to end in those five characters. LINE's own exports always
/// begin with it, so anchoring to the start keeps every real match and drops
/// the accidents. The same reasoning moved `QQ_`, `IMO_`, `RECEIVED_`,
/// `DOWNLOAD` and `IMG-` into the prefix list, and reduced WhatsApp's marker to
/// the hyphenated `-WA` that its filenames actually carry, which stops it
/// firing on `AWARD_1.jpg`.
enum SavedFromAppMarkers {
    /// Matched against the **start** of an uppercased filename.
    ///
    /// Every entry here appears inside ordinary words, so a substring match
    /// would misfire on filenames that have nothing to do with the app.
    static let prefixes: [String] = [
        "LINE_",        // LINE album export: LINE_ALBUM_20240101_1.jpg
        "LINE-",        // LINE, hyphenated variant
        "QQ_",          // Tencent QQ
        "IMO_",         // imo
        "IMO-",
        "RECEIVED_",    // generic Android share target
        "DOWNLOAD",     // generic Android download
        "IMG-",         // Android export shape: IMG-20240101-WA0001.jpg
    ]

    /// Matched **anywhere** in an uppercased filename.
    ///
    /// Each entry is long enough, or distinctive enough, that no ordinary
    /// filename contains it by accident.
    static let substrings: [String] = [
        // Global
        "-WA",          // WhatsApp: IMG-20240101-WA0001.jpg, VID-20240101-WA0001.mp4
        "WHATSAPP",     // spelled out, seen in some Android exports
        "FB_IMG",       // Facebook
        "MESSENGER",    // Facebook Messenger
        "INSTA",        // Instagram
        "TELEGRAM",     // Telegram
        "SNAPCHAT",     // Snapchat
        "SIGNAL",       // Signal: signal-2024-01-01-120000.jpg
        "DISCORD",      // Discord
        "TIKTOK",       // TikTok

        // China
        "MMEXPORT",     // WeChat saved-from-chat export: mmexport1704067200000.jpg
        "WX_CAMERA",    // WeChat in-app camera: wx_camera_1704067200000.jpg
        "WEIXIN",       // WeChat, alternate spelling
        "WEIBO",        // Weibo
        "DOUYIN",       // Douyin (the mainland TikTok)

        // Korea
        "KAKAO",        // KakaoTalk, KakaoStory: KakaoTalk_20240101_120000.jpg
        "NAVER",        // Naver, Naver Blog

        // South Asia
        "SHAREIT",      // ShareIt, still widely used for phone-to-phone transfer

        // Middle East, Eastern Europe, South Asia
        "VIBER",        // Viber: viber_image_2024-01-01_12-00-00.jpg
        "ZALO",         // Zalo, Vietnam
    ]

    /// Every marker, whichever list it came from. The hygiene tests below have
    /// to cover the whole set, not one half of it.
    static var all: [String] { prefixes + substrings }

    /// True when `filename` carries a marker for an app-saved file.
    ///
    /// Callers pass the raw filename; the uppercasing happens here so no caller
    /// can forget it and silently match nothing.
    static func matches(filename: String?) -> Bool {
        guard let filename, !filename.isEmpty else { return false }
        let name = filename.uppercased()
        if prefixes.contains(where: { name.hasPrefix($0) }) { return true }
        return substrings.contains { name.contains($0) }
    }
}
