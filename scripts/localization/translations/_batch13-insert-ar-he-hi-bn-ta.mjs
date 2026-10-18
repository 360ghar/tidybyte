#!/usr/bin/env node
// Batch 13 (ar, he, hi, bn, ta): the 16 picker/segmented-control labels, plus
// the two empty-state strings that name the All / Photos / Videos segments.
//
// Adds the keys from `_batch13-keys.json` to translations/<code>.json. Existing
// keys are never touched except the two empty-state strings below (they used to
// name the segments in English, which pointed users at a tab that no longer
// exists once the segments are translated). `plurals` is never touched, and the
// file keeps its existing order (plain UTF-16 code-unit sort, `[...keys].sort()`).
//
// Read `_batch13-brief.md` before changing any value here.
//
// Run: node scripts/localization/translations/_batch13-insert-ar-he-hi-bn-ta.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

const KEYS = JSON.parse(readFileSync(join(here, "_batch13-keys.json"), "utf8"));

const NO_LARGE_PHOTOS =
  "No photos larger than %lld MB. Lower the threshold or switch to All/Videos.";
const NO_LARGE_VIDEOS =
  "No videos larger than %lld MB. Lower the threshold or switch to All/Photos.";

// --- Arabic -----------------------------------------------------------------
// Apple-style MSA. «…» quotes a UI control's own name, the convention the rest
// of this file already uses ("«الصور»", "«تحديد الكل»"). Segment labels are bare
// and definite, so they match a control the user can actually see. "Visual" is
// بصري, the word the file already uses for the visual-duplicate scan
// ("المكررات المطابقة والمتشابهة بصريًا"). Low/Medium/High are masculine to
// agree with the existing "Balanced" = متوازن.
const ar = {
  All: "الكل",
  Broad: "واسع",
  "By Source": "حسب المصدر",
  "By Year": "حسب السنة",
  Exact: "مطابق",
  Filename: "اسم الملف",
  High: "مرتفع",
  Largest: "الأكبر",
  Low: "منخفض",
  Medium: "متوسط",
  Newest: "الأحدث",
  Oldest: "الأقدم",
  Photos: "الصور",
  Strict: "صارم",
  Videos: "الفيديوهات",
  Visual: "بصري",
  [NO_LARGE_PHOTOS]:
    "لا توجد صور أكبر من %lld MB. خفّض الحد أو بدّل إلى «الكل»/«الفيديوهات».",
  [NO_LARGE_VIDEOS]:
    "لا توجد فيديوهات أكبر من %lld MB. خفّض الحد أو بدّل إلى «الكل»/«الصور».",
};

// --- Hebrew -----------------------------------------------------------------
// "All" is הכול, the spelling the file already uses for Select All / Show All /
// Deselect All. Sort labels are the standard superlatives (the sort control is a
// menu, not a segmented control, so it has room). Low/Medium/High and
// Strict/Broad are the bare masculine forms a Hebrew picker shows.
const he = {
  All: "הכול",
  Broad: "רחב",
  "By Source": "לפי מקור",
  "By Year": "לפי שנה",
  Exact: "זהים",
  Filename: "שם קובץ",
  High: "גבוה",
  Largest: "הגדול ביותר",
  Low: "נמוך",
  Medium: "בינוני",
  Newest: "החדש ביותר",
  Oldest: "הישן ביותר",
  Photos: "תמונות",
  Strict: "מחמיר",
  Videos: "סרטונים",
  Visual: "חזותיים",
  [NO_LARGE_PHOTOS]:
    'אין תמונות גדולות מ-%lld MB. הורד את הסף או עבור אל "הכול"/"סרטונים".',
  [NO_LARGE_VIDEOS]:
    'אין סרטונים גדולים מ-%lld MB. הורד את הסף או עבור אל "הכול"/"תמונות".',
};

// --- Hindi ------------------------------------------------------------------
// "All" is सभी, the file's word for Select All / Show All. Exact is सटीक and
// Visual is दृश्य, both already in this file ("सटीक और दिखने में मिलते-जुलते",
// "दृश्य गुणवत्ता"). Low/Medium/High are कम / मध्यम / ज़्यादा, the register the
// file uses for sensitivity ("ज़्यादा धुंधलापन संवेदनशीलता"). Broad is व्यापक,
// from the file's "व्यापक क्रमबद्धता". The two sentences take the label's bare
// form plus "पर" — Hindi does not inflect either word further.
const hi = {
  All: "सभी",
  Broad: "व्यापक",
  "By Source": "स्रोत के अनुसार",
  "By Year": "वर्ष के अनुसार",
  Exact: "सटीक",
  Filename: "फ़ाइल नाम",
  High: "ज़्यादा",
  Largest: "सबसे बड़ा",
  Low: "कम",
  Medium: "मध्यम",
  Newest: "सबसे नया",
  Oldest: "सबसे पुराना",
  Photos: "फ़ोटो",
  Strict: "सख़्त",
  Videos: "वीडियो",
  Visual: "दृश्य",
  [NO_LARGE_PHOTOS]:
    "%lld MB से बड़ी कोई फ़ोटो नहीं. सीमा घटाएँ या सभी/वीडियो पर स्विच करें.",
  [NO_LARGE_VIDEOS]:
    "%lld MB से बड़ा कोई वीडियो नहीं. सीमा घटाएँ या सभी/फ़ोटो पर स्विच करें.",
};

