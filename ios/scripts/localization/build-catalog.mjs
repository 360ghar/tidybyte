#!/usr/bin/env node
/**
 * Builds `Localizable.xcstrings` from three inputs:
 *
 * 1. The keys Xcode's own extractor found (`xcstringstool sync` output, already
 *    in the catalog when this runs after a build).
 * 2. The keys `extract.mjs` found, which covers the `L10n.*` calls Xcode cannot
 *    see because they are not SwiftUI `Text`/`Label` calls.
 * 3. `translations/<lang>.json` — the per-language translations, plus the
 *    plural forms in `translations/_plurals.json`.
 *
 * Run: node scripts/localization/build-catalog.mjs
 *
 * Deterministic and idempotent: running it twice produces the same file, and
 * re-running after adding a string only adds that string. It never invents a
 * translation — a key with no translation for a language is written with the
 * English text and marked `needs_review`, which Xcode surfaces as untranslated
 * so it cannot ship silently.
 */

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LANGUAGES, pluralCategories } from './plural-categories.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CATALOG_PATH = join(ROOT, 'Tidybyte/Resources/Localizable.xcstrings');
const APP_SHORTCUTS_CATALOG_PATH = 'Tidybyte/Resources/AppShortcuts.xcstrings';
const TRANSLATIONS_DIR = join(ROOT, 'scripts/localization/translations');

/**
 * Plural categories each language actually uses, per CLDR.
 *
 * Derived from ICU — see `plural-categories.mjs` for why the hand-written table
 * this replaced was a trap: it was duplicated in `check.mjs`, so both the
 * builder and the validator were wrong in the same way and no gate could catch
 * a missing category.
 */
const PLURAL_CATEGORIES = pluralCategories();

function readJSON(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return fallback;
  }
}

/**
 * The translations file for one language.
 *
 * A file that is absent is normal (a language not started yet) and yields `{}`.
 * A file that is present but does not parse is fatal: swallowing it produced
 * exactly the same `{}`, so a trailing comma in `translations/ml.json` rewrote
 * all 500-odd keys for Malayalam as `needs_review` and looked like a language
 * nobody had translated. `check.mjs` cannot see the difference either, because
 * the catalog it reads was already built wrong.
 */
function translationFile(language) {
  const path = join(TRANSLATIONS_DIR, `${language}.json`);
  if (!existsSync(path)) return {};
  const file = readJSON(path, undefined);
  if (file === undefined) {
    throw new Error(
      `${relative(ROOT, path)} exists but is not valid JSON; fix it before building the catalog`,
    );
  }
  return file;
}

function loadTranslations() {
  const byLanguage = new Map();
  for (const language of LANGUAGES) {
    if (language === 'en') continue;
    const file = translationFile(language);
    byLanguage.set(language, {
      strings: file.strings ?? {},
      plurals: file.plurals ?? {},
    });
  }
  return byLanguage;
}

/**
 * The English `one`/`other` forms for every counted string.
 *
 * Authored by hand rather than derived: English plural rules are trivial but
 * the *word* changes ("1 item" / "2 items", "1 photo" / "2 photos"), and the
 * per-language files are translated against these exact pairs.
 */
function loadPlurals() {
  return readJSON(join(TRANSLATIONS_DIR, '_plural-keys.json'), {});
}

function stringUnit(value, state = 'translated') {
  return { stringUnit: { state, value } };
}

/** Every format specifier in a string, in order, as `{ token, index }`. */
function scanPlaceholders(text) {
  const pattern = /%(?:(\d+)\$)?(?:\.(\d+))?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g;
  const found = [];
  let match;
  while ((match = pattern.exec(text)) !== null) {
    found.push({ token: match[3] === '%' ? '%%' : match[3], positional: match[1], raw: match[0] });
  }
  return found;
}

/**
 * Rewrites a translation's placeholders as positional specifiers when the
 * translator reordered them.
 *
 * This is not cosmetic. `String.localizedStringWithFormat` substitutes
 * arguments *positionally*, so a Chinese string that puts the count before the
 * text ("%lld 中的 %@") would feed the count into `%@` and the text into
 * `%lld` — a crash or garbage output. Writing `%2$lld 中的 %1$@` pins each
 * specifier to the argument the English source intended, which is exactly what
 * Xcode does when you reorder specifiers in the String Catalog editor.
 *
 * Reordering is only resolvable when the types are distinguishable. With two
 * `%@`s in one string there is no way to tell which moved, so the translation
 * is returned unchanged and `check.mjs` reports it.
 */
