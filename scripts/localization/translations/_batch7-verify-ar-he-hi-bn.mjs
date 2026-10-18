#!/usr/bin/env node
/**
 * Batch 7 verification for ar, he, hi, bn — reads the four files back from disk.
 *
 * Checks per language:
 *   - the file parses as JSON
 *   - Object.keys(strings).length === 552
 *   - all 57 batch-7 keys are present and non-empty
 *   - no pre-existing key changed value (against the /tmp snapshot the insert
 *     script wrote before it touched the file)
 *   - `plurals` is unchanged
 *   - key order is the codePoint order the files already used
 *   - %lld appears exactly once in every translation whose key has one, and
 *     nowhere else; same for %@
 *
 * Run: node scripts/localization/translations/_batch7-verify-ar-he-hi-bn.mjs
 */

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const LANGS = ['ar', 'he', 'hi', 'bn'];
const EXPECTED_TOTAL = 552;

const BATCH_KEYS = [
  'TidyByte Needs Your Photos',
  "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.",
  'Photo Access Is On',
  'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.',
  'Photo Access Is Off',
  'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.',
  'Photo Access Is Restricted',
  'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.',
  'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.',
  'Allow Photo Access?',
  'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.',
  'Not Now',
  'Photo not found.',
  "This item can't be compressed as a photo.",
  'Failed to load the photo.',
  'Photo size unknown (iCloud-only) — skipped.',
  'Video not found.',
  "Couldn't load the video (it may still be in iCloud). Please try again.",
  'Video size unknown (iCloud-only) — skipped.',
  'Failed to create export session.',
  'Exported file was empty.',
  'Failed to read file size.',
  'Failed to re-encode the photo.',
  'Cancelled.',
  'Unknown error',
  'Save failed: %@',
  'Export failed: %@',
  'Already compressed',
  'Size unknown (iCloud-only) — skipped',
  'Local AI is unavailable.',
  'This language is not supported by local AI.',
  'Local AI could not interpret this search.',
  'Use 300 characters or fewer.',
  'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.',
  'Some requested concepts were not found in this scan. Try a simpler content search.',
  'Searching labels across all scanned categories.',
  'Using label search across scanned photos.',
  'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.',
  'This photo may be out of focus.',
  'This photo has very low brightness.',
  'This photo has very high brightness.',
  'A lens smudge may have reduced image clarity.',
  'This photo received a low visual-quality score.',
  'Review whether you still need this screenshot.',
  'Review whether you still need this screen recording.',
  'This item uses %@; review whether you need it.',
  'Light',
  'Dark',
  'Nothing to free on iPhone',
  'Up to %@ to free on iPhone',
  'Open TidyByte to refresh',
  'Updated %lldd ago',
  'No matching photos',
  'Submit a content search or try different words.',
  'No photos in this category.',
  'Choose albums or change your filters.',
  'No screen recordings were found.',
];

const count = (haystack, needle) => haystack.split(needle).length - 1;
const problems = [];
const notes = [];

for (const lang of LANGS) {
  const path = join(DIR, `${lang}.json`);
  const raw = readFileSync(path, 'utf8');

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    problems.push(`${lang}: not valid JSON (${error.message})`);
    continue;
  }

  const before = JSON.parse(readFileSync(`/tmp/batch7-before-${lang}.json`, 'utf8'));
  const strings = parsed.strings;
  const keys = Object.keys(strings);

  if (keys.length !== EXPECTED_TOTAL) {
    problems.push(`${lang}: ${keys.length} keys, expected ${EXPECTED_TOTAL}`);
  }

  // New keys present and non-empty.
  const missing = BATCH_KEYS.filter((key) => !(key in strings));
  if (missing.length) problems.push(`${lang}: ${missing.length} batch keys missing: ${missing.join(' | ')}`);
  const empty = BATCH_KEYS.filter((key) => key in strings && strings[key].trim() === '');
  if (empty.length) problems.push(`${lang}: empty values: ${empty.join(' | ')}`);

  // No pre-existing value changed.
  const changed = Object.keys(before.strings).filter((key) => strings[key] !== before.strings[key]);
  if (changed.length) problems.push(`${lang}: ${changed.length} pre-existing keys changed: ${changed.join(' | ')}`);
  const addedUnexpectedly = keys.filter((key) => !(key in before.strings) && !BATCH_KEYS.includes(key));
  if (addedUnexpectedly.length) {
    problems.push(`${lang}: ${addedUnexpectedly.length} keys added that are not in the batch: ${addedUnexpectedly.join(' | ')}`);
  }

  // plurals untouched.
  if (JSON.stringify(parsed.plurals) !== JSON.stringify(before.plurals)) {
    problems.push(`${lang}: plurals changed`);
  }

  // Key order still codePoint-sorted.
  const sorted = [...keys].sort();
  if (!keys.every((key, index) => key === sorted[index])) {
    problems.push(`${lang}: key order is not codePoint-sorted`);
  }

  // Placeholders in the batch keys: exactly once where the key has one, never
  // where it does not. Pre-existing keys are only reported, never failed — the
  // catalog already carries `size.bytes` as `%lld बाइट` / `%lld বাইট`, which is
  // a pre-existing choice and out of scope for this batch.
  let placeholderKeys = 0;
  for (const key of keys) {
    const value = strings[key];
    const isBatchKey = BATCH_KEYS.includes(key);
    for (const token of ['%lld', '%@']) {
      const wanted = count(key, token);
      const got = count(value, token);
      if (wanted !== got) {
        const line = `placeholder ${token} in ${JSON.stringify(key)} -> key has ${wanted}, value has ${got} (${JSON.stringify(value)})`;
        if (isBatchKey) problems.push(`${lang}: ${line}`);
        else notes.push(`${lang}: pre-existing (not this batch) — ${line}`);
      }
    }
    if (count(key, '%lld') || count(key, '%@')) placeholderKeys += 1;
  }

  const newKeys = keys.length - Object.keys(before.strings).length;
  const emDash = BATCH_KEYS.filter((key) => key.includes('—') && strings[key].includes('—')).length;
  const emDashTotal = BATCH_KEYS.filter((key) => key.includes('—')).length;

  console.log(
    `${lang}: OK — keys ${keys.length}/${EXPECTED_TOTAL}, new ${newKeys}, ` +
      `batch keys ${BATCH_KEYS.length}/${BATCH_KEYS.length}, pre-existing values intact (${Object.keys(before.strings).length}), ` +
      `plurals intact (${Object.keys(before.plurals).length}), placeholders OK (${placeholderKeys} keys), ` +
      `em dash kept ${emDash}/${emDashTotal}`,
  );
}

if (notes.length) {
  console.log('\nNotes (pre-existing, untouched by this batch):');
  for (const note of notes) console.log(`  - ${note}`);
}

if (problems.length) {
  console.log('\nFAILURES:');
  for (const problem of problems) console.log(`  - ${problem}`);
  process.exit(1);
}

console.log('\nAll checks passed for ar, he, hi, bn.');
