#!/usr/bin/env node
// Batch 12 (ar, he, hi, bn, ta): the 43 keys the prose audit found.
//
// Adds the keys from `_batch12-keys.json` to translations/<code>.json. Existing
// keys are never touched, `plurals` is never touched, and the file keeps its
// existing order (plain UTF-16 code-unit sort, i.e. `[...keys].sort()`).
//
// Read `_batch12-brief.md` before changing any value here.
//
// Run: node scripts/localization/translations/_batch12-insert-ar-he-hi-bn-ta.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

const KEYS = JSON.parse(readFileSync(join(here, "_batch12-keys.json"), "utf8"));

// --- Arabic -----------------------------------------------------------------
// Apple-style MSA. UI names are quoted with the Arabic guillemets «…» the rest
// of this file already uses. "Don't Allow" is the iOS button label: عدم السماح.
const ar = {
  " known · %lld sizes unavailable": " معروف · %lld أحجام غير متاحة",
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.":
    "1. يحفظ TidyByte %@.\n2. عندما تُحفظ كل النسخ، يطلب iOS منك حذف %@.\n\nإذا نقرت على «عدم السماح»، فستحتفظ بالنسختين. تبقى الأصول المحذوفة في «المحذوفة مؤخرًا» لمدة 30 يومًا.",
  "Best": "الأفضل",
  "Best exposed": "أفضل تعريض",
  "Best overall": "الأفضل إجمالًا",
  "Best quality": "أفضل جودة",
  "Blur": "الضبابية",
  "Brightness": "السطوع",
  "Couldn't prepare the selected items to share.":
    "تعذر تجهيز العناصر المحددة للمشاركة.",
  "Darkness": "الظلام",
  "Detected by file name heuristics — may include some camera photos":
    "تم اكتشافها استنادًا إلى اسم الملف — قد تشمل بعض صور الكاميرا",
  "Don't Delete": "عدم الحذف",
  "Failed to save compressed photo to library.":
    "تعذر حفظ الصورة المضغوطة في المكتبة.",
  "Failed to save compressed video to library.":
    "تعذر حفظ الفيديو المضغوط في المكتبة.",
  "Highest res": "أعلى دقة",
  "In iCloud.": "في iCloud.",
  "Keep as Best": "الاحتفاظ كأفضل",
  "Keeping this · %@": "الاحتفاظ بهذه · %@",
  "Lens smudge confidence": "احتمالية لطخة العدسة",
  "Live Photo.": "Live Photo.",
  "Most recent": "الأحدث",
  "No Large Files": "لا توجد ملفات كبيرة",
  "No Large Videos": "لا توجد فيديوهات كبيرة",
  "No files larger than %lld MB. Lower the threshold to see more.":
    "لا توجد ملفات أكبر من %lld MB. خفّض الحد لرؤية المزيد.",
  "No photos larger than %lld MB. Lower the threshold or switch to All/Videos.":
    "لا توجد صور أكبر من %lld MB. خفّض الحد أو بدّل إلى All/Videos.",
  "No savings — kept original": "بلا توفير — تم الاحتفاظ بالأصل",
  "No videos larger than %lld MB. Lower the threshold or switch to All/Photos.":
    "لا توجد فيديوهات أكبر من %lld MB. خفّض الحد أو بدّل إلى All/Photos.",
  "Not loaded yet. Delete is off until it shows.":
    "لم يتم التحميل بعد. الحذف معطّل حتى تظهر.",
  "Original kept — both versions in your library":
    "تم الاحتفاظ بالأصل — النسختان في مكتبتك",
  "Recommended: %@": "موصى به: %@",
  "Sharpest": "الأكثر حدة",
  "Sizes unavailable": "الأحجام غير متاحة",
  "Step 1 of 2 · Saving copy %lld of %lld":
    "الخطوة 1 من 2 · حفظ النسخة %lld من %lld",
  "Step 2 of 2 · Confirm in the iOS alert to delete the originals":
    "الخطوة 2 من 2 · أكّد في تنبيه iOS لحذف الأصول",
  "Working…": "جارٍ العمل…",
  "Your choice": "اختيارك",
  "Your library changed during analysis. Scan again for current results.":
    "تغيّرت مكتبتك أثناء التحليل. أعد الفحص للحصول على النتائج الحالية.",
  "a new, smaller copy of each photo": "نسخة جديدة أصغر من كل صورة",
  "a new, smaller copy of each video": "نسخة جديدة أصغر من كل فيديو",
  "the Live Photos": "Live Photos",
  "the original photos": "الصور الأصلية",
  "the original videos": "الفيديوهات الأصلية",
  "the still image of each Live Photo as a new photo":
    "الصورة الثابتة لكل Live Photo كصورة جديدة",
};

