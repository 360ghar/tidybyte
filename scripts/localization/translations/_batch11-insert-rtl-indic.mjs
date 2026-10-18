#!/usr/bin/env node
// Batch 11 (RTL + Indic): landing-page title + meta description for 10 languages.
//
// Writes scripts/localization/site/site-translations/<slug>.meta.json, one file
// per language, shaped exactly { "title": "…", "description": "…" }.
//
// Character limits are enforced the same way scripts/seo-audit.mjs enforces
// them: on the DECODED string (HTML entities collapsed, whitespace collapsed,
// trimmed). `&mdash;` is one character, not seven.
//
// Run: node scripts/localization/translations/_batch11-insert-rtl-indic.mjs

import { writeFileSync, readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const OUT_DIR = join(root, "scripts", "localization", "site", "site-translations");

const SOURCE_TITLE =
  "TidyByte &mdash; iPhone Storage Cleaner &amp; Photo Cleaner App";
const SOURCE_DESC =
  "TidyByte is a free iPhone storage cleaner and photo cleaner: swipe to delete junk, remove duplicates and screenshots, and compress videos. 100% on-device.";

// lang slug -> { title, description }
const LANGS = {
  ar: {
    title: "TidyByte &mdash; منظف تخزين وصور مجاني للآيفون",
    description:
      "TidyByte تطبيق مجاني لتنظيف تخزين وصور iPhone: اسحب لحذف الملفات غير المرغوبة، وأزل الصور المكررة ولقطات الشاشة، واضغط الفيديوهات. يعمل 100% على الجهاز.",
  },
  he: {
    title: "TidyByte &mdash; מנקה אחסון ותמונות חינמי לאייפון",
    description:
      "TidyByte הוא מנקה אחסון ותמונות חינמי לאייפון: החליקו כדי למחוק קבצים מיותרים, הסירו כפילויות וצילומי מסך, ודחסו סרטונים. 100% על המכשיר עצמו.",
  },
  hi: {
    title: "TidyByte &mdash; iPhone स्टोरेज और फ़ोटो क्लीनर ऐप",
    description:
      "TidyByte एक मुफ़्त iPhone स्टोरेज और फ़ोटो क्लीनर ऐप है: कचरा हटाने के लिए स्वाइप करें, डुप्लीकेट और स्क्रीनशॉट हटाएँ, और वीडियो कंप्रेस करें। 100% डिवाइस पर ही।",
  },
  bn: {
    title: "TidyByte &mdash; iPhone স্টোরেজ ও ফটো ক্লিনার অ্যাপ",
    description:
      "TidyByte হলো একটি ফ্রি iPhone স্টোরেজ ও ফটো ক্লিনার অ্যাপ: অপ্রয়োজনীয় ফটো মুছতে সোয়াইপ করুন, ডুপ্লিকেট ও স্ক্রিনশট সরান, ভিডিও কমপ্রেস করুন। 100% ডিভাইসেই।",
  },
  ta: {
    title: "TidyByte &mdash; iPhone சேமிப்பு &amp; புகைப்பட க்ளீனர் ஆப்",
    description:
      "TidyByte ஒரு இலவச iPhone சேமிப்பு &amp; புகைப்பட க்ளீனர்: தேவையற்றவற்றை நீக்க ஸ்வைப் செய்யுங்கள், நகல்களை அகற்றி, வீடியோவை சுருக்குங்கள். 100% சாதனத்திலேயே.",
  },
  te: {
    title: "TidyByte &mdash; iPhone స్టోరేజ్ &amp; ఫోటో క్లీనర్ యాప్",
    description:
      "TidyByte ఉచిత iPhone స్టోరేజ్ &amp; ఫోటో క్లీనర్: పనికిరానివి తొలగించడానికి స్వైప్ చేయండి, డూప్లికేట్లు తీసేయండి, వీడియోలు కుదించండి. 100% పరికరంలోనే.",
  },
  mr: {
    title: "TidyByte &mdash; iPhone स्टोरेज आणि फोटो क्लीनर अ‍ॅप",
    description:
      "TidyByte हे मोफत iPhone स्टोरेज &amp; फोटो क्लीनर अ‍ॅप आहे: नको असलेले फोटो डिलीट करण्यासाठी स्वाइप करा, डुप्लिकेट काढा, व्हिडिओ कॉम्प्रेस करा. 100% डिव्हाइसवर.",
  },
  gu: {
    title: "TidyByte &mdash; iPhone સ્ટોરેજ અને ફોટો ક્લીનર એપ",
    description:
      "TidyByte એ મફત iPhone સ્ટોરેજ અને ફોટો ક્લીનર એપ છે: બિનજરૂરી ફોટા ડિલીટ કરવા સ્વાઇપ કરો, ડુપ્લિકેટ દૂર કરો, વિડિયો કોમ્પ્રેસ કરો. 100% ડિવાઇસ પર.",
  },
  pa: {
    title: "TidyByte &mdash; iPhone ਸਟੋਰੇਜ ਅਤੇ ਫੋਟੋ ਕਲੀਨਰ ਐਪ",
    description:
      "TidyByte ਇੱਕ ਮੁਫ਼ਤ iPhone ਸਟੋਰੇਜ ਅਤੇ ਫੋਟੋ ਕਲੀਨਰ ਐਪ ਹੈ: ਬੇਲੋੜੀਆਂ ਫੋਟੋਆਂ ਹਟਾਉਣ ਲਈ ਸਵਾਈਪ ਕਰੋ, ਡੁਪਲੀਕੇਟ ਅਤੇ ਸਕਰੀਨਸ਼ਾਟ ਹਟਾਓ, ਵੀਡੀਓ ਕੰਪ੍ਰੈਸ ਕਰੋ। ਸਭ ਕੁਝ 100% ਡਿਵਾਈਸ 'ਤੇ।",
  },
  kn: {
    title: "TidyByte &mdash; iPhone ಸ್ಟೋರೇಜ್ ಮತ್ತು ಫೋಟೋ ಕ್ಲೀನರ್ ಆ್ಯಪ್",
    description:
      "TidyByte ಒಂದು ಉಚಿತ iPhone ಸ್ಟೋರೇಜ್ ಮತ್ತು ಫೋಟೋ ಕ್ಲೀನರ್ ಆ್ಯಪ್: ಅನಗತ್ಯ ಫೋಟೋಗಳನ್ನು ಅಳಿಸಲು ಸ್ವೈಪ್ ಮಾಡಿ, ನಕಲುಗಳನ್ನು ತೆಗೆಯಿರಿ, ವಿಡಿಯೋ ಕಂಪ್ರೆಸ್ ಮಾಡಿ. 100% ಸಾಧನದಲ್ಲೇ.",
  },
};

// Mirrors scripts/seo-audit.mjs `decode()`.
function decode(s) {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&#x27;|&rsquo;/g, "'")
    .replace(/&quot;|&rdquo;|&ldquo;/g, '"')
    .replace(/&mdash;/g, "\u2014")
    .replace(/&ndash;/g, "\u2013")
    .replace(/\s+/g, " ")
    .trim();
}

// --- write ---
for (const [slug, entry] of Object.entries(LANGS)) {
  writeFileSync(
    join(OUT_DIR, `${slug}.meta.json`),
    `${JSON.stringify({ title: entry.title, description: entry.description }, null, 2)}\n`,
  );
  console.log(`wrote site-translations/${slug}.meta.json`);
}

// --- verify by reading back from disk ---
console.log("\n=== verification (decode-then-count, same as seo-audit.mjs) ===\n");

const problems = [];
const sourceTitleDecoded = decode(SOURCE_TITLE);
const sourceDescDecoded = decode(SOURCE_DESC);

for (const slug of Object.keys(LANGS)) {
  const file = join(OUT_DIR, `${slug}.meta.json`);
  const issues = [];
  if (!existsSync(file)) {
    issues.push("file missing");
    problems.push(`${slug}: file missing`);
    console.log(`${slug.padEnd(3)} FAIL  ${issues.join("; ")}`);
    continue;
  }
  let obj;
  try {
    obj = JSON.parse(readFileSync(file, "utf8"));
  } catch (e) {
    issues.push(`does not parse: ${String(e).slice(0, 60)}`);
    problems.push(`${slug}: does not parse`);
    console.log(`${slug.padEnd(3)} FAIL  ${issues.join("; ")}`);
    continue;
  }

  const keys = Object.keys(obj).sort().join(",");
  if (keys !== "description,title") issues.push(`keys are [${keys}], expected [description,title]`);

  const t = typeof obj.title === "string" ? obj.title : "";
  const d = typeof obj.description === "string" ? obj.description : "";
  const tDec = decode(t);
  const dDec = decode(d);

  if (tDec.length > 65) issues.push(`title ${tDec.length} > 65`);
  if (dDec.length < 110 || dDec.length > 165) issues.push(`description ${dDec.length} outside 110-165`);
  if (/—/.test(t) || /—/.test(d)) issues.push("contains a literal em dash");
  if (/&(?!amp;|mdash;|ndash;|#x27;|rsquo;|quot;|rdquo;|ldquo;)/.test(t) || /&(?!amp;|mdash;|ndash;|#x27;|rsquo;|quot;|rdquo;|ldquo;)/.test(d))
    issues.push("contains a bare &");
  if (!t.startsWith("TidyByte")) issues.push("title does not start with TidyByte");
  if (t === SOURCE_TITLE || tDec === sourceTitleDecoded) issues.push("title is the English source");
  if (d === SOURCE_DESC || dDec === sourceDescDecoded) issues.push("description is the English source");
  if (/\n|\r/.test(t) || /\n|\r/.test(d)) issues.push("contains a line break");

  const status = issues.length ? "FAIL" : "ok  ";
  console.log(
    `${slug.padEnd(3)} ${status}  title ${String(tDec.length).padStart(2)}/65  desc ${String(dDec.length).padStart(3)}/165`,
  );
  for (const i of issues) {
    console.log(`      - ${i}`);
    problems.push(`${slug}: ${i}`);
  }
}

console.log(
  `\n${Object.keys(LANGS).length} file(s) written; ${problems.length} problem(s)`,
);
if (problems.length) process.exit(1);
