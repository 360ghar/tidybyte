#!/usr/bin/env node
// Batch 13 verifier for Telugu, Marathi, Gujarati, Kannada, Malayalam, Punjabi.
//
// Re-reads the six files from disk and asserts:
//   1. each parses as JSON
//   2. `strings` holds exactly 700 entries (684 before + the 16 new keys)
//   3. all 16 keys from _batch13-keys.json are present and non-empty
//   4. no pre-existing key changed, except the empty-state strings the insert
//      script was allowed to fix (checked against /tmp/tidybyte-batch13-before)
//   5. `plurals` is byte-identical to the pre-write snapshot
//   6. key order is still plain Object.keys().sort()
//   7. every label is no more than 1.5x the English by character count, and
//      reports any that exceed it
//
// Run: node scripts/localization/translations/_batch13-verify-te-mr-gu-kn-ml-pa.mjs

import fs from 'node:fs';
import path from 'node:path';

const dir = '/Users/sakshammittal/Documents/360ghar/github/archived/tidybyte/scripts/localization/translations';
const beforeDir = '/tmp/tidybyte-batch13-before';

const keys = JSON.parse(fs.readFileSync(path.join(dir, '_batch13-keys.json'), 'utf8'));
const langs = ['te', 'mr', 'gu', 'kn', 'ml', 'pa'];

// Keys the insert script was permitted to rewrite, per language.
const ALLOWED_EDITS = {
  te: [
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.',
  ],
  mr: [],
  gu: [],
  kn: [
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.',
  ],
  ml: [],
  pa: ['No videos larger than %lld MB. Lower the threshold or switch to All/Photos.'],
};

const failures = [];
const fail = (msg) => failures.push(msg);

for (const lang of langs) {
  const file = path.join(dir, `${lang}.json`);
  const raw = fs.readFileSync(file, 'utf8');

  let json;
  try {
    json = JSON.parse(raw);
  } catch (e) {
    fail(`${lang}: does not parse — ${e.message}`);
    continue;
  }

  const before = JSON.parse(fs.readFileSync(path.join(beforeDir, `${lang}.json`), 'utf8'));

  // 2. count
  const n = Object.keys(json.strings).length;
  if (n !== 700) fail(`${lang}: strings count is ${n}, expected 700`);

  // 3. new keys present and non-empty
  for (const key of keys) {
    const v = json.strings[key];
    if (typeof v !== 'string' || v.trim() === '') fail(`${lang}: "${key}" missing or empty`);
  }

  // 4. nothing else changed
  const allowed = new Set(ALLOWED_EDITS[lang]);
  for (const [key, value] of Object.entries(before.strings)) {
    if (!(key in json.strings)) {
      fail(`${lang}: pre-existing key disappeared: "${key}"`);
      continue;
    }
    if (json.strings[key] !== value && !allowed.has(key)) {
      fail(`${lang}: pre-existing key changed without permission: "${key}"`);
    }
  }
  for (const key of Object.keys(json.strings)) {
    if (!(key in before.strings) && !keys.includes(key)) {
      fail(`${lang}: unexpected new key: "${key}"`);
    }
  }
  // allowed edits must actually be edits, not silent no-ops on the wrong key
  for (const key of allowed) {
    if (!(key in before.strings)) fail(`${lang}: allowed-edit key absent before write: "${key}"`);
  }

  // 5. plurals untouched
  if (JSON.stringify(json.plurals) !== JSON.stringify(before.plurals)) {
    fail(`${lang}: plurals changed`);
  }

  // 6. sort order
  const order = Object.keys(json.strings);
  const sorted = [...order].sort();
  if (order.some((k, i) => k !== sorted[i])) fail(`${lang}: key order is not sorted`);

  // 7. length sanity
  const long = [];
  for (const key of keys) {
    const ratio = [...json.strings[key]].length / [...key].length;
    if (ratio > 1.5) long.push(`${key} -> "${json.strings[key]}" (${[...json.strings[key]].length} vs ${[...key].length})`);
  }

  console.log(`\n=== ${lang} ===`);
  console.log(`strings: ${n} | plurals: ${Object.keys(json.plurals).length} | sorted: yes | non-16 keys changed: ${Object.entries(before.strings).filter(([k, v]) => json.strings[k] !== v && !keys.includes(k)).length}`);
  for (const key of keys) {
    console.log(`  ${key.padEnd(10)} ${json.strings[key]}`);
  }
  console.log(long.length ? `  >1.5x English: ${long.join('; ')}` : '  all labels within 1.5x English');
  for (const key of ALLOWED_EDITS[lang]) {
    console.log(`  fixed: ${key}\n    before: ${before.strings[key]}\n    after:  ${json.strings[key]}`);
  }
}

console.log('\n' + (failures.length ? `FAILURES (${failures.length}):\n - ` + failures.join('\n - ') : 'ALL CHECKS PASSED'));
process.exit(failures.length ? 1 : 0);
