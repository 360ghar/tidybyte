// Batch 14 — German, Spanish, French, Italian, Brazilian Portuguese.
//
// Adds the final 10 keys from `_batch14-keys.json`: 8 whole-sentence / label
// strings in `.strings`, 2 counted strings in `.plurals`.
//
//   node scripts/localization/translations/_batch14-insert-de-es-fr-it-ptbr.mjs
//
// A pre-write copy of each file is written to /tmp/batch14-baseline/ so
// `_batch14-verify-de-es-fr-it-ptbr.mjs` can prove no pre-existing key changed.
//
// `.strings` is kept in plain code-point sort order (the files already are).
// `.plurals` is NOT sorted in these files, so the two new keys are appended and
// every existing plural entry keeps its position and value.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = '/tmp/batch14-baseline';

const LANGS = ['de', 'es', 'fr', 'it', 'pt-BR'];
const EXPECTED_BASELINE_STRINGS = 699;
const EXPECTED_BASELINE_PLURALS = 64;
const EXPECTED_FINAL_STRINGS = EXPECTED_BASELINE_STRINGS + 8;
const EXPECTED_FINAL_PLURALS = EXPECTED_BASELINE_PLURALS + 2;

// Every language in this batch uses `one` / `other`, which is the set its other
// 64 plural entries already use.
const CATEGORIES = ['one', 'other'];

// ---------------------------------------------------------------------------
// Translations.
//
// `Mixed` is the quality picker's label when the selection has no single preset.
// It renders as `Quality: <Mixed>`, so the adjective agrees with the noun the
// language uses for quality: de "Qualität" (neuter) -> "Gemischt"; es "Calidad"
// (f) -> "Mixta"; fr "Qualité" (f) -> "Mixte"; it "Qualità" (f) -> "Mista";
// pt-BR "Qualidade" (f) -> "Mista". ("Mixte" is invariable in gender.)
//
// `Start here. ` keeps the trailing space: the app glues the tool name directly
// after the value for VoiceOver.
//
// `Untitled` uses the word iOS Photos itself shows for a nameless album.
//
// `media` is the mid-sentence noun already used in this file: de "Medien",
// es "elementos", fr "éléments", it "contenuti", pt-BR "mídia".
//
// `look-alike photos` echoes that file's `Visual` scan label while staying a
// natural group header: the "visually similar" form.
// ---------------------------------------------------------------------------

const TRANSLATIONS = {
  de: {
    strings: {
      Mixed: 'Gemischt',
      'Start here. ': 'Hier beginnen. ',
      Untitled: 'Ohne Titel',
      media: 'Medien',
      "Couldn't load this photo.": 'Dieses Foto konnte nicht geladen werden.',
      "Couldn't load this video.": 'Dieses Video konnte nicht geladen werden.',
      "Couldn't download this photo from iCloud.":
        'Dieses Foto konnte nicht aus iCloud heruntergeladen werden.',
      "Couldn't download this video from iCloud.":
        'Dieses Video konnte nicht aus iCloud heruntergeladen werden.',
    },
    plurals: {
      '%lld exact copies': { one: '%lld exakte Kopie', other: '%lld exakte Kopien' },
      '%lld look-alike photos': {
        one: '%lld visuell ähnliches Foto',
        other: '%lld visuell ähnliche Fotos',
      },
    },
  },

  es: {
    strings: {
      Mixed: 'Mixta',
      'Start here. ': 'Empieza aquí. ',
      Untitled: 'Sin título',
      media: 'elementos',
      "Couldn't load this photo.": 'No se pudo cargar esta foto.',
      "Couldn't load this video.": 'No se pudo cargar este vídeo.',
      "Couldn't download this photo from iCloud.": 'No se pudo descargar esta foto de iCloud.',
      "Couldn't download this video from iCloud.": 'No se pudo descargar este vídeo de iCloud.',
    },
    plurals: {
      '%lld exact copies': { one: '%lld copia exacta', other: '%lld copias exactas' },
      '%lld look-alike photos': {
        one: '%lld foto visualmente similar',
        other: '%lld fotos visualmente similares',
      },
    },
  },

  fr: {
    strings: {
      Mixed: 'Mixte',
      'Start here. ': 'Commencez ici. ',
      Untitled: 'Sans titre',
      media: 'éléments',
      "Couldn't load this photo.": 'Impossible de charger cette photo.',
      "Couldn't load this video.": 'Impossible de charger cette vidéo.',
      "Couldn't download this photo from iCloud.":
        'Impossible de télécharger cette photo depuis iCloud.',
      "Couldn't download this video from iCloud.":
        'Impossible de télécharger cette vidéo depuis iCloud.',
    },
    plurals: {
      '%lld exact copies': { one: '%lld copie exacte', other: '%lld copies exactes' },
      '%lld look-alike photos': {
        one: '%lld photo visuellement similaire',
        other: '%lld photos visuellement similaires',
      },
    },
  },

  it: {
    strings: {
      Mixed: 'Mista',
      'Start here. ': 'Inizia da qui. ',
      Untitled: 'Senza titolo',
      media: 'contenuti',
      "Couldn't load this photo.": 'Impossibile caricare questa foto.',
      "Couldn't load this video.": 'Impossibile caricare questo video.',
      "Couldn't download this photo from iCloud.": 'Impossibile scaricare questa foto da iCloud.',
      "Couldn't download this video from iCloud.": 'Impossibile scaricare questo video da iCloud.',
    },
    plurals: {
      '%lld exact copies': { one: '%lld copia esatta', other: '%lld copie esatte' },
      '%lld look-alike photos': {
        one: '%lld foto visivamente simile',
        other: '%lld foto visivamente simili',
      },
    },
  },

  'pt-BR': {
    strings: {
      Mixed: 'Mista',
      'Start here. ': 'Comece por aqui. ',
      Untitled: 'Sem título',
      media: 'mídia',
      "Couldn't load this photo.": 'Não foi possível carregar esta foto.',
      "Couldn't load this video.": 'Não foi possível carregar este vídeo.',
      "Couldn't download this photo from iCloud.": 'Não foi possível baixar esta foto do iCloud.',
      "Couldn't download this video from iCloud.": 'Não foi possível baixar este vídeo do iCloud.',
    },
    plurals: {
      '%lld exact copies': { one: '%lld cópia exata', other: '%lld cópias exatas' },
      '%lld look-alike photos': {
        one: '%lld foto visualmente semelhante',
        other: '%lld fotos visualmente semelhantes',
      },
    },
  },
};