// --- Hebrew -----------------------------------------------------------------
// Singular informal imperative, matching the rest of this file ("נסה שוב",
// "פנה מקום"). "Don't Allow" is the iOS button label: אל תאפשר.
// The two "copies" fragments stay indefinite (no את) and the three "originals"
// fragments carry את, because that is what the two sentence positions need.
const he = {
  " known · %lld sizes unavailable": " ידוע · %lld גדלים לא זמינים",
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.":
    "1. TidyByte שומר %@.\n2. כשכל העותקים נשמרים, iOS מבקש ממך למחוק %@.\n\nאם תלחץ על \"אל תאפשר\", תשאיר את שתי הגרסאות. המקוריים שנמחקו נשארים ב\"נמחקו לאחרונה\" למשך 30 יום.",
  "Best": "הטוב ביותר",
  "Best exposed": "החשיפה הטובה ביותר",
  "Best overall": "הטובה ביותר בסך הכול",
  "Best quality": "האיכות הטובה ביותר",
  "Blur": "טשטוש",
  "Brightness": "בהירות",
  "Couldn't prepare the selected items to share.":
    "לא ניתן היה להכין את הפריטים שנבחרו לשיתוף.",
  "Darkness": "כהות",
  "Detected by file name heuristics — may include some camera photos":
    "זוהה לפי ניתוח שם הקובץ — עשוי לכלול גם תמונות מצלמה",
  "Don't Delete": "אל תמחק",
  "Failed to save compressed photo to library.":
    "שמירת התמונה המכווצת לספרייה נכשלה.",
  "Failed to save compressed video to library.":
    "שמירת הסרטון המכווץ לספרייה נכשלה.",
  "Highest res": "הרזולוציה הגבוהה ביותר",
  "In iCloud.": "ב-iCloud.",
  "Keep as Best": "שמור כטוב ביותר",
  "Keeping this · %@": "שומר את זו · %@",
  "Lens smudge confidence": "וודאות לכתם על העדשה",
  "Live Photo.": "Live Photo.",
  "Most recent": "האחרונה ביותר",
  "No Large Files": "אין קבצים גדולים",
  "No Large Videos": "אין סרטונים גדולים",
  "No files larger than %lld MB. Lower the threshold to see more.":
    "אין קבצים גדולים מ-%lld MB. הורד את הסף כדי לראות עוד.",
  "No photos larger than %lld MB. Lower the threshold or switch to All/Videos.":
    "אין תמונות גדולות מ-%lld MB. הורד את הסף או עבור אל All/Videos.",
  "No savings — kept original": "אין חיסכון — נשמר המקורי",
  "No videos larger than %lld MB. Lower the threshold or switch to All/Photos.":
    "אין סרטונים גדולים מ-%lld MB. הורד את הסף או עבור אל All/Photos.",
  "Not loaded yet. Delete is off until it shows.":
    "עדיין לא נטען. המחיקה מושבתת עד שהוא יופיע.",
  "Original kept — both versions in your library":
    "המקורי נשמר — שתי הגרסאות בספרייה שלך",
  "Recommended: %@": "מומלץ: %@",
  "Sharpest": "החדה ביותר",
  "Sizes unavailable": "הגדלים אינם זמינים",
  "Step 1 of 2 · Saving copy %lld of %lld":
    "שלב 1 מתוך 2 · שומר עותק %lld מתוך %lld",
  "Step 2 of 2 · Confirm in the iOS alert to delete the originals":
    "שלב 2 מתוך 2 · אשר בהתראה של iOS כדי למחוק את המקוריים",
  "Working…": "עובד…",
  "Your choice": "הבחירה שלך",
  "Your library changed during analysis. Scan again for current results.":
    "הספרייה שלך השתנתה במהלך הניתוח. סרוק שוב כדי לקבל תוצאות מעודכנות.",
  "a new, smaller copy of each photo": "עותק חדש וקטן יותר של כל תמונה",
  "a new, smaller copy of each video": "עותק חדש וקטן יותר של כל סרטון",
  "the Live Photos": "את ה-Live Photos",
  "the original photos": "את התמונות המקוריות",
  "the original videos": "את הסרטונים המקוריים",
  "the still image of each Live Photo as a new photo":
    "תמונה סטטית של כל Live Photo כתמונה חדשה",
};

