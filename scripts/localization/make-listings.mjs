#!/usr/bin/env node
// Scaffolds docs/appstore/listings.json from the English copy in
// docs/APP_STORE_LISTING.md.
//
// This is a SCAFFOLD, and it is safe to rerun. Only the `en` entry comes from
// the doc; every other entry is carried forward from the file already on disk,
// so the 20 translated listings survive a rerun after the English copy changes.
// Clearing a translated field takes `--force`, and that is the only way it can
// happen: a scaffold that blanks twenty languages of hand-translated copy on
// its next run is a data-loss bug, not a convenience.
//
// The doc's §1-§4 and §12 copy is the source for `en`, so editing those
// sections and rerunning this script is the normal workflow (see
// docs/APP_STORE_LISTING.md, "Localized listings").
//
// Run: node scripts/localization/make-listings.mjs [--out <path>] [--force]

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const args = process.argv.slice(2);
const force = args.includes('--force');
const outFlag = args.indexOf('--out');
if (outFlag !== -1 && !args[outFlag + 1]) {
  console.error('usage: make-listings.mjs [--out <path>] [--force]');
  process.exit(2);
}

/** `--out` exists so this can run against a copy: it rewrites the whole file. */
const OUT = outFlag === -1 ? join(ROOT, 'docs/appstore/listings.json') : resolve(args[outFlag + 1]);

/** Hard limits App Store Connect enforces. A value over the limit is rejected. */
const LIMITS = {
  name: 30,
  subtitle: 30,
  promotionalText: 170,
  description: 4000,
  keywords: 100,
  whatsNew: 4000,
};

/**
 * The fields the scaffold can pre-fill for `en` and can only carry forward for
 * every other language. `name` is deliberately absent: it is the brand, and the
 * scaffold fills it in every entry rather than asking for 20 translations of a
 * word that must never be translated.
 */
const TRANSLATED = ['subtitle', 'promotionalText', 'description', 'keywords', 'whatsNew'];

const LANGUAGES = [
  'hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa',
  'es', 'fr', 'de', 'pt-BR', 'it', 'ja', 'ko', 'zh-Hans', 'ru', 'ar', 'he',
];

const doc = readFileSync(join(ROOT, 'docs/APP_STORE_LISTING.md'), 'utf8');

/** Pulls the first fenced block after a heading, so the doc stays the source. */
function blockAfter(heading) {
  const section = doc.split(heading)[1];
  if (!section) throw new Error(`heading not found in APP_STORE_LISTING.md: ${heading}`);
  const fenced = section.split('```')[1];
  if (!fenced) throw new Error(`no fenced block under: ${heading}`);
  return fenced.trim();
}

const english = {
  name: 'TidyByte',
  // Option I in docs/APP_STORE_LISTING.md §1, the one marked "In use" and the
  // one docs/appstore/listings.json ships. Option H was the earlier working
  // default and must not be reintroduced here: regenerating would then publish
  // stale ASO copy.
  subtitle: 'Clean photos, free up storage',
  promotionalText: blockAfter('## 2. Promotional Text'),
  description: blockAfter('## 3. Description'),
  // Read from §4, like the other three doc-backed fields: that section is where
  // the shipped keyword field lives, and the script header says editing §1-§4
  // and rerunning is the normal workflow. A hardcoded copy here was a second
  // source of truth, so a §4 edit regenerated the *old* keywords and quietly
  // reverted the doc — which is exactly the drift §4's rationale paragraph
  // records. `blockAfter` returns the first fenced block under the heading,
  // which §4 labels as the shipped set.
  keywords: blockAfter('## 4. Keywords'),
  whatsNew: blockAfter('## 12. What'),
};

/**
 * Reads the file this script is about to replace, so its translations can be
 * carried forward. `{}` only for a genuinely absent file (first run on a clean
 * checkout). A malformed file is fatal: falling back to `{}` would blank every
 * translation in the file this scaffold exists to preserve.
 */
function readExisting(path) {
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    console.error(`FAIL: ${path} is malformed and cannot be read: ${error.message}`);
    console.error('      fix or move it first; scaffolding from scratch would blank the');
    console.error('      translations it holds.');
    process.exit(1);
  }
}

const existing = readExisting(OUT);
const carried = [];
const blanked = [];
const replaced = [];

/**
 * The value to write for one field.
 *
 * A value the scaffold has wins (for `en` that is the doc, which is the point
 * of the script). An empty scaffold value never replaces text already in the
 * file, because the non-`en` entries exist to hold twenty languages of
 * translated copy the scaffold knows nothing about. `--force` is the explicit
 * override for clearing a field on purpose.
 */
