// Batch 8 verification for te, kn, ml, ru.
//
// Reads the four files back from disk and asserts the batch is correct.
// Run: node _batch8-verify-teknmlru.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const BASELINE = "/tmp/batch8-baseline";
const LANGS = ["te", "kn", "ml", "ru"];
const CATEGORIES = {
  te: ["one", "other"],
  kn: ["one", "other"],
  ml: ["one", "other"],
  ru: ["one", "few", "many", "other"],
};

// The 80 plain keys, read straight from the brief's Part B tables.
const NEW_PLAIN = JSON.parse(fs.readFileSync("/tmp/batch8-plain-keys.json", "utf8"));
const PLAIN_SET = new Set(NEW_PLAIN);

// The 13 plural keys: everything the _plural-keys.json catalog lists after the
// 51 keys that were already shipped.
const pluralCatalog = JSON.parse(
  fs.readFileSync(path.join(here, "_plural-keys.json"), "utf8"),
);
const ALL_PLURAL = Object.keys(pluralCatalog);
const NEW_PLURAL = ALL_PLURAL.slice(51);

const failures = [];
let assertions = 0;
function check(ok, msg) {
  assertions += 1;
  if (!ok) failures.push(msg);
  return ok;
}

const countOf = (haystack, needle) => haystack.split(needle).length - 1;
const pluralCount = (s) => s.split("%lld").length - 1 + s.split("%@").length - 1;

// Placeholders the English source spells out, per key.
const sourcePlaceholders = new Map(
  [...NEW_PLAIN, ...NEW_PLURAL].map((k) => [k, { lld: countOf(k, "%lld"), at: countOf(k, "%@") }]),
);

// Latin-script words that are allowed to survive in a non-English value.
const LATIN_ALLOWED = new Set([
  "TidyByte", "iOS", "iPhone", "iPad", "iCloud", "Live", "Photo", "Photos",
  "HEIC", "MB", "GB", "KB", "PNG", "JPEG", "ProRAW", "ProRes", "RAW", "JPEG",
  "HDR", "App", "Store", "Siri", "Shortcuts", "Spotlight", "1080p", "720p",
  "480p", "3K", "2K",
]);

console.log(`new plain keys:  ${NEW_PLAIN.length}`);
console.log(`new plural keys: ${NEW_PLURAL.length}`);
console.log("");

