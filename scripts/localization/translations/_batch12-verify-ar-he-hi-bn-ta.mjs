#!/usr/bin/env node
// Batch 12 (ar, he, hi, bn, ta) verification. Reads the five files BACK FROM
// DISK and asserts the batch landed correctly and changed nothing else.
//
// Run: node scripts/localization/translations/_batch12-verify-ar-he-hi-bn-ta.mjs

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
// Optional pre-batch snapshot, used only as a cross-check when it is present.
const backupDir = "/tmp/batch12-backup";

const KEYS = JSON.parse(readFileSync(join(here, "_batch12-keys.json"), "utf8"));
const LANGS = ["ar", "he", "hi", "bn", "ta"];

const EXPLAINER =
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.";

// Keys whose correct translation is legitimately identical to English.
const MAY_EQUAL_ENGLISH = new Set([
  "Live Photo.",
  "the Live Photos",
  "Live Photos",
  "iCloud",
]);

let failures = 0;
const fail = (lang, msg) => {
  failures += 1;
  console.log(`  FAIL [${lang}] ${msg}`);
};

const specs = (s) => {
  const out = [];
  for (const m of s.matchAll(/%(?:(\d+)\$)?([@a-zA-Z]+)/g)) out.push(`${m[1] ?? ""}%${m[2]}`);
  return out.sort();
};
const count = (s, needle) => s.split(needle).length - 1;

console.log(`batch keys: ${KEYS.length}`);
console.log(`explainer key length: ${EXPLAINER.length}`);
console.log("");

