#!/usr/bin/env node
// Batch 13: 16 picker / segmented-control labels for Telugu, Marathi, Gujarati,
// Kannada, Malayalam, Punjabi — plus the two empty-state strings that name the
// All / Photos / Videos segments by hand.
//
// Reads each target JSON, adds exactly the keys from _batch13-keys.json, and
// writes it back with 2-space indent and the file's existing key sort order
// (plain Object.keys().sort(), i.e. UTF-16 code-unit order — verified to
// round-trip every file in this directory byte-for-byte). `plurals` is never
// touched. A copy of each file as it was before the write is dropped in
// /tmp/tidybyte-batch13-before/ so the verifier can prove nothing pre-existing
// changed except the two empty-state strings listed in EMPTY_STATE_FIX.
//
// Run: node scripts/localization/translations/_batch13-insert-te-mr-gu-kn-ml-pa.mjs

import fs from 'node:fs';
import path from 'node:path';

const dir = '/Users/sakshammittal/Documents/360ghar/github/archived/tidybyte/scripts/localization/translations';
const beforeDir = '/tmp/tidybyte-batch13-before';

const keys = JSON.parse(fs.readFileSync(path.join(dir, '_batch13-keys.json'), 'utf8'));

// Short labels for controls whose segments share the screen width. Six of the
// sixteen are one-word English and stay one word here; `By Year` / `By Source`
// are the only two-segment labels and have room for two words. Vocabulary is
// taken from strings already shipped in the same files (for example Telugu
// `ఫైల్ పేరు` from "Detected by file name heuristics", Marathi `व्यापक` from
// "Broad sorting") so a screen never disagrees with itself.
const LABELS = {
  te: {
    'All': 'అన్నీ',
    'Broad': 'విస్తృతం',
    'By Source': 'మూలం ప్రకారం',
    'By Year': 'సంవత్సరం ప్రకారం',
    'Exact': 'ఖచ్చితమైన',
    'Filename': 'ఫైల్ పేరు',
    'High': 'ఎక్కువ',
    'Largest': 'అతిపెద్దవి',
    'Low': 'తక్కువ',
    'Medium': 'మధ్యస్థ',
    'Newest': 'కొత్తవి',
    'Oldest': 'పాతవి',
    'Photos': 'ఫోటోలు',
    'Strict': 'కఠినం',
    'Videos': 'వీడియోలు',
    'Visual': 'కనిపించే',
  },
  mr: {
    'All': 'सर्व',
    'Broad': 'व्यापक',
    'By Source': 'स्रोतानुसार',
    'By Year': 'वर्षानुसार',
    'Exact': 'अचूक',
    'Filename': 'फाइल नाव',
    'High': 'जास्त',
    'Largest': 'सर्वात मोठे',
    'Low': 'कमी',
    'Medium': 'मध्यम',
    'Newest': 'नवीनतम',
    'Oldest': 'जुने',
    'Photos': 'फोटो',
    'Strict': 'कठोर',
    'Videos': 'व्हिडिओ',
    'Visual': 'दृश्य',
  },
  gu: {
    'All': 'બધું',
    'Broad': 'વ્યાપક',
    'By Source': 'સ્રોત પ્રમાણે',
    'By Year': 'વર્ષ પ્રમાણે',
    'Exact': 'ચોક્કસ',
    'Filename': 'ફાઇલ નામ',
    'High': 'વધુ',
    'Largest': 'સૌથી મોટા',
    'Low': 'ઓછી',
    'Medium': 'મધ્યમ',
    'Newest': 'નવા',
    'Oldest': 'જૂના',
    'Photos': 'ફોટા',
    'Strict': 'કડક',
    'Videos': 'વિડિયો',
    'Visual': 'દ્રશ્ય',
  },
  kn: {
    'All': 'ಎಲ್ಲಾ',
    'Broad': 'ವಿಶಾಲ',
    'By Source': 'ಮೂಲದ ಪ್ರಕಾರ',
    'By Year': 'ವರ್ಷದ ಪ್ರಕಾರ',
    'Exact': 'ನಿಖರ',
    'Filename': 'ಫೈಲ್ ಹೆಸರು',
    'High': 'ಹೆಚ್ಚು',
    'Largest': 'ಅತಿದೊಡ್ಡವು',
    'Low': 'ಕಡಿಮೆ',
    'Medium': 'ಮಧ್ಯಮ',
    'Newest': 'ಹೊಸದು',
    'Oldest': 'ಹಳೆಯದು',
    'Photos': 'ಫೋಟೋಗಳು',
    'Strict': 'ಕಠಿಣ',
    'Videos': 'ವೀಡಿಯೊಗಳು',
    'Visual': 'ದೃಶ್ಯ',
  },
  ml: {
    'All': 'എല്ലാം',
    'Broad': 'വിശാലം',
    'By Source': 'ഉറവിടം അനുസരിച്ച്',
    'By Year': 'വർഷം അനുസരിച്ച്',
    'Exact': 'കൃത്യം',
    'Filename': 'ഫയൽ പേര്',
    'High': 'കൂടുതൽ',
    'Largest': 'ഏറ്റവും വലിയത്',
    'Low': 'കുറവ്',
    'Medium': 'ഇടത്തരം',
    'Newest': 'പുതിയത്',
    'Oldest': 'പഴയത്',
    'Photos': 'ഫോട്ടോകൾ',
    'Strict': 'കർശനം',
    'Videos': 'വീഡിയോകൾ',
    'Visual': 'ദൃശ്യം',
  },
  pa: {
    'All': 'ਸਭ',
    'Broad': 'ਵਿਆਪਕ',
    'By Source': 'ਸਰੋਤ ਅਨੁਸਾਰ',
    'By Year': 'ਸਾਲ ਅਨੁਸਾਰ',
    'Exact': 'ਸਟੀਕ',
    'Filename': 'ਫ਼ਾਈਲ ਨਾਮ',
    'High': 'ਵੱਧ',
    'Largest': 'ਸਭ ਤੋਂ ਵੱਡੇ',
    'Low': 'ਘੱਟ',
    'Medium': 'ਮੱਧਮ',
    'Newest': 'ਨਵੇਂ',
    'Oldest': 'ਪੁਰਾਣੇ',
    'Photos': 'ਫ਼ੋਟੋ',
    'Strict': 'ਸਖ਼ਤ',
    'Videos': 'ਵੀਡੀਓ',
    'Visual': 'ਦਿੱਖੀ',
  },
};

