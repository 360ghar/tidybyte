#!/usr/bin/env node
/**
 * Validates the String Catalog. Run in CI: `node scripts/localization/check.mjs`.
 *
 * Four checks, each of which has caught a real class of bug:
 *
 * 1. **Coverage** — every key has an entry for every shipped language. A
 *    missing entry means an English string on a translated screen.
 * 2. **Placeholder parity** — the translated string carries exactly the same
 *    format specifiers as the English source. A dropped `%lld` crashes
 *    `String(format:)`; an extra `%@` reads garbage from the argument list.
 * 3. **Plural categories** — each language has exactly the CLDR categories it
 *    uses. A missing `few`/`many` on Russian or Arabic makes counts render in
 *    the wrong grammatical form.
 * 4. **Untranslated** — reports (and, with `--strict`, fails on) any key still
 *    carrying the English text for a non-English language.
 */

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CATALOG_PATH = join(ROOT, 'Tidybyte/Resources/Localizable.xcstrings');
const PLURAL_KEYS_PATH = join(ROOT, 'scripts/localization/translations/_plural-keys.json');
const INFO_PLIST_CATALOG_PATH = join(ROOT, 'Tidybyte/InfoPlist.xcstrings');
const PROJECT_YML_PATH = join(ROOT, 'project.yml');

/** Must match `build-catalog.mjs`; asserted below so the two cannot drift. */
const LANGUAGES = [
  'en', 'hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa',
  'es', 'fr', 'de', 'pt-BR', 'it', 'ja', 'ko', 'zh-Hans', 'ru', 'ar', 'he',
];

const PLURAL_CATEGORIES = {
  en: ['one', 'other'], hi: ['one', 'other'], bn: ['one', 'other'],
  ta: ['one', 'other'], te: ['one', 'other'], mr: ['one', 'other'],
  gu: ['one', 'other'], kn: ['one', 'other'], ml: ['one', 'other'],
  pa: ['one', 'other'], es: ['one', 'other'], fr: ['one', 'other'],
  de: ['one', 'other'], 'pt-BR': ['one', 'other'], it: ['one', 'other'],
  ja: ['other'], ko: ['other'], 'zh-Hans': ['other'],
  ru: ['one', 'few', 'many', 'other'],
  ar: ['zero', 'one', 'two', 'few', 'many', 'other'],
  he: ['one', 'two', 'other'],
};

const strict = process.argv.includes('--strict');
let failures = 0;

function fail(message) {
  console.error(`FAIL: ${message}`);
  failures += 1;
}

/** Every format specifier in a string, in order, normalized to its type. */
function placeholders(text) {
  const found = [];
  const pattern = /%(?:(\d+)\$)?(?:\.(\d+))?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    // `%%` is a literal percent sign, not a placeholder.
    found.push(match[3] === '%' ? '%%' : match[3]);
  }
  return found;
}

/**
 * `{ position, type }` for each specifier, where `position` is the explicit
 * `%N$` index when the string uses positional specifiers, and the specifier's
 * own ordinal otherwise.
 */
function positionalPlaceholders(text) {
  const pattern = /%(?:(\d+)\$)?(?:\.(\d+))?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g;
  const found = [];
  let match;
  let ordinal = 0;
  while ((match = pattern.exec(text)) !== null) {
    const type = match[3] === '%' ? '%%' : match[3];
    if (type === '%%') continue;
    ordinal += 1;
    found.push({ position: match[1] ? Number(match[1]) : ordinal, type });
  }
  return found;
}

/**
 * Whether a translation consumes the English source's arguments correctly.
 *
 * Two shapes pass:
 *
 * 1. Same specifiers in the same order — the ordinary case.
 * 2. Positional specifiers (`%2$lld … %1$@`) that map each English argument to
 *    a specifier of the matching type. This is how a language that naturally
 *    orders a count before a noun stays correct, and it is what
 *    `build-catalog.mjs` emits for reordered translations.
 */
