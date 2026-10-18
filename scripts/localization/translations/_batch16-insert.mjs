#!/usr/bin/env node
/**
 * Batch 16 — the two keys the new extractor guards surfaced.
 *
 * `extract.mjs` grew `scanStoredDisplayStrings()` and `scanVerbatimTextCalls()`
 * this session. Both reported zero false positives, and both independently
 * named the same real bug plus two keys that were being rendered but had no
 * catalog entry:
 *
 *   "Still image"     CompressionHistoryView.presetLabel — the label for the
 *                     "still" export preset, written by the Live Photos
 *                     converter. Previously returned raw and rendered through
 *                     `Text(String)`, so it read English in all 21 languages.
 *
 *   "%@ cleaned up"   StorageDashboardView.savingsHeadline — substituted as a
 *                     `%@` argument into "%@ · %lld items cleaned", so the
 *                     sentence was translated but the value inside it was not.
 *
 * Vocabulary is taken from keys that already exist in each language rather than
 * invented, so the new labels agree with the strings around them:
 *
 *   "still"       <- "Converted to Still" / "Convert Live Photo to Still"
 *   "cleaned up"  <- "%@ cleaned up in the last 30 days" / "Cleaned up %@ so far"
 *
 * Run from the repo root: node scripts/localization/translations/_batch16-insert.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const LANGS = [
  'ar', 'bn', 'de', 'es', 'fr', 'gu', 'he', 'hi', 'it', 'ja',
  'kn', 'ko', 'ml', 'mr', 'pa', 'pt-BR', 'ru', 'ta', 'te', 'zh-Hans',
];

/** Both keys, per language. */
const PLAIN = {
  ar: {
    'Still image': 'صورة ثابتة',
    '%@ cleaned up': 'تم تنظيف %@',
  },
  bn: {
    'Still image': 'স্থির ছবি',
    '%@ cleaned up': '%@ পরিষ্কার করা হয়েছে',
  },
  de: {
    'Still image': 'Standbild',
    '%@ cleaned up': '%@ freigegeben',
  },
  es: {
    'Still image': 'Foto fija',
    '%@ cleaned up': '%@ liberados',
  },
  fr: {
    'Still image': 'Photo fixe',
    '%@ cleaned up': '%@ libérés',
  },
  gu: {
    'Still image': 'સ્ટિલ ફોટો',
    '%@ cleaned up': '%@ સાફ કર્યું',
  },
  he: {
    'Still image': 'תמונה סטטית',
    '%@ cleaned up': 'נוקו %@',
  },
  hi: {
    'Still image': 'स्थिर छवि',
    '%@ cleaned up': '%@ साफ़ किया गया',
  },
  it: {
    'Still image': 'Foto statica',
    '%@ cleaned up': '%@ liberati',
  },
  ja: {
    'Still image': '静止画',
    '%@ cleaned up': '%@をクリーンアップしました',
  },
  kn: {
    'Still image': 'ಸ್ಟಿಲ್ ಫೋಟೋ',
    '%@ cleaned up': '%@ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ',
  },
  ko: {
    'Still image': '정지 사진',
    '%@ cleaned up': '%@ 정리됨',
  },
  ml: {
    'Still image': 'സ്റ്റിൽ ഫോട്ടോ',
    '%@ cleaned up': '%@ ക്ലീൻ ചെയ്തു',
  },
  mr: {
    'Still image': 'स्टिल फोटो',
    '%@ cleaned up': '%@ स्वच्छ केले',
  },
  pa: {
    'Still image': 'ਸਥਿਰ ਫ਼ੋਟੋ',
    '%@ cleaned up': '%@ ਖਾਲੀ ਕੀਤਾ',
  },
  'pt-BR': {
    'Still image': 'Foto estática',
    '%@ cleaned up': '%@ liberados',
  },
  ru: {
    'Still image': 'Статичное фото',
    '%@ cleaned up': 'Очищено %@',
  },
  ta: {
    'Still image': 'நிலைப்படம்',
    '%@ cleaned up': '%@ சுத்தம் செய்யப்பட்டது',
  },
  te: {
    'Still image': 'స్థిర చిత్రం',
    '%@ cleaned up': '%@ శుభ్రం చేయబడింది',
  },
  'zh-Hans': {
    'Still image': '静帧',
    '%@ cleaned up': '已清理 %@',
  },
};

let changed = 0;
for (const language of LANGS) {
  const path = join(DIR, `${language}.json`);
  const data = JSON.parse(readFileSync(path, 'utf8'));
  const before = Object.keys(data.strings ?? {}).length;

  data.strings ??= {};
  for (const [key, value] of Object.entries(PLAIN[language])) {
    data.strings[key] = value;
  }

  // `.strings` is kept in code-unit key order — plain `.sort()`, not
  // `localeCompare`, which disagrees on keys beginning with punctuation.
  // `.plurals` is deliberately left alone: this batch adds no plural keys, and
  // reordering that object would bury the addition in churn.
  data.strings = Object.fromEntries(
    Object.entries(data.strings).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
  );

  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);

  const after = Object.keys(data.strings).length;
  console.log(`${language.padEnd(9)} strings ${before} -> ${after} (+${after - before})`);
  changed += 1;
}
console.log(`\n${changed} file(s) written.`);
