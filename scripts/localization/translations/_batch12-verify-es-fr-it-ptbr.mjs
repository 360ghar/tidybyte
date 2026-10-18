// Batch 12 verification — reads the five files back from disk.
//
//   node scripts/localization/translations/_batch12-verify-es-fr-it-ptbr.mjs
//
// Asserts, per language:
//   1. the file parses as JSON
//   2. `strings` holds 684 entries (641 before + the 43 keys in
//      _batch12-keys.json) and `plurals` still holds 64
//   3. all 43 keys are present and non-empty
//   4. placeholder counts match the English key for every one of the 43
//   5. the explainer template keeps two %@ (in order), its two list markers,
//      and the paragraph break: three newline characters, one of them a
//      blank-line run
//   6. no pre-existing key changed, no key was removed, key order is still the
//      file's plain code-point sort
//   7. `plurals` is byte-for-byte identical to the pre-insert baseline
//
// The baseline is written by _batch12-insert-es-fr-it-ptbr.mjs to
// /tmp/batch12-baseline/. If it is missing, checks 6 and 7 cannot run and are
// reported as skipped rather than passed.

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = '/tmp/batch12-baseline';
const CATALOG = join(HERE, '..', '..', '..', 'Tidybyte', 'Resources', 'Localizable.xcstrings');

const LANGS = ['es', 'fr', 'de', 'pt-BR', 'it'];
const KEYS = JSON.parse(readFileSync(join(HERE, '_batch12-keys.json'), 'utf8'));
const KEY_SET = new Set(KEYS);

const BASELINE_STRINGS = 641;
const BASELINE_PLURALS = 64;
const EXPECTED_STRINGS = BASELINE_STRINGS + KEYS.length; // 684

const TEMPLATE_KEY = KEYS.find((key) => key.includes('\n'));

let failures = 0;
const notes = [];

function fail(message) {
  failures += 1;
  console.log(`  FAIL  ${message}`);
}

function ok(message) {
  console.log(`  ok    ${message}`);
}

/** Every format specifier in a string, normalized to its type. */
function placeholders(text) {
  const found = [];
  const pattern = /%(?:(\d+)\$)?(?:\.(\d+))?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g;
  let match;
  while ((match = pattern.exec(text)) !== null) found.push(match[3]);
  return found;
}

function sameCounts(a, b) {
  if (a.length !== b.length) return false;
  const count = (list) => {
    const map = new Map();
    for (const item of list) map.set(item, (map.get(item) ?? 0) + 1);
    return map;
  };
  const left = count(a);
  const right = count(b);
  if (left.size !== right.size) return false;
  for (const [key, value] of left) if (right.get(key) !== value) return false;
  return true;
}

console.log(`Batch 12 verification — ${KEYS.length} keys x ${LANGS.length} languages`);
console.log(`Expected: strings ${BASELINE_STRINGS} -> ${EXPECTED_STRINGS}, plurals ${BASELINE_PLURALS}\n`);

const baselineAvailable = LANGS.every((lang) => existsSync(join(BACKUP_DIR, `${lang}.json`)));