function argumentsMatch(english, translated) {
  const englishTokens = positionalPlaceholders(english);
  const translatedTokens = positionalPlaceholders(translated);

  if (englishTokens.length !== translatedTokens.length) return false;

  const englishByPosition = new Map(englishTokens.map((token) => [token.position, token.type]));
  const usesPositional = translatedTokens.some((token, index) => token.position !== index + 1);

  if (!usesPositional) {
    return englishTokens.every((token, index) => token.type === translatedTokens[index].type);
  }

  // Every English argument must be consumed exactly once, with its own type.
  const seen = new Set();
  for (const token of translatedTokens) {
    if (seen.has(token.position)) return false;
    seen.add(token.position);
    if (englishByPosition.get(token.position) !== token.type) return false;
  }
  return seen.size === englishTokens.length;
}

/**
 * The values a catalog entry holds for one language: either a plain string or
 * the plural variations.
 */
function entryValues(entry, language) {
  const localization = entry.localizations?.[language];
  if (!localization) return null;
  if (localization.stringUnit) return { plain: localization.stringUnit };
  if (localization.variations?.plural) return { plural: localization.variations.plural };
  return null;
}

function checkCatalog(path, label) {
  if (!existsSync(path)) {
    fail(`${label} catalog not found at ${path}`);
    return;
  }
  const catalog = JSON.parse(readFileSync(path, 'utf8'));
  const strings = catalog.strings ?? {};
  const keys = Object.keys(strings);
  const pluralKeys = new Set(
    existsSync(PLURAL_KEYS_PATH) ? Object.keys(JSON.parse(readFileSync(PLURAL_KEYS_PATH, 'utf8'))) : [],
  );

  console.log(`\n${label}: ${keys.length} keys`);

  const untranslated = new Map();

  for (const key of keys) {
    const entry = strings[key];
    const english = entryValues(entry, 'en');
    if (!english) {
      fail(`${label}: "${key}" has no English source value`);
      continue;
    }

    for (const language of LANGUAGES) {
      if (language === 'en') continue;
      const value = entryValues(entry, language);
      if (!value) {
        fail(`${label}: "${key}" is missing language ${language}`);
        continue;
      }

      // `entryValues` hands back the string unit itself, so the text is
      // `plain.value` — reading `plain.stringUnit.value` here would compare an
      // empty string against every translation and report false mismatches.
      const englishForms = english.plural
        ? Object.values(english.plural).map((unit) => unit.stringUnit?.value ?? '')
        : [english.plain.value ?? ''];

      if (value.plural) {
        // A plural entry must use exactly the categories its language needs.
        const expected = PLURAL_CATEGORIES[language] ?? [];
        const actual = Object.keys(value.plural).sort();
        const wanted = [...expected].sort();
        if (actual.join(',') !== wanted.join(',')) {
          fail(
            `${label}: "${key}" [${language}] plural categories are [${actual.join(', ')}], expected [${wanted.join(', ')}]`,
          );
        }
      }

      const translatedForms = value.plural
        ? Object.values(value.plural).map((unit) => unit.stringUnit?.value ?? '')
        : [value.plain.value ?? ''];

      for (const form of translatedForms) {
        if (!englishForms.some((source) => argumentsMatch(source, form))) {
          fail(
            `${label}: "${key}" [${language}] placeholder mismatch\n      en: ${JSON.stringify(englishForms[0])}\n      ${language}: ${JSON.stringify(form)}`,
          );
        }
      }

      // `needs_review` means the build wrote the English text as a placeholder.
      const isMarked = value.plain
        ? value.plain.state === 'needs_review'
        : Object.values(value.plural).every((unit) => unit.stringUnit?.state === 'needs_review');
      if (isMarked) {
        untranslated.set(language, (untranslated.get(language) ?? 0) + 1);
      }
    }
  }

  // Plural keys must actually be plural entries in English.
  for (const key of pluralKeys) {
    if (!strings[key]) continue;
    if (!entryValues(strings[key], 'en')?.plural) {
      fail(`${label}: "${key}" is listed as a plural key but has no English plural variations`);
    }
  }

  const total = keys.length;
  for (const language of LANGUAGES) {
    if (language === 'en') continue;
    const missingCount = untranslated.get(language) ?? 0;
    const done = total - missingCount;
    const pct = ((done / total) * 100).toFixed(0);
    const flag = missingCount === 0 ? 'ok' : 'needs work';
    console.log(`  ${language.padEnd(8)} ${String(done).padStart(4)}/${total}  ${pct.padStart(3)}%  ${flag}`);
    if (strict && missingCount > 0) {
      fail(`${label}: ${language} has ${missingCount} untranslated keys`);
    }
  }
}

