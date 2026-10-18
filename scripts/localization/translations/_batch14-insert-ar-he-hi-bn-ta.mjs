// Batch 14: add 8 plain strings + 2 plural keys to ar, he, hi, bn, ta.
// Snapshot -> write -> verify by reading back from disk.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const LANGS = ["ar", "he", "hi", "bn", "ta"];
const P = (l) => join(HERE, `${l}.json`);
const serialize = (j) => JSON.stringify(j, null, 2) + "\n";

// --- translations ---------------------------------------------------------
// Plain strings (value identical to English where the term is untranslated).
const plain = {
  ar: {
    "Couldn't download this photo from iCloud.": "تعذر تنزيل هذه الصورة من iCloud.",
    "Couldn't download this video from iCloud.": "تعذر تنزيل هذا الفيديو من iCloud.",
    "Couldn't load this photo.": "تعذر تحميل هذه الصورة.",
    "Couldn't load this video.": "تعذر تحميل هذا الفيديو.",
    "Mixed": "مختلط",
    "Start here. ": "ابدأ من هنا. ",
    "Untitled": "بلا عنوان",
    "media": "الوسائط",
  },
  he: {
    "Couldn't download this photo from iCloud.": "לא ניתן היה להוריד את התמונה הזו מ-iCloud.",
    "Couldn't download this video from iCloud.": "לא ניתן היה להוריד את הסרטון הזה מ-iCloud.",
    "Couldn't load this photo.": "לא ניתן היה לטעון את התמונה הזו.",
    "Couldn't load this video.": "לא ניתן היה לטעון את הסרטון הזה.",
    "Mixed": "מעורב",
    "Start here. ": "התחל כאן. ",
    "Untitled": "ללא כותרת",
    "media": "מדיה",
  },
  hi: {
    "Couldn't download this photo from iCloud.": "यह फ़ोटो iCloud से डाउनलोड नहीं हो सकी.",
    "Couldn't download this video from iCloud.": "यह वीडियो iCloud से डाउनलोड नहीं हो सका.",
    "Couldn't load this photo.": "यह फ़ोटो लोड नहीं हो सकी.",
    "Couldn't load this video.": "यह वीडियो लोड नहीं हो सका.",
    "Mixed": "मिश्रित",
    "Start here. ": "यहाँ से शुरू करें. ",
    "Untitled": "बिना शीर्षक",
    "media": "मीडिया",
  },
  bn: {
    "Couldn't download this photo from iCloud.": "এই ফটো iCloud থেকে ডাউনলোড করা যায়নি.",
    "Couldn't download this video from iCloud.": "এই ভিডিও iCloud থেকে ডাউনলোড করা যায়নি.",
    "Couldn't load this photo.": "এই ফটো লোড করা যায়নি.",
    "Couldn't load this video.": "এই ভিডিও লোড করা যায়নি.",
    "Mixed": "মিশ্র",
    "Start here. ": "এখান থেকে শুরু করুন. ",
    "Untitled": "শিরোনামহীন",
    "media": "মিডিয়া",
  },
  ta: {
    "Couldn't download this photo from iCloud.": "இந்தப் புகைப்படத்தை iCloud-இல் இருந்து பதிவிறக்க முடியவில்லை.",
    "Couldn't download this video from iCloud.": "இந்த வீடியோவை iCloud-இல் இருந்து பதிவிறக்க முடியவில்லை.",
    "Couldn't load this photo.": "இந்தப் புகைப்படத்தை ஏற்ற முடியவில்லை.",
    "Couldn't load this video.": "இந்த வீடியோவை ஏற்ற முடியவில்லை.",
    "Mixed": "கலவை",
    "Start here. ": "இங்கே தொடங்கு. ",
    "Untitled": "தலைப்பற்றது",
    "media": "மீடியா",
  },
};

// Plural keys. Category sets: ar 6, he 3, hi/bn/ta 2.
const plurals = {
  ar: {
    "%lld exact copies": {
      zero: "%lld نسخ مطابقة",
      one: "%lld نسخة مطابقة",
      two: "%lld نسختان مطابقتان",
      few: "%lld نسخ مطابقة",
      many: "%lld نسخةً مطابقةً",
      other: "%lld نسخة مطابقة",
    },
    "%lld look-alike photos": {
      zero: "%lld صور مشابهة",
      one: "%lld صورة مشابهة",
      two: "%lld صورتان مشابهتان",
      few: "%lld صور مشابهة",
      many: "%lld صورةً مشابهةً",
      other: "%lld صورة مشابهة",
    },
  },
  he: {
    "%lld exact copies": {
      one: "%lld עותק זהה",
      two: "%lld עותקים זהים",
      other: "%lld עותקים זהים",
    },
    "%lld look-alike photos": {
      one: "%lld תמונה דומה",
      two: "%lld תמונות דומות",
      other: "%lld תמונות דומות",
    },
  },
  hi: {
    "%lld exact copies": {
      one: "%lld सटीक प्रति",
      other: "%lld सटीक प्रतियाँ",
    },
    "%lld look-alike photos": {
      one: "%lld मिलती-जुलती फ़ोटो",
      other: "%lld मिलती-जुलती फ़ोटो",
    },
  },
  bn: {
    "%lld exact copies": {
      one: "%lld হুবহু কপি",
      other: "%lld হুবহু কপি",
    },
    "%lld look-alike photos": {
      one: "%lld একইরকম ফটো",
      other: "%lld একইরকম ফটো",
    },
  },
  ta: {
    "%lld exact copies": {
      one: "%lld சரியான நகல்",
      other: "%lld சரியான நகல்கள்",
    },
    "%lld look-alike photos": {
      one: "%lld ஒத்த புகைப்படம்",
      other: "%lld ஒத்த புகைப்படங்கள்",
    },
  },
};

