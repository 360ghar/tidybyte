// Text that stays English on the localized landing pages.
//
// Shared by the extractor and the builder on purpose. The extractor leaves these
// out of `site-strings.json` so no translator is ever asked about them, and the
// builder has to know they were deliberately excluded — otherwise it finds a
// Latin-script string on the page with no translation, calls it untranslated,
// and fails the build for all 20 languages.
//
// Product names, Apple framework names and a version string. Translating any of
// them would be wrong in every language, which is what earns them a place here
// rather than a translation.

export const KEEP_LITERAL = new Set([
  "TidyByte",
  "TidyByte Free",
  "iOS 17+",
  "iPhone",
  "iPad",
  "App Store",
  "GitHub",
  "Vision",
  "Photos",
  "SHA-256",
  "WhatsApp",
  "Telegram",
  "1.0.5",
]);

/// True when a page string is deliberately not translated.
///
/// Matches the trimmed string exactly. A partial match would be wrong: the
/// string "Photos never leave your phone" contains "Photos" and must be
/// translated, while the bare legend label "Photos" must not.
export function isKeepLiteral(text) {
  return KEEP_LITERAL.has(text.trim());
}
