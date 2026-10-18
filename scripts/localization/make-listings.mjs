// Builds docs/appstore/listings.json from the English copy in
// docs/APP_STORE_LISTING.md, with an empty slot per storefront language for the
// translation step to fill.
//
// Run: node scripts/localization/make-listings.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Hard limits App Store Connect enforces. A value over the limit is rejected. */
const LIMITS = {
  name: 30,
  subtitle: 30,
  promotionalText: 170,
  description: 4000,
  keywords: 100,
  whatsNew: 4000,
};

const LANGUAGES = [
  'hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa',
  'es', 'fr', 'de', 'pt-BR', 'it', 'ja', 'ko', 'zh-Hans', 'ru', 'ar', 'he',
];

const doc = readFileSync(join(ROOT, 'docs/APP_STORE_LISTING.md'), 'utf8');

/** Pulls the first fenced block after a heading, so the doc stays the source. */
function blockAfter(heading) {
  const section = doc.split(heading)[1];
  if (!section) throw new Error(`heading not found in APP_STORE_LISTING.md: ${heading}`);
  const fenced = section.split('```')[1];
  if (!fenced) throw new Error(`no fenced block under: ${heading}`);
  return fenced.trim();
}

const english = {
  name: 'TidyByte',
  subtitle: 'Photo cleaner, free space',
  promotionalText: blockAfter('## 2. Promotional Text'),
  description: blockAfter('## 3. Description'),
  keywords:
    'storage cleaner,duplicate photo,image compressor,compress video,screenshot,blurry,declutter,gallery',
  whatsNew: blockAfter('## 12. What'),
};

const listings = {};
for (const code of LANGUAGES) {
  listings[code] = {
    // Pre-filled, not left blank: the app name is the brand and is the same
    // word in every storefront. Leaving it empty would make the validator
    // report 20 missing fields that must never be translated.
    name: english.name,
    subtitle: '',
    promotionalText: '',
    description: '',
    keywords: '',
    whatsNew: '',
  };
}

const out = {
  _comment:
    'App Store Connect localizations for TidyByte. One entry per storefront language. The limits below are App Store Connect hard limits: a value over the limit is rejected at submission, so check-listings.mjs validates every field. The en entry is the source of truth; every other entry is a translation of it. name is the brand and stays TidyByte in every language.',
  _limits: LIMITS,
  _pendingDecision:
    'The English subtitle is the one open product decision in docs/APP_STORE_LISTING.md section 1. Option F, "Photo cleaner, free space", is used here because it is the shortest phrase carrying both the photo-cleaner and storage intents. If a different subtitle ships, change en.subtitle and re-translate that one field in all 20 languages. The keywords field is tuned against the subtitle: Apple indexes name, subtitle and keywords together, so a word already in the subtitle must not repeat in keywords.',
  en: english,
  ...listings,
};

writeFileSync(join(ROOT, 'docs/appstore/listings.json'), JSON.stringify(out, null, 2) + '\n');

console.log('written docs/appstore/listings.json');
for (const [field, limit] of Object.entries(LIMITS)) {
  const used = english[field].length;
  const flag = used <= limit ? 'ok' : 'OVER LIMIT';
  console.log(`  en.${field.padEnd(16)} ${String(used).padStart(4)}/${limit}  ${flag}`);
}
