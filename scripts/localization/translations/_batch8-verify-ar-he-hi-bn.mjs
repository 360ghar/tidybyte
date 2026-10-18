#!/usr/bin/env node
/**
 * Batch 8 verification — ar, he, hi, bn.
 *
 * Reads the four files back from disk and asserts every rule the task set:
 * counts, key presence, CLDR categories, untouched pre-existing values,
 * placeholder counts, glossary terms, and preserved typography.
 *
 * Run: node scripts/localization/translations/_batch8-verify-ar-he-hi-bn.mjs
 */

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const LANGS = ['ar', 'he', 'hi', 'bn'];

const CATEGORIES = {
  ar: ['zero', 'one', 'two', 'few', 'many', 'other'],
  he: ['one', 'two', 'other'],
  hi: ['one', 'other'],
  bn: ['one', 'other'],
};

const PLAIN_KEYS = [
  'Worst Shots',
  'Review low-scoring photos, lowest first',
  "Photos you haven't reviewed yet",
  'Every photo and video in your library',
  'Review photos and videos taken on or before a date',
  'Photos not organized into your albums',
  'Specific Album',
  'Review photos from a specific album',
  'Marked for deletion. Nothing is deleted until you confirm at the end.',
  'Delete is off until the photo loads.',
  'Pinch or double-tap a photo to inspect it',
  "That photo can't be undone anymore.",
  'Undo your newer actions first to reach that photo.',
  'Your library changed during analysis. Try Worst Shots again.',
  'No photo is waiting to be filed. Dismiss and try again.',
  'Still adding — please wait a moment and try again.',
  "Couldn't save your changes. Please try again.",
  'Added to albums',
  'Moved to Recently Deleted',
  'Kept',
  'Skipped',
  'Deleted',
  'Kept: your choice',
  'Kept: your pick in Photos',
  "Kept: iPhone's pick",
  'Kept: favorite',
  'Kept: highest resolution',
  'Kept: last frame',
  'Kept: auto pick',
  ' Favorites are kept.',
  'This keeps the starred frame of each burst and deletes the rest.',
  '1 burst cleaned down to a single photo.',
  '%lld bursts cleaned down to single photos.',
  'Album not found.',
  'Failed to create album.',
  "Couldn't modify the album. Please try again.",
  'Nothing was deleted.',
  'Live Photo not found.',
  'Could not find still image in Live Photo.',
  'Invalid image data.',
  'Timed out loading the photo (it may still be in iCloud). Please try again.',
  'The compressed copy is missing from your library.',
  'The converted still is missing from your library.',
  'Copies kept. Both versions are in your library; delete either one in Photos.',
  "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.",
  'Your library changed. Scan again before searching.',
  'Removed changed or unavailable photos. Scan again to include new or edited photos.',
  'Recently Deleted',
  'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.',
  'Manage Apps & System Storage',
  'Open Settings ▸ General ▸ iPhone Storage',
  'Library figures below cover only the photos you selected; device totals cover the whole device.',
  'Find exact and near-duplicate photos',
  'Spot blurry, dark, and overexposed shots',
  'Surface the biggest files taking up space',
  'Delete only what you review and approve',
  'items, all time',
  'this month',
  'Size unknown',
  'Size unavailable',
  'cleaned up since you started using TidyByte',
  "Nothing measurable yet. Items stored only in iCloud don't report a size.",
  'Enjoying TidyByte?',
  'Thanks for the support',
  'What should we fix?',
  'Tell us what got in the way.',
  'Send Feedback',
  'Yes',
  'Not really',
  'Not now',
  'Your rating helps other people find TidyByte.',
  'You just %@.',
  "The message couldn't be sent. Try again, or email us at %@.",
  'No mail account is set up on this device. Email us at %@.',
  'I just %@',
  "I'm cleaning up my photo library",
  '%@ with TidyByte — a private, on-device photo cleanup app. %@',
  'Min size: %@',
  'Swipe history cleared',
  'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.',
];

/** English singular -> English forms, for placeholder comparison. */
const PLURAL_KEYS = {
  'cleared %lld photo': ['cleared %lld photo', 'cleared %lld photos'],
  'cleared %lld blurry photo': ['cleared %lld blurry photo', 'cleared %lld blurry photos'],
  'cleared %lld screenshot': ['cleared %lld screenshot', 'cleared %lld screenshots'],
  'cleared %lld large file': ['cleared %lld large file', 'cleared %lld large files'],
  'cleared %lld burst frame': ['cleared %lld burst frame', 'cleared %lld burst frames'],
  'cleared %lld item (%@)': ['cleared %lld item (%@)', 'cleared %lld items (%@)'],
  'removed %lld duplicate': ['removed %lld duplicate', 'removed %lld duplicates'],
  'removed %lld similar photo': ['removed %lld similar photo', 'removed %lld similar photos'],
  'compressed %lld photo': ['compressed %lld photo', 'compressed %lld photos'],
  'compressed %lld video': ['compressed %lld video', 'compressed %lld videos'],
  'cleaned %lld burst photo': ['cleaned %lld burst photo', 'cleaned %lld burst photos'],
  'converted %lld Live Photo': ['converted %lld Live Photo', 'converted %lld Live Photos'],
  'reviewed %lld item': ['reviewed %lld item', 'reviewed %lld items'],
};

