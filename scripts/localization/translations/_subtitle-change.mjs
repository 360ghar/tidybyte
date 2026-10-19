#!/usr/bin/env node
/**
 * Subtitle change: `Photo cleaner, free space` -> `Clean photos, free up storage`.
 *
 * The English subtitle is the one open product decision in
 * docs/APP_STORE_LISTING.md section 1. The product owner chose the verb-forward
 * option I, so this rewrites the subtitle in all 20 storefront languages.
 *
 * Two things make this more than a find-and-replace:
 *
 *   1. The localized subtitles are re-authored per language, not literal
 *      translations of the English. Several already carried the verb-forward
 *      positioning ("Limpia fotos, libera espacio"), so they only needed the
 *      "space" -> "storage" shift; others were noun phrases and were rewritten.
 *   2. App Store Connect enforces 30 characters as a hard limit, and CJK,
 *      Devanagari and other complex scripts do not count the way ASCII does.
 *      Every value below is measured with `[...text].length` (grapheme-ish
 *      code-point count) and the script refuses to write a value over 30.
 *
 * Four languages (ja, ko, zh-Hans and the "free of charge" reading elsewhere)
 * previously led with a word for "free" — 無料 / 무료 / 免费. The English has
 * never claimed the app is free in the subtitle, and "free up storage" is a
 * different sense of the word, so those are dropped.
 *
 * Machine-drafted: these are reviewed translations of the previous subtitle
 * carried forward, but the new phrasing has not been through a native
 * reviewer. Treat the same as the rest of the store copy.
 *
 * Run from the repo root: node scripts/localization/translations/_subtitle-change.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const LISTINGS = join(ROOT, 'docs', 'appstore', 'listings.json');
const LIMIT = 30;

/** New subtitle per language. `null` means "keep the existing value". */
const SUBTITLES = {
  en: 'Clean photos, free up storage',
  // Already verb-forward; only "space" needed to become "storage".
  es: 'Limpia fotos, libera espacio',
  it: 'Pulisci foto, libera spazio',
  'pt-BR': 'Limpe fotos, libere espaço',
  de: 'Fotos aufräumen, Speicher frei',
  fr: 'Photos nettes, espace libéré',
  ru: 'Чистите фото, освободите место',
  ar: 'نظّف الصور ووفّر مساحة',
  he: 'נקה תמונות, פנה מקום',
  hi: 'फ़ोटो साफ़ करें, जगह खाली करें',
  bn: 'ছবি পরিষ্কার করুন, জায়গা খালি',
  mr: 'फोटो साफ करा, जागा मोकळी करा',
  gu: 'ફોટો સાફ કરો, જગ્યા ખાલી કરો',
  pa: 'ਫ਼ੋਟੋ ਸਾਫ਼ ਕਰੋ, ਥਾਂ ਖਾਲੀ ਕਰੋ',
  ta: 'புகைப்படம் சுத்தம், இடம் காலி',
  te: 'ఫోటో శుభ్రం చేయండి, స్థలం ఖాళీ',
  kn: 'ಫೋಟೋ ಸ್ವಚ್ಛ ಮಾಡಿ, ಜಾಗ ಖಾಲಿ',
  ml: 'ഫോട്ടോ ക്ലീൻ, സ്ഥലം ഒഴിവ്',
  ja: '写真を整理して容量を空ける',
  ko: '사진 정리하고 저장 공간 확보',
  'zh-Hans': '清理照片，释放存储空间',
};

const listings = JSON.parse(readFileSync(LISTINGS, 'utf8'));
const langs = Object.keys(listings).filter((k) => !k.startsWith('_'));

// Measure first. A single over-limit value would be rejected at submission, so
// nothing is written unless every value fits.
const measured = [];
let over = 0;
for (const lang of langs) {
  const next = SUBTITLES[lang];
  if (next === undefined) {
    console.error(`FAIL: no subtitle supplied for ${lang}`);
    over += 1;
    continue;
  }
  const len = [...next].length;
  if (len > LIMIT) over += 1;
  measured.push({ lang, len, next, prev: listings[lang].subtitle });
}
if (over > 0) {
  for (const m of measured) {
    const flag = m.len > LIMIT ? `  OVER by ${m.len - LIMIT}` : '';
    console.error(`${m.lang.padEnd(9)} ${String(m.len).padStart(2)}/${LIMIT}${flag}  ${m.next}`);
  }
  console.error(`\nFAIL: ${over} value(s) unusable. Nothing written.`);
  process.exit(1);
}

console.log('language  len/30  old -> new');
console.log('-'.repeat(78));
for (const m of measured) {
  const changed = m.prev === m.next ? '  (unchanged)' : '';
  console.log(`${m.lang.padEnd(9)} ${String(m.len).padStart(2)}/30  ${m.prev}${changed}`);
  if (!changed) console.log(`${''.padEnd(15)}       -> ${m.next}`);
}

for (const m of measured) listings[m.lang].subtitle = m.next;
writeFileSync(LISTINGS, `${JSON.stringify(listings, null, 2)}\n`);
console.log(`\n${langs.length} subtitle(s) written to docs/appstore/listings.json`);
