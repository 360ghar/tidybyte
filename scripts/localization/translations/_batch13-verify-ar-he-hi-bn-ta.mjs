#!/usr/bin/env node
// Batch 13 (ar, he, hi, bn, ta) verification. Reads the five files BACK FROM
// DISK and asserts the batch landed correctly and changed nothing else.
//
// Run: node scripts/localization/translations/_batch13-verify-ar-he-hi-bn-ta.mjs

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
// Optional pre-batch snapshot, used only as a cross-check when it is present.
const backupDir = "/tmp/batch13-backup";

const KEYS = JSON.parse(readFileSync(join(here, "_batch13-keys.json"), "utf8"));
const LANGS = ["ar", "he", "hi", "bn", "ta"];

const NO_LARGE_PHOTOS =
  "No photos larger than %lld MB. Lower the threshold or switch to All/Videos.";
const NO_LARGE_VIDEOS =
  "No videos larger than %lld MB. Lower the threshold or switch to All/Photos.";

// Values that are legitimately identical to the English key.
const MAY_EQUAL_ENGLISH = new Set([]);

// The 16 labels live in segmented controls (3 or 4 segments share the width) and
// one menu. Anything much longer than the English risks truncation; report it
// rather than silently shipping a clipped label.
const LIMIT = 1.5;

// Cross-language sanity: the three labels must not be each other's substrings,
// or the "sentence names the segment" check below would pass by accident.
const PAIR_KEYS = ["All", "Photos", "Videos"];

// The exact segment reference each fixed sentence must contain. The label is a
// bare form on the control; the sentence needs quotes (ar/he), a postposition
// (hi), a locative (bn) or a dative (ta). The stem check ties each form back to
// the label stored in the file.
const SENTENCE_FORMS = {
  ar: {
    [NO_LARGE_PHOTOS]: "«الكل»/«الفيديوهات»",
    [NO_LARGE_VIDEOS]: "«الكل»/«الصور»",
  },
  he: {
    [NO_LARGE_PHOTOS]: '"הכול"/"סרטונים"',
    [NO_LARGE_VIDEOS]: '"הכול"/"תמונות"',
  },
  hi: {
    [NO_LARGE_PHOTOS]: "सभी/वीडियो",
    [NO_LARGE_VIDEOS]: "सभी/फ़ोटो",
  },
  bn: {
    [NO_LARGE_PHOTOS]: "সব/ভিডিও-তে",
    [NO_LARGE_VIDEOS]: "সব/ফটো-তে",
  },
  ta: {
    [NO_LARGE_PHOTOS]: "அனைத்தும்/வீடியோக்களுக்கு",
    [NO_LARGE_VIDEOS]: "அனைத்தும்/புகைப்படங்களுக்கு",
  },
};

let failures = 0;
const fail = (lang, msg) => {
  failures += 1;
  console.log(`  FAIL [${lang}] ${msg}`);
};
const note = (lang, msg) => console.log(`  note [${lang}] ${msg}`);

const specs = (s) => {
  const out = [];
  for (const m of s.matchAll(/%(?:(\d+)\$)?([@a-zA-Z]+)/g)) out.push(`${m[1] ?? ""}%${m[2]}`);
  return out.sort();
};
const count = (s, needle) => s.split(needle).length - 1;

console.log(`batch keys: ${KEYS.length}`);
console.log("");

