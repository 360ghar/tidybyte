#!/usr/bin/env node
/**
 * Batch 7 insert — 57 new keys for ar, he, hi, bn.
 *
 * Keys come from `_batch7-brief.md`. The brief's tables list 56 keys; the
 * catalog/count target is 57 (495 + 57 = 552). The missing one is
 * "Failed to re-encode the photo." (Tidybyte/Services/PhotoCompressionService.swift),
 * which sits with the other compression errors in the brief's section 2 and is
 * the only key left in that file that no batch had claimed. It is included here.
 * The other batch-7 language groups (de/ja/ko/zh-Hans, es/fr/it/pt-BR,
 * te/kn/ml/ru, mr/gu/pa/ta) carry the identical 57-key set.
 *
 * Writes with 2-space indentation, codePoint key order (the order the files
 * already use), and leaves the `plurals` block byte-identical by splicing text
 * instead of re-serializing the whole document.
 *
 * Run: node scripts/localization/translations/_batch7-insert-ar-he-hi-bn.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const LANGS = ['ar', 'he', 'hi', 'bn'];

const KEYS = [
  // 1. Photo permission — five states plus a primer
  'TidyByte Needs Your Photos',
  "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.",
  'Photo Access Is On',
  'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.',
  'Photo Access Is Off',
  'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.',
  'Photo Access Is Restricted',
  'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.',
  'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.',
  'Allow Photo Access?',
  'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.',
  'Not Now',

  // 2. Compression errors
  'Photo not found.',
  "This item can't be compressed as a photo.",
  'Failed to load the photo.',
  'Photo size unknown (iCloud-only) — skipped.',
  'Video not found.',
  "Couldn't load the video (it may still be in iCloud). Please try again.",
  'Video size unknown (iCloud-only) — skipped.',
  'Failed to create export session.',
  'Exported file was empty.',
  'Failed to read file size.',
  'Failed to re-encode the photo.',
  'Cancelled.',
  'Unknown error',
  'Save failed: %@',
  'Export failed: %@',
  'Already compressed',
  'Size unknown (iCloud-only) — skipped',

  // 3. Local AI and search messages
  'Local AI is unavailable.',
  'This language is not supported by local AI.',
  'Local AI could not interpret this search.',
  'Use 300 characters or fewer.',
  'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.',
  'Some requested concepts were not found in this scan. Try a simpler content search.',
  'Searching labels across all scanned categories.',
  'Using label search across scanned photos.',
  'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.',

  // 4. Swipe review reasons
  'This photo may be out of focus.',
  'This photo has very low brightness.',
  'This photo has very high brightness.',
  'A lens smudge may have reduced image clarity.',
  'This photo received a low visual-quality score.',
  'Review whether you still need this screenshot.',
  'Review whether you still need this screen recording.',
  'This item uses %@; review whether you need it.',

  // 5. Appearance picker and widget
  'Light',
  'Dark',
  'Nothing to free on iPhone',
  'Up to %@ to free on iPhone',
  'Open TidyByte to refresh',
  'Updated %lldd ago',

  // 6. Empty-state fixes
  'No matching photos',
  'Submit a content search or try different words.',
  'No photos in this category.',
  'Choose albums or change your filters.',
  'No screen recordings were found.',
];

const TRANS = {
  ar: {
    'TidyByte Needs Your Photos': 'TidyByte يحتاج إلى صورك',
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.":
      'يراجع TidyByte مكتبتك على هذا الجهاز ليجد ما يستحق التنظيف. لا يُرفع أي شيء، ولا يتغير أي شيء دون موافقتك. سيطلب iOS الوصول بعد ذلك.',
    'Photo Access Is On': 'الوصول إلى الصور مُفعَّل',
    'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.':
      'يمكن لـTidyByte مراجعة مكتبتك على هذا الجهاز. لا يُرفع أي شيء، ولا يتغير أي شيء دون موافقتك.',
    'Photo Access Is Off': 'الوصول إلى الصور متوقف',
    'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.':
      'يمنع iOS وصول TidyByte إلى مكتبتك، ولن يسأل مرة أخرى. «الإعدادات» هي الطريق الوحيد للعودة — فعّل الوصول إلى الصور هناك وسيعمل كل شيء هنا من جديد.',
    'Photo Access Is Restricted': 'الوصول إلى الصور مقيّد',
    'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.':
      'هناك قيد من Screen Time أو من إدارة الجهاز يمنع الوصول إلى الصور. لا يستطيع مفتاح «الصور» في «الإعدادات» تغييره — يجب رفع هذا القيد أولًا.',
    'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.':
      'لا يرى TidyByte إلا الصور التي اخترتها. أضف المزيد متى شئت أن يراجع بقية مكتبتك.',
    'Allow Photo Access?': 'السماح بالوصول إلى الصور؟',
    'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.':
      'يطلب iOS الوصول إلى الصور مرة واحدة فقط، وهذا هو ذلك الطلب. بعدها يراجع TidyByte مكتبتك على هذا الجهاز. لا يُرفع أي شيء، ولا يتغير أي شيء دون مراجعتك.',
    'Not Now': 'ليس الآن',

    'Photo not found.': 'لم يُعثر على الصورة.',
    "This item can't be compressed as a photo.": 'لا يمكن ضغط هذا العنصر كصورة.',
    'Failed to load the photo.': 'تعذر تحميل الصورة.',
    'Photo size unknown (iCloud-only) — skipped.': 'حجم الصورة غير معروف (iCloud فقط) — تم التخطي.',
    'Video not found.': 'لم يُعثر على الفيديو.',
    "Couldn't load the video (it may still be in iCloud). Please try again.":
      'تعذر تحميل الفيديو (قد يكون لا يزال في iCloud). حاول مرة أخرى.',
    'Video size unknown (iCloud-only) — skipped.': 'حجم الفيديو غير معروف (iCloud فقط) — تم التخطي.',
    'Failed to create export session.': 'تعذر إنشاء جلسة التصدير.',
    'Exported file was empty.': 'كان الملف المُصدَّر فارغًا.',
    'Failed to read file size.': 'تعذر قراءة حجم الملف.',
    'Failed to re-encode the photo.': 'تعذر إعادة ترميز الصورة.',
    'Cancelled.': 'تم الإلغاء.',
    'Unknown error': 'خطأ غير معروف',
    'Save failed: %@': 'فشل الحفظ: %@',
    'Export failed: %@': 'فشل التصدير: %@',
    'Already compressed': 'تم الضغط بالفعل',
    'Size unknown (iCloud-only) — skipped': 'الحجم غير معروف (iCloud فقط) — تم التخطي',

    'Local AI is unavailable.': 'الذكاء الاصطناعي المحلي غير متاح.',
    'This language is not supported by local AI.': 'الذكاء الاصطناعي المحلي لا يدعم هذه اللغة.',
    'Local AI could not interpret this search.': 'تعذر على الذكاء الاصطناعي المحلي تفسير هذا البحث.',
    'Use 300 characters or fewer.': 'استخدم 300 حرف أو أقل.',
    'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.':
      'يدعم البحث المحتوى المرئي فقط، مثل كلاب على شاطئ. التواريخ والأماكن والأسماء والنصوص غير مفهرسة.',
    'Some requested concepts were not found in this scan. Try a simpler content search.':
      'لم يُعثر على بعض المفاهيم المطلوبة في هذا الفحص. جرّب بحثًا أبسط عن المحتوى.',
    'Searching labels across all scanned categories.': 'جارٍ البحث عن التسميات في كل الفئات المفحوصة.',
    'Using label search across scanned photos.': 'يُستخدم البحث بالتسميات في الصور المفحوصة.',
    'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.':
      'هذه الكلمات لا تشكل بحثًا بالتسميات مدعومًا. جرّب محتوى مرئيًا مثل «كلب» أو «شاطئ». لا يدعم البحث بالتسميات التواريخ أو الأسماء أو الاستثناءات.',

    'This photo may be out of focus.': 'قد تكون هذه الصورة غير واضحة التركيز.',
    'This photo has very low brightness.': 'سطوع هذه الصورة منخفض جدًا.',
    'This photo has very high brightness.': 'سطوع هذه الصورة مرتفع جدًا.',
    'A lens smudge may have reduced image clarity.': 'قد يكون اتساخ العدسة قد قلّل وضوح الصورة.',
    'This photo received a low visual-quality score.': 'حصلت هذه الصورة على تقييم منخفض للجودة البصرية.',
    'Review whether you still need this screenshot.': 'راجع ما إذا كنت لا تزال تحتاج إلى لقطة الشاشة هذه.',
    'Review whether you still need this screen recording.': 'راجع ما إذا كنت لا تزال تحتاج إلى تسجيل الشاشة هذا.',
    'This item uses %@; review whether you need it.': 'يستخدم هذا العنصر %@؛ راجع ما إذا كنت تحتاج إليه.',

    Light: 'فاتح',
    Dark: 'داكن',
    'Nothing to free on iPhone': 'لا شيء يمكن تحريره على iPhone',
    'Up to %@ to free on iPhone': 'يمكن تحرير حتى %@ على iPhone',
    'Open TidyByte to refresh': 'افتح TidyByte للتحديث',
    'Updated %lldd ago': 'آخر تحديث قبل %lld يوم',

    'No matching photos': 'لا توجد صور مطابقة',
    'Submit a content search or try different words.': 'أرسل بحثًا عن المحتوى أو جرّب كلمات مختلفة.',
    'No photos in this category.': 'لا توجد صور في هذه الفئة.',
    'Choose albums or change your filters.': 'اختر ألبومات أو غيّر عوامل التصفية.',
    'No screen recordings were found.': 'لم يُعثر على تسجيلات شاشة.',
  },

  he: {
    'TidyByte Needs Your Photos': 'TidyByte צריך את התמונות שלך',
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.":
      'TidyByte סורק את הספרייה שלך במכשיר הזה כדי למצוא מה שווה לנקות. שום דבר לא מועלה, ושום דבר לא משתנה בלי אישורך. iOS יבקש גישה בהמשך.',
    'Photo Access Is On': 'הגישה לתמונות פעילה',
    'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.':
      'TidyByte יכול לסרוק את הספרייה שלך במכשיר הזה. שום דבר לא מועלה, ושום דבר לא משתנה בלי אישורך.',
    'Photo Access Is Off': 'הגישה לתמונות כבויה',
    'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.':
      'iOS חוסם את הגישה של TidyByte לספרייה שלך, והוא לא ישאל שוב. "הגדרות" היא הדרך היחידה חזרה — הפעל שם את הגישה לתמונות והכול כאן יתחיל לעבוד שוב.',
    'Photo Access Is Restricted': 'הגישה לתמונות מוגבלת',
    'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.':
      'הגבלה של Screen Time או של ניהול מכשירים חוסמת את הגישה לתמונות. המתג "תמונות" בהגדרות לא יכול לשנות זאת — צריך להסיר קודם את ההגבלה.',
    'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.':
      'TidyByte רואה רק את התמונות שבחרת. הוסף עוד בכל זמן שתרצה שהוא יסרוק את שאר הספרייה שלך.',
    'Allow Photo Access?': 'לאפשר גישה לתמונות?',
    'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.':
      'iOS מבקש גישה לתמונות פעם אחת בלבד, וזו הבקשה הזו. לאחר מכן TidyByte סורק את הספרייה שלך במכשיר הזה. שום דבר לא מועלה, ושום דבר לא משתנה בלי הסקירה שלך.',
    'Not Now': 'לא עכשיו',

    'Photo not found.': 'התמונה לא נמצאה.',
    "This item can't be compressed as a photo.": 'לא ניתן לכווץ את הפריט הזה כתמונה.',
    'Failed to load the photo.': 'טעינת התמונה נכשלה.',
    'Photo size unknown (iCloud-only) — skipped.': 'גודל התמונה אינו ידוע (iCloud בלבד) — דולג.',
    'Video not found.': 'הסרטון לא נמצא.',
    "Couldn't load the video (it may still be in iCloud). Please try again.":
      'לא ניתן היה לטעון את הסרטון (ייתכן שהוא עדיין ב-iCloud). נסה שוב.',
    'Video size unknown (iCloud-only) — skipped.': 'גודל הסרטון אינו ידוע (iCloud בלבד) — דולג.',
    'Failed to create export session.': 'יצירת סשן הייצוא נכשלה.',
    'Exported file was empty.': 'הקובץ המיוצא היה ריק.',
    'Failed to read file size.': 'קריאת גודל הקובץ נכשלה.',
    'Failed to re-encode the photo.': 'קידוד התמונה מחדש נכשל.',
    'Cancelled.': 'בוטל.',
    'Unknown error': 'שגיאה לא ידועה',
    'Save failed: %@': 'השמירה נכשלה: %@',
    'Export failed: %@': 'הייצוא נכשל: %@',
    'Already compressed': 'כווץ כבר',
    'Size unknown (iCloud-only) — skipped': 'הגודל אינו ידוע (iCloud בלבד) — דולג',

    'Local AI is unavailable.': 'ה-AI המקומי אינו זמין.',
    'This language is not supported by local AI.': 'ה-AI המקומי אינו תומך בשפה הזו.',
    'Local AI could not interpret this search.': 'ה-AI המקומי לא הצליח לפרש את החיפוש הזה.',
    'Use 300 characters or fewer.': 'השתמש ב-300 תווים או פחות.',
    'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.':
      'החיפוש תומך בתוכן גלוי בלבד, כמו כלבים על חוף. תאריכים, מקומות, שמות וטקסט אינם נכללים באינדקס.',
    'Some requested concepts were not found in this scan. Try a simpler content search.':
      'חלק מהמושגים המבוקשים לא נמצאו בסריקה הזו. נסה חיפוש תוכן פשוט יותר.',
    'Searching labels across all scanned categories.': 'מחפש תוויות בכל הקטגוריות שנסרקו.',
    'Using label search across scanned photos.': 'משתמש בחיפוש תוויות בתמונות שנסרקו.',
    'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.':
      'המילים האלה אינן יוצרות חיפוש תוויות נתמך. נסה תוכן גלוי כמו כלב או חוף. חיפוש תוויות אינו תומך בתאריכים, בשמות או בשלילות.',

    'This photo may be out of focus.': 'ייתכן שהתמונה הזו לא מפוקסת.',
    'This photo has very low brightness.': 'הבהירות של התמונה הזו נמוכה מאוד.',
    'This photo has very high brightness.': 'הבהירות של התמונה הזו גבוהה מאוד.',
    'A lens smudge may have reduced image clarity.': 'ייתכן שלכלוך על העדשה הפחית את חדות התמונה.',
    'This photo received a low visual-quality score.': 'התמונה הזו קיבלה ציון נמוך באיכות חזותית.',
    'Review whether you still need this screenshot.': 'בדוק אם אתה עדיין צריך את צילום המסך הזה.',
    'Review whether you still need this screen recording.': 'בדוק אם אתה עדיין צריך את הקלטת המסך הזו.',
    'This item uses %@; review whether you need it.': 'הפריט הזה תופס %@; בדוק אם הוא נחוץ לך.',

    Light: 'בהיר',
    Dark: 'כהה',
    'Nothing to free on iPhone': 'אין מה לפנות ב-iPhone',
    'Up to %@ to free on iPhone': 'אפשר לפנות עד %@ ב-iPhone',
    'Open TidyByte to refresh': 'פתח את TidyByte כדי לרענן',
    'Updated %lldd ago': 'עודכן לפני %lld ימים',

    'No matching photos': 'אין תמונות תואמות',
    'Submit a content search or try different words.': 'שלח חיפוש תוכן או נסה מילים אחרות.',
    'No photos in this category.': 'אין תמונות בקטגוריה הזו.',
    'Choose albums or change your filters.': 'בחר אלבומים או שנה את המסננים.',
    'No screen recordings were found.': 'לא נמצאו הקלטות מסך.',
  },

  hi: {
    'TidyByte Needs Your Photos': 'TidyByte को आपकी फ़ोटो चाहिए',
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.":
      'TidyByte साफ़ करने लायक चीज़ें ढूँढने के लिए इस डिवाइस पर आपकी लाइब्रेरी जाँचता है. कुछ भी अपलोड नहीं होता, और आपकी अनुमति के बिना कुछ नहीं बदलता. इसके बाद iOS ऐक्सेस माँगेगा.',
    'Photo Access Is On': 'फ़ोटो ऐक्सेस चालू है',
    'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.':
      'TidyByte इस डिवाइस पर आपकी लाइब्रेरी जाँच सकता है. कुछ भी अपलोड नहीं होता, और आपकी अनुमति के बिना कुछ नहीं बदलता.',
    'Photo Access Is Off': 'फ़ोटो ऐक्सेस बंद है',
    'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.':
      'iOS, TidyByte को आपकी लाइब्रेरी से रोक रहा है और दोबारा नहीं पूछेगा. वापस जाने का एक ही रास्ता सेटिंग्स है — वहाँ फ़ोटो ऐक्सेस चालू करें और यहाँ सब कुछ फिर से काम करने लगेगा.',
    'Photo Access Is Restricted': 'फ़ोटो ऐक्सेस प्रतिबंधित है',
    'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.':
      'Screen Time या डिवाइस-प्रबंधन का प्रतिबंध फ़ोटो ऐक्सेस रोक रहा है. सेटिंग्स में फ़ोटो स्विच इसे नहीं बदल सकता — पहले वह प्रतिबंध हटाना होगा.',
    'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.':
      'TidyByte सिर्फ़ वही फ़ोटो देख सकता है जो आपने चुनी हैं. बाकी लाइब्रेरी की समीक्षा कराने के लिए जब चाहें और जोड़ें.',
    'Allow Photo Access?': 'फ़ोटो ऐक्सेस की अनुमति दें?',
    'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.':
      'iOS फ़ोटो ऐक्सेस सिर्फ़ एक बार माँगता है, और यह वही अनुरोध है. इसके बाद TidyByte इस डिवाइस पर आपकी लाइब्रेरी जाँचता है. कुछ भी अपलोड नहीं होता, और आपकी समीक्षा के बिना कुछ नहीं बदलता.',
    'Not Now': 'अभी नहीं',

    'Photo not found.': 'फ़ोटो नहीं मिली.',
    "This item can't be compressed as a photo.": 'इस आइटम को फ़ोटो के रूप में कंप्रेस नहीं किया जा सकता.',
    'Failed to load the photo.': 'फ़ोटो लोड नहीं हो सकी.',
    'Photo size unknown (iCloud-only) — skipped.': 'फ़ोटो का आकार अज्ञात (केवल iCloud) — छोड़ा गया.',
    'Video not found.': 'वीडियो नहीं मिला.',
    "Couldn't load the video (it may still be in iCloud). Please try again.":
      'वीडियो लोड नहीं हो सका (यह अभी भी iCloud में हो सकता है). कृपया फिर से प्रयास करें.',
    'Video size unknown (iCloud-only) — skipped.': 'वीडियो का आकार अज्ञात (केवल iCloud) — छोड़ा गया.',
    'Failed to create export session.': 'एक्सपोर्ट सेशन नहीं बन सका.',
    'Exported file was empty.': 'एक्सपोर्ट की गई फ़ाइल खाली थी.',
    'Failed to read file size.': 'फ़ाइल का आकार पढ़ा नहीं जा सका.',
    'Failed to re-encode the photo.': 'फ़ोटो फिर से एनकोड नहीं हो सकी.',
    'Cancelled.': 'रद्द किया गया.',
    'Unknown error': 'अज्ञात त्रुटि',
    'Save failed: %@': 'सहेजना विफल: %@',
    'Export failed: %@': 'एक्सपोर्ट विफल: %@',
    'Already compressed': 'पहले ही कंप्रेस हो चुका',
    'Size unknown (iCloud-only) — skipped': 'आकार अज्ञात (केवल iCloud) — छोड़ा गया',

    'Local AI is unavailable.': 'लोकल AI उपलब्ध नहीं है.',
    'This language is not supported by local AI.': 'लोकल AI इस भाषा का समर्थन नहीं करता.',
    'Local AI could not interpret this search.': 'लोकल AI इस खोज को समझ नहीं सका.',
    'Use 300 characters or fewer.': '300 या उससे कम अक्षर इस्तेमाल करें.',
    'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.':
      'खोज केवल दिखने वाली सामग्री का समर्थन करती है, जैसे समुद्र तट पर कुत्ते. तारीख़ें, जगहें, नाम और टेक्स्ट इंडेक्स नहीं होते.',
    'Some requested concepts were not found in this scan. Try a simpler content search.':
      'इस स्कैन में कुछ माँगी गई अवधारणाएँ नहीं मिलीं. कोई आसान कॉन्टेंट खोज आज़माएँ.',
    'Searching labels across all scanned categories.': 'सभी स्कैन की गई श्रेणियों में लेबल खोजे जा रहे हैं.',
    'Using label search across scanned photos.': 'स्कैन की गई फ़ोटो में लेबल खोज का उपयोग हो रहा है.',
    'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.':
      'ये शब्द समर्थित लेबल खोज नहीं बनाते. कुत्ता या समुद्र तट जैसी दिखने वाली सामग्री आज़माएँ. लेबल खोज तारीख़ों, नामों या बहिष्करण का समर्थन नहीं करती.',

    'This photo may be out of focus.': 'यह फ़ोटो फ़ोकस से बाहर हो सकती है.',
    'This photo has very low brightness.': 'इस फ़ोटो की चमक बहुत कम है.',
    'This photo has very high brightness.': 'इस फ़ोटो की चमक बहुत ज़्यादा है.',
    'A lens smudge may have reduced image clarity.': 'लेंस पर लगे धब्बे से छवि की स्पष्टता कम हो सकती है.',
    'This photo received a low visual-quality score.': 'इस फ़ोटो को दृश्य गुणवत्ता में कम स्कोर मिला.',
    'Review whether you still need this screenshot.': 'देखें कि क्या आपको यह स्क्रीनशॉट अभी भी चाहिए.',
    'Review whether you still need this screen recording.': 'देखें कि क्या आपको यह स्क्रीन रिकॉर्डिंग अभी भी चाहिए.',
    'This item uses %@; review whether you need it.': 'यह आइटम %@ लेता है; देखें कि क्या आपको इसकी ज़रूरत है.',

    Light: 'हल्का',
    Dark: 'गहरा',
    'Nothing to free on iPhone': 'iPhone पर खाली करने के लिए कुछ नहीं',
    'Up to %@ to free on iPhone': 'iPhone पर %@ तक खाली करें',
    'Open TidyByte to refresh': 'रीफ़्रेश करने के लिए TidyByte खोलें',
    'Updated %lldd ago': '%lld दिन पहले अपडेट किया गया',

    'No matching photos': 'कोई मेल खाती फ़ोटो नहीं',
    'Submit a content search or try different words.': 'कोई कॉन्टेंट खोज भेजें या अलग शब्द आज़माएँ.',
    'No photos in this category.': 'इस श्रेणी में कोई फ़ोटो नहीं.',
    'Choose albums or change your filters.': 'एल्बम चुनें या फ़िल्टर बदलें.',
    'No screen recordings were found.': 'कोई स्क्रीन रिकॉर्डिंग नहीं मिली.',
  },

  bn: {
    'TidyByte Needs Your Photos': 'TidyByte-এর আপনার ফটো দরকার',
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.":
      'TidyByte পরিষ্কার করার মতো কিছু খুঁজতে এই ডিভাইসেই আপনার লাইব্রেরি দেখে. কিছুই আপলোড হয় না, আর আপনার অনুমতি ছাড়া কিছু বদলায় না. এরপর iOS অ্যাক্সেস চাইবে.',
    'Photo Access Is On': 'ফটো অ্যাক্সেস চালু আছে',
    'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.':
      'TidyByte এই ডিভাইসেই আপনার লাইব্রেরি দেখতে পারে. কিছুই আপলোড হয় না, আর আপনার অনুমতি ছাড়া কিছু বদলায় না.',
    'Photo Access Is Off': 'ফটো অ্যাক্সেস বন্ধ আছে',
    'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.':
      'iOS আপনার লাইব্রেরি থেকে TidyByte-কে আটকে রেখেছে এবং আর জিজ্ঞাসা করবে না. ফিরে আসার একমাত্র পথ সেটিংস — সেখানে ফটো অ্যাক্সেস চালু করুন, তাহলে এখানে সব কিছু আবার কাজ শুরু করবে.',
    'Photo Access Is Restricted': 'ফটো অ্যাক্সেস সীমাবদ্ধ',
    'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.':
      'Screen Time বা ডিভাইস-ম্যানেজমেন্টের সীমাবদ্ধতা ফটো অ্যাক্সেস আটকে রেখেছে. সেটিংসের ফটো সুইচ এটি বদলাতে পারে না — আগে সেই সীমাবদ্ধতা তুলতে হবে.',
    'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.':
      'TidyByte শুধু আপনি বেছে নেওয়া ফটোগুলিই দেখতে পারে. বাকি লাইব্রেরি দেখতে চাইলে যখন খুশি আরও যোগ করুন.',
    'Allow Photo Access?': 'ফটো অ্যাক্সেসের অনুমতি দেবেন?',
    'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.':
      'iOS ফটো অ্যাক্সেস শুধু একবার চায়, আর এটাই সেই অনুরোধ. এরপর TidyByte এই ডিভাইসেই আপনার লাইব্রেরি দেখে. কিছুই আপলোড হয় না, আর আপনার পর্যালোচনা ছাড়া কিছু বদলায় না.',
    'Not Now': 'এখন নয়',

    'Photo not found.': 'ফটো পাওয়া যায়নি.',
    "This item can't be compressed as a photo.": 'এই আইটেমটি ফটো হিসেবে কমপ্রেস করা যায় না.',
    'Failed to load the photo.': 'ফটো লোড করা যায়নি.',
    'Photo size unknown (iCloud-only) — skipped.': 'ফটোর আকার অজানা (শুধু iCloud) — এড়িয়ে যাওয়া হয়েছে.',
    'Video not found.': 'ভিডিও পাওয়া যায়নি.',
    "Couldn't load the video (it may still be in iCloud). Please try again.":
      'ভিডিও লোড করা যায়নি (এটি এখনও iCloud-এ থাকতে পারে). আবার চেষ্টা করুন.',
    'Video size unknown (iCloud-only) — skipped.': 'ভিডিওর আকার অজানা (শুধু iCloud) — এড়িয়ে যাওয়া হয়েছে.',
    'Failed to create export session.': 'এক্সপোর্ট সেশন তৈরি করা যায়নি.',
    'Exported file was empty.': 'এক্সপোর্ট করা ফাইলটি খালি ছিল.',
    'Failed to read file size.': 'ফাইলের আকার পড়া যায়নি.',
    'Failed to re-encode the photo.': 'ফটো আবার এনকোড করা যায়নি.',
    'Cancelled.': 'বাতিল করা হয়েছে.',
    'Unknown error': 'অজানা ত্রুটি',
    'Save failed: %@': 'সেভ করা যায়নি: %@',
    'Export failed: %@': 'এক্সপোর্ট ব্যর্থ: %@',
    'Already compressed': 'আগেই কমপ্রেস করা হয়েছে',
    'Size unknown (iCloud-only) — skipped': 'আকার অজানা (শুধু iCloud) — এড়িয়ে যাওয়া হয়েছে',

    'Local AI is unavailable.': 'লোকাল AI উপলব্ধ নয়.',
    'This language is not supported by local AI.': 'লোকাল AI এই ভাষা সমর্থন করে না.',
    'Local AI could not interpret this search.': 'লোকাল AI এই অনুসন্ধান বুঝতে পারেনি.',
    'Use 300 characters or fewer.': '300 বা তার কম অক্ষর ব্যবহার করুন.',
    'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.':
      'অনুসন্ধান শুধু দৃশ্যমান বিষয়বস্তু সমর্থন করে, যেমন সৈকতে কুকুর. তারিখ, জায়গা, নাম ও লেখা ইনডেক্স করা হয় না.',
    'Some requested concepts were not found in this scan. Try a simpler content search.':
      'এই স্ক্যানে কিছু চাওয়া ধারণা পাওয়া যায়নি. আরও সহজ কনটেন্ট অনুসন্ধান চেষ্টা করুন.',
    'Searching labels across all scanned categories.': 'সব স্ক্যান করা শ্রেণিতে লেবেল খোঁজা হচ্ছে.',
    'Using label search across scanned photos.': 'স্ক্যান করা ফটোতে লেবেল অনুসন্ধান ব্যবহার করা হচ্ছে.',
    'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.':
      'এই শব্দগুলি সমর্থিত লেবেল অনুসন্ধান তৈরি করে না. কুকুর বা সৈকতের মতো দৃশ্যমান বিষয়বস্তু চেষ্টা করুন. লেবেল অনুসন্ধান তারিখ, নাম বা বাদ দেওয়া সমর্থন করে না.',

    'This photo may be out of focus.': 'এই ফটোটি ফোকাসের বাইরে থাকতে পারে.',
    'This photo has very low brightness.': 'এই ফটোর উজ্জ্বলতা খুব কম.',
    'This photo has very high brightness.': 'এই ফটোর উজ্জ্বলতা খুব বেশি.',
    'A lens smudge may have reduced image clarity.': 'লেন্সের দাগ ছবির স্পষ্টতা কমিয়ে থাকতে পারে.',
    'This photo received a low visual-quality score.': 'এই ফটোটি দৃশ্যমান গুণমানের কম স্কোর পেয়েছে.',
    'Review whether you still need this screenshot.': 'দেখে নিন এই স্ক্রিনশট আপনার এখনও দরকার কি না.',
    'Review whether you still need this screen recording.': 'দেখে নিন এই স্ক্রিন রেকর্ডিং আপনার এখনও দরকার কি না.',
    'This item uses %@; review whether you need it.': 'এই আইটেমটি %@ নেয়; দেখে নিন এটি আপনার দরকার কি না.',

    Light: 'হালকা',
    Dark: 'গাঢ়',
    'Nothing to free on iPhone': 'iPhone-এ খালি করার মতো কিছু নেই',
    'Up to %@ to free on iPhone': 'iPhone-এ %@ পর্যন্ত খালি করা যায়',
    'Open TidyByte to refresh': 'রিফ্রেশ করতে TidyByte খুলুন',
    'Updated %lldd ago': '%lld দিন আগে আপডেট হয়েছে',

    'No matching photos': 'মিলে যায় এমন কোনও ফটো নেই',
    'Submit a content search or try different words.': 'একটি কনটেন্ট অনুসন্ধান দিন বা অন্য শব্দ চেষ্টা করুন.',
    'No photos in this category.': 'এই শ্রেণিতে কোনও ফটো নেই.',
    'Choose albums or change your filters.': 'অ্যালবাম বেছে নিন বা ফিল্টার বদল করুন.',
    'No screen recordings were found.': 'কোনও স্ক্রিন রেকর্ডিং পাওয়া যায়নি.',
  },
};

const fail = (message) => {
  console.error(`FAIL: ${message}`);
  process.exit(1);
};

const BOUNDARY = '\n  },\n  "plurals"';
const HEADER = '{\n  "strings": {\n';

for (const lang of LANGS) {
  const path = join(DIR, `${lang}.json`);
  const raw = readFileSync(path, 'utf8');
  const parsed = JSON.parse(raw);

  // Snapshot the pre-existing state so the verifier can prove nothing moved.
  writeFileSync(
    `/tmp/batch7-before-${lang}.json`,
    `${JSON.stringify({ strings: parsed.strings, plurals: parsed.plurals }, null, 2)}\n`,
  );

  const existing = Object.keys(parsed.strings);
  const sortedExisting = [...existing].sort();
  if (!existing.every((key, index) => key === sortedExisting[index])) {
    fail(`${lang}.json: existing keys are not in codePoint order`);
  }

  const boundary = raw.indexOf(BOUNDARY);
  if (!raw.startsWith(HEADER) || boundary === -1) {
    fail(`${lang}.json: unexpected file layout`);
  }

  const translations = TRANS[lang];
  if (!translations) fail(`${lang}: no translation table`);
  if (Object.keys(translations).length !== KEYS.length) {
    fail(`${lang}: table has ${Object.keys(translations).length} entries, expected ${KEYS.length}`);
  }
  for (const key of KEYS) {
    const value = translations[key];
    if (typeof value !== 'string' || value.length === 0) fail(`${lang}: missing value for ${JSON.stringify(key)}`);
  }
  for (const key of Object.keys(translations)) {
    if (!KEYS.includes(key)) fail(`${lang}: table has a key not in the brief: ${JSON.stringify(key)}`);
    if (key in parsed.strings) fail(`${lang}: key already exists in the file: ${JSON.stringify(key)}`);
  }

  const merged = { ...parsed.strings, ...translations };
  const keys = Object.keys(merged).sort();
  const body = keys
    .map((key) => `    ${JSON.stringify(key)}: ${JSON.stringify(merged[key])}`)
    .join(',\n');

  writeFileSync(path, HEADER + body + raw.slice(boundary));
  console.log(
    `${lang}: ${existing.length} -> ${keys.length} keys (+${keys.length - existing.length})`,
  );
}