// --- Hindi ------------------------------------------------------------------
// Formal "आप" register, matching the rest of this file. "Don't Allow" is the
// iOS button label: अनुमति न दें. All/Videos and All/Photos stay English: those
// are the segmented-control labels, and they are still English on screen.
const hi = {
  " known · %lld sizes unavailable": " ज्ञात · %lld आकार अनुपलब्ध",
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.":
    "1. TidyByte %@ सहेजता है.\n2. सभी कॉपियाँ सहेजे जाने के बाद, iOS आपसे %@ हटाने के लिए कहता है.\n\n\"अनुमति न दें\" पर टैप करने पर दोनों वर्शन आपके पास रहेंगे. हटाए गए मूल आइटम 30 दिनों तक हाल ही में हटाए गए में रहते हैं.",
  "Best": "सर्वश्रेष्ठ",
  "Best exposed": "सर्वश्रेष्ठ एक्सपोज़र",
  "Best overall": "कुल मिलाकर सर्वश्रेष्ठ",
  "Best quality": "सर्वश्रेष्ठ गुणवत्ता",
  "Blur": "धुंधलापन",
  "Brightness": "चमक",
  "Couldn't prepare the selected items to share.":
    "चयनित आइटम शेयर करने के लिए तैयार नहीं हो सके.",
  "Darkness": "अंधेरा",
  "Detected by file name heuristics — may include some camera photos":
    "फ़ाइल नाम के अनुमान से पहचाना गया — इसमें कुछ कैमरा फ़ोटो भी शामिल हो सकती हैं",
  "Don't Delete": "हटाएँ नहीं",
  "Failed to save compressed photo to library.":
    "कंप्रेस की गई फ़ोटो लाइब्रेरी में सहेजी नहीं जा सकी.",
  "Failed to save compressed video to library.":
    "कंप्रेस किया गया वीडियो लाइब्रेरी में सहेजा नहीं जा सका.",
  "Highest res": "सबसे ज़्यादा रिज़ॉल्यूशन",
  "In iCloud.": "iCloud में.",
  "Keep as Best": "सर्वश्रेष्ठ के रूप में रखें",
  "Keeping this · %@": "इसे रखा जा रहा है · %@",
  "Lens smudge confidence": "लेंस पर धब्बे की संभावना",
  "Live Photo.": "Live Photo.",
  "Most recent": "सबसे हाल का",
  "No Large Files": "कोई बड़ी फ़ाइल नहीं",
  "No Large Videos": "कोई बड़ा वीडियो नहीं",
  "No files larger than %lld MB. Lower the threshold to see more.":
    "%lld MB से बड़ी कोई फ़ाइल नहीं. और देखने के लिए सीमा घटाएँ.",
  "No photos larger than %lld MB. Lower the threshold or switch to All/Videos.":
    "%lld MB से बड़ी कोई फ़ोटो नहीं. सीमा घटाएँ या All/Videos पर स्विच करें.",
  "No savings — kept original": "कोई बचत नहीं — मूल रखा गया",
  "No videos larger than %lld MB. Lower the threshold or switch to All/Photos.":
    "%lld MB से बड़ा कोई वीडियो नहीं. सीमा घटाएँ या All/Photos पर स्विच करें.",
  "Not loaded yet. Delete is off until it shows.":
    "अभी लोड नहीं हुआ. दिखने तक हटाना बंद है.",
  "Original kept — both versions in your library":
    "मूल रखा गया — आपकी लाइब्रेरी में दोनों वर्शन हैं",
  "Recommended: %@": "सुझाव: %@",
  "Sharpest": "सबसे शार्प",
  "Sizes unavailable": "आकार अनुपलब्ध",
  "Step 1 of 2 · Saving copy %lld of %lld":
    "चरण 1/2 · कॉपी %lld/%lld सहेजी जा रही है",
  "Step 2 of 2 · Confirm in the iOS alert to delete the originals":
    "चरण 2/2 · मूल फ़ाइलें हटाने के लिए iOS अलर्ट में पुष्टि करें",
  "Working…": "काम हो रहा है…",
  "Your choice": "आपकी पसंद",
  "Your library changed during analysis. Scan again for current results.":
    "विश्लेषण के दौरान आपकी लाइब्रेरी बदल गई. मौजूदा नतीजों के लिए फिर से स्कैन करें.",
  "a new, smaller copy of each photo": "हर फ़ोटो की नई, छोटी कॉपी",
  "a new, smaller copy of each video": "हर वीडियो की नई, छोटी कॉपी",
  "the Live Photos": "Live Photos",
  "the original photos": "मूल फ़ोटो",
  "the original videos": "मूल वीडियो",
  "the still image of each Live Photo as a new photo":
    "हर Live Photo की स्थिर छवि को नई फ़ोटो के रूप में",
};