// Job 2 — the empty states that name the All / Photos / Videos segments inline.
// Only where the inline name was inflected away from the label on the control:
//
//   te  "అన్నీ/వీడియోలకు"  (dative)  -> label is "వీడియోలు"
//   kn  "ಎಲ್ಲಾ/ವೀಡಿಯೊಗಳಿಗೆ" (dative)  -> label is "ವೀಡಿಯೊಗಳು"
//   pa  "ਸਭ/ਫ਼ੋਟੋਆਂ"       (oblique plural) -> label is "ਫ਼ੋਟੋ"
//
// Each fix keeps the bare label word the user sees on the control and puts the
// case ending on an added "tab" noun instead, so the two agree word for word.
// Marathi ("सर्व/व्हिडिओ वर जा"), Gujarati ("બધું/વિડિયો પર જાઓ") and Malayalam
// ("എല്ലാം/വീഡിയോകൾ എന്നതിലേക്ക് മാറുക") already show the bare forms and are
// deliberately left untouched.
const EMPTY_STATE_FIX = {
  te: {
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      '%lld MB కంటే పెద్ద ఫోటోలు లేవు. పరిమితిని తగ్గించండి లేదా అన్నీ/వీడియోలు ట్యాబ్కు మారండి.',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      '%lld MB కంటే పెద్ద వీడియోలు లేవు. పరిమితిని తగ్గించండి లేదా అన్నీ/ఫోటోలు ట్యాబ్కు మారండి.',
  },
  kn: {
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      '%lld MB ಗಿಂತ ದೊಡ್ಡ ಫೋಟೋಗಳಿಲ್ಲ. ಮಿತಿ ಕಡಿಮೆ ಮಾಡಿ ಅಥವಾ ಎಲ್ಲಾ/ವೀಡಿಯೊಗಳು ಟ್ಯಾಬ್ಗೆ ಬದಲಿಸಿ.',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      '%lld MB ಗಿಂತ ದೊಡ್ಡ ವೀಡಿಯೊಗಳಿಲ್ಲ. ಮಿತಿ ಕಡಿಮೆ ಮಾಡಿ ಅಥವಾ ಎಲ್ಲಾ/ಫೋಟೋಗಳು ಟ್ಯಾಬ್ಗೆ ಬದಲಿಸಿ.',
  },
  pa: {
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      '%lld MB ਤੋਂ ਵੱਡੇ ਵੀਡੀਓ ਨਹੀਂ. ਹੱਦ ਘਟਾਓ ਜਾਂ ਸਭ/ਫ਼ੋਟੋ ਟੈਬ ਉੱਤੇ ਜਾਓ.',
  },
};

fs.mkdirSync(beforeDir, { recursive: true });

for (const lang of Object.keys(LABELS)) {
  const file = path.join(dir, `${lang}.json`);
  const raw = fs.readFileSync(file, 'utf8');
  const json = JSON.parse(raw);

  // Snapshot before any change, so the verifier can diff the write.
  fs.writeFileSync(path.join(beforeDir, `${lang}.json`), raw);

  const labels = LABELS[lang];
  const fixes = EMPTY_STATE_FIX[lang] ?? {};

  // Guard: the key list and the label map have to line up exactly.
  const labelKeys = Object.keys(labels).sort();
  if (labelKeys.length !== keys.length || labelKeys.some((k, i) => k !== [...keys].sort()[i])) {
    throw new Error(`${lang}: LABELS does not cover exactly _batch13-keys.json`);
  }

  for (const key of keys) {
    const value = labels[key];
    if (typeof value !== 'string' || value.trim() === '') {
      throw new Error(`${lang}: empty label for "${key}"`);
    }
    if (Object.prototype.hasOwnProperty.call(json.strings, key)) {
      throw new Error(`${lang}: "${key}" already present — refusing to overwrite`);
    }
    json.strings[key] = value;
  }

  for (const [key, value] of Object.entries(fixes)) {
    if (!Object.prototype.hasOwnProperty.call(json.strings, key)) {
      throw new Error(`${lang}: empty-state key missing: "${key}"`);
    }
    json.strings[key] = value;
  }

  const sorted = {};
  for (const key of Object.keys(json.strings).sort()) sorted[key] = json.strings[key];
  json.strings = sorted;

  fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n');
  console.log(`${lang}: ${Object.keys(sorted).length} strings written`);
}
