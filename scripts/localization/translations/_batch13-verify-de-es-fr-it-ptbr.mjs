// Batch 13 verification — German, Spanish, French, Italian, Brazilian Portuguese.
//
//   node scripts/localization/translations/_batch13-verify-de-es-fr-it-ptbr.mjs
//
// Reads the five files back from disk and asserts, per language:
//   * the JSON parses and `strings` holds exactly 700 entries;
//   * all 16 batch keys are present and non-empty;
//   * no pre-existing key changed value and no pre-existing key vanished
//     (Job 2 was a no-op for these five languages);
//   * `plurals` is byte-identical to the baseline;
//   * key order is still plain code-point sort;
//   * every label is within ~1.5x the English length, or is reported;
//   * the two empty-state strings name the tabs exactly as the labels do.
//
// Needs /tmp/batch13-baseline/ from the insert script.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = '/tmp/batch13-baseline';

const LANGS = ['de', 'es', 'fr', 'it', 'pt-BR'];
const EXPECTED_STRINGS = 700;

const NO_PHOTOS_KEY =
  'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.';
const NO_VIDEOS_KEY =
  'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.';

const wantedKeys = JSON.parse(readFileSync(join(HERE, '_batch13-keys.json'), 'utf8'));

/// 16 + the two empty-state keys, which are the only pre-existing keys this
/// batch is allowed to touch.
const EMPTY_STATE_KEYS = new Set([NO_PHOTOS_KEY, NO_VIDEOS_KEY]);

let failures = 0;
function check(condition, message) {
  if (!condition) {
    failures += 1;
    console.error(`  FAIL ${message}`);
  }
}

for (const lang of LANGS) {
  const path = join(HERE, `${lang}.json`);
  let file;
  try {
    file = JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    failures += 1;
    console.error(`${lang}: does not parse — ${error.message}`);
    continue;
  }

  const baseline = JSON.parse(readFileSync(join(BACKUP_DIR, `${lang}.json`), 'utf8'));
  const strings = file.strings;

  console.log(`\n=== ${lang}`);

  // 1. counts
  check(
    Object.keys(strings).length === EXPECTED_STRINGS,
    `strings count is ${Object.keys(strings).length}, expected ${EXPECTED_STRINGS}`,
  );
  check(
    Object.keys(baseline.strings).length === EXPECTED_STRINGS - 16,
    `baseline strings count is ${Object.keys(baseline.strings).length}, expected ${EXPECTED_STRINGS - 16}`,
  );

  // 2. the 16 keys present and non-empty
  for (const key of wantedKeys) {
    const value = strings[key];
    check(typeof value === 'string' && value.trim() !== '', `"${key}" missing or empty`);
    check(!/^\s|\s$/.test(value ?? ''), `"${key}" has stray whitespace: ${JSON.stringify(value)}`);
    check(!/[.!?…]$/.test(value ?? ''), `"${key}" ends with punctuation: ${JSON.stringify(value)}`);
  }

  // 3. nothing else changed, nothing lost
  const changed = [];
  for (const [key, value] of Object.entries(baseline.strings)) {
    if (!(key in strings)) {
      failures += 1;
      console.error(`  FAIL pre-existing key disappeared: ${JSON.stringify(key)}`);
    } else if (strings[key] !== value) {
      changed.push(key);
      if (!EMPTY_STATE_KEYS.has(key)) {
        failures += 1;
        console.error(`  FAIL pre-existing key changed: ${JSON.stringify(key)}`);
      }
    }
  }
  check(
    Object.keys(strings).length === Object.keys(baseline.strings).length + 16,
    'string count moved by something other than the 16 new keys',
  );

  // 4. plurals untouched
  check(
    JSON.stringify(file.plurals) === JSON.stringify(baseline.plurals),
    'plurals changed',
  );
  check(
    Object.keys(file).join(',') === Object.keys(baseline).join(','),
    `top-level keys changed: ${Object.keys(file).join(',')}`,
  );

  // 5. key order
  const keys = Object.keys(strings);
  check(keys.join('\n') === [...keys].sort().join('\n'), 'keys are not in code-point sort order');

  // 6. length sanity
  const long = [];
  for (const key of wantedKeys) {
    const ratio = strings[key].length / key.length;
    if (ratio > 1.5) long.push(`${key}="${strings[key]}" (${strings[key].length} vs ${key.length}, ${ratio.toFixed(2)}x)`);
  }

  // 7. Job 2 — the empty-state strings must name the tabs as the labels do
  const inlinePhotos = `${strings.All}/${strings.Photos}`;
  const inlineVideos = `${strings.All}/${strings.Videos}`;
  check(
    strings[NO_PHOTOS_KEY].includes(inlineVideos),
    `${NO_PHOTOS_KEY} does not contain "${inlineVideos}": ${strings[NO_PHOTOS_KEY]}`,
  );
  check(
    strings[NO_VIDEOS_KEY].includes(inlinePhotos),
    `${NO_VIDEOS_KEY} does not contain "${inlinePhotos}": ${strings[NO_VIDEOS_KEY]}`,
  );
  check(
    baseline.strings['No files larger than %lld MB. Lower the threshold to see more.'] ===
      strings['No files larger than %lld MB. Lower the threshold to see more.'],
    'the third empty-state string changed (it names no tab)',
  );

  console.log(`  strings ${Object.keys(baseline.strings).length} -> ${Object.keys(strings).length}`);
  console.log(`  labels: ${wantedKeys.map((k) => `${k}=${strings[k]}`).join('  ')}`);
  console.log(`  inline tab names: ${inlinePhotos} , ${inlineVideos}`);
  console.log(
    `  changed pre-existing keys: ${changed.length ? JSON.stringify(changed) : 'none'}`,
  );
  console.log(`  plurals: ${Object.keys(file.plurals).length} (unchanged)`);
  console.log(`  labels over 1.5x English length: ${long.length ? long.join(' | ') : 'none'}`);
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