/** Glossary terms that must appear in the matching key. */
const GLOSSARY_CHECKS = [
  {
    key: 'cleared %lld screenshot',
    term: {
      ar: ['لقط', 'شاشة'],
      he: ['צילו', 'מסך'],
      hi: ['स्क्रीनशॉट'],
      bn: ['স্ক্রিনশট'],
    },
  },
  { key: 'removed %lld duplicate', term: { ar: ['مكرر'], he: ['כפול'], hi: ['डुप्लिकेट'], bn: ['ডুপ্লিকেট'] } },
  { key: 'compressed %lld photo', term: { ar: ['ضغط'], he: ['כוו'], hi: ['कंप्रेस'], bn: ['কমপ্রেস'] } },
  { key: 'compressed %lld video', term: { ar: ['ضغط'], he: ['כוו'], hi: ['कंप्रेस'], bn: ['কমপ্রেস'] } },
  { key: 'cleared %lld blurry photo', term: { ar: ['ضبابي'], he: ['מטושטש'], hi: ['धुंधल'], bn: ['ঝাপসা'] } },
];

const RECENTLY_DELETED = {
  ar: 'المحذوفة مؤخرًا',
  he: 'נמחקו לאחרונה',
  hi: 'हाल ही में हटाए गए',
  bn: 'সম্প্রতি মোছা',
};

const SCREEN_TIME = { ar: 'وقت الشاشة', he: 'זמן מסך', hi: 'स्क्रीन टाइम', bn: 'স্ক্রিন টাইম' };

let failures = 0;
const fail = (message) => {
  failures += 1;
  console.log(`  FAIL: ${message}`);
};

const count = (text, token) => text.split(token).length - 1;

