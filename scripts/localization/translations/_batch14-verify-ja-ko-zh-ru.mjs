// Batch 14 verify — re-reads ja/ko/zh-Hans/ru FROM DISK and asserts every rule.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const dir = dirname(fileURLToPath(import.meta.url));
const snapshot = JSON.parse(readFileSync("/tmp/batch14-snapshot.json", "utf8"));

const PLAIN_KEYS = [
  "Mixed",
  "Start here. ",
  "Untitled",
  "media",
  "Couldn't load this photo.",
  "Couldn't load this video.",
  "Couldn't download this photo from iCloud.",
  "Couldn't download this video from iCloud.",
];
const COULDNTS = PLAIN_KEYS.filter((k) => k.startsWith("Couldn't"));
const PLURAL_KEYS = ["%lld exact copies", "%lld look-alike photos"];

// categories the file's pre-existing plurals used (from snapshot)
function catSet(obj) {
  return [...new Set(Object.values(obj).flatMap((v) => Object.keys(v)))].sort();
}

let fail = 0;
const check = (label, ok, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? "  " + detail : ""}`);
  if (!ok) fail++;
};

for (const lang of ["ja", "ko", "zh-Hans", "ru"]) {
  console.log(`\n=== ${lang}.json ===`);
  const raw = readFileSync(join(dir, `${lang}.json`), "utf8");
  let j;
  try {
    j = JSON.parse(raw);
    check("parses", true);
  } catch (e) {
    check("parses", false, e.message);
    continue;
  }

  check("strings = 707", Object.keys(j.strings).length === 707, `got ${Object.keys(j.strings).length}`);
  check("plurals = 66", Object.keys(j.plurals).length === 66, `got ${Object.keys(j.plurals).length}`);
  check("round-trips", JSON.stringify(j, null, 2) + "\n" === raw);

  // 3. plain keys present + non-empty
  for (const k of PLAIN_KEYS) {
    const v = j.strings[k];
    check(`plain present+non-empty: ${JSON.stringify(k)}`, typeof v === "string" && v.length > 0, `= ${JSON.stringify(v)}`);
  }

  // 7. Start here. trailing space
  check("'Start here. ' value ends with a space", j.strings["Start here. "].endsWith(" "));

  // 8. Couldn't sentences end with sentence-ending punctuation
  for (const k of COULDNTS) {
    check(`sentence ends with punctuation: ${JSON.stringify(k)}`, /[.!?。．！？]$/.test(j.strings[k]), `= ${JSON.stringify(j.strings[k])}`);
  }

  // 4. plural keys + category set matches file's other plurals
  const old = snapshot[lang];
  const oldCats = catSet(old.plurals);
  const oldCatSets = [...new Set(Object.values(old.plurals).map((v) => Object.keys(v).sort().join("+")))];

  for (const k of PLURAL_KEYS) {
    const v = j.plurals[k];
    const cats = v ? Object.keys(v).sort() : [];
    check(`plural present: ${JSON.stringify(k)}`, !!v);
    check(`  category set == file's existing set`, cats.join(",") === oldCats.join(","), `got [${cats}] want [${oldCats}]`);
    check(`  same set on every entry`, v ? Object.keys(v).sort().join("+") === oldCatSets[0] : false);
    // 5. %lld exactly once per form
    if (v) for (const [cat, s] of Object.entries(v)) {
      const n = (s.match(/%lld/g) || []).length;
      check(`  %lld x1 [${cat}]`, n === 1, `= ${JSON.stringify(s)} (${n})`);
      check(`  non-empty [${cat}]`, s.length > 0);
    }
  }

  // 6. no pre-existing key changed/removed
  let changed = 0;
  for (const [k, v] of Object.entries(old.strings)) if (j.strings[k] !== v) { changed++; console.log("  changed string:", JSON.stringify(k)); }
  for (const [k, v] of Object.entries(old.plurals)) if (JSON.stringify(j.plurals[k]) !== JSON.stringify(v)) { changed++; console.log("  changed plural:", JSON.stringify(k)); }
  check("0 pre-existing keys changed", changed === 0, `changed=${changed}`);

  // key order still sorted
  const ks = Object.keys(j.strings);
  check(".strings still key-sorted", ks.join("\u0000") === [...ks].sort().join("\u0000"));
}

console.log(`\n${fail === 0 ? "ALL CHECKS PASSED" : fail + " CHECK(S) FAILED"}`);
process.exit(fail === 0 ? 0 : 1);
