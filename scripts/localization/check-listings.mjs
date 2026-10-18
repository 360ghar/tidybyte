// Validates docs/appstore/listings.json before it is pasted into App Store
// Connect.
//
//   node scripts/localization/check-listings.mjs [--strict]
//
// App Store Connect rejects a submission outright when a field is over its
// limit, and the rejection comes at the end of an upload rather than at edit
// time. This catches it locally instead. Without `--strict` it reports coverage
// and fails only on hard errors; with `--strict` it also fails while any
// language is still untranslated, which is what CI should run once the
// translations land.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const PATH = join(ROOT, 'docs/appstore/listings.json');

const strict = process.argv.includes('--strict');

let failures = 0;
function fail(message) {
  failures += 1;
  console.error(`FAIL: ${message}`);
}

const raw = JSON.parse(readFileSync(PATH, 'utf8'));
const limits = raw._limits ?? {};
const english = raw.en ?? {};

if (!raw._limits) {
  fail('listings.json has no _limits block; the validator cannot check field sizes');
}

/**
 * Fields that must be non-empty for a listing to be submittable.
 *
 * `name` is exempt from the translation requirement: it is the brand, and
 * "TidyByte" is the same word in every storefront. Requiring a translation of
 * it would force 20 pointless copies.
 */
const REQUIRED = ['subtitle', 'promotionalText', 'description', 'keywords', 'whatsNew'];

const languages = Object.keys(raw).filter((k) => !k.startsWith('_'));

console.log(`listings.json: ${languages.length - 1} languages + en\n`);

// The English listing is the source; everything else is measured against it.
for (const field of ['name', ...REQUIRED]) {
  const value = english[field];
  if (typeof value !== 'string' || value.trim() === '') {
    fail(`en.${field} is empty`);
    continue;
  }
  const limit = limits[field];
  if (limit && value.length > limit) {
    fail(`en.${field} is ${value.length} chars, over the ${limit} limit`);
  }
}

const untranslated = new Map();

for (const language of languages) {
  if (language === 'en') continue;
  const listing = raw[language];

  for (const field of ['name', ...REQUIRED]) {
    const value = listing[field];

    if (typeof value !== 'string') {
      fail(`${language}.${field} is not a string`);
      continue;
    }

    // `name` is the brand. A storefront that translated it would show a
    // different app name than the one users search for.
    if (field === 'name') {
      if (value !== english.name) {
        fail(`${language}.name is ${JSON.stringify(value)}, expected ${JSON.stringify(english.name)}`);
      }
      continue;
    }

    if (value.trim() === '') {
      untranslated.set(language, (untranslated.get(language) ?? 0) + 1);
      continue;
    }

    const limit = limits[field];
    if (limit && value.length > limit) {
      fail(`${language}.${field} is ${value.length} chars, over the ${limit} limit`);
    }
  }

  // Keywords are comma-separated with no spaces after the commas. A space
  // wastes a character from a 100-character budget, so it is worth catching.
  const keywords = listing.keywords;
  if (typeof keywords === 'string' && keywords.trim() !== '') {
    if (/,\s/.test(keywords)) {
      fail(`${language}.keywords has a space after a comma; that wastes the 100-char budget`);
    }
    const terms = keywords.split(',').filter((t) => t.trim() !== '');
    const dupes = terms.filter((t, i) => terms.indexOf(t) !== i);
    if (dupes.length > 0) {
      fail(`${language}.keywords repeats: ${[...new Set(dupes)].join(', ')}`);
    }
    // Apple indexes name + subtitle + keywords together, so a word already in
    // the subtitle earns nothing in the keyword field.
    const subtitleWords = new Set(
      (listing.subtitle ?? '')
        .toLowerCase()
        .split(/[^\p{L}\p{N}]+/u)
        .filter((w) => w.length > 2),
    );
    for (const term of terms) {
      const single = term.trim().toLowerCase();
      if (single.includes(' ') ) continue;
      if (subtitleWords.has(single)) {
        fail(`${language}.keywords repeats the subtitle word ${JSON.stringify(term)}`);
      }
    }
  }
}

// A language present in one listing but missing from another is a mistake the
// per-field checks cannot see.
const expectedFields = ['name', 'subtitle', 'promotionalText', 'description', 'keywords', 'whatsNew'];
for (const language of languages) {
  const keys = Object.keys(raw[language]);
  const missing = expectedFields.filter((f) => !keys.includes(f));
  if (missing.length > 0) {
    fail(`${language} is missing field(s): ${missing.join(', ')}`);
  }
}

for (const language of languages) {
  if (language === 'en') continue;
  const remaining = untranslated.get(language) ?? 0;
  const done = REQUIRED.length - remaining;
  const flag = remaining === 0 ? 'ok' : `${remaining} to translate`;
  console.log(`  ${language.padEnd(9)} ${String(done).padStart(2)}/${REQUIRED.length}  ${flag}`);
  if (strict && remaining > 0) {
    fail(`${language} has ${remaining} untranslated field(s)`);
  }
}

console.log('');
if (failures > 0) {
  console.error(`${failures} problem(s) found.`);
  process.exit(1);
}
console.log(strict ? 'Listing checks passed.' : 'Listing checks passed (coverage not enforced; run with --strict).');