// --- Bengali ----------------------------------------------------------------
// Formal "আপনি" register. This file terminates sentences with an ASCII period,
// not a danda, so these do too. "Don't Allow" is the iOS button label:
// অনুমতি দেবেন না. Recently Deleted follows the glossary: সম্প্রতি মোছা.
const bn = {
  " known · %lld sizes unavailable": " জানা · %lld আকার অনুপলব্ধ",
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.":
    "1. TidyByte %@ সেভ করে.\n2. সব কপি সেভ হয়ে গেলে, iOS আপনাকে %@ মুছতে বলে.\n\n\"অনুমতি দেবেন না\" চাপলে দুইটি ভার্সনই আপনার কাছে থাকবে. মোছা মূল আইটেমগুলি 30 দিনের জন্য সম্প্রতি মোছা-য় থাকে.",
  "Best": "সেরা",
  "Best exposed": "সেরা এক্সপোজার",
  "Best overall": "সামগ্রিকভাবে সেরা",
  "Best quality": "সেরা গুণমান",
  "Blur": "ঝাপসা",
  "Brightness": "উজ্জ্বলতা",
  "Couldn't prepare the selected items to share.":
    "নির্বাচিত আইটেমগুলি শেয়ার করার জন্য তৈরি করা যায়নি.",
  "Darkness": "অন্ধকার",
  "Detected by file name heuristics — may include some camera photos":
    "ফাইলের নাম বিশ্লেষণ করে শনাক্ত — কিছু ক্যামেরার ফটোও থাকতে পারে",
  "Don't Delete": "মুছবেন না",
  "Failed to save compressed photo to library.":
    "কমপ্রেস করা ফটো লাইব্রেরিতে সেভ করা যায়নি.",
  "Failed to save compressed video to library.":
    "কমপ্রেস করা ভিডিও লাইব্রেরিতে সেভ করা যায়নি.",
  "Highest res": "সর্বোচ্চ রেজোলিউশন",
  "In iCloud.": "iCloud-এ.",
  "Keep as Best": "সেরা হিসেবে রাখুন",
  "Keeping this · %@": "এটি রাখা হচ্ছে · %@",
  "Lens smudge confidence": "লেন্সে দাগ থাকার সম্ভাবনা",
  "Live Photo.": "Live Photo.",
  "Most recent": "সবচেয়ে সাম্প্রতিক",
  "No Large Files": "কোনও বড় ফাইল নেই",
  "No Large Videos": "কোনও বড় ভিডিও নেই",
  "No files larger than %lld MB. Lower the threshold to see more.":
    "%lld MB-এর চেয়ে বড় কোনও ফাইল নেই. আরও দেখতে সীমা কম করুন.",
  "No photos larger than %lld MB. Lower the threshold or switch to All/Videos.":
    "%lld MB-এর চেয়ে বড় কোনও ফটো নেই. সীমা কম করুন বা All/Videos-এ যান.",
  "No savings — kept original": "কোনও সঞ্চয় নেই — মূল রাখা হয়েছে",
  "No videos larger than %lld MB. Lower the threshold or switch to All/Photos.":
    "%lld MB-এর চেয়ে বড় কোনও ভিডিও নেই. সীমা কম করুন বা All/Photos-এ যান.",
  "Not loaded yet. Delete is off until it shows.":
    "এখনও লোড হয়নি. এটি দেখা যাওয়ার আগে মোছা বন্ধ.",
  "Original kept — both versions in your library":
    "মূল রাখা হয়েছে — দুইটি ভার্সনই আপনার লাইব্রেরিতে আছে",
  "Recommended: %@": "সুপারিশ: %@",
  "Sharpest": "সবচেয়ে স্পষ্ট",
  "Sizes unavailable": "আকার অনুপলব্ধ",
  "Step 1 of 2 · Saving copy %lld of %lld":
    "ধাপ 1/2 · কপি %lld/%lld সেভ করা হচ্ছে",
  "Step 2 of 2 · Confirm in the iOS alert to delete the originals":
    "ধাপ 2/2 · মূল ফাইলগুলি মুছতে iOS অ্যালার্টে নিশ্চিত করুন",
  "Working…": "কাজ চলছে…",
  "Your choice": "আপনার পছন্দ",
  "Your library changed during analysis. Scan again for current results.":
    "বিশ্লেষণের সময় আপনার লাইব্রেরি বদলে গেছে. বর্তমান ফলাফলের জন্য আবার স্ক্যান করুন.",
  "a new, smaller copy of each photo": "প্রতিটি ফটোর নতুন, ছোট কপি",
  "a new, smaller copy of each video": "প্রতিটি ভিডিওর নতুন, ছোট কপি",
  "the Live Photos": "Live Photos",
  "the original photos": "মূল ফটোগুলি",
  "the original videos": "মূল ভিডিওগুলি",
  "the still image of each Live Photo as a new photo":
    "প্রতিটি Live Photo-এর স্থির ছবি নতুন ফটো হিসেবে",
};