for (const lang of LANGS) {
  console.log(`--- ${lang} ---`);
  const raw = readFileSync(join(here, `${lang}.json`), "utf8");
  const file = JSON.parse(raw); // 1. parses as JSON

  const before = {
    strings: Object.fromEntries(
      Object.entries(file.strings).filter(([k]) => !KEYS.includes(k))
    ),
    plurals: file.plurals,
  };
  const backupPath = join(backupDir, `${lang}.json`);
  if (existsSync(backupPath)) {
    const snap = JSON.parse(readFileSync(backupPath, "utf8"));
    const snapKeys = Object.keys(snap.strings);
    // The two empty-state strings are intentional edits; every other value must
    // be byte-identical to the pre-batch snapshot.
    const changed = snapKeys.filter(
      (k) => file.strings[k] !== snap.strings[k] && k !== NO_LARGE_PHOTOS && k !== NO_LARGE_VIDEOS
    );
    console.log(
      `  pre-batch snapshot: ${snapKeys.length} strings, changed values=${changed.length}`
    );
    if (changed.length) fail(lang, `pre-existing value(s) changed: ${changed.join(" | ")}`);
    if (snapKeys.length !== Object.keys(before.strings).length) {
      fail(lang, "key count drift against the pre-batch snapshot");
    }
    if (JSON.stringify(snap.plurals) !== JSON.stringify(file.plurals)) {
      fail(lang, "plurals changed");
    }
  }

  // 2. strings count
  const n = Object.keys(file.strings).length;
  const expected = Object.keys(before.strings).length + KEYS.length;
  console.log(`  strings: ${Object.keys(before.strings).length} -> ${n} (expected ${expected})`);
  if (n !== expected) fail(lang, `strings count ${n} != ${expected}`);
  if (n !== 700) fail(lang, `strings count ${n} != 700`);

  // 3. every batch key present and non-empty
  const missing = KEYS.filter((k) => typeof file.strings[k] !== "string" || !file.strings[k].trim());
  if (missing.length) fail(lang, `missing/empty: ${missing.join(" | ")}`);

  // 4. untranslated (still English) values
  for (const k of KEYS) {
    if (file.strings[k] === k && !MAY_EQUAL_ENGLISH.has(k)) fail(lang, `"${k}" still English`);
  }

  // 5. length check against English
  const long = [];
  for (const k of KEYS) {
    const v = file.strings[k];
    if (v.length > k.length * LIMIT) long.push(`${k} (${k.length}) -> ${v} (${v.length})`);
  }
  if (long.length) note(lang, `${long.length} label(s) over ${LIMIT}x English: ${long.join(" | ")}`);

  // 6. key order still plain code-unit sort
  const keys = Object.keys(file.strings);
  if (JSON.stringify(keys) !== JSON.stringify([...keys].sort())) fail(lang, "key order not sorted");

  // 7. the two fixed sentences must name the segments with the labels' own
  //    words, in whatever inflected form the sentence needs. SENTENCE_FORMS
  //    records the expected form; the stem check below ties it back to the
  //    label actually stored in this file, so the two cannot drift apart.
  for (const a of PAIR_KEYS) {
    for (const b of PAIR_KEYS) {
      if (a !== b && file.strings[a].includes(file.strings[b])) {
        fail(lang, `label "${a}" contains label "${b}"`);
      }
    }
  }
  const stem = (s) => s.slice(0, Math.ceil(s.length / 2));
  const forms = SENTENCE_FORMS[lang];
  const pairs = [
    [NO_LARGE_PHOTOS, "Videos", "All/Videos"],
    [NO_LARGE_VIDEOS, "Photos", "All/Photos"],
  ];
  for (const [key, otherKey, label] of pairs) {
    const v = file.strings[key];
    const want = forms[key];
    console.log(`  ${label}: ${JSON.stringify(v)}`);
    if (!v) fail(lang, `missing ${key}`);
    if (v.includes("All/") || v.includes("All ")) fail(lang, `${label} still has English "All"`);
    if (!v.includes(want)) fail(lang, `${label} does not contain ${JSON.stringify(want)}`);
    for (const k of ["All", otherKey]) {
      if (!want.includes(stem(file.strings[k]))) {
        fail(lang, `${label}: sentence form does not use the stored "${k}" label`);
      }
    }
    if (JSON.stringify(specs(v)) !== JSON.stringify(specs(key))) {
      fail(lang, `${label} placeholder drift: ${specs(v).join(",")} vs ${specs(key).join(",")}`);
    }
    if (count(v, "%lld") !== 1) fail(lang, `${label} has ${count(v, "%lld")} %lld`);
  }

  // 8. unchanged sentence that names no tab must be byte-identical
  const noTab = "No files larger than %lld MB. Lower the threshold to see more.";
  if (existsSync(backupPath)) {
    const snap = JSON.parse(readFileSync(backupPath, "utf8"));
    if (file.strings[noTab] !== snap.strings[noTab]) fail(lang, "the no-tab sentence changed");
  }
}

console.log("");
console.log(failures ? `${failures} failure(s)` : "all checks passed");
process.exit(failures ? 1 : 0);
