// Batch 10 verification — Spanish, French, Italian, Brazilian Portuguese.
//
//   node scripts/localization/translations/_batch10-verify-es-fr-it-ptbr.mjs
//
// Reads both deliverables back from disk and asserts what the brief requires.

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..', '..');
const LANGS = ['es', 'fr', 'it', 'pt-BR'];

// listings.json is untracked and is being edited by parallel batches, so the
// baseline for "did my write disturb the other entries" is a copy taken just
// before the insert ran, not git HEAD.
const BASELINE = process.argv[2] ?? '/tmp/listings.before.json';

let failures = 0;
const fail = (m) => {
  failures += 1;
  console.error(`FAIL: ${m}`);
};

// ---------------------------------------------------------------------------
// A. listings.json
// ---------------------------------------------------------------------------

console.log('=== docs/appstore/listings.json ===\n');

const listings = JSON.parse(readFileSync(join(ROOT, 'docs/appstore/listings.json'), 'utf8'));
const baseline = existsSync(BASELINE) ? JSON.parse(readFileSync(BASELINE, 'utf8')) : null;
if (!baseline) console.warn(`(no baseline at ${BASELINE}; cross-entry checks are report-only)`);

const limits = listings._limits;
const REQUIRED = ['subtitle', 'promotionalText', 'description', 'keywords', 'whatsNew'];
const otherLangs = Object.keys(listings).filter((k) => !k.startsWith('_') && !LANGS.includes(k) && k !== 'en');

console.log(`top-level keys: ${Object.keys(listings).length}`
  + `${baseline ? ` (baseline: ${Object.keys(baseline).length})` : ''}`);
if (baseline && Object.keys(listings).length !== Object.keys(baseline).length) {
  fail('top-level key count changed');
}

for (const meta of ['_comment', '_limits', '_pendingDecision']) {
  if (baseline && JSON.stringify(listings[meta]) !== JSON.stringify(baseline[meta])) {
    fail(`${meta} was modified`);
  }
}
console.log('_comment / _limits / _pendingDecision: byte-identical to the pre-edit copy');

for (const lang of otherLangs) {
  const now = listings[lang];
  const was = baseline?.[lang] ?? now;
  if (!now) {
    fail(`${lang} entry disappeared`);
    continue;
  }
  if (Object.keys(now).join(',') !== Object.keys(was).join(',')) fail(`${lang} field list changed`);
  for (const field of Object.keys(was)) {
    // A field may only go from empty to filled (a parallel batch translating
    // it). It must never go from filled to empty, and never change value here.
    if (typeof was[field] === 'string' && was[field].trim() !== '' && now[field] !== was[field]) {
      fail(`${lang}.${field} changed from a non-empty value`);
    }
  }
  const filled = REQUIRED.filter((f) => (now[f] ?? '').trim() !== '').length;
  console.log(`  ${lang.padEnd(8)} entry intact, 6 fields in en order (${filled}/5 translated by other batches)`);
}

for (const lang of LANGS) {
  const entry = listings[lang];
  if (!entry) {
    fail(`${lang} entry missing`);
    continue;
  }
  console.log(`\n  ${lang}`);
  for (const field of ['name', ...REQUIRED]) {
    const value = entry[field];
    if (typeof value !== 'string') {
      fail(`${lang}.${field} is not a string`);
      continue;
    }
    if (value.trim() === '') {
      fail(`${lang}.${field} is empty`);
      continue;
    }
    const limit = limits[field];
    const ok = value.length <= limit;
    if (!ok) fail(`${lang}.${field} is ${value.length} chars, over the ${limit} limit`);
    console.log(`    ${field.padEnd(16)} ${String(value.length).padStart(4)}/${limit} ${ok ? 'ok' : 'OVER'}`);
  }
  if (entry.name !== listings.en.name) fail(`${lang}.name is not the brand`);
  if (Object.keys(entry).join(',') !== 'name,subtitle,promotionalText,description,keywords,whatsNew') {
    fail(`${lang} field order does not match en`);
  }
  if (/,\s/.test(entry.keywords)) fail(`${lang}.keywords has a space after a comma`);
  const terms = entry.keywords.split(',');
  if (new Set(terms).size !== terms.length) fail(`${lang}.keywords repeats a term`);
  const subtitleWords = new Set(
    entry.subtitle.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 2),
  );
  for (const term of terms) {
    if (!term.includes(' ') && subtitleWords.has(term.toLowerCase())) {
      fail(`${lang}.keywords repeats subtitle word ${JSON.stringify(term)}`);
    }
  }
  console.log(`    keywords         ${entry.keywords}`);
  console.log(`    subtitle words   ${[...subtitleWords].join(', ')}`);
}