// --- Bengali ----------------------------------------------------------------
// "All" is সব, the file's word for Select All / Show All. Exact is হুবহু and
// Visual is দৃশ্যমান, both from the file ("হুবহু ও দেখতে একইরকম", "দৃশ্যমান
// গুণমান"). Low/Medium/High are কম / মাঝারি / বেশি, matching "বেশি ঝাপসা
// সংবেদনশীলতা". Broad is বিস্তৃত, from "বিস্তৃত সাজানো". In the sentences the
// locative takes the hyphenated form this file already uses for case endings
// ("%@-এ", "সম্প্রতি মোছা-য়").
const bn = {
  All: "সব",
  Broad: "বিস্তৃত",
  "By Source": "উৎস অনুযায়ী",
  "By Year": "বছর অনুযায়ী",
  Exact: "হুবহু",
  Filename: "ফাইলের নাম",
  High: "বেশি",
  Largest: "সবচেয়ে বড়",
  Low: "কম",
  Medium: "মাঝারি",
  Newest: "সবচেয়ে নতুন",
  Oldest: "সবচেয়ে পুরোনো",
  Photos: "ফটো",
  Strict: "কঠোর",
  Videos: "ভিডিও",
  Visual: "দৃশ্যমান",
  [NO_LARGE_PHOTOS]:
    "%lld MB-এর চেয়ে বড় কোনও ফটো নেই. সীমা কম করুন বা সব/ভিডিও-তে যান.",
  [NO_LARGE_VIDEOS]:
    "%lld MB-এর চেয়ে বড় কোনও ভিডিও নেই. সীমা কম করুন বা সব/ফটো-তে যান.",
};

// --- Tamil ------------------------------------------------------------------
// "All" is அனைத்தும் (the nominative behind அனைத்தையும் in Select All / Show
// All). Photos stays புகைப்படங்கள், the word this file uses everywhere, rather
// than the shorter படங்கள், so the segment agrees with the rest of the app.
// Exact is சரியான and Visual is காட்சி, both from "சரியான & காட்சி நகல்கள்".
// Broad is பரந்த, from "பரந்த வரிசைப்படுத்தல்". In the sentences the dative is
// written on the word itself (வீடியோக்களுக்கு), not as a detached suffix.
const ta = {
  All: "அனைத்தும்",
  Broad: "பரந்த",
  "By Source": "மூலம் வாரியாக",
  "By Year": "ஆண்டு வாரியாக",
  Exact: "சரியான",
  Filename: "கோப்புப் பெயர்",
  High: "அதிக",
  Largest: "மிகப் பெரியது",
  Low: "குறைந்த",
  Medium: "நடுத்தர",
  Newest: "மிக சமீபத்தியது",
  Oldest: "மிகப் பழையது",
  Photos: "புகைப்படங்கள்",
  Strict: "கண்டிப்பான",
  Videos: "வீடியோக்கள்",
  Visual: "காட்சி",
  [NO_LARGE_PHOTOS]:
    "%lld MB-ஐ விட பெரிய புகைப்படங்கள் இல்லை. வரம்பைக் குறைக்கவும் அல்லது அனைத்தும்/வீடியோக்களுக்கு மாறவும்.",
  [NO_LARGE_VIDEOS]:
    "%lld MB-ஐ விட பெரிய வீடியோக்கள் இல்லை. வரம்பைக் குறைக்கவும் அல்லது அனைத்தும்/புகைப்படங்களுக்கு மாறவும்.",
};

const LANGS = { ar, he, hi, bn, ta };

// The two sentences are edits to existing values, not new keys; everything else
// in each table is a new key. Anything else is a bug.
const EDITS = [NO_LARGE_PHOTOS, NO_LARGE_VIDEOS];

for (const [code, table] of Object.entries(LANGS)) {
  const expected = [...KEYS, ...EDITS];
  const missing = expected.filter((k) => typeof table[k] !== "string" || !table[k].trim());
  if (missing.length) throw new Error(`${code}: ${missing.length} missing value(s)`);
  const extra = Object.keys(table).filter((k) => !expected.includes(k));
  if (extra.length) throw new Error(`${code}: ${extra.length} key(s) not in the batch`);

  const path = join(here, `${code}.json`);
  const file = JSON.parse(readFileSync(path, "utf8"));
  const before = Object.keys(file.strings).length;

  for (const key of expected) file.strings[key] = table[key];

  const sorted = {};
  for (const key of Object.keys(file.strings).sort()) sorted[key] = file.strings[key];
  file.strings = sorted;

  writeFileSync(path, JSON.stringify(file, null, 2) + "\n");
  console.log(
    `${code}: ${before} -> ${Object.keys(file.strings).length} strings (+${KEYS.length})`
  );
}