for (const lang of LANGS) {
  console.log(`${lang}`);

  const raw = readFileSync(join(HERE, `${lang}.json`), 'utf8');
  let file;
  try {
    file = JSON.parse(raw);
  } catch (error) {
    fail(`does not parse as JSON: ${error.message}`);
    continue;
  }
  ok('parses as JSON');

  const keys = Object.keys(file.strings);

  if (keys.length === EXPECTED_STRINGS) ok(`strings count is ${EXPECTED_STRINGS}`);
  else fail(`strings count is ${keys.length}, expected ${EXPECTED_STRINGS}`);

  const pluralCount = Object.keys(file.plurals ?? {}).length;
  if (pluralCount === BASELINE_PLURALS) ok(`plurals count is ${BASELINE_PLURALS}`);
  else fail(`plurals count is ${pluralCount}, expected ${BASELINE_PLURALS}`);

  // 3 — presence and non-emptiness
  const missing = KEYS.filter((key) => !(key in file.strings));
  const empty = KEYS.filter((key) => (file.strings[key] ?? '').trim() === '');
  if (missing.length === 0 && empty.length === 0) ok(`all ${KEYS.length} keys present and non-empty`);
  else {
    if (missing.length) fail(`${missing.length} key(s) missing: ${JSON.stringify(missing)}`);
    if (empty.length) fail(`${empty.length} key(s) empty: ${JSON.stringify(empty)}`);
  }

  // 4 — placeholder parity against the English key
  const mismatches = [];
  for (const key of KEYS) {
    const value = file.strings[key];
    if (typeof value !== 'string') continue;
    if (!sameCounts(placeholders(key), placeholders(value))) {
      mismatches.push(`${JSON.stringify(key)}\n          en: ${JSON.stringify(key)}\n          ${lang}: ${JSON.stringify(value)}`);
    }
  }
  if (mismatches.length === 0) ok('placeholder counts match English for all 43 keys');
  else fail(`placeholder mismatch on ${mismatches.length} key(s):\n        ${mismatches.join('\n        ')}`);

  // 5 — the explainer template
  const template = file.strings[TEMPLATE_KEY];
  if (typeof template !== 'string') fail('explainer template missing');
  else {
    const atCount = (template.match(/%@/g) ?? []).length;
    const newlineCount = (template.match(/\n/g) ?? []).length;
    const blankRuns = (template.match(/\n\n/g) ?? []).length;
    const firstAt = template.indexOf('%@');
    const secondAt = template.indexOf('%@', firstAt + 1);

    if (atCount === 2) ok('explainer has exactly two %@');
    else fail(`explainer has ${atCount} %@, expected 2`);

    if (newlineCount === 3 && blankRuns === 1) {
      ok('explainer has 3 newline chars: one line break + one blank-line run');
    } else {
      fail(`explainer newline structure is ${newlineCount} newline char(s), ${blankRuns} blank-line run(s); expected 3 and 1`);
    }

    if (firstAt !== -1 && secondAt !== -1 && firstAt < secondAt) ok('%@ order preserved (copies before originals)');
    else fail('%@ placeholders are not both present in order');

    if (template.startsWith('1.') && template.includes('\n2.')) ok('list markers 1. and 2. kept');
    else fail('list markers 1. / 2. lost');

    // The translated sentence must actually read as two steps.
    if (/^1\.\s\S/.test(template) && /\n2\.\s\S/.test(template)) ok('both numbered steps carry text');
    else fail('a numbered step has no text');
  }

  // 6 — nothing pre-existing changed
  if (baselineAvailable) {
    const baseline = JSON.parse(readFileSync(join(BACKUP_DIR, `${lang}.json`), 'utf8'));
    const changed = Object.keys(baseline.strings).filter(
      (key) => file.strings[key] !== baseline.strings[key],
    );
    const removed = Object.keys(baseline.strings).filter((key) => !(key in file.strings));
    if (changed.length === 0 && removed.length === 0) {
      ok(`all ${Object.keys(baseline.strings).length} pre-existing keys unchanged, none removed`);
    } else {
      if (changed.length) fail(`${changed.length} pre-existing key(s) changed: ${JSON.stringify(changed)}`);
      if (removed.length) fail(`${removed.length} key(s) removed: ${JSON.stringify(removed)}`);
    }

    const added = Object.keys(file.strings).filter((key) => !(key in baseline.strings));
    if (added.length === KEYS.length && added.every((key) => KEY_SET.has(key))) {
      ok(`exactly ${KEYS.length} keys added, all from the batch list`);
    } else {
      fail(`${added.length} keys added: ${JSON.stringify(added.filter((key) => !KEY_SET.has(key)))}`);
    }

    const pluralsSame = JSON.stringify(file.plurals) === JSON.stringify(baseline.plurals);
    if (pluralsSame) ok('plurals byte-identical to baseline');
    else fail('plurals changed');
  } else {
    notes.push(`${lang}: baseline missing, "no pre-existing key changed" and plurals checks skipped`);
  }

  // key order
  if (JSON.stringify(keys) === JSON.stringify([...keys].sort())) ok('key order is still the plain code-point sort');
  else fail('key order changed');

  console.log('');
}

// Catalog reconciliation: the parent's 744 is the catalog total, not `strings`.
if (existsSync(CATALOG)) {
  const catalog = JSON.parse(readFileSync(CATALOG, 'utf8'));
  const catalogKeys = Object.keys(catalog.strings);
  const es = JSON.parse(readFileSync(join(HERE, 'es.json'), 'utf8'));
  const inCatalog = Object.keys(es.strings).filter((key) => key in catalog.strings);
  const notInCatalog = Object.keys(es.strings).filter((key) => !(key in catalog.strings));
  console.log('Catalog reconciliation (es):');
  console.log(`  catalog keys                 ${catalogKeys.length}`);
  console.log(`  es strings in catalog        ${inCatalog.length}`);
  console.log(`  es plural keys in catalog    ${Object.keys(es.plurals).filter((k) => k in catalog.strings).length}`);
  console.log(`  es strings not in catalog    ${notInCatalog.length} ${JSON.stringify(notInCatalog)}`);
  console.log(
    `  ${inCatalog.length} + ${Object.keys(es.plurals).filter((k) => k in catalog.strings).length} = ${
      inCatalog.length + Object.keys(es.plurals).filter((k) => k in catalog.strings).length
    } of ${catalogKeys.length} catalog keys`,
  );
  const stillEnglish = catalogKeys.filter(
    (key) => catalog.strings[key].localizations?.es?.stringUnit?.state === 'needs_review',
  ).length;
  console.log(`  catalog keys still English in es: ${stillEnglish} (pre-rebuild)`);
  console.log('');
}

for (const note of notes) console.log(`NOTE  ${note}`);
console.log(failures === 0 ? '\nRESULT: PASS — all assertions held' : `\nRESULT: FAIL — ${failures} assertion(s) failed`);
process.exit(failures === 0 ? 0 : 1);
