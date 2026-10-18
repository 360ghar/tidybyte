// Batch 7 verification for te, kn, ml, ru.
//
// Reads the four files back from disk and asserts the batch is correct.
// Run: node _batch7-verify-teknmlru.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const BASELINE = "/tmp/batch7-baseline";
const LANGS = ["te", "kn", "ml", "ru"];

const fail = [];
const note = (s) => console.log(s);
function check(ok, msg) {
  if (!ok) fail.push(msg);
  return ok;
}

// The 57 new keys, read straight from the brief plus the one key the brief's
// prose omits but the source contains.
const briefRaw = fs.readFileSync(path.join(here, "_batch7-brief.md"), "utf8");
const briefKeys = [];
for (const line of briefRaw.split("\n")) {
  const t = line.trim();
  if (!t.startsWith("|") || /^\|\s*-+/.test(t)) continue;
  if (/^\|\s*(Title|English)\s*\|/.test(t)) continue;
  for (const cell of t.split("|").slice(1, -1).map((c) => c.trim())) {
    const m = /^`([^`]+)`$/.exec(cell);
    if (m) briefKeys.push(m[1]);
  }
}
const NEW_KEYS = [...briefKeys, "Failed to re-encode the photo."];
const NEW_SET = new Set(NEW_KEYS);

note(`brief keys: ${briefKeys.length}  + inferred: 1  = new keys: ${NEW_KEYS.length}`);
note("");

for (const lang of LANGS) {
  const file = path.join(here, `${lang}.json`);
  const raw = fs.readFileSync(file, "utf8");

  let json;
  try {
    json = JSON.parse(raw);
  } catch (e) {
    check(false, `${lang}: does not parse as JSON: ${e.message}`);
    continue;
  }
  check(
    typeof json.strings === "object" && json.strings !== null,
    `${lang}: no "strings" object`,
  );
  check(
    typeof json.plurals === "object" && json.plurals !== null,
    `${lang}: no "plurals" object`,
  );

  const keys = Object.keys(json.strings);
  const countOk = check(
    keys.length === 552,
    `${lang}: expected 552 strings, got ${keys.length}`,
  );

  // New keys present and non-empty.
  const missing = NEW_KEYS.filter((k) => !(k in json.strings));
  check(missing.length === 0, `${lang}: missing keys ${JSON.stringify(missing)}`);
  const empty = NEW_KEYS.filter(
    (k) => k in json.strings && String(json.strings[k]).trim() === "",
  );
  check(empty.length === 0, `${lang}: empty translations ${JSON.stringify(empty)}`);

  // No extra keys beyond the baseline + the 57.
  const baseline = JSON.parse(
    fs.readFileSync(path.join(BASELINE, `${lang}.json`), "utf8"),
  );
  const oldKeys = Object.keys(baseline.strings);
  const extra = keys.filter((k) => !(k in baseline.strings) && !NEW_SET.has(k));
  check(extra.length === 0, `${lang}: unexpected extra keys ${JSON.stringify(extra)}`);

  // No pre-existing key changed value; none removed.
  const changed = [];
  for (const k of oldKeys) {
    if (!(k in json.strings)) changed.push(`removed ${JSON.stringify(k)}`);
    else if (json.strings[k] !== baseline.strings[k])
      changed.push(`changed ${JSON.stringify(k)}`);
  }
  check(changed.length === 0, `${lang}: baseline diff ${JSON.stringify(changed)}`);

  // Plurals untouched.
  check(
    JSON.stringify(json.plurals) === JSON.stringify(baseline.plurals),
    `${lang}: plurals changed`,
  );

  // Sort order preserved (plain UTF-16 code-unit sort).
  const sorted = [...keys].sort();
  check(
    JSON.stringify(keys) === JSON.stringify(sorted),
    `${lang}: key sort order is not the file's sort order`,
  );

  // Placeholders: each appears exactly once in a key that has one, and no
  // placeholder appears in a key that has none.
  const placeholderIssues = [];
  for (const k of NEW_KEYS) {
    const v = json.strings[k];
    if (typeof v !== "string") continue;
    for (const ph of ["%lld", "%@"]) {
      const inSource = k.split(ph).length - 1;
      const inValue = v.split(ph).length - 1;
      if (inSource !== inValue) {
        placeholderIssues.push(
          `${JSON.stringify(k)}: ${ph} source=${inSource} value=${inValue}`,
        );
      }
      if (inSource > 0 && inValue !== 1) {
        placeholderIssues.push(
          `${JSON.stringify(k)}: ${ph} must appear exactly once, found ${inValue}`,
        );
      }
    }
    if (/%/.test(v) && !/%(lld|@)/.test(v)) {
      placeholderIssues.push(`${JSON.stringify(k)}: stray % in value`);
    }
  }
  check(
    placeholderIssues.length === 0,
    `${lang}: placeholder problems ${JSON.stringify(placeholderIssues)}`,
  );

  // Placeholder-bearing keys, for the report.
  const withPlaceholders = NEW_KEYS.filter((k) => /%(lld|@)/.test(k));

  note(
    `${lang}.json: parse=ok strings=${keys.length}${countOk ? "" : " (FAIL)"} ` +
      `new=${NEW_KEYS.length - missing.length}/${NEW_KEYS.length} ` +
      `baselineDiff=${changed.length} pluralsUnchanged=${JSON.stringify(json.plurals) === JSON.stringify(baseline.plurals)} ` +
      `sorted=ok placeholders=${withPlaceholders.length} keys`,
  );
}

note("");
if (fail.length) {
  note(`FAILED (${fail.length}):`);
  for (const f of fail) note("  - " + f);
  process.exit(1);
}
note("ALL CHECKS PASSED");
