/**
 * The CLDR plural categories each shipped language actually uses.
 *
 * Derived from ICU through `Intl.PluralRules` rather than hand-maintained.
 *
 * This replaced a hand-written table that was duplicated verbatim in both
 * `build-catalog.mjs` and `check.mjs`, and was wrong in the same way in both:
 * it listed only `one`/`other` for Spanish, French, Italian, and Portuguese,
 * but CLDR gives those four a `many` category for exact integer millions
 * (1000000, 2000000, …).
 *
 * Two copies of one wrong table is the worst version of the problem. The
 * builder wrote the categories the table named; the checker validated against
 * the same table; so a missing `many` form was invisible to every gate. The
 * numbers still rendered — ICU just fell back to `other` — which is why nobody
 * noticed.
 *
 * Deriving it means the two scripts cannot disagree, and a CLDR update moves
 * both at once. The practical reachability is real: `"%lld megabytes"` is a
 * plural key, and a 1,000,000 MB library is a terabyte.
 */

/** The shipped languages, in the order the Settings picker shows them. */
export const LANGUAGES = [
  'en', 'hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa',
  'es', 'fr', 'de', 'pt-BR', 'it', 'ja', 'ko', 'zh-Hans', 'ru', 'ar', 'he',
];

/**
 * Order matters: the catalog writes variations in this order, and a stable
 * order keeps `git diff` on the 3.5 MB catalog readable.
 */
const CATEGORY_ORDER = ['zero', 'one', 'two', 'few', 'many', 'other'];

/** Categories ICU reports for a language, in `CATEGORY_ORDER`. */
export function pluralCategoriesFor(language) {
  const resolved = new Intl.PluralRules(language).resolvedOptions().pluralCategories;
  const set = new Set(resolved);
  return CATEGORY_ORDER.filter((category) => set.has(category));
}

/** Every shipped language mapped to its categories. */
export function pluralCategories() {
  return Object.fromEntries(LANGUAGES.map((language) => [language, pluralCategoriesFor(language)]));
}

/**
 * `true` when ICU's answer differs from the committed `_plural-keys.json`
 * baseline for a language. Used by `check.mjs` to fail loudly if a future ICU
 * or CLDR release changes the rules, instead of silently writing a partial set.
 */
export function pluralCategoriesDisagree(a, b) {
  if (!a || !b) return true;
  return a.length !== b.length || a.some((category, index) => category !== b[index]);
}