for (const lang of LANGS) {
  const file = path.join(here, `${lang}.json`);
  let json;
  try {
    json = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    check(false, `${lang}: does not parse as JSON: ${e.message}`);
    continue;
  }
  const baseline = JSON.parse(fs.readFileSync(path.join(BASELINE, `${lang}.json`), "utf8"));

  check(typeof json.strings === "object" && json.strings, `${lang}: no "strings" object`);
  check(typeof json.plurals === "object" && json.plurals, `${lang}: no "plurals" object`);

  const keys = Object.keys(json.strings);
  const pkeys = Object.keys(json.plurals);

  // ---- counts
  check(keys.length === 632, `${lang}: expected 632 strings, got ${keys.length}`);
  check(pkeys.length === 64, `${lang}: expected 64 plurals, got ${pkeys.length}`);

  // ---- every new plain key present, non-empty, string
  const missingPlain = NEW_PLAIN.filter((k) => !(k in json.strings));
  check(missingPlain.length === 0, `${lang}: missing plain keys ${JSON.stringify(missingPlain)}`);
  const emptyPlain = NEW_PLAIN.filter(
    (k) => typeof json.strings[k] !== "string" || json.strings[k].trim() === "",
  );
  check(emptyPlain.length === 0, `${lang}: non-string or empty values ${JSON.stringify(emptyPlain)}`);

  // ---- every new plural key present with exactly the right categories
  const missingPlural = NEW_PLURAL.filter((k) => !(k in json.plurals));
  check(missingPlural.length === 0, `${lang}: missing plural keys ${JSON.stringify(missingPlural)}`);
  const badCats = [];
  const badForms = [];
  for (const k of NEW_PLURAL) {
    const entry = json.plurals[k];
    if (!entry || typeof entry !== "object") {
      badCats.push(`${k}: not an object`);
      continue;
    }
    const actual = Object.keys(entry).sort();
    const wanted = [...CATEGORIES[lang]].sort();
    if (actual.join(",") !== wanted.join(",")) {
      badCats.push(`${k}: [${actual.join(", ")}] != [${wanted.join(", ")}]`);
    }
    for (const c of Object.keys(entry)) {
      if (typeof entry[c] !== "string" || entry[c].trim() === "") {
        badForms.push(`${k}.${c}: empty`);
      }
    }
  }
  check(badCats.length === 0, `${lang}: plural category problems ${JSON.stringify(badCats)}`);
  check(badForms.length === 0, `${lang}: empty plural forms ${JSON.stringify(badForms)}`);

  // ---- no extra keys beyond baseline + the new batch
  const extraStrings = keys.filter((k) => !(k in baseline.strings) && !PLAIN_SET.has(k));
  check(extraStrings.length === 0, `${lang}: unexpected extra string keys ${JSON.stringify(extraStrings)}`);
  const extraPlurals = pkeys.filter((k) => !(k in baseline.plurals) && !NEW_PLURAL.includes(k));
  check(extraPlurals.length === 0, `${lang}: unexpected extra plural keys ${JSON.stringify(extraPlurals)}`);

  // ---- no pre-existing key changed value or disappeared
  const drift = [];
  for (const [k, v] of Object.entries(baseline.strings)) {
    if (!(k in json.strings)) drift.push(`removed string ${JSON.stringify(k)}`);
    else if (json.strings[k] !== v) drift.push(`changed string ${JSON.stringify(k)}`);
  }
  for (const [k, v] of Object.entries(baseline.plurals)) {
    if (!(k in json.plurals)) drift.push(`removed plural ${JSON.stringify(k)}`);
    else if (JSON.stringify(json.plurals[k]) !== JSON.stringify(v)) {
      drift.push(`changed plural ${JSON.stringify(k)}`);
    }
  }
  check(drift.length === 0, `${lang}: pre-existing key drift ${JSON.stringify(drift)}`);

  // ---- sort order: strings plain UTF-16 code-unit, plurals appended in catalog order
  const sortedKeys = [...keys].sort();
  check(
    JSON.stringify(keys) === JSON.stringify(sortedKeys),
    `${lang}: string key order is not the file's plain sort order`,
  );
  check(
    JSON.stringify(pkeys.slice(0, 51)) === JSON.stringify(ALL_PLURAL.slice(0, 51)),
    `${lang}: pre-existing plural key order changed`,
  );
  check(
    JSON.stringify(pkeys.slice(51)) === JSON.stringify(NEW_PLURAL),
    `${lang}: new plural keys are not appended in catalog order`,
  );

  // ---- placeholders: exactly once per form, same count and type as the source
  const phProblems = [];
  for (const k of [...NEW_PLAIN, ...NEW_PLURAL]) {
    const src = sourcePlaceholders.get(k);
    const forms = k in json.plurals ? Object.values(json.plurals[k]) : [json.strings[k]];
    for (const form of forms) {
      if (typeof form !== "string") continue;
      const lld = countOf(form, "%lld");
      const at = countOf(form, "%@");
      if (lld !== src.lld) {
        phProblems.push(`${JSON.stringify(k)}: %lld x${lld}, source has x${src.lld} :: ${form}`);
      }
      if (at !== src.at) {
        phProblems.push(`${JSON.stringify(k)}: %@ x${at}, source has x${src.at} :: ${form}`);
      }
      // No positional syntax and no stray percent signs.
      if (/%\d+\$/.test(form)) phProblems.push(`${JSON.stringify(k)}: positional syntax used :: ${form}`);
      const stripped = form.replace(/%(lld|@)/g, "");
      if (/%/.test(stripped)) phProblems.push(`${JSON.stringify(k)}: stray % :: ${form}`);
    }
  }
  check(phProblems.length === 0, `${lang}: placeholder problems ${JSON.stringify(phProblems)}`);

  // The three-placeholder key, explicitly.
  const THREE = "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.";
  check(
    pluralCount(json.strings[THREE] ?? "") === 3,
    `${lang}: "${THREE}" has ${pluralCount(json.strings[THREE] ?? "")} placeholders, expected 3`,
  );

  // ---- punctuation and whitespace carried over from the source
  const punct = [];
  if (!json.strings["Still adding — please wait a moment and try again."].includes("—")) {
    punct.push("em dash lost in 'Still adding — ...'");
  }
  if (!json.strings["%@ with TidyByte — a private, on-device photo cleanup app. %@"].includes("—")) {
    punct.push("em dash lost in share text");
  }
  if (!json.strings["Open Settings ▸ General ▸ iPhone Storage"].includes("▸")) {
    punct.push("U+25B8 lost in 'Open Settings ...'");
  }
  if (countOf(json.strings["Open Settings ▸ General ▸ iPhone Storage"], "▸") !== 2) {
    punct.push("expected exactly two U+25B8 separators");
  }
  check(!json.strings[" Favorites are kept."].startsWith("Favorites"), "leading space lost in ' Favorites are kept.'");
  // Trailing punctuation of each new key matches the source.
  for (const k of NEW_PLAIN) {
    const srcEnd = k[k.length - 1];
    const val = json.strings[k];
    if (srcEnd === "." && !val.endsWith(".")) punct.push(`${JSON.stringify(k)}: lost trailing period`);
    if (srcEnd !== "." && val.endsWith(".") && !/[!?]/.test(srcEnd)) {
      punct.push(`${JSON.stringify(k)}: added trailing period`);
    }
    if (srcEnd === "?" && !val.endsWith("?")) punct.push(`${JSON.stringify(k)}: lost question mark`);
  }
  check(punct.length === 0, `${lang}: punctuation problems ${JSON.stringify(punct)}`);

  // ---- glossary terms
  const glossMissing = [];
  const gloss = {
    te: {
      "Recently Deleted": "ఇటీవల తొలగించినవి",
      screenshot: "స్క్రీన్షాట్",
      duplicate: "నకిలీ",
    },
    kn: {
      "Recently Deleted": "ಇತ್ತೀಚೆಗೆ ಅಳಿಸಿದವು",
      screenshot: "ಸ್ಕ್ರೀನ್ಶಾಟ್",
      duplicate: "ನಕಲಿ",
    },
    ml: {
      "Recently Deleted": "അടുത്തിടെ ഇല്ലാതാക്കിയവ",
      screenshot: "സ്ക്രീൻഷോട്ട്",
      duplicate: "ഡ്യൂപ്ലിക്കേറ്റ്",
    },
    ru: {
      "Recently Deleted": "Недавно удаленные",
      screenshot: "скриншот",
      duplicate: "дубликат",
    },
  }[lang];
  const need = [
    [gloss["Recently Deleted"], "Recently Deleted"],
    [gloss["Recently Deleted"], "Moved to Recently Deleted"],
    [gloss["Recently Deleted"], "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted."],
    [gloss["Recently Deleted"], "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days."],
    [gloss.screenshot, "cleared %lld screenshot"],
    [gloss.duplicate, "removed %lld duplicate"],
  ];
  for (const [term, key] of need) {
    const val = json.strings[key] ?? Object.values(json.plurals[key] ?? {}).join(" ");
    if (!val.includes(term)) glossMissing.push(`${JSON.stringify(key)} missing ${JSON.stringify(term)}`);
  }
  // keepLiteral terms stay verbatim.
  const literal = ["TidyByte", "iPhone", "iOS", "iCloud", "Live Photo", "Live Photos"];
  const literalKeys = [
    "Thanks for the support", "Enjoying TidyByte?", "Your rating helps other people find TidyByte.",
    "cleaned up since you started using TidyByte", "Nothing measurable yet. Items stored only in iCloud don't report a size.",
    "Kept: iPhone's pick", "Open Settings ▸ General ▸ iPhone Storage",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.",
    "Could not find still image in Live Photo.", "Timed out loading the photo (it may still be in iCloud). Please try again.",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@",
  ];
  for (const k of literalKeys) {
    const val = json.strings[k];
    for (const t of literal) {
      if (k.includes(t) && !val.includes(t)) glossMissing.push(`${JSON.stringify(k)} missing literal ${JSON.stringify(t)}`);
    }
  }
  check(glossMissing.length === 0, `${lang}: glossary problems ${JSON.stringify(glossMissing)}`);

  // ---- Latin leftovers in the new values (untranslated text)
  const latin = new Set();
  for (const k of [...NEW_PLAIN, ...NEW_PLURAL]) {
    const forms =
      k in json.plurals ? Object.values(json.plurals[k]) : [json.strings[k]];
    for (const form of forms) {
      // Placeholders are not prose; drop them before looking for Latin words.
      const prose = String(form).replace(/%(?:\d+\$)?(?:lld|@)/g, " ");
      for (const word of prose.split(/[^\p{Script=Latin}\p{N}]+/u)) {
        if (!word || !/\p{Script=Latin}/u.test(word)) continue;
        if (LATIN_ALLOWED.has(word)) continue;
        if (/^\d+$/.test(word)) continue;
        latin.add(word);
      }
    }
  }
  check(latin.size === 0, `${lang}: untranslated Latin text ${JSON.stringify([...latin])}`);

  // ---- report
  console.log(
    `${lang}.json  parse=ok  strings=${keys.length}  plurals=${pkeys.length}  ` +
      `newPlain=${NEW_PLAIN.length - missingPlain.length}/${NEW_PLAIN.length}  ` +
      `newPlurals=${NEW_PLURAL.length - missingPlural.length}/${NEW_PLURAL.length}  ` +
      `cats=[${CATEGORIES[lang].join(",")}]  baselineDrift=${drift.length}  ` +
      `sorted=ok  placeholders=ok`,
  );
}

console.log("");
console.log(`${assertions} assertions run`);
if (failures.length) {
  console.log(`FAILED (${failures.length}):`);
  for (const f of failures) console.log("  - " + f);
  process.exit(1);
}
console.log("ALL CHECKS PASSED");