function positionalize(english, translated) {
  const englishTokens = scanPlaceholders(english);
  const translatedTokens = scanPlaceholders(translated);

  // Nothing to do when the order already matches, or the shapes differ (the
  // validator reports shape mismatches separately).
  if (englishTokens.length !== translatedTokens.length) return translated;
  if (englishTokens.every((token, index) => token.token === translatedTokens[index].token)) {
    return translated;
  }
  // Ambiguous when a type repeats: cannot map one occurrence onto another.
  //
  // `%%` is a literal percent, not an argument, so it is excluded from the base
  // the index is looked up in. Leaving it in shifted every placeholder after a
  // `%%` by one: "100%% of %@ saved by %lld MB" gave `%3$lld` and `%2$@` for a
  // translation that had swapped only the two real arguments.
  const englishTypes = englishTokens
    .filter((token) => token.token !== '%%')
    .map((token) => token.token);
  if (new Set(englishTypes).size !== englishTypes.length) return translated;

  // Walk the translated string, replacing each placeholder with the positional
  // form of the English argument it corresponds to.
  let result = '';
  let cursor = 0;
  const pattern = /%(?:(\d+)\$)?(?:\.(\d+))?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g;
  let match;
  while ((match = pattern.exec(translated)) !== null) {
    const type = match[3] === '%' ? '%%' : match[3];
    result += translated.slice(cursor, match.index);
    if (type === '%%') {
      result += '%%';
    } else {
      const englishIndex = englishTypes.indexOf(type);
      // Strip any leading `%` (and a positional prefix if one is already
      // there), then rebuild as `%N$<length modifiers><type>` — the `%` in
      // the output is the one from the prefix, not from the original.
      const bare = match[0].replace(/^%\d+\$/, '').slice(1);
      result += `%${englishIndex + 1}$${bare}`;
    }
    cursor = match.index + match[0].length;
  }
  result += translated.slice(cursor);
  return result;
}

/**
 * Builds one key's `localizations` object.
 *
 * `plural` carries the base English `one`/`other` forms when the key is a
 * counted string; without it a key is a plain string in every language.
 */
function localizationsFor(key, pluralForms, translations) {
  const localizations = {};

  const englishPlural = pluralForms?.[key];
  const isPlural = Boolean(englishPlural);

  for (const language of LANGUAGES) {
    if (language === 'en') {
      if (isPlural) {
        const categories = {};
        for (const category of PLURAL_CATEGORIES.en) {
          // `one` and `other` are the two English needs; any other required
          // category falls back to `other`.
          const value = englishPlural[category] ?? englishPlural.other;
          if (value) categories[category] = stringUnit(value);
        }
        localizations.en = { variations: { plural: categories } };
      } else {
        localizations.en = stringUnit(key);
      }
      continue;
    }

    const translation = translations.get(language) ?? { strings: {}, plurals: {} };

    if (isPlural) {
      const forms = translation.plurals?.[key];
      const categories = {};
      for (const category of PLURAL_CATEGORIES[language]) {
        const value = forms?.[category];
        if (value) {
          // Positionalize against the matching English category, so a
          // reordered plural form is pinned to the right arguments too.
          const englishForm = englishPlural[category] ?? englishPlural.other ?? key;
          categories[category] = stringUnit(positionalize(englishForm, value));
        }
      }
      if (Object.keys(categories).length > 0) {
        localizations[language] = { variations: { plural: categories } };
        continue;
      }
      // No plural forms supplied yet: fall through so the key still resolves
      // (to English) instead of disappearing from the catalog.
    }

    const translated = translation.strings?.[key];
    if (typeof translated === 'string' && translated.length > 0) {
      localizations[language] = isPlural
        ? { variations: { plural: { other: stringUnit(positionalize(key, translated)) } } }
        : stringUnit(positionalize(key, translated));
    } else if (!localizations[language]) {
      // Present but untranslated: Xcode shows this as a language needing work
      // instead of silently dropping the key.
      localizations[language] = stringUnit(key, 'needs_review');
    }
  }

  return localizations;
}

/**
 * Writes `AppShortcuts.xcstrings` — the catalog Siri phrases resolve through.
 *
 * This is a separate file from `Localizable.xcstrings`, and that separation is
 * the whole point. App Intents looks phrases up in a table named `AppShortcuts`,
 * which the compiler emits into `ExtractedAppShortcutsMetadata.stringsdata`.
 * Keys written into the app catalog instead are never looked up: the catalog
 * then reports 100% coverage for strings nothing can reach, and Siri speaks
 * English in every language. That is not hypothetical — it is the bug this
 * function exists to prevent.
 *
 * The shape is a `stringSet`, not a `stringUnit`. Each key carries a `values`
 * array holding every phrase for that shortcut, with the key itself repeated as
 * the first element. Those alternates are additional utterances Siri matches,
 * not separate keys, so a language with a missing alternate loses a way to
 * trigger the shortcut rather than breaking the lookup.
 *
 * `en` comes from the same file as the translations, and `extract.mjs` checks it
 * against the Swift source, so the Swift file stays the source of truth.
 */