const EXPECTED_CATS = { ar: 6, he: 3, hi: 2, bn: 2, ta: 2 };
const PLAIN_KEYS = Object.keys(plain.ar).sort();
const PLURAL_KEYS = ["%lld exact copies", "%lld look-alike photos"];

// --- snapshot BEFORE writing ---------------------------------------------
const before = {};
for (const l of LANGS) before[l] = readFileSync(P(l), "utf8");

// --- write ----------------------------------------------------------------
for (const l of LANGS) {
  const j = JSON.parse(before[l]);
  Object.assign(j.strings, plain[l]);
  j.strings = Object.fromEntries(Object.keys(j.strings).sort().map((k) => [k, j.strings[k]]));
  for (const k of PLURAL_KEYS) j.plurals[k] = plurals[l][k];
  let out = serialize(j);
  // sanity: round-trips
  if (serialize(JSON.parse(out)) !== out) throw new Error(`${l}: does not round-trip`);
  writeFileSync(P(l), out);
}

// --- verify by reading back FROM DISK ------------------------------------
let failures = 0;
const fail = (m) => { failures++; console.log("  FAIL:", m); };
const ok = (m) => console.log("  ok:", m);

for (const l of LANGS) {
  console.log(`\n=== ${l} ===`);
  const disk = readFileSync(P(l), "utf8");
  let j;
  try { j = JSON.parse(disk); ok("parses"); } catch (e) { fail("parse: " + e.message); continue; }

  const s = j.strings, p = j.plurals;
  const sk = Object.keys(s), pk = Object.keys(p);

  sk.length === 707 ? ok(`strings = ${sk.length}`) : fail(`strings = ${sk.length}, expected 707`);
  pk.length === 66 ? ok(`plurals = ${pk.length}`) : fail(`plurals = ${pk.length}, expected 66`);

  // sorted plain keys (code-unit)
  JSON.stringify(sk) === JSON.stringify([...sk].sort())
    ? ok("strings key order sorted")
    : fail("strings key order NOT sorted");

  // all 8 plain keys present + non-empty
  for (const k of PLAIN_KEYS) {
    if (!(k in s)) fail(`missing plain key: ${JSON.stringify(k)}`);
    else if (typeof s[k] !== "string" || s[k].length === 0) fail(`empty plain value: ${JSON.stringify(k)}`);
  }
  if (PLAIN_KEYS.every((k) => k in s)) ok("all 8 plain keys present + non-empty");

  // Start here. ends with a space
  s["Start here. "].endsWith(" ") ? ok('"Start here. " value ends with a space') : fail('"Start here. " value does not end with a space');

  // plurals present + category set
  const refCats = new Set(
    pk.filter((k) => k !== "%lld exact copies" && k !== "%lld look-alike photos")
      .map((k) => Object.keys(p[k]).sort().join(","))
  );
  refCats.size === 1 ? ok(`existing plural category set: ${[...refCats][0]}`) : fail(`inconsistent existing plural category sets: ${[...refCats].join(" | ")}`);
  const wantCats = [...refCats][0].split(",");
  if (wantCats.length === EXPECTED_CATS[l]) ok(`category count ${wantCats.length} matches expected ${EXPECTED_CATS[l]}`);
  else fail(`category count ${wantCats.length}, expected ${EXPECTED_CATS[l]}`);

  for (const k of PLURAL_KEYS) {
    if (!(k in p)) { fail(`missing plural key: ${JSON.stringify(k)}`); continue; }
    const got = Object.keys(p[k]).sort().join(",");
    got === wantCats.slice().sort().join(",") ? ok(`plural "${k}" categories match`) : fail(`plural "${k}" cats ${got} != ${wantCats.join(",")}`);
    let bad = false;
    for (const [cat, v] of Object.entries(p[k])) {
      const n = (v.match(/%lld/g) || []).length;
      if (n !== 1) { fail(`plural "${k}"[${cat}] has %lld x${n}`); bad = true; }
      if (!v || v.length === 0) { fail(`plural "${k}"[${cat}] empty`); bad = true; }
    }
    if (!bad) ok(`plural "${k}" %lld x1 in every form`);
  }

  // 0 pre-existing keys changed: replay insert onto snapshot, compare all original keys
  const orig = JSON.parse(before[l]);
  for (const k of Object.keys(orig.strings)) {
    if (JSON.stringify(orig.strings[k]) !== JSON.stringify(s[k])) fail(`pre-existing string changed: ${JSON.stringify(k)}`);
  }
  for (const k of Object.keys(orig.plurals)) {
    if (JSON.stringify(orig.plurals[k]) !== JSON.stringify(p[k])) fail(`pre-existing plural changed: ${JSON.stringify(k)}`);
  }
  ok("0 pre-existing keys changed");
}

console.log(`\n${failures === 0 ? "ALL CHECKS PASSED" : failures + " CHECK(S) FAILED"}`);
process.exit(failures === 0 ? 0 : 1);