// --- Tamil ------------------------------------------------------------------
// Polite imperative ("-வும்"), matching the majority of this file. "Don't
// Allow" is the iOS button label: அனுமதிக்க வேண்டாம். Recently Deleted follows
// the glossary: சமீபத்தில் நீக்கியவை.
const ta = {
  " known · %lld sizes unavailable": " தெரிந்தது · %lld அளவுகள் கிடைக்கவில்லை",
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.":
    "1. TidyByte %@ சேமிக்கும்.\n2. எல்லா நகல்களும் சேமிக்கப்பட்டதும், iOS %@ நீக்கக் கேட்கும்.\n\n\"அனுமதிக்க வேண்டாம்\" எனத் தட்டினால், இரண்டு பதிப்புகளையும் நீங்கள் வைத்திருப்பீர்கள். நீக்கப்பட்ட மூலங்கள் 30 நாட்களுக்கு சமீபத்தில் நீக்கியவை-இல் இருக்கும்.",
  "Best": "சிறந்தது",
  "Best exposed": "சிறந்த வெளிச்சம்",
  "Best overall": "மொத்தத்தில் சிறந்தது",
  "Best quality": "சிறந்த தரம்",
  "Blur": "மங்கல்",
  "Brightness": "பிரகாசம்",
  "Couldn't prepare the selected items to share.":
    "தேர்ந்தெடுத்த உருப்படிகளைப் பகிரத் தயார் செய்ய முடியவில்லை.",
  "Darkness": "இருள்",
  "Detected by file name heuristics — may include some camera photos":
    "கோப்புப் பெயரின் ஊகத்தால் கண்டறியப்பட்டது — சில கேமரா புகைப்படங்களும் இருக்கலாம்",
  "Don't Delete": "நீக்க வேண்டாம்",
  "Failed to save compressed photo to library.":
    "சுருக்கிய புகைப்படத்தை நூலகத்தில் சேமிக்க முடியவில்லை.",
  "Failed to save compressed video to library.":
    "சுருக்கிய வீடியோவை நூலகத்தில் சேமிக்க முடியவில்லை.",
  "Highest res": "அதிக தெளிவுத்திறன்",
  "In iCloud.": "iCloud-இல்.",
  "Keep as Best": "சிறந்ததாக வைத்திரு",
  "Keeping this · %@": "இதை வைத்திருக்கிறது · %@",
  "Lens smudge confidence": "லென்ஸ் கறையின் நம்பகத்தன்மை",
  "Live Photo.": "Live Photo.",
  "Most recent": "மிக சமீபத்தியது",
  "No Large Files": "பெரிய கோப்புகள் இல்லை",
  "No Large Videos": "பெரிய வீடியோக்கள் இல்லை",
  "No files larger than %lld MB. Lower the threshold to see more.":
    "%lld MB-ஐ விட பெரிய கோப்புகள் இல்லை. மேலும் பார்க்க வரம்பைக் குறைக்கவும்.",
  "No photos larger than %lld MB. Lower the threshold or switch to All/Videos.":
    "%lld MB-ஐ விட பெரிய புகைப்படங்கள் இல்லை. வரம்பைக் குறைக்கவும் அல்லது All/Videos-க்கு மாறவும்.",
  "No savings — kept original": "சேமிப்பு இல்லை — மூலம் வைக்கப்பட்டது",
  "No videos larger than %lld MB. Lower the threshold or switch to All/Photos.":
    "%lld MB-ஐ விட பெரிய வீடியோக்கள் இல்லை. வரம்பைக் குறைக்கவும் அல்லது All/Photos-க்கு மாறவும்.",
  "Not loaded yet. Delete is off until it shows.":
    "இன்னும் ஏற்றப்படவில்லை. அது தெரியும் வரை நீக்கம் முடக்கப்பட்டுள்ளது.",
  "Original kept — both versions in your library":
    "மூலம் வைக்கப்பட்டது — இரண்டு பதிப்புகளும் உங்கள் நூலகத்தில் உள்ளன",
  "Recommended: %@": "பரிந்துரை: %@",
  "Sharpest": "மிகத் தெளிவானது",
  "Sizes unavailable": "அளவுகள் கிடைக்கவில்லை",
  "Step 1 of 2 · Saving copy %lld of %lld":
    "படி 1/2 · நகல் %lld/%lld சேமிக்கப்படுகிறது",
  "Step 2 of 2 · Confirm in the iOS alert to delete the originals":
    "படி 2/2 · மூலங்களை நீக்க iOS எச்சரிக்கையில் உறுதிப்படுத்தவும்",
  "Working…": "வேலை நடக்கிறது…",
  "Your choice": "உங்கள் தேர்வு",
  "Your library changed during analysis. Scan again for current results.":
    "பரிசோதனையின் போது உங்கள் நூலகம் மாறியது. தற்போதைய முடிவுகளுக்கு மீண்டும் ஸ்கேன் செய்யவும்.",
  "a new, smaller copy of each photo": "ஒவ்வொரு புகைப்படத்தின் புதிய, சிறிய நகல்",
  "a new, smaller copy of each video": "ஒவ்வொரு வீடியோவின் புதிய, சிறிய நகல்",
  "the Live Photos": "Live Photos",
  "the original photos": "மூலப் புகைப்படங்கள்",
  "the original videos": "மூல வீடியோக்கள்",
  "the still image of each Live Photo as a new photo":
    "ஒவ்வொரு Live Photo-இன் நிலைப்படத்தைப் புதிய புகைப்படமாக",
};

const LANGS = { ar, he, hi, bn, ta };

for (const [code, table] of Object.entries(LANGS)) {
  // Every value must be a non-empty string and every key in the batch must be
  // covered, or the write is wrong and there is no point writing it.
  const missing = KEYS.filter((k) => typeof table[k] !== "string" || !table[k].trim());
  if (missing.length) throw new Error(`${code}: ${missing.length} missing value(s)`);
  const extra = Object.keys(table).filter((k) => !KEYS.includes(k));
  if (extra.length) throw new Error(`${code}: ${extra.length} key(s) not in the batch`);

  const path = join(here, `${code}.json`);
  const file = JSON.parse(readFileSync(path, "utf8"));
  const before = Object.keys(file.strings).length;

  for (const key of KEYS) file.strings[key] = table[key];

  const sorted = {};
  for (const key of Object.keys(file.strings).sort()) sorted[key] = file.strings[key];
  file.strings = sorted;

  writeFileSync(path, JSON.stringify(file, null, 2) + "\n");
  console.log(
    `${code}: ${before} -> ${Object.keys(file.strings).length} strings (+${KEYS.length})`
  );
}