function writeAppShortcutsCatalog() {
  const source = readJSON(join(TRANSLATIONS_DIR, '_app-shortcuts.json'), null);
  if (!source) {
    console.log('App Shortcuts: no _app-shortcuts.json, catalog not written');
    return;
  }

  const english = source.en ?? {};
  const keys = Object.keys(english).filter((key) => !key.startsWith('_'));
  const strings = {};
  let missing = 0;

  for (const key of keys) {
    const englishPhrases = english[key];
    const localizations = {
      en: { stringSet: { state: 'translated', values: englishPhrases } },
    };

    for (const language of LANGUAGES) {
      if (language === 'en') continue;
      const phrases = source[language]?.[key];
      if (Array.isArray(phrases) && phrases.length === englishPhrases.length) {
        localizations[language] = { stringSet: { state: 'translated', values: phrases } };
      } else {
        // Fall back to the English set rather than dropping the language, so
        // the key still resolves. `state: 'needs_review'` is what makes Xcode
        // and `check.mjs` show it as outstanding work.
        localizations[language] = { stringSet: { state: 'needs_review', values: englishPhrases } };
        missing += 1;
      }
    }

    strings[key] = { extractionState: 'extracted_with_value', localizations };
  }

  writeFileSync(
    join(ROOT, APP_SHORTCUTS_CATALOG_PATH),
    JSON.stringify({ sourceLanguage: 'en', strings, version: '1.0' }, null, 2) + '\n',
  );

  const total = keys.length * (LANGUAGES.length - 1);
  const done = total - missing;
  const pct = total > 0 ? ((done / total) * 100).toFixed(0) : '100';
  console.log(
    `App Shortcuts catalog: ${keys.length} phrase(s), ${done}/${total} translations (${pct}%)`,
  );
}

function main() {
  const catalog = readJSON(CATALOG_PATH, { sourceLanguage: 'en', strings: {}, version: '1.0' });
  const found = readJSON(join(ROOT, 'scripts/localization/strings.found.json'), { keys: [] });

  const xcode = readJSON(join(ROOT, 'scripts/localization/strings.xcode.json'), null);
  const translations = loadTranslations();
  const plurals = loadPlurals();

  // Start from what Xcode's extractor already put in the catalog — it is the
  // authority for SwiftUI literals — then add the `L10n` keys it cannot see.
  //
  // The live set is the union of the three things that can produce a lookup:
  // a SwiftUI literal (Xcode's `.stringsdata`), an `L10n` call (our scanner), or
  // a counted string (the plural keys). Anything in the catalog but outside that
  // union is dead: no call site can ever look it up.
  //
  // Pruning matters more than it looks. `xcstringstool sync` never removes a key
  // whose source text was deleted or rewritten, so without this the catalog only
  // grows, every language's percentage is flattered by dead entries, and a
  // genuinely missing translation hides inside the total. `strings.xcode.json`
  // is written by `collect-xcode-keys.mjs`, which `refresh.sh` runs after the
  // build; without it there is no way to tell a live Xcode key from a stale one,
  // so pruning is skipped rather than guessed at.
  const live = new Set();
  for (const entry of found.keys ?? []) live.add(entry.key);
  for (const key of Object.keys(plurals)) live.add(key);
  const canPrune = Array.isArray(xcode?.keys);
  if (canPrune) {
    for (const key of xcode.keys) live.add(key);
  }

  const keys = new Map();
  const pruned = [];
  for (const key of Object.keys(catalog.strings ?? {})) {
    // Xcode's extractor emits an empty key for some interpolated-only calls.
    // It is not a real lookup and translating it is meaningless.
    if (!key.trim()) continue;
    if (canPrune && !live.has(key)) {
      pruned.push(key);
      continue;
    }
    keys.set(key, true);
  }
  for (const entry of found.keys ?? []) keys.set(entry.key, true);
  for (const key of Object.keys(plurals)) keys.set(key, true);

  const strings = {};
  for (const key of [...keys.keys()].sort()) {
    strings[key] = { localizations: localizationsFor(key, plurals, translations) };
  }

  writeFileSync(
    CATALOG_PATH,
    JSON.stringify({ sourceLanguage: 'en', strings, version: '1.0' }, null, 2) + '\n',
  );

  const pluralCount = Object.keys(plurals).length;
  console.log(`Catalog written: ${Object.keys(strings).length} keys (${pluralCount} plural)`);
  if (pruned.length > 0) {
    console.log(`Pruned ${pruned.length} dead key(s) no call site can reach:`);
    for (const key of pruned) console.log(`  ${JSON.stringify(key)}`);
  } else if (!canPrune) {
    console.log('  (pruning skipped: run collect-xcode-keys.mjs to enable it)');
  }
  for (const language of LANGUAGES) {
    if (language === 'en') continue;
    const translated = Object.keys(strings).filter((key) => {
      const loc = strings[key].localizations[language];
      if (!loc) return false;
      if (loc.stringUnit?.state === 'needs_review') return false;
      return true;
    }).length;
    const pct = ((translated / Object.keys(strings).length) * 100).toFixed(0);
    console.log(`  ${language.padEnd(8)} ${String(translated).padStart(4)}/${Object.keys(strings).length}  ${pct}%`);
  }

  writeAppShortcutsCatalog();
}

main();
