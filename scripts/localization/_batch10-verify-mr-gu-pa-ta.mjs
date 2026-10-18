// Batch 10 read-back verification for mr / gu / pa / ta.
//
// Run: node scripts/localization/_batch10-verify-mr-gu-pa-ta.mjs
//
// Reads both deliverables back from disk and asserts everything the batch brief
// requires. It also re-reads the pre-edit copy of listings.json (written by the
// insert step to /tmp) to prove the other 16 language entries and the three
// underscore blocks were not disturbed.

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const LISTINGS = join(ROOT, 'docs/appstore/listings.json');
const BEFORE = '/tmp/listings-before-batch10.json';
const SITE_DIR = join(ROOT, 'scripts/localization/site');
const SOURCE = join(SITE_DIR, 'site-strings.json');
const OUT_DIR = join(SITE_DIR, 'site-translations');

const LANGS = ['mr', 'gu', 'pa', 'ta'];
const FIELDS = ['name', 'subtitle', 'promotionalText', 'description', 'keywords', 'whatsNew'];
// Values that are correct as-is in every language: a unit and an Apple product
// name. Everything else must differ from the English source.
const KEEP_LITERAL = new Set(['64 GB', 'Live Photos']);

let failures = 0;
const fail = (m) => {
  failures += 1;
  console.error(`FAIL: ${m}`);
};
const ok = (m) => console.log(`  ok  ${m}`);

// --- Deliverable A: listings.json -------------------------------------------

console.log('\nA. docs/appstore/listings.json');

const listingsRaw = readFileSync(LISTINGS, 'utf8');
let listings;
try {
  listings = JSON.parse(listingsRaw);
} catch (error) {
  fail(`listings.json does not parse: ${error.message}`);
  process.exit(1);
}
ok('parses as JSON');

if (!listingsRaw.endsWith(JSON.stringify(listings, null, 2) + '\n')) {
  fail('listings.json is not in the canonical 2-space + trailing-newline form');
} else {
  ok('serialization is canonical (JSON.stringify, 2 spaces, trailing newline)');
}

for (const key of ['_comment', '_limits', '_pendingDecision']) {
  if (!listings[key]) fail(`${key} is missing from listings.json`);
}
if (!failures) ok('_limits, _comment and _pendingDecision are present');

const limits = listings._limits;
const english = listings.en;
const languages = Object.keys(listings).filter((k) => !k.startsWith('_'));

for (const lang of LANGS) {
  if (!(lang in listings)) {
    fail(`${lang} entry missing from listings.json`);
    continue;
  }
  const entry = listings[lang];
  const report = [];
  for (const field of FIELDS) {
    const value = entry[field];
    if (typeof value !== 'string') {
      fail(`${lang}.${field} is not a string`);
      continue;
    }
    if (value.trim() === '') fail(`${lang}.${field} is empty`);
    if (value.length > limits[field]) {
      fail(`${lang}.${field} is ${value.length} chars, over the ${limits[field]} limit`);
    }
    report.push(`${field} ${value.length}/${limits[field]}`);
  }
  const keys = Object.keys(entry);
  const missingFields = FIELDS.filter((f) => !keys.includes(f));
  if (missingFields.length) fail(`${lang} is missing field(s): ${missingFields.join(', ')}`);
  if (entry.name !== english.name) fail(`${lang}.name is ${JSON.stringify(entry.name)}`);
  ok(`${lang}: all six fields present, non-empty, within limit (${report.join(', ')})`);

  // Keyword hygiene: no space after a comma, no repeat, nothing already in the subtitle.
  if (/,\s/.test(entry.keywords)) fail(`${lang}.keywords has a space after a comma`);
  const terms = entry.keywords.split(',').filter((t) => t.trim() !== '');
  const dupes = terms.filter((t, i) => terms.indexOf(t) !== i);
  if (dupes.length) fail(`${lang}.keywords repeats: ${[...new Set(dupes)].join(', ')}`);
  const subtitleWords = new Set(
    entry.subtitle.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 2),
  );
  for (const term of terms) {
    const t = term.trim().toLowerCase();
    if (!t.includes(' ') && subtitleWords.has(t)) {
      fail(`${lang}.keywords repeats the subtitle word ${JSON.stringify(term)}`);
    }
  }
  ok(`${lang}.keywords: no space after commas, no repeated term, nothing reused from the subtitle`);
}

