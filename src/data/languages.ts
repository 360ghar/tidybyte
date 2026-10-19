// Languages the marketing site is published in.
//
// The set is the same one the iOS app ships (`Tidybyte/Shared/Localization/
// AppLanguage.swift`). Keeping them identical matters for more than tidiness:
// the App Store listing, the app's UI, and this site all describe the same
// product, and a language that exists in one but not the others sends a user
// who taps through to a page they cannot read.
//
// `code` is the app's language code and the source of truth. `slug` is the URL
// segment — lowercased, because search engines treat paths case-sensitively and
// a mixed-case segment invites duplicate URLs. `htmlLang` is what goes in
// `<html lang>`, which is what screen readers and search engines actually read.

export interface SiteLanguage {
  /** Matches `AppLanguage.rawValue` in the iOS app. */
  code: string;
  /** URL segment: `/de/`, `/pt-br/`. */
  slug: string;
  /** BCP-47 tag for `<html lang>` and `hreflang`. */
  htmlLang: string;
  /** The language's own name, for the language switcher. */
  endonym: string;
  /** Right-to-left script: the layout mirrors. */
  rtl: boolean;
  /** `og:locale` format, e.g. `de_DE`. */
  ogLocale: string;
}

/** The base language. It has no URL prefix — `/` is English. */
export const BASE_LANGUAGE: SiteLanguage = {
  code: "en",
  slug: "",
  htmlLang: "en",
  endonym: "English",
  rtl: false,
  ogLocale: "en_US",
};

/**
 * Every non-base language, in the order the switcher shows them.
 *
 * Indian languages first, then European, then CJK and RTL — the same order the
 * app's Settings picker uses, so a user who picked a language in the app finds
 * it in the same place here.
 */
export const SITE_LANGUAGES: SiteLanguage[] = [
  { code: "hi", slug: "hi", htmlLang: "hi", endonym: "हिन्दी", rtl: false, ogLocale: "hi_IN" },
  { code: "bn", slug: "bn", htmlLang: "bn", endonym: "বাংলা", rtl: false, ogLocale: "bn_IN" },
  { code: "ta", slug: "ta", htmlLang: "ta", endonym: "தமிழ்", rtl: false, ogLocale: "ta_IN" },
  { code: "te", slug: "te", htmlLang: "te", endonym: "తెలుగు", rtl: false, ogLocale: "te_IN" },
  { code: "mr", slug: "mr", htmlLang: "mr", endonym: "मराठी", rtl: false, ogLocale: "mr_IN" },
  { code: "gu", slug: "gu", htmlLang: "gu", endonym: "ગુજરાતી", rtl: false, ogLocale: "gu_IN" },
  { code: "kn", slug: "kn", htmlLang: "kn", endonym: "ಕನ್ನಡ", rtl: false, ogLocale: "kn_IN" },
  { code: "ml", slug: "ml", htmlLang: "ml", endonym: "മലയാളം", rtl: false, ogLocale: "ml_IN" },
  { code: "pa", slug: "pa", htmlLang: "pa", endonym: "ਪੰਜਾਬੀ", rtl: false, ogLocale: "pa_IN" },
  { code: "es", slug: "es", htmlLang: "es", endonym: "Español", rtl: false, ogLocale: "es_ES" },
  { code: "fr", slug: "fr", htmlLang: "fr", endonym: "Français", rtl: false, ogLocale: "fr_FR" },
  { code: "de", slug: "de", htmlLang: "de", endonym: "Deutsch", rtl: false, ogLocale: "de_DE" },
  { code: "pt-BR", slug: "pt-br", htmlLang: "pt-BR", endonym: "Português (Brasil)", rtl: false, ogLocale: "pt_BR" },
  { code: "it", slug: "it", htmlLang: "it", endonym: "Italiano", rtl: false, ogLocale: "it_IT" },
  { code: "ja", slug: "ja", htmlLang: "ja", endonym: "日本語", rtl: false, ogLocale: "ja_JP" },
  { code: "ko", slug: "ko", htmlLang: "ko", endonym: "한국어", rtl: false, ogLocale: "ko_KR" },
  { code: "zh-Hans", slug: "zh-hans", htmlLang: "zh-Hans", endonym: "简体中文", rtl: false, ogLocale: "zh_CN" },
  { code: "ru", slug: "ru", htmlLang: "ru", endonym: "Русский", rtl: false, ogLocale: "ru_RU" },
  { code: "ar", slug: "ar", htmlLang: "ar", endonym: "العربية", rtl: true, ogLocale: "ar_SA" },
  { code: "he", slug: "he", htmlLang: "he", endonym: "עברית", rtl: true, ogLocale: "he_IL" },
];

/** Base language first, then the rest — the order used everywhere else. */
export const ALL_LANGUAGES: SiteLanguage[] = [BASE_LANGUAGE, ...SITE_LANGUAGES];

export function languageBySlug(slug: string): SiteLanguage | undefined {
  return ALL_LANGUAGES.find((l) => l.slug === slug);
}

/**
 * Routes that exist in every language.
 *
 * Deliberately just the landing page for now. Translating 40+ blog posts into
 * 20 languages would multiply the maintenance surface without a matching
 * audience — a translated post that goes stale is worse for trust than an
 * English one that is current. The landing page is what an App Store visitor
 * and a search result actually land on, so that is what gets translated, and
 * `hreflang` is only emitted for pages that genuinely exist in both languages.
 * Claiming an alternate that 404s is a search-engine penalty.
 */
export const TRANSLATED_ROUTES = ["/"];
