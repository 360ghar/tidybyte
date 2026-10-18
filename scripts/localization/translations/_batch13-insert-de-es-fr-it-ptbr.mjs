// Batch 13 — German, Spanish, French, Italian, Brazilian Portuguese.
//
// Two jobs:
//   1. add the 16 picker / segmented-control labels in `_batch13-keys.json`;
//   2. make the two empty-state strings that name the `All` / `Photos` /
//      `Videos` segments use the same words as those segments.
//
//   node scripts/localization/translations/_batch13-insert-de-es-fr-it-ptbr.mjs
//
// A baseline copy of each file is written to /tmp/batch13-baseline/ before the
// file is touched, so `_batch13-verify-de-es-fr-it-ptbr.mjs` can prove that no
// pre-existing key changed and that `plurals` is untouched.
//
// Key order: the files are in plain code-point sort order (asserted below), so
// the union is re-sorted the same way.
//
// Job 2 result for these five languages: all five already named the tabs with
// the words chosen for the labels, so the two strings are asserted, not
// rewritten. The assertion below fails loudly if a label ever drifts from the
// sentence that points at it.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = '/tmp/batch13-baseline';

const LANGS = ['de', 'es', 'fr', 'it', 'pt-BR'];
const EXPECTED_BASELINE_STRINGS = 684;
const EXPECTED_FINAL_STRINGS = EXPECTED_BASELINE_STRINGS + 16;

const NO_PHOTOS_KEY =
  'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.';
const NO_VIDEOS_KEY =
  'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.';

/// Labels whose correct translation is the English text, because the language
/// spells that word the same way. Anything else that came back unchanged is a
/// mistake, not a translation.
const ALLOWED_IDENTICAL = {
  de: new Set(['Videos']),
  es: new Set([]),
  fr: new Set(['Photos', 'Exact', 'Strict']),
  it: new Set([]),
  'pt-BR': new Set([]),
};

// ---------------------------------------------------------------------------
// The 16 labels. Register: a bare noun or adjective on a picker, no trailing
// punctuation. `All` is one key shared by `LargeFileFilter` and
// `DuplicateScanType`, so it has to read correctly in front of `Photos` /
// `Videos` *and* after `Exact` / `Visual`.
//
// `Largest` / `Newest` / `Oldest` / `Filename` sit in a `.menu` picker (see
// `LargeFilesView`), so those four carry the idiomatic superlative; everything
// else is a segment of a `.segmented` control and is kept to one word.
// ---------------------------------------------------------------------------

const TRANSLATIONS = {
  de: {
    All: 'Alle',
    Photos: 'Fotos',
    Videos: 'Videos',
    Largest: 'Größte',
    Newest: 'Neueste',
    Oldest: 'Älteste',
    Filename: 'Dateiname',
    Exact: 'Exakt',
    Visual: 'Visuell',
    'By Year': 'Nach Jahr',
    'By Source': 'Nach Quelle',
    Low: 'Niedrig',
    Medium: 'Mittel',
    High: 'Hoch',
    Strict: 'Streng',
    Broad: 'Breit',
  },

  es: {
    All: 'Todo',
    Photos: 'Fotos',
    Videos: 'Vídeos',
    Largest: 'Más grandes',
    Newest: 'Más recientes',
    Oldest: 'Más antiguos',
    Filename: 'Nombre',
    Exact: 'Exactos',
    Visual: 'Visuales',
    'By Year': 'Por año',
    'By Source': 'Por origen',
    Low: 'Baja',
    Medium: 'Media',
    High: 'Alta',
    Strict: 'Estricto',
    Broad: 'Amplio',
  },

  fr: {
    All: 'Tout',
    Photos: 'Photos',
    Videos: 'Vidéos',
    Largest: 'Plus volumineux',
    Newest: 'Plus récents',
    Oldest: 'Plus anciens',
    Filename: 'Nom',
    Exact: 'Exact',
    Visual: 'Visuel',
    'By Year': 'Par année',
    'By Source': 'Par source',
    Low: 'Faible',
    Medium: 'Moyenne',
    High: 'Élevée',
    Strict: 'Strict',
    Broad: 'Large',
  },

  it: {
    All: 'Tutti',
    Photos: 'Foto',
    Videos: 'Video',
    Largest: 'Più grandi',
    Newest: 'Più recenti',
    Oldest: 'Più vecchi',
    Filename: 'Nome',
    Exact: 'Esatti',
    Visual: 'Visivi',
    'By Year': 'Per anno',
    'By Source': 'Per origine',
    Low: 'Bassa',
    Medium: 'Media',
    High: 'Alta',
    Strict: 'Rigoroso',
    Broad: 'Ampio',
  },

  'pt-BR': {
    All: 'Tudo',
    Photos: 'Fotos',
    Videos: 'Vídeos',
    Largest: 'Maiores',
    Newest: 'Mais recentes',
    Oldest: 'Mais antigos',
    Filename: 'Nome',
    Exact: 'Exatas',
    Visual: 'Visuais',
    'By Year': 'Por ano',
    'By Source': 'Por origem',
    Low: 'Baixa',
    Medium: 'Média',
    High: 'Alta',
    Strict: 'Estrito',
    Broad: 'Amplo',
  },
};