// ---------------------------------------------------------------------------
// Guard rails
// ---------------------------------------------------------------------------

const wanted = JSON.parse(readFileSync(join(HERE, '_batch14-keys.json'), 'utf8'));
const wantedStrings = Object.keys(wanted.plain);
const wantedPlurals = Object.keys(wanted.plurals);

function die(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

if (wantedStrings.length !== 8) die(`expected 8 plain keys, found ${wantedStrings.length}`);
if (wantedPlurals.length !== 2) die(`expected 2 plural keys, found ${wantedPlurals.length}`);

mkdirSync(BACKUP_DIR, { recursive: true });

for (const lang of LANGS) {
  const table = TRANSLATIONS[lang];
  if (!table) die(`${lang}: no translation table`);

  const missing = wantedStrings.filter((k) => !(k in table.strings));
  const extra = Object.keys(table.strings).filter((k) => !wantedStrings.includes(k));
  if (missing.length) die(`${lang}: ${missing.length} untranslated string(s): ${JSON.stringify(missing)}`);
  if (extra.length) die(`${lang}: ${extra.length} string(s) not in the list: ${JSON.stringify(extra)}`);
  const pMissing = wantedPlurals.filter((k) => !(k in table.plurals));
  if (pMissing.length) die(`${lang}: missing plurals: ${JSON.stringify(pMissing)}`);

  for (const key of wantedStrings) {
    const value = table.strings[key];
    if (typeof value !== 'string' || value.trim() === '') die(`${lang}: "${key}" is empty`);
    if (key.endsWith(' ')) {
      if (!value.endsWith(' ')) die(`${lang}: "${key}" value must keep the trailing space`);
    } else if (value !== value.trim()) {
      die(`${lang}: "${key}" value has unexpected surrounding whitespace`);
    }
  }
  for (const key of wantedPlurals) {
    const forms = table.plurals[key];
    const cats = Object.keys(forms).sort();
    if (cats.join(',') !== [...CATEGORIES].sort().join(',')) {
      die(`${lang}: "${key}" categories are ${cats}, expected ${CATEGORIES}`);
    }
    for (const cat of cats) {
      const form = forms[cat];
      const hits = (form.match(/%lld/g) ?? []).length;
      if (hits !== 1) die(`${lang}: "${key}" [${cat}] has %lld ${hits} times`);
    }
  }

  const path = join(HERE, `${lang}.json`);
  const raw = readFileSync(path, 'utf8');
  const file = JSON.parse(raw);

  const before = Object.keys(file.strings).length;
  if (before !== EXPECTED_BASELINE_STRINGS) {
    die(`${lang}: expected ${EXPECTED_BASELINE_STRINGS} existing strings, found ${before}`);
  }
  if (Object.keys(file.plurals).length !== EXPECTED_BASELINE_PLURALS) {
    die(`${lang}: expected ${EXPECTED_BASELINE_PLURALS} existing plurals, found ${Object.keys(file.plurals).length}`);
  }
  for (const key of wantedStrings) if (key in file.strings) die(`${lang}: "${key}" already exists`);
  for (const key of wantedPlurals) if (key in file.plurals) die(`${lang}: plural "${key}" already exists`);

  const existingStrings = Object.keys(file.strings);
  if (existingStrings.join('\n') !== [...existingStrings].sort().join('\n')) {
    die(`${lang}: existing strings are not in code-point sort order`);
  }

  // Snapshot before touching anything.
  const backup = join(BACKUP_DIR, `${lang}.json`);
  if (existsSync(backup)) die(`${lang}: baseline already exists at ${backup}, refusing to overwrite`);
  copyFileSync(path, backup);

  for (const key of wantedStrings) file.strings[key] = table.strings[key];

  const sorted = {};
  for (const key of Object.keys(file.strings).sort()) sorted[key] = file.strings[key];
  file.strings = sorted;

  // Append the two plural keys; existing entries keep their order.
  for (const key of wantedPlurals) file.plurals[key] = table.plurals[key];

  const after = Object.keys(file.strings).length;
  if (after !== EXPECTED_FINAL_STRINGS) {
    die(`${lang}: expected ${EXPECTED_FINAL_STRINGS} strings after insert, found ${after}`);
  }
  if (Object.keys(file.plurals).length !== EXPECTED_FINAL_PLURALS) {
    die(`${lang}: expected ${EXPECTED_FINAL_PLURALS} plurals after insert, found ${Object.keys(file.plurals).length}`);
  }

  writeFileSync(path, `${JSON.stringify(file, null, 2)}\n`);
  console.log(
    `${lang.padEnd(6)} ${before} -> ${after} strings, ` +
      `${EXPECTED_BASELINE_PLURALS} -> ${EXPECTED_FINAL_PLURALS} plurals`,
  );
}

console.log('\nbaseline copies in', BACKUP_DIR);
