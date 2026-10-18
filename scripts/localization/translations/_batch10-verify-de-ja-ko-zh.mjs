#!/usr/bin/env node
// Batch 10 verification — reads both deliverables back from disk and asserts
// the contract in scripts/localization/translations/_batch10-brief.md.
//
// Run: node scripts/localization/translations/_batch10-verify-de-ja-ko-zh.mjs

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..', '..');

const LISTINGS = join(root, 'docs', 'appstore', 'listings.json');
const SITE_STRINGS = join(root, 'scripts', 'localization', 'site', 'site-strings.json');
const OUT_DIR = join(root, 'scripts', 'localization', 'site', 'site-translations');
const BACKUP = '/tmp/batch10-listings-before.json';

const MINE = ['de', 'ja', 'ko', 'zh-Hans'];
const FIELDS = ['name', 'subtitle', 'promotionalText', 'description', 'keywords', 'whatsNew'];

let failures = 0;
const fail = (m) => {
  failures += 1;
  console.log(`FAIL: ${m}`);
};

// ---------------------------------------------------------------- listings ---
const raw = JSON.parse(readFileSync(LISTINGS, 'utf8'));
const before = JSON.parse(readFileSync(BACKUP, 'utf8'));
const limits = raw._limits;

console.log('=== docs/appstore/listings.json ===');
console.log(`parses: yes · languages: ${Object.keys(raw).filter((k) => !k.startsWith('_')).length} + en`);

// Meta keys untouched.
for (const key of ['_comment', '_limits', '_pendingDecision']) {
  const same = JSON.stringify(raw[key]) === JSON.stringify(before[key]);
  console.log(`${same ? 'ok  ' : 'FAIL'} ${key} untouched: ${same}`);
  if (!same) fail(`${key} changed`);
}

// Every language that is not mine is byte-identical to the pre-edit copy.
const others = Object.keys(before).filter((k) => k !== 'en' && !MINE.includes(k));
const drifted = others.filter(
  (k) => JSON.stringify(raw[k]) !== JSON.stringify(before[k]),
);
console.log(
  `${drifted.length === 0 ? 'ok  ' : 'FAIL'} other ${others.length} language entries unchanged (${others.join(', ')})`,
);
if (drifted.length > 0) fail(`drifted entries: ${drifted.join(', ')}`);
const enSame = JSON.stringify(raw.en) === JSON.stringify(before.en);
console.log(`${enSame ? 'ok  ' : 'FAIL'} en unchanged: ${enSame}`);
if (!enSame) fail('en changed');

for (const lang of MINE) {
  const entry = raw[lang];
  if (!entry) {
    fail(`${lang} missing`);
    continue;
  }
  const keys = Object.keys(entry);
  const missingFields = FIELDS.filter((f) => !keys.includes(f));
  if (missingFields.length > 0) fail(`${lang} missing fields: ${missingFields.join(', ')}`);
  if (keys.length !== FIELDS.length) fail(`${lang} has ${keys.length} fields, expected 6`);
  console.log(`\n${lang}:`);
  for (const field of FIELDS) {
    const value = entry[field];
    if (typeof value !== 'string' || value.trim() === '') {
      fail(`${lang}.${field} empty or not a string`);
      continue;
    }
    const len = value.length;
    const over = len > limits[field];
    console.log(
      `  ${over ? 'FAIL' : 'ok  '} ${field.padEnd(15)} ${String(len).padStart(4)}/${limits[field]}`,
    );
    if (over) fail(`${lang}.${field} is ${len} chars, over the ${limits[field]} limit`);
  }
  if (entry.name !== 'TidyByte') fail(`${lang}.name is ${JSON.stringify(entry.name)}`);
  if (/,\s/.test(entry.keywords)) fail(`${lang}.keywords has a space after a comma`);
  const terms = entry.keywords.split(',').filter((t) => t.trim() !== '');
  const dupes = terms.filter((t, i) => terms.indexOf(t) !== i);
  if (dupes.length > 0) fail(`${lang}.keywords repeats: ${[...new Set(dupes)].join(', ')}`);
  const subtitleWords = new Set(
    entry.subtitle
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter((w) => w.length > 2),
  );
  const clash = terms.filter((t) => !t.includes(' ') && subtitleWords.has(t.trim().toLowerCase()));
  if (clash.length > 0) fail(`${lang}.keywords repeats subtitle word(s): ${clash.join(', ')}`);
  console.log(`  ok   keywords: ${terms.length} terms, no comma-space, no repeat, no subtitle clash`);
}

// ------------------------------------------------------------------- site ---
const source = JSON.parse(readFileSync(SITE_STRINGS, 'utf8'));
const expected = new Set(source.strings);
console.log(`\n=== scripts/localization/site/site-translations/ ===`);
console.log(`source site-strings.json: ${source.strings.length} strings (${expected.size} unique)`);

for (const lang of MINE) {
  const file = join(OUT_DIR, `${lang}.json`);
  let map;
  try {
    map = JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`${lang}.json does not parse: ${error.message}`);
    continue;
  }
  const keys = Object.keys(map);
  const missing = source.strings.filter((k) => !(k in map));
  const extra = keys.filter((k) => !expected.has(k));
  const empty = keys.filter((k) => typeof map[k] !== 'string' || map[k].trim() === '');
  const unchanged = keys.filter((k) => map[k] === k);
  const byteIdentical = source.strings.every((k) => keys.includes(k));

  console.log(`\n${lang}.json: ${keys.length} keys`);
  console.log(`  ${keys.length === 108 ? 'ok  ' : 'FAIL'} exactly 108 keys`);
  console.log(`  ${missing.length === 0 ? 'ok  ' : 'FAIL'} no missing key (${missing.length})`);
  console.log(`  ${extra.length === 0 ? 'ok  ' : 'FAIL'} no extra key (${extra.length})`);
  console.log(`  ${byteIdentical ? 'ok  ' : 'FAIL'} every key byte-identical to a source string`);
  console.log(`  ${empty.length === 0 ? 'ok  ' : 'FAIL'} no empty value (${empty.length})`);
  console.log(`  ${unchanged.length === 0 ? 'ok  ' : 'warn'} values identical to English: ${unchanged.length}`);

  if (keys.length !== 108) fail(`${lang}.json has ${keys.length} keys`);
  if (missing.length > 0) fail(`${lang}.json missing: ${missing.slice(0, 3).join(' | ')}`);
  if (extra.length > 0) fail(`${lang}.json extra: ${extra.slice(0, 3).join(' | ')}`);
  if (!byteIdentical) fail(`${lang}.json has a key that is not in site-strings.json`);
  if (empty.length > 0) fail(`${lang}.json empty values: ${empty.slice(0, 3).join(' | ')}`);
  if (unchanged.length > 0) {
    for (const key of unchanged) console.log(`      identical to English: ${JSON.stringify(key)}`);
  }
  const entities = keys.filter((k) => /&[a-z]+;/.test(k) !== /&[a-z]+;/.test(map[k]));
  if (entities.length > 0) {
    console.log(`  warn HTML entity mismatch in ${entities.length} value(s):`);
    for (const key of entities) {
      console.log(`      key: ${JSON.stringify(key)}\n      val: ${JSON.stringify(map[key])}`);
    }
  } else {
    console.log('  ok   HTML entities preserved in every value');
  }
}

console.log(`\n${failures === 0 ? 'ALL CHECKS PASSED' : `${failures} FAILURE(S)`}`);
process.exit(failures === 0 ? 0 : 1);