// The other language entries and the underscore blocks must be byte-identical
// to the pre-edit copy.
if (!existsSync(BEFORE)) {
  fail(`${BEFORE} is missing; cannot prove the other entries are untouched`);
} else {
  const before = JSON.parse(readFileSync(BEFORE, 'utf8'));
  const beforeLangs = Object.keys(before).filter((k) => !k.startsWith('_'));
  let touched = 0;
  for (const lang of beforeLangs) {
    if (LANGS.includes(lang)) continue;
    if (JSON.stringify(before[lang]) !== JSON.stringify(listings[lang])) {
      fail(`${lang} entry changed, but it is not part of this batch`);
      touched += 1;
    }
  }
  for (const key of ['_comment', '_limits', '_pendingDecision']) {
    if (JSON.stringify(before[key]) !== JSON.stringify(listings[key])) {
      fail(`${key} changed`);
      touched += 1;
    }
  }
  if (touched === 0) {
    ok(
      `the other ${beforeLangs.length - LANGS.length} language entries and _comment/_limits/_pendingDecision are byte-identical to the pre-edit copy`,
    );
  }
  if (beforeLangs.length !== languages.length) {
    fail(`language count changed: ${beforeLangs.length} before, ${languages.length} now`);
  }
}

// --- Deliverable B: site-translations ---------------------------------------

console.log('\nB. scripts/localization/site/site-translations/<lang>.json');

const source = JSON.parse(readFileSync(SOURCE, 'utf8'));
const sourceStrings = source.strings;
ok(`site-strings.json: ${sourceStrings.length} English strings`);
const sourceSet = new Set(sourceStrings);

for (const lang of LANGS) {
  const path = join(OUT_DIR, `${lang}.json`);
  if (!existsSync(path)) {
    fail(`${path} does not exist`);
    continue;
  }
  const raw = readFileSync(path, 'utf8');
  let doc;
  try {
    doc = JSON.parse(raw);
  } catch (error) {
    fail(`${lang}.json does not parse: ${error.message}`);
    continue;
  }
  if (Array.isArray(doc) || typeof doc !== 'object') {
    fail(`${lang}.json is not a JSON object`);
    continue;
  }
  const keys = Object.keys(doc);
  if (keys.length !== sourceStrings.length) {
    fail(`${lang}.json has ${keys.length} keys, expected ${sourceStrings.length}`);
  }
  const missing = sourceStrings.filter((s) => !(s in doc));
  const extra = keys.filter((k) => !sourceSet.has(k));
  if (missing.length) {
    fail(`${lang}.json is missing ${missing.length} key(s): ${missing.slice(0, 3).map((m) => JSON.stringify(m)).join(', ')}`);
  }
  if (extra.length) {
    fail(`${lang}.json has ${extra.length} key(s) not in site-strings.json: ${extra.slice(0, 3).map((e) => JSON.stringify(e)).join(', ')}`);
  }
  const empty = keys.filter((k) => typeof doc[k] !== 'string' || doc[k].trim() === '');
  if (empty.length) fail(`${lang}.json has ${empty.length} empty/non-string value(s)`);
  const untranslated = keys.filter(
    (k) => !KEEP_LITERAL.has(k) && doc[k].trim() === k.trim(),
  );
  if (untranslated.length) {
    fail(`${lang}.json leaves ${untranslated.length} value(s) as the English source: ${untranslated.slice(0, 3).map((k) => JSON.stringify(k)).join(', ')}`);
  }
  const identical = keys.filter((k) => doc[k].trim() === k.trim());
  if (identical.length) {
    const unexpected = identical.filter((k) => !KEEP_LITERAL.has(k));
    if (!unexpected.length) {
      ok(
        `${lang}: ${identical.length} value(s) identical to English by design (${identical
          .map((k) => JSON.stringify(k))
          .join(', ')})`,
      );
    }
  }
  // A broken entity (a bare & that is not the start of an entity) would render
  // as-is in HTML, so catch it here.
  const brokenEntity = keys.filter((k) => /&(?!(?:[a-zA-Z]+|#\d+);)/.test(doc[k]));
  if (brokenEntity.length) {
    fail(`${lang}.json has ${brokenEntity.length} value(s) with a bare "&": ${brokenEntity.slice(0, 3).map((k) => JSON.stringify(k)).join(', ')}`);
  }
  if (raw !== JSON.stringify(doc, null, 2) + '\n') {
    fail(`${lang}.json is not in the canonical 2-space + trailing-newline form`);
  }
  if (failures === 0) {
    ok(
      `${lang}: ${keys.length} keys, all byte-identical to site-strings.json, no missing/extra, no empty value, no English left in place, no broken entity`,
    );
  }
}

console.log('');
if (failures > 0) {
  console.error(`${failures} problem(s) found.`);
  process.exit(1);
}
console.log('Batch 10 checks passed for mr, gu, pa, ta.');