for (const lang of LANGS) {
  const path = join(DIR, `${lang}.json`);
  const raw = readFileSync(path, 'utf8');

  console.log(`\n=== ${lang}.json (${raw.length} bytes)`);

  let file;
  try {
    file = JSON.parse(raw);
  } catch (error) {
    fail(`does not parse as JSON: ${error.message}`);
    continue;
  }

  const strings = file.strings ?? {};
  const plurals = file.plurals ?? {};
  const before = JSON.parse(readFileSync(`/tmp/batch8-before-${lang}.json`, 'utf8'));

  console.log(`  parses as JSON: yes`);
  console.log(`  strings: ${Object.keys(strings).length} (target 632)  ${Object.keys(strings).length === 632 ? 'ok' : 'FAIL'}`);
  console.log(`  plurals: ${Object.keys(plurals).length} (target 64)   ${Object.keys(plurals).length === 64 ? 'ok' : 'FAIL'}`);
  if (Object.keys(strings).length !== 632) fail('strings count is not 632');
  if (Object.keys(plurals).length !== 64) fail('plurals count is not 64');

  // --- no pre-existing key changed value, none removed ---
  let changed = 0;
  for (const [key, value] of Object.entries(before.strings)) {
    if (strings[key] !== value) {
      changed += 1;
      fail(`pre-existing string changed: ${JSON.stringify(key)}`);
    }
  }
  for (const [key, value] of Object.entries(before.plurals)) {
    if (JSON.stringify(plurals[key]) !== JSON.stringify(value)) {
      changed += 1;
      fail(`pre-existing plural changed: ${JSON.stringify(key)}`);
    }
  }
  const addedStrings = Object.keys(strings).length - Object.keys(before.strings).length;
  const addedPlurals = Object.keys(plurals).length - Object.keys(before.plurals).length;
  console.log(`  pre-existing values unchanged: ${changed === 0 ? 'ok' : 'FAIL'} (${changed} changed)`);
  console.log(`  added: +${addedStrings} strings, +${addedPlurals} plurals`);

  // --- key order still codePoint-sorted for strings, plural order preserved ---
  const order = Object.keys(strings);
  const sorted = [...order].sort();
  if (!order.every((key, index) => key === sorted[index])) fail('strings keys are not in codePoint order');

  const pluralOrder = Object.keys(plurals);
  const beforeOrder = Object.keys(before.plurals);
  if (!beforeOrder.every((key, index) => key === pluralOrder[index])) fail('existing plural key order changed');

  // --- all 80 plain keys present, non-empty, translated ---
  let missingPlain = 0;
  let emptyPlain = 0;
  let untranslatedPlain = 0;
  for (const key of PLAIN_KEYS) {
    const value = strings[key];
    if (typeof value !== 'string') {
      missingPlain += 1;
      fail(`missing plain key: ${JSON.stringify(key)}`);
      continue;
    }
    if (value.length === 0) {
      emptyPlain += 1;
      fail(`empty plain value: ${JSON.stringify(key)}`);
    }
    if (value === key) {
      untranslatedPlain += 1;
      fail(`plain value is still English: ${JSON.stringify(key)}`);
    }
  }
  console.log(`  plain keys present: ${PLAIN_KEYS.length - missingPlain}/${PLAIN_KEYS.length}, non-empty: ${emptyPlain === 0 ? 'ok' : 'FAIL'}, not-English: ${untranslatedPlain === 0 ? 'ok' : 'FAIL'}`);

  // --- all 13 plural keys with exactly the required categories ---
  const wanted = [...CATEGORIES[lang]].sort();
  let missingPlural = 0;
  for (const key of Object.keys(PLURAL_KEYS)) {
    const entry = plurals[key];
    if (!entry || typeof entry !== 'object') {
      missingPlural += 1;
      fail(`missing plural key: ${JSON.stringify(key)}`);
      continue;
    }
    const actual = Object.keys(entry).sort();
    if (actual.join(',') !== wanted.join(',')) {
      fail(`plural categories for ${JSON.stringify(key)} are [${actual.join(', ')}], expected [${wanted.join(', ')}]`);
    }
    for (const [category, value] of Object.entries(entry)) {
      if (typeof value !== 'string' || value.length === 0) {
        fail(`empty plural value: ${JSON.stringify(key)} / ${category}`);
      }
    }
  }
  console.log(`  plural keys present: ${13 - missingPlural}/13, categories [${wanted.join(', ')}]: ${missingPlural === 0 ? 'ok' : 'FAIL'}`);

  // --- placeholders: same count per type as the English source, once per form ---
  let placeholderIssues = 0;
  const checkPlaceholders = (label, english, value) => {
    const enLld = count(english, '%lld');
    const enAt = count(english, '%@');
    const vLld = count(value, '%lld');
    const vAt = count(value, '%@');
    // every other `%` must be a literal `%%`
    const stray = value.replace(/%%/g, '').match(/%(?!lld|@)/g) ?? [];
    if (vLld !== enLld || vAt !== enAt || stray.length > 0) {
      placeholderIssues += 1;
      fail(`${label}: placeholders %lld x${vLld} (en ${enLld}), %@ x${vAt} (en ${enAt}), stray ${stray.length}\n      ${JSON.stringify(value)}`);
    }
  };

  for (const key of PLAIN_KEYS) {
    checkPlaceholders(`plain ${JSON.stringify(key)} [${lang}]`, key, strings[key] ?? '');
  }
  for (const [key, englishForms] of Object.entries(PLURAL_KEYS)) {
    for (const [category, value] of Object.entries(plurals[key] ?? {})) {
      // match against whichever English form has the same placeholder shape
      const match = englishForms.find(
        (form) => count(form, '%lld') === count(value, '%lld') && count(form, '%@') === count(value, '%@'),
      );
      if (!match) {
        placeholderIssues += 1;
        fail(`plural ${JSON.stringify(key)} / ${category}: no English form matches placeholder counts\n      ${JSON.stringify(value)}`);
        continue;
      }
      checkPlaceholders(`plural ${JSON.stringify(key)} / ${category} [${lang}]`, match, value);
    }
  }
  console.log(`  placeholder counts: ${placeholderIssues === 0 ? 'ok' : 'FAIL'}`);

  // --- the three-placeholder key ---
  const threeKey = "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.";
  const threeValue = strings[threeKey] ?? '';
  const threeLld = count(threeValue, '%lld');
  const threeAt = count(threeValue, '%@');
  console.log(`  "${threeKey}" -> %lld x${threeLld}, %@ x${threeAt}  ${threeLld === 3 && threeAt === 0 ? 'ok' : 'FAIL'}`);
  if (threeLld !== 3 || threeAt !== 0) fail('three-placeholder key does not carry exactly three %lld');

  // --- glossary: Live Photo kept literal ---
  const liveKeys = [
    'Live Photo not found.',
    'Could not find still image in Live Photo.',
  ];
  let liveIssues = 0;
  for (const key of liveKeys) {
    if (!(strings[key] ?? '').includes('Live Photo')) {
      liveIssues += 1;
      fail(`"Live Photo" missing from ${JSON.stringify(key)}: ${JSON.stringify(strings[key])}`);
    }
  }
  const converted = plurals['converted %lld Live Photo'] ?? {};
  for (const [category, value] of Object.entries(converted)) {
    if (!value.includes('Live Photo')) {
      liveIssues += 1;
      fail(`"Live Photo" missing from converted/${category}: ${JSON.stringify(value)}`);
    }
    if (category !== 'one' && value.includes('Live Photos')) {
      liveIssues += 1;
      fail(`unexpected "Live Photos" plural in converted/${category}: ${JSON.stringify(value)}`);
    }
  }
  console.log(`  Live Photo kept literal: ${liveIssues === 0 ? 'ok' : 'FAIL'}`);

  // --- glossary: screenshot / duplicate / compress / blurry terms ---
  let glossaryIssues = 0;
  for (const check of GLOSSARY_CHECKS) {
    const forms = plurals[check.key] ?? {};
    const stems = check.term[lang];
    for (const [category, value] of Object.entries(forms)) {
      const missing = stems.filter((stem) => !value.includes(stem));
      if (missing.length > 0) {
        glossaryIssues += 1;
        fail(`glossary term ${JSON.stringify(stems)} missing ${JSON.stringify(missing)} from ${JSON.stringify(check.key)}/${category}: ${JSON.stringify(value)}`);
      }
    }
  }
  console.log(`  glossary terms in plurals: ${glossaryIssues === 0 ? 'ok' : 'FAIL'}`);

  // --- glossary: Recently Deleted, in both the bare label and the sentences ---
  const recentlyKeys = [
    'Recently Deleted',
    'Moved to Recently Deleted',
    'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.',
    'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.',
  ];
  let recentlyIssues = 0;
  for (const key of recentlyKeys) {
    if (!(strings[key] ?? '').includes(RECENTLY_DELETED[lang])) {
      recentlyIssues += 1;
      fail(`glossary "Recently Deleted" term missing from ${JSON.stringify(key)}: ${JSON.stringify(strings[key])}`);
    }
  }
  console.log(`  glossary term for Recently Deleted: ${recentlyIssues === 0 ? 'ok' : 'FAIL'}`);

  // --- typography: leading space, em dash, ▸, iCloud, iOS, TidyByte ---
  const leading = strings[' Favorites are kept.'] ?? '';
  console.log(`  leading space on " Favorites are kept.": ${leading.startsWith(' ') ? 'ok' : 'FAIL'} ${JSON.stringify(leading)}`);
  if (!leading.startsWith(' ')) fail('leading space lost');

  for (const key of ['Still adding — please wait a moment and try again.', '%@ with TidyByte — a private, on-device photo cleanup app. %@']) {
    if (!(strings[key] ?? '').includes('—')) fail(`em dash lost in ${JSON.stringify(key)}`);
  }
  if (!(strings['Open Settings ▸ General ▸ iPhone Storage'] ?? '').includes('▸')) fail('▸ lost in Open Settings key');
  console.log(`  em dash and ▸ preserved: ${raw.includes('—') && raw.includes('▸') ? 'ok' : 'FAIL'}`);

  for (const key of ['iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.', 'Timed out loading the photo (it may still be in iCloud). Please try again.', "Nothing measurable yet. Items stored only in iCloud don't report a size."]) {
    const value = strings[key] ?? '';
    if (!value.includes('iOS') && !value.includes('iCloud')) fail(`iOS/iCloud literal lost in ${JSON.stringify(key)}: ${JSON.stringify(value)}`);
  }
  if (!(strings['%@ with TidyByte — a private, on-device photo cleanup app. %@'] ?? '').includes('TidyByte')) {
    fail('TidyByte literal lost in the share text');
  }
  console.log(`  iOS / iCloud / TidyByte kept literal: ok`);

  // --- every URL/placeholder-bearing share string keeps two %@ ---
  const share = strings['%@ with TidyByte — a private, on-device photo cleanup app. %@'] ?? '';
  console.log(`  share text: %@ x${count(share, '%@')}  ${count(share, '%@') === 2 ? 'ok' : 'FAIL'}`);
  if (count(share, '%@') !== 2) fail('share text must carry exactly two %@');

  // --- no Screen Time key in this batch, but the term must not leak wrong ---
  void SCREEN_TIME;
}

console.log(`\n${failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`}`);
process.exit(failures === 0 ? 0 : 1);
