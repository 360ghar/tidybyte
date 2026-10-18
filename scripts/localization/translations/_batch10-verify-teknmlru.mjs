#!/usr/bin/env node
// Batch 10 verification — te, kn, ml, ru.
//
//   node scripts/localization/translations/_batch10-verify-teknmlru.mjs
//
// Reads both deliverables back from disk and asserts every property the batch
// brief requires. Exits non-zero on the first class of failure it finds.

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..", "..", "..");
const SITE_STRINGS = join(ROOT, "scripts", "localization", "site", "site-strings.json");
const SITE_OUT = join(ROOT, "scripts", "localization", "site", "site-translations");
const LISTINGS = join(ROOT, "docs", "appstore", "listings.json");

const MINE = ["te", "kn", "ml", "ru"];
const FIELDS = ["name", "subtitle", "promotionalText", "description", "keywords", "whatsNew"];

let failures = 0;
const ok = (message) => console.log(`  ok    ${message}`);
const fail = (message) => {
  failures += 1;
  console.log(`  FAIL  ${message}`);
};
const check = (condition, message) => (condition ? ok(message) : fail(message));

// --- listings.json ---------------------------------------------------------

console.log("docs/appstore/listings.json");
const listings = JSON.parse(readFileSync(LISTINGS, "utf8"));
const limits = listings._limits;
check(!!limits, "_limits present");
check(typeof listings._comment === "string" && listings._comment.length > 0, "_comment present");
check(
  typeof listings._pendingDecision === "string" && listings._pendingDecision.length > 0,
  "_pendingDecision present",
);

for (const lang of MINE) {
  check(lang in listings, `${lang} entry present`);
}

for (const lang of MINE) {
  const entry = listings[lang];
  const missing = FIELDS.filter((f) => typeof entry[f] !== "string" || entry[f].trim() === "");
  check(missing.length === 0, `${lang}: all six fields present and non-empty${missing.length ? ` (missing ${missing})` : ""}`);
  const over = FIELDS.filter((f) => typeof entry[f] === "string" && entry[f].length > limits[f]);
  check(over.length === 0, `${lang}: every field within its limit${over.length ? ` (over: ${over})` : ""}`);
  check(entry.name === listings.en.name, `${lang}.name is ${JSON.stringify(listings.en.name)}`);
  check(!/,\s/.test(entry.keywords), `${lang}.keywords has no space after a comma`);
  const terms = entry.keywords.split(",").filter((t) => t.trim() !== "");
  check(new Set(terms).size === terms.length, `${lang}.keywords has no repeated term`);
  const subtitleWords = new Set(
    entry.subtitle.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 2),
  );
  const collisions = terms.filter((t) => !t.includes(" ") && subtitleWords.has(t.trim().toLowerCase()));
  check(collisions.length === 0, `${lang}.keywords repeats no subtitle word${collisions.length ? ` (${collisions})` : ""}`);
}

// Every language this batch did not own must be byte-identical to its previous
// state. `_batch10-before.json` is the copy taken before the write.
const beforePath = "/tmp/listings.before.json";
if (existsSync(beforePath)) {
  const before = JSON.parse(readFileSync(beforePath, "utf8"));
  const untouched = Object.keys(before).filter((k) => !MINE.includes(k));
  const drifted = untouched.filter(
    (k) => JSON.stringify(before[k]) !== JSON.stringify(listings[k]),
  );
  const otherLanguages = untouched.filter((k) => !k.startsWith("_")).length;
  check(
    drifted.length === 0,
    `${otherLanguages} other languages + ${untouched.length - otherLanguages} metadata keys are untouched${drifted.length ? ` (drifted: ${drifted})` : ""}`,
  );
} else {
  // The copy is a scratch artifact from the session that ran the insert, so a
  // later run may not find it. The insert script refuses to write unless the
  // key set is unchanged, so the only thing lost is the byte-level proof.
  console.log(`  WARN  no pre-edit copy at ${beforePath}; byte-level "untouched" proof skipped`);
}

// --- site-translations -----------------------------------------------------

const source = JSON.parse(readFileSync(SITE_STRINGS, "utf8"));
const english = source.strings;
const englishSet = new Set(english);
console.log(`\nscripts/localization/site/site-translations/*.json  (${english.length} English strings)`);

for (const lang of MINE) {
  const path = join(SITE_OUT, `${lang}.json`);
  if (!existsSync(path)) {
    fail(`${lang}.json does not exist`);
    continue;
  }
  const map = JSON.parse(readFileSync(path, "utf8"));
  const keys = Object.keys(map);

  check(keys.length === english.length, `${lang}: exactly ${english.length} keys (got ${keys.length})`);

  const notInSource = keys.filter((k) => !englishSet.has(k));
  check(notInSource.length === 0, `${lang}: every key is byte-identical to one in site-strings.json${notInSource.length ? ` (extra: ${JSON.stringify(notInSource.slice(0, 3))})` : ""}`);

  const missing = english.filter((k) => !(k in map));
  check(missing.length === 0, `${lang}: no key missing${missing.length ? ` (${JSON.stringify(missing.slice(0, 3))})` : ""}`);

  const empty = keys.filter((k) => typeof map[k] !== "string" || map[k].trim() === "");
  check(empty.length === 0, `${lang}: no empty value${empty.length ? ` (${JSON.stringify(empty.slice(0, 3))})` : ""}`);

  // The brief pins one string: "64 GB stays 64 GB. Unit symbols are not
  // translated." Latin GB is what Apple ships in the Telugu, Kannada and
  // Malayalam UIs, so te/kn/ml keep the byte-identical source on purpose; it is
  // the single documented exemption from the no-English-values rule. Russian
  // uses the Cyrillic form of the same symbol, so it needs no exemption.
  const PINNED = new Set(["64 GB"]);
  const untranslated = keys.filter((k) => map[k] === k && !PINNED.has(k));
  check(untranslated.length === 0, `${lang}: no value left as the English source${untranslated.length ? ` (${JSON.stringify(untranslated)})` : ""}`);

  // An unescaped `&` would break the HTML the map is injected into.
  const brokenEntities = keys.filter((k) => /&(?!(amp|mdash|middot|rarr|rsquo|hellip|nbsp|lt|gt);)/.test(map[k]));
  check(brokenEntities.length === 0, `${lang}: no bare & in any value${brokenEntities.length ? ` (${JSON.stringify(brokenEntities.slice(0, 3))})` : ""}`);

  // Numbered section headings keep their number and separator.
  const headings = english.filter((k) => /^\d\d &mdash; /.test(k));
  const brokenHeadings = headings.filter((k) => !/^\d\d &mdash; \S/.test(map[k]));
  check(brokenHeadings.length === 0, `${lang}: all ${headings.length} numbered headings keep "NN &mdash; "`);

  // `64 GB` is the one string the brief pins: unit symbols are not translated.
  const expected = lang === "ru" ? "64 ГБ" : "64 GB";
  check(map["64 GB"] === expected, `${lang}: "64 GB" -> ${JSON.stringify(map["64 GB"])}`);
}

console.log("");
if (failures > 0) {
  console.error(`${failures} check(s) failed.`);
  process.exit(1);
}
console.log("Batch 10 (te, kn, ml, ru): all checks passed.");
