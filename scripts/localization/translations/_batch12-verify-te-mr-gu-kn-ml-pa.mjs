#!/usr/bin/env node
// Verifier for batch 12 (Telugu, Marathi, Gujarati, Kannada, Malayalam, Punjabi).
//
// Reads the six files back from disk and proves:
//   - each parses as JSON
//   - `strings` grew by exactly 43 (641 -> 684) and every batch key is present
//     and non-empty
//   - placeholder counts match the English for every batch key
//   - the explainer template keeps two %@, its newlines (incl. the blank line),
//     and the 1./2. list markers
//   - no pre-existing key changed and `plurals` is byte-identical
//   - keys are still in the file's code-unit sort order
//
// Run: node scripts/localization/translations/_batch12-verify-te-mr-gu-kn-ml-pa.mjs

import fs from 'node:fs';
import path from 'node:path';

const dir = '/Users/sakshammittal/Documents/360ghar/github/archived/tidybyte/scripts/localization/translations';
const beforeDir = '/tmp/tidybyte-batch12-before';
const langs = ['te', 'mr', 'gu', 'kn', 'ml', 'pa'];
const keys = JSON.parse(fs.readFileSync(path.join(dir, '_batch12-keys.json'), 'utf8'));
const explainerKey = keys.find((k) => k.includes('TidyByte saves'));

const tokens = (s) => (s.match(/%(?:\d+\$)?[@lldfs]/g) || []).sort();
const count = (s, t) => (s.split(t).length - 1);

let failures = 0;
const fail = (msg) => {
  failures++;
  console.log(`  FAIL ${msg}`);
};

console.log(`batch keys: ${keys.length}`);
console.log(`explainer key newlines in English: ${count(explainerKey, '\n')}, %@: ${count(explainerKey, '%@')}`);
console.log('');

for (const lang of langs) {
  const file = path.join(dir, `${lang}.json`);
  const raw = fs.readFileSync(file, 'utf8');
  let json;
  try {
    json = JSON.parse(raw);
  } catch (e) {
    fail(`${lang}: does not parse as JSON (${e.message})`);
    continue;
  }
  const before = JSON.parse(fs.readFileSync(path.join(beforeDir, `${lang}.json`), 'utf8'));

  const s = json.strings;
  const beforeStrings = before.strings;

  // 1. counts
  if (Object.keys(s).length !== 684) fail(`${lang}: strings count is ${Object.keys(s).length}, expected 684`);
  if (Object.keys(beforeStrings).length !== 641) fail(`${lang}: pre-insert count was ${Object.keys(beforeStrings).length}, expected 641`);

  // 2. every batch key present, non-empty, placeholders matching English
  let missing = 0;
  let placeholderMismatch = 0;
  for (const k of keys) {
    const v = s[k];
    if (typeof v !== 'string' || v.trim() === '') {
      fail(`${lang}: missing/empty value for ${JSON.stringify(k)}`);
      missing++;
      continue;
    }
    const a = tokens(k);
    const b = tokens(v);
    if (a.length !== b.length || a.some((t, i) => t !== b[i])) {
      fail(`${lang}: placeholder mismatch for ${JSON.stringify(k)} -> ${JSON.stringify(v)} (${JSON.stringify(a)} vs ${JSON.stringify(b)})`);
      placeholderMismatch++;
    }
  }

  // 3. explainer template shape
  const ex = s[explainerKey] || '';
  if (count(ex, '%@') !== 2) fail(`${lang}: explainer has ${count(ex, '%@')} %@, expected 2`);
  if (count(ex, '%lld') !== 0) fail(`${lang}: explainer has an unexpected %lld`);
  if (count(ex, '\n') !== count(explainerKey, '\n')) {
    fail(`${lang}: explainer newlines ${count(ex, '\n')} != English ${count(explainerKey, '\n')}`);
  }
  if (!ex.includes('\n\n')) fail(`${lang}: explainer lost the blank-line paragraph break`);
  if (!ex.startsWith('1. ') || !ex.includes('\n2. ')) fail(`${lang}: explainer lost the 1./2. list markers`);

  // 4. no pre-existing key changed, removed, or reordered; plurals untouched
  const beforeKeys = Object.keys(beforeStrings);
  const changed = beforeKeys.filter((k) => s[k] !== beforeStrings[k]);
  if (changed.length) fail(`${lang}: ${changed.length} pre-existing key(s) changed: ${changed.slice(0, 3).join(' | ')}`);
  const afterNonBatch = Object.keys(s).filter((k) => !keys.includes(k));
  if (afterNonBatch.length !== beforeKeys.length) fail(`${lang}: non-batch key count ${afterNonBatch.length} != ${beforeKeys.length}`);
  if (JSON.stringify(json.plurals) !== JSON.stringify(before.plurals)) fail(`${lang}: plurals changed`);
  if (json.strings === before.strings) fail(`${lang}: strings object identity changed`);

  // 5. sort order preserved
  const actual = Object.keys(s);
  const sorted = [...actual].sort();
  if (JSON.stringify(actual) !== JSON.stringify(sorted)) fail(`${lang}: keys are not in code-unit sort order`);

  const ok = !failures;
  console.log(
    `${lang}: ${ok ? 'OK' : 'ERRORS'} · strings ${beforeKeys.length} -> ${Object.keys(s).length} · ` +
      `batch keys present ${keys.length - missing}/${keys.length} · placeholder mismatches ${placeholderMismatch} · ` +
      `pre-existing changed ${changed.length} · plurals identical ${JSON.stringify(json.plurals) === JSON.stringify(before.plurals)}`
  );
}

// Sample dump: the assembled sentences, so the fragments can be eyeballed in place.
console.log('\n--- assembled explainer sentences ---');
const assemble = (tpl, copies, originals) => tpl.replace('%@', copies).replace('%@', originals);
for (const lang of langs) {
  const s = JSON.parse(fs.readFileSync(path.join(dir, `${lang}.json`), 'utf8')).strings;
  for (const [c, o] of [
    ['a new, smaller copy of each photo', 'the original photos'],
    ['a new, smaller copy of each video', 'the original videos'],
    ['the still image of each Live Photo as a new photo', 'the Live Photos'],
  ]) {
    console.log(`${lang}: ${assemble(s[explainerKey], s[c], s[o])}`);
  }
  console.log('');
}

console.log(failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