function mergeField(language, field, scaffoldValue, existingValue) {
  const label = `${language}.${field}`;
  if (typeof scaffoldValue === 'string' && scaffoldValue.trim() !== '') {
    // Replacing text that is already there is the intended behaviour for `en`,
    // but it is worth naming: the doc and the shipped file can drift (the doc
    // §3 copy is currently behind `en.description`), and a silent overwrite of
    // published copy is how a sentence disappears.
    if (typeof existingValue === 'string' && existingValue.trim() !== '' && existingValue !== scaffoldValue) {
      replaced.push(label);
    }
    return scaffoldValue;
  }
  if (typeof existingValue !== 'string' || existingValue.trim() === '') return '';

  if (force) {
    blanked.push(label);
    return '';
  }
  carried.push(label);
  return existingValue;
}

const en = {};
for (const field of ['name', ...TRANSLATED]) {
  en[field] = mergeField('en', field, english[field], existing.en?.[field]);
}

const listings = {};
for (const code of LANGUAGES) {
  const previous = existing[code] ?? {};
  const entry = {
    // Pre-filled, not left blank: the app name is the brand and is the same
    // word in every storefront. Leaving it empty would make the validator
    // report 20 missing fields that must never be translated.
    name: english.name,
  };
  for (const field of TRANSLATED) {
    entry[field] = mergeField(code, field, '', previous[field]);
  }
  listings[code] = entry;
}

// A language this scaffold does not know about is kept rather than dropped.
// Removing it here would look exactly like the translations were never written,
// and check-listings.mjs is the place that fails on an unexpected locale.
const unexpected = Object.keys(existing).filter(
  (key) => !key.startsWith('_') && key !== 'en' && !LANGUAGES.includes(key),
);
if (unexpected.length > 0) {
  console.error(`WARNING: keeping ${unexpected.length} language(s) this script does not know: ${unexpected.join(', ')}`);
  console.error('         check-listings.mjs will fail on them until they are fixed or added here.');
}

const out = {
  _comment:
    'App Store Connect localizations for TidyByte. One entry per storefront language. The limits below are App Store Connect hard limits: a value over the limit is rejected at submission, so check-listings.mjs validates every field. The en entry is the source of truth; every other entry is a translation of it. name is the brand and stays TidyByte in every language.',
  _limits: LIMITS,
  _pendingDecision:
    'The subtitle decision is CLOSED: option I, "Clean photos, free up storage" (29 chars), ships in all 21 locales. It replaced the earlier working default, option H "Photo cleaner, free space", because it is verb-forward and names the storage outcome rather than just space. The 20 localized values were rewritten for I (see scripts/localization/translations/_subtitle-change.mjs) and are machine-drafted: they carry each language previous phrasing forward with the verb-forward shift, but have not had a native review pass. The keywords field is tuned against the subtitle: Apple indexes name, subtitle and keywords together, so a word already in the subtitle must not repeat in keywords. Five keyword fields were re-derived when the subtitle changed - en, bn, de, ar, he. If the subtitle changes again, change every subtitle here and re-derive the keyword fields. Separately, en.keywords was changed on 2026-10-26 to drop \'gallery\' for \'ai\' and \'cleaner\' (see docs/APP_STORE_LISTING.md section 4); the 20 translated keyword fields were left as they were, so this is the only field that differs from its translation source.',
  en,
  ...listings,
  ...Object.fromEntries(unexpected.map((key) => [key, existing[key]])),
};

writeFileSync(OUT, JSON.stringify(out, null, 2) + '\n');

console.log(`written ${OUT}`);
if (Object.keys(existing).length === 0) {
  console.log('  no readable listings file yet: every non-en field starts empty');
} else {
  console.log(`  carried forward ${carried.length} translated field(s) from the existing file`);
}
if (blanked.length > 0) {
  console.error(`  FORCED EMPTY ${blanked.length} field(s) because of --force:`);
  for (const label of blanked) console.error(`    ${label}`);
}
if (replaced.length > 0) {
  console.log(`  replaced ${replaced.length} existing field(s) with the doc's copy:`);
  for (const label of replaced) console.log(`    ${label}`);
}
for (const [field, limit] of Object.entries(LIMITS)) {
  const used = en[field].length;
  const flag = used <= limit ? 'ok' : 'OVER LIMIT';
  console.log(`  en.${field.padEnd(16)} ${String(used).padStart(4)}/${limit}  ${flag}`);
}