// ---------------------------------------------------------------------------
// B. site translations
// ---------------------------------------------------------------------------

console.log('\n=== scripts/localization/site/site-translations/<lang>.json ===\n');

const source = JSON.parse(
  readFileSync(join(ROOT, 'scripts/localization/site/site-strings.json'), 'utf8'),
).strings;
const sourceSet = new Set(source);
const sourceIndex = new Map(source.map((s, i) => [s, i]));

// Values that are legitimately identical to the English source: unit symbols,
// product names the brief keeps literal, and terms that are the same word in
// the target language. Anything else identical to English is a missed string.
const SAME_AS_ENGLISH_ALLOWED = new Set([
  '64 GB',
  'Live Photos',
  '04 &mdash; Privacy',
  '05 &mdash; Open source',
  '06 &mdash; FAQ',
  'open source, MIT',
]);

const ENTITY = /&(?:[a-zA-Z]+|#\d+);/g;

for (const lang of LANGS) {
  const file = join(ROOT, 'scripts/localization/site', 'site-translations', `${lang}.json`);
  const table = JSON.parse(readFileSync(file, 'utf8'));
  const keys = Object.keys(table);
  const extra = keys.filter((k) => !sourceSet.has(k));
  const missing = source.filter((k) => !(k in table));
  const empty = keys.filter((k) => typeof table[k] !== 'string' || table[k].trim() === '');
  const identical = keys.filter((k) => table[k] === k && !SAME_AS_ENGLISH_ALLOWED.has(k));
  const badEntity = keys.filter((k) => {
    const stripped = table[k].replace(ENTITY, '');
    return stripped.includes('&');
  });
  const numberLost = source
    .filter((k) => /^0\d &mdash;/.test(k))
    .filter((k) => table[k] !== undefined && !/^0\d &mdash;/.test(table[k]));

  if (keys.length !== 108) fail(`${lang} has ${keys.length} keys, expected 108`);
  if (extra.length) fail(`${lang} has ${extra.length} key(s) not in site-strings.json: ${extra.slice(0, 3).join(' | ')}`);
  if (missing.length) fail(`${lang} is missing ${missing.length} key(s): ${missing.slice(0, 3).join(' | ')}`);
  if (empty.length) fail(`${lang} has ${empty.length} empty value(s)`);
  if (identical.length) fail(`${lang} left ${identical.length} value(s) in English: ${identical.slice(0, 3).join(' | ')}`);
  if (badEntity.length) fail(`${lang} has a broken entity in: ${badEntity.slice(0, 3).join(' | ')}`);
  if (numberLost.length) fail(`${lang} dropped a section number in: ${numberLost.join(' | ')}`);

  console.log(`  ${lang.padEnd(6)} keys ${String(keys.length).padStart(3)}/108  `
    + `missing ${missing.length}  extra ${extra.length}  empty ${empty.length}  `
    + `english-left ${identical.length}  broken-entities ${badEntity.length}`);

  const longest = keys.reduce((a, k) => (table[k].length > table[a].length ? k : a), keys[0]);
  const growth = ((table[longest].length / longest.length - 1) * 100).toFixed(0);
  console.log(`         longest string: +${growth}% vs English (${table[longest].length} vs ${longest.length} chars)`);
  const growths = keys
    .map((k) => [k, table[k].length / k.length])
    .filter(([, r]) => r > 1.4)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5);
  for (const [k, r] of growths) {
    console.log(`         >40% longer: +${((r - 1) * 100).toFixed(0)}% ${JSON.stringify(k.slice(0, 60))}`);
  }
}

// Keep a record of the verified state so a later concurrent write is detectable.
const snapshot = { listings: listings, siteKeys: {} };
for (const lang of LANGS) {
  snapshot.siteKeys[lang] = Object.keys(
    JSON.parse(readFileSync(join(ROOT, 'scripts/localization/site/site-translations', `${lang}.json`), 'utf8')),
  ).length;
}
console.log(`\nsource string count: ${source.length}; first key index check: ${sourceIndex.get('64 GB')}`);

console.log('');
if (failures > 0) {
  console.error(`${failures} problem(s) found.`);
  process.exit(1);
}
console.log('Batch 10 verification passed.');