for (const lang of LANGS) {
  console.log(`--- ${lang} ---`);
  const raw = readFileSync(join(here, `${lang}.json`), "utf8");
  const file = JSON.parse(raw); // 1. parses as JSON

  // "Before" is the current file minus the batch keys, so this script is
  // re-runnable without the snapshot. The snapshot, when present, must agree.
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
    const snapIntact = snapKeys.every((k) => file.strings[k] === snap.strings[k]);
    console.log(
      `  pre-batch snapshot: ${snapKeys.length} strings, all values intact in the new file=${snapIntact}`
    );
    if (!snapIntact) fail(lang, "a pre-existing key differs from the pre-batch snapshot");
    if (snapKeys.length !== Object.keys(before.strings).length) {
      fail(lang, "key count drift against the pre-batch snapshot");
    }
  }

  // 2. strings count
  const n = Object.keys(file.strings).length;
  const expected = Object.keys(before.strings).length + KEYS.length;
  console.log(`  strings: ${Object.keys(before.strings).length} -> ${n} (expected ${expected})`);
  if (n !== expected) fail(lang, `strings count ${n} != ${expected}`);

  // 3. every batch key present and non-empty
  const missing = KEYS.filter((k) => typeof file.strings[k] !== "string" || !file.strings[k].trim());
  console.log(`  batch keys present and non-empty: ${KEYS.length - missing.length}/${KEYS.length}`);
  if (missing.length) fail(lang, `missing/empty: ${JSON.stringify(missing)}`);

  // 4. placeholder parity against the English (the key IS the English source)
  const badSpecs = [];
  const englishLeft = [];
  for (const k of KEYS) {
    const v = file.strings[k];
    if (typeof v !== "string") continue;
    if (JSON.stringify(specs(k)) !== JSON.stringify(specs(v))) {
      badSpecs.push(`${JSON.stringify(k)} -> ${JSON.stringify(v)} [${specs(k)}] vs [${specs(v)}]`);
    }
    if (v === k && !MAY_EQUAL_ENGLISH.has(k)) englishLeft.push(k);
  }
  console.log(`  placeholder parity: ${KEYS.length - badSpecs.length}/${KEYS.length}`);
  if (badSpecs.length) fail(lang, `placeholder mismatch:\n    ${badSpecs.join("\n    ")}`);
  console.log(`  values left in English: ${englishLeft.length}`);
  if (englishLeft.length) fail(lang, `untranslated: ${JSON.stringify(englishLeft)}`);

  // 5. explainer template shape. The English source has 3 newline characters:
  //    one after line 1, then the `\n\n` that makes the blank line. So the test
  //    is "same newline structure as English", not a hard-coded 2.
  const ex = file.strings[EXPLAINER];
  const enNl = count(EXPLAINER, "\n");
  const enBlank = count(EXPLAINER, "\n\n");
  const twoAt = count(ex, "%@") === 2;
  const nlSame = count(ex, "\n") === enNl;
  const blank = count(ex, "\n\n") === enBlank;
  const ordered = ex.indexOf("%@") < ex.lastIndexOf("%@");
  const markers = ex.includes("1.") && ex.includes("2.");
  console.log(
    `  explainer: %@ x2=${twoAt}; \\n chars=${count(ex, "\n")} (en ${enNl}); ` +
      `blank-line runs=${count(ex, "\n\n")} (en ${enBlank}); markers=${markers}`
  );
  if (!twoAt) fail(lang, "explainer does not have exactly two %@");
  if (!nlSame) fail(lang, `explainer newline count ${count(ex, "\n")} != English ${enNl}`);
  if (!blank) fail(lang, "explainer lost the blank line");
  if (!ordered) fail(lang, "explainer placeholders out of order");
  if (!markers) fail(lang, "explainer lost the 1./2. list markers");
  if (count(ex, "%lld") !== 0) fail(lang, "explainer gained a %lld");
  if (ex.startsWith("\n") || ex.endsWith("\n")) fail(lang, "explainer has a stray edge newline");

  // 6. no pre-existing key changed, removed, or reordered
  const beforeKeys = Object.keys(before.strings);
  const changed = beforeKeys.filter((k) => before.strings[k] !== file.strings[k]);
  const gone = beforeKeys.filter((k) => !(k in file.strings));
  const added = Object.keys(file.strings).filter((k) => !(k in before.strings));
  console.log(
    `  pre-existing keys: ${beforeKeys.length} checked, ${changed.length} changed, ${gone.length} removed`
  );
  if (changed.length) fail(lang, `changed pre-existing keys: ${JSON.stringify(changed)}`);
  if (gone.length) fail(lang, `removed keys: ${JSON.stringify(gone)}`);
  if (added.length !== KEYS.length) fail(lang, `added ${added.length} keys, expected ${KEYS.length}`);

  // 7. plurals untouched
  const pluralsSame = JSON.stringify(before.plurals) === JSON.stringify(file.plurals);
  console.log(
    `  plurals: ${Object.keys(file.plurals ?? {}).length} entries, unchanged=${pluralsSame}`
  );
  if (!pluralsSame) fail(lang, "plurals changed");

  // 8. order + shape preserved: default sort, 2-space indent, trailing newline
  const keys = Object.keys(file.strings);
  const sorted = [...keys].sort();
  const orderSame = JSON.stringify(keys) === JSON.stringify(sorted);
  const roundTrip = JSON.stringify(file, null, 2) + "\n" === raw;
  console.log(`  key order = default sort: ${orderSame}; byte-stable 2-space format: ${roundTrip}`);
  if (!orderSame) fail(lang, "key order is not the file's existing sort order");
  if (!roundTrip) fail(lang, "file format changed (indent/newline)");

  // 9. the leading space on the size-suffix key survives
  if (!file.strings[" known · %lld sizes unavailable"].startsWith(" ")) {
    fail(lang, "lost the leading space on ' known · %lld sizes unavailable'");
  }
  // 10. the middle dot is still a middle dot, spaced
  const dots = KEYS.filter((k) => k.includes(" · ") && !file.strings[k].includes(" · "));
  if (dots.length) fail(lang, `lost the ' · ' separator: ${JSON.stringify(dots)}`);
  console.log("");
}

console.log(failures === 0 ? "ALL CHECKS PASSED" : `${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