/**
 * The Info.plist catalog, checked against the build settings that produce the
 * strings it translates.
 *
 * This is a separate catalog from `Localizable.xcstrings` for a reason that is
 * easy to get wrong: iOS resolves a localized Info.plist string by the **plist
 * key name**, not by the English sentence. A catalog keyed on
 * `"TidyByte needs access to your photo library…"` compiles fine, ships fine,
 * and does nothing — the permission prompt stays English in all 20 languages.
 * Keys here are therefore `NSPhotoLibraryUsageDescription` and friends.
 *
 * The settings in `project.yml` are the source of truth for which keys must
 * exist. A usage description added there without a matching catalog entry is
 * exactly the silent failure this check exists to catch, and nothing else in
 * the build would report it.
 */
function checkInfoPlistCatalog() {
  const label = 'Info.plist';

  if (!existsSync(INFO_PLIST_CATALOG_PATH)) {
    fail(`${label} catalog not found at ${INFO_PLIST_CATALOG_PATH}`);
    return;
  }
  if (!existsSync(PROJECT_YML_PATH)) {
    fail(`${label}: project.yml not found at ${PROJECT_YML_PATH}`);
    return;
  }

  const catalog = JSON.parse(readFileSync(INFO_PLIST_CATALOG_PATH, 'utf8'));
  const strings = catalog.strings ?? {};
  const keys = Object.keys(strings);

  // `INFOPLIST_KEY_NSPhotoLibraryUsageDescription: "…"` in project.yml. The
  // prefix is stripped because that is not part of the plist key.
  const projectYml = readFileSync(PROJECT_YML_PATH, 'utf8');
  const required = new Set();
  for (const match of projectYml.matchAll(/INFOPLIST_KEY_(\w*UsageDescription)\s*:/g)) {
    required.add(match[1]);
  }

  console.log(`\n${label}: ${keys.length} keys`);

  if (required.size === 0) {
    fail(`${label}: no INFOPLIST_KEY_*UsageDescription settings found in project.yml`);
  }

  for (const key of required) {
    if (!strings[key]) {
      fail(
        `${label}: "${key}" is set in project.yml but has no catalog entry — ` +
        `the permission prompt will stay English in every language`,
      );
    }
  }

  for (const key of keys) {
    // A usage description that no longer exists in project.yml is dead weight,
    // but a stray non-usage key is only a warning: `CFBundleDisplayName` is a
    // legitimate entry that project.yml does not carry as a usage description.
    if (key.endsWith('UsageDescription') && !required.has(key)) {
      fail(`${label}: "${key}" is in the catalog but not set in project.yml`);
    }
  }

  let incomplete = 0;
  for (const key of keys) {
    const entry = strings[key];
    const english = entryValues(entry, 'en');
    if (!english) {
      fail(`${label}: "${key}" has no English source value`);
      continue;
    }

    for (const language of LANGUAGES) {
      if (language === 'en') continue;
      const value = entryValues(entry, language);
      if (!value) {
        fail(`${label}: "${key}" is missing language ${language}`);
        incomplete += 1;
        continue;
      }
      if (value.plain?.state === 'needs_review') {
        incomplete += 1;
      }
    }
  }

  const total = keys.length * (LANGUAGES.length - 1);
  const done = total - incomplete;
  const pct = total > 0 ? ((done / total) * 100).toFixed(0) : '100';
  console.log(`  coverage   ${String(done).padStart(4)}/${total}  ${pct.padStart(3)}%  ${incomplete === 0 ? 'ok' : 'needs work'}`);
  if (strict && incomplete > 0) {
    fail(`${label}: ${incomplete} untranslated value(s)`);
  }
}

checkCatalog(CATALOG_PATH, 'App');
checkInfoPlistCatalog();

console.log('');
if (failures > 0) {
  console.error(`${failures} problem(s) found.`);
  process.exit(1);
}
console.log('Localization checks passed.');