// ---------------------------------------------------------------------------
// Guard rails
// ---------------------------------------------------------------------------

const wantedKeys = JSON.parse(readFileSync(join(HERE, '_batch13-keys.json'), 'utf8'));
const wantedSet = new Set(wantedKeys);

function die(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

if (wantedKeys.length !== 16) die(`_batch13-keys.json holds ${wantedKeys.length} keys, expected 16`);
if (wantedSet.size !== 16) die('_batch13-keys.json has duplicate keys');

mkdirSync(BACKUP_DIR, { recursive: true });

for (const lang of LANGS) {
  const table = TRANSLATIONS[lang];
  if (!table) die(`${lang}: no translation table`);

  const missing = wantedKeys.filter((key) => !(key in table));
  const extra = Object.keys(table).filter((key) => !wantedSet.has(key));
  if (missing.length) die(`${lang}: ${missing.length} untranslated key(s): ${JSON.stringify(missing)}`);
  if (extra.length) die(`${lang}: ${extra.length} key(s) not in the list: ${JSON.stringify(extra)}`);

  const identicalAllowed = ALLOWED_IDENTICAL[lang] ?? new Set();
  for (const key of wantedKeys) {
    const value = table[key];
    if (typeof value !== 'string' || value.trim() === '') die(`${lang}: "${key}" is empty`);
    if (value === key && !identicalAllowed.has(key)) {
      die(`${lang}: "${key}" was left in English`);
    }
  }

  const path = join(HERE, `${lang}.json`);
  const file = JSON.parse(readFileSync(path, 'utf8'));

  const before = Object.keys(file.strings).length;
  if (before !== EXPECTED_BASELINE_STRINGS) {
    die(`${lang}: expected ${EXPECTED_BASELINE_STRINGS} existing strings, found ${before}`);
  }
  for (const key of wantedKeys) {
    if (key in file.strings) die(`${lang}: "${key}" already exists`);
  }
  if (!file.plurals || Object.keys(file.plurals).length === 0) die(`${lang}: plurals missing`);
  const pluralBefore = JSON.stringify(file.plurals);

  const existing = Object.keys(file.strings);
  if (existing.join('\n') !== [...existing].sort().join('\n')) {
    die(`${lang}: existing keys are not in code-point sort order`);
  }

  // Job 2: the sentence that points at a segment must name that segment with
  // the exact words the control shows.
  const all = table.All;
  const photos = table.Photos;
  const videos = table.Videos;
  const expected = [
    [NO_PHOTOS_KEY, `${all}/${videos}`],
    [NO_VIDEOS_KEY, `${all}/${photos}`],
  ];
  for (const [key, inline] of expected) {
    const value = file.strings[key];
    if (typeof value !== 'string') die(`${lang}: "${key}" missing`);
    if (!value.includes(inline)) {
      die(
        `${lang}: "${key}" does not name the tabs as the labels do.\n` +
          `  sentence: ${value}\n  expected to contain: ${inline}`,
      );
    }
  }

  copyFileSync(path, join(BACKUP_DIR, `${lang}.json`));

  for (const key of wantedKeys) file.strings[key] = table[key];

  const strings = {};
  for (const key of Object.keys(file.strings).sort()) strings[key] = file.strings[key];
  file.strings = strings;

  const after = Object.keys(file.strings).length;
  if (after !== EXPECTED_FINAL_STRINGS) {
    die(`${lang}: expected ${EXPECTED_FINAL_STRINGS} strings after insert, found ${after}`);
  }
  if (JSON.stringify(file.plurals) !== pluralBefore) die(`${lang}: plurals changed`);

  writeFileSync(path, `${JSON.stringify(file, null, 2)}\n`);
  console.log(
    `${lang.padEnd(6)} ${before} -> ${after} strings  ` +
      `(plurals untouched: ${Object.keys(file.plurals).length}; ` +
      `tabs already named ${all}/${photos} and ${all}/${videos})`,
  );
}

console.log('\nbaseline copies in', BACKUP_DIR);
