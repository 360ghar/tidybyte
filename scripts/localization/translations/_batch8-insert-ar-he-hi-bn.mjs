#!/usr/bin/env node
/**
 * Batch 8 insert — 93 new keys (80 plain + 13 plural) for ar, he, hi, bn.
 *
 * Keys come from `_batch8-brief.md` and match the 93 catalog entries in
 * `Tidybyte/Resources/Localizable.xcstrings` that had no translation yet.
 *
 * Note: `Not now` (lowercase, rate-prompt decline) is a different key from the
 * already-translated `Not Now` (photo-permission decline). Both exist.
 *
 * Writes with 2-space indentation, codePoint key order for `strings`, and the
 * `_plural-keys.json` order for `plurals` (the order the files already use).
 * The pre-existing bytes are left untouched: the `strings` block is spliced at
 * the `plurals` boundary, and the new plural entries are appended before the
 * closing brace.
 *
 * Run: node scripts/localization/translations/_batch8-insert-ar-he-hi-bn.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const LANGS = ['ar', 'he', 'hi', 'bn'];

/** 80 plain keys: key is the exact English text, value is per-language. */
const PLAIN = [
  // --- Swipe home filter cards ---
  {
    en: 'Worst Shots',
    ar: 'أسوأ اللقطات',
    he: 'הצילומים הגרועים',
    hi: 'सबसे खराब शॉट',
    bn: 'সবচেয়ে খারাপ শট',
  },
  {
    en: 'Review low-scoring photos, lowest first',
    ar: 'راجع الصور ذات التقييم المنخفض، الأدنى أولًا',
    he: 'סקור תמונות עם ציון נמוך, מהנמוך לגבוה',
    hi: 'कम स्कोर वाली फ़ोटो देखें, सबसे कम पहले',
    bn: 'কম স্কোরের ফটো দেখুন, সবচেয়ে কম আগে',
  },
  {
    en: "Photos you haven't reviewed yet",
    ar: 'صور لم تراجعها بعد',
    he: 'תמונות שעוד לא סקרת',
    hi: 'वे फ़ोटो जिनकी आपने अभी समीक्षा नहीं की',
    bn: 'যে ফটোগুলি আপনি এখনও দেখেননি',
  },
  {
    en: 'Every photo and video in your library',
    ar: 'كل صورة وفيديو في مكتبتك',
    he: 'כל תמונה וסרטון בספרייה שלך',
    hi: 'आपकी लाइब्रेरी की हर फ़ोटो और वीडियो',
    bn: 'আপনার লাইব্রেরির প্রতিটি ফটো ও ভিডিও',
  },
  {
    en: 'Review photos and videos taken on or before a date',
    ar: 'راجع الصور والفيديوهات الملتقطة في تاريخ معيّن أو قبله',
    he: 'סקור תמונות וסרטונים שצולמו בתאריך מסוים או לפניו',
    hi: 'किसी तारीख़ को या उससे पहले ली गई फ़ोटो और वीडियो देखें',
    bn: 'একটি তারিখে বা তার আগে তোলা ফটো ও ভিডিও দেখুন',
  },
  {
    en: 'Photos not organized into your albums',
    ar: 'صور غير منظّمة في ألبوماتك',
    he: 'תמונות שלא מסודרות באלבומים שלך',
    hi: 'वे फ़ोटो जो आपके एल्बम में नहीं रखी हैं',
    bn: 'যে ফটোগুলি আপনার অ্যালবামে সাজানো নেই',
  },
  {
    en: 'Specific Album',
    ar: 'ألبوم محدد',
    he: 'אלבום מסוים',
    hi: 'कोई ख़ास एल्बम',
    bn: 'নির্দিষ্ট অ্যালবাম',
  },
  {
    en: 'Review photos from a specific album',
    ar: 'راجع الصور من ألبوم محدد',
    he: 'סקור תמונות מאלבום מסוים',
    hi: 'किसी ख़ास एल्बम की फ़ोटो देखें',
    bn: 'একটি নির্দিষ্ট অ্যালবামের ফটো দেখুন',
  },

  // --- Swipe session: messages and undo ---
  {
    en: 'Marked for deletion. Nothing is deleted until you confirm at the end.',
    ar: 'تم وضع علامة للحذف. لن يُحذف شيء حتى تؤكد في النهاية.',
    he: 'סומן למחיקה. שום דבר לא יימחק עד שתאשר בסוף.',
    hi: 'हटाने के लिए चिह्नित. अंत में पुष्टि करने तक कुछ नहीं हटेगा.',
    bn: 'মুছে ফেলার জন্য চিহ্নিত. শেষে নিশ্চিত না করলে কিছুই মোছা হবে না.',
  },
  {
    en: 'Delete is off until the photo loads.',
    ar: 'الحذف معطّل حتى تُحمَّل الصورة.',
    he: 'המחיקה מושבתת עד שהתמונה תיטען.',
    hi: 'फ़ोटो लोड होने तक हटाना बंद है.',
    bn: 'ফটো লোড না হওয়া পর্যন্ত মোছা বন্ধ থাকে.',
  },
  {
    en: 'Pinch or double-tap a photo to inspect it',
    ar: 'اضغط بإصبعين أو انقر نقرًا مزدوجًا على أي صورة لفحصها',
    he: 'צבוט או הקש פעמיים על תמונה כדי לבדוק אותה',
    hi: 'फ़ोटो देखने के लिए उसे पिंच करें या डबल-टैप करें',
    bn: 'ফটো দেখতে পিঞ্চ করুন বা ডাবল-ট্যাপ করুন',
  },
  {
    en: "That photo can't be undone anymore.",
    ar: 'لم يعد ممكنًا التراجع عن هذه الصورة.',
    he: 'לא ניתן יותר לבטל את התמונה הזו.',
    hi: 'उस फ़ोटो को अब पूर्ववत नहीं किया जा सकता.',
    bn: 'ওই ফটোটি আর ফিরিয়ে আনা যাবে না.',
  },
  {
    en: 'Undo your newer actions first to reach that photo.',
    ar: 'تراجع عن إجراءاتك الأحدث أولًا للوصول إلى هذه الصورة.',
    he: 'בטל קודם את הפעולות החדשות יותר כדי להגיע לתמונה הזו.',
    hi: 'उस फ़ोटो तक पहुँचने के लिए पहले अपनी नई कार्रवाइयाँ पूर्ववत करें.',
    bn: 'ওই ফটোতে পৌঁছাতে আগে আপনার নতুন কাজগুলি আনডু করুন.',
  },
  {
    en: 'Your library changed during analysis. Try Worst Shots again.',
    ar: 'تغيّرت مكتبتك أثناء التحليل. جرّب «أسوأ اللقطات» مرة أخرى.',
    he: 'הספרייה שלך השתנתה בזמן הניתוח. נסה שוב את "הצילומים הגרועים".',
    hi: 'विश्लेषण के दौरान आपकी लाइब्रेरी बदल गई. "सबसे खराब शॉट" फिर से आज़माएँ.',
    bn: 'বিশ্লেষণের সময় আপনার লাইব্রেরি বদলে গেছে. "সবচেয়ে খারাপ শট" আবার চেষ্টা করুন.',
  },
  {
    en: 'No photo is waiting to be filed. Dismiss and try again.',
    ar: 'لا توجد صورة في انتظار الحفظ في ألبوم. أغلق وحاول مرة أخرى.',
    he: 'אין תמונה שממתינה לשיוך לאלבום. סגור ונסה שוב.',
    hi: 'एल्बम में रखने के लिए कोई फ़ोटो प्रतीक्षा में नहीं है. बंद करें और फिर से प्रयास करें.',
    bn: 'অ্যালবামে রাখার মতো কোনও ফটো অপেক্ষা করছে না. বন্ধ করে আবার চেষ্টা করুন.',
  },
  {
    en: 'Still adding — please wait a moment and try again.',
    ar: 'جارٍ الإضافة — انتظر لحظة وحاول مرة أخرى.',
    he: 'עדיין מוסיף — המתן רגע ונסה שוב.',
    hi: 'अभी जोड़ा जा रहा है — कृपया एक पल रुकें और फिर से प्रयास करें.',
    bn: 'এখনও যোগ করা হচ্ছে — একটু অপেক্ষা করে আবার চেষ্টা করুন.',
  },
  {
    en: "Couldn't save your changes. Please try again.",
    ar: 'تعذر حفظ تغييراتك. حاول مرة أخرى.',
    he: 'לא ניתן היה לשמור את השינויים שלך. נסה שוב.',
    hi: 'आपके बदलाव सहेजे नहीं जा सके. कृपया फिर से प्रयास करें.',
    bn: 'আপনার পরিবর্তনগুলি সেভ করা যায়নি. আবার চেষ্টা করুন.',
  },

  // --- Session completion: result rows ---
  {
    en: 'Added to albums',
    ar: 'تمت الإضافة إلى الألبومات',
    he: 'נוסף לאלבומים',
    hi: 'एल्बम में जोड़ी गईं',
    bn: 'অ্যালবামে যোগ করা হয়েছে',
  },
  {
    en: 'Moved to Recently Deleted',
    ar: 'تم النقل إلى «المحذوفة مؤخرًا»',
    he: 'הועבר אל "נמחקו לאחרונה"',
    hi: 'हाल ही में हटाए गए में भेजी गईं',
    bn: 'সম্প্রতি মোছা-য় সরানো হয়েছে',
  },
  { en: 'Kept', ar: 'تم الاحتفاظ', he: 'נשמר', hi: 'रखी गईं', bn: 'রাখা হয়েছে' },
  { en: 'Skipped', ar: 'تم التخطي', he: 'דולג', hi: 'छोड़ी गईं', bn: 'এড়িয়ে যাওয়া হয়েছে' },
  { en: 'Deleted', ar: 'تم الحذف', he: 'נמחק', hi: 'हटाई गईं', bn: 'মোছা হয়েছে' },

  // --- Burst cleaner: keeper reasons ---
  {
    en: 'Kept: your choice',
    ar: 'محتفظ بها: اختيارك',
    he: 'נשמר: הבחירה שלך',
    hi: 'रखी गई: आपकी पसंद',
    bn: 'রাখা হয়েছে: আপনার পছন্দ',
  },
  {
    en: 'Kept: your pick in Photos',
    ar: 'محتفظ بها: اختيارك في «الصور»',
    he: 'נשמר: הבחירה שלך ב"תמונות"',
    hi: 'रखी गई: फ़ोटो में आपकी पसंद',
    bn: 'রাখা হয়েছে: ফটো অ্যাপে আপনার পছন্দ',
  },
  {
    en: "Kept: iPhone's pick",
    ar: 'محتفظ بها: اختيار iPhone',
    he: 'נשמר: הבחירה של iPhone',
    hi: 'रखी गई: iPhone की पसंद',
    bn: 'রাখা হয়েছে: iPhone-এর পছন্দ',
  },
  {
    en: 'Kept: favorite',
    ar: 'محتفظ بها: مفضلة',
    he: 'נשמר: מועדף',
    hi: 'रखी गई: पसंदीदा',
    bn: 'রাখা হয়েছে: প্রিয়',
  },
  {
    en: 'Kept: highest resolution',
    ar: 'محتفظ بها: أعلى دقة',
    he: 'נשמר: הרזולוציה הגבוהה ביותר',
    hi: 'रखी गई: सबसे ज़्यादा रिज़ॉल्यूशन',
    bn: 'রাখা হয়েছে: সর্বোচ্চ রেজোলিউশন',
  },
  {
    en: 'Kept: last frame',
    ar: 'محتفظ بها: آخر إطار',
    he: 'נשמר: הפריים האחרון',
    hi: 'रखी गई: आख़िरी फ़्रेम',
    bn: 'রাখা হয়েছে: শেষ ফ্রেম',
  },
  {
    en: 'Kept: auto pick',
    ar: 'محتفظ بها: اختيار تلقائي',
    he: 'נשמר: בחירה אוטומטית',
    hi: 'रखी गई: ऑटो पसंद',
    bn: 'রাখা হয়েছে: স্বয়ংক্রিয় পছন্দ',
  },
  {
    en: ' Favorites are kept.',
    ar: ' المفضلة محتفظ بها.',
    he: ' מועדפים נשמרים.',
    hi: ' पसंदीदा रखी जाती हैं.',
    bn: ' প্রিয় আইটেম রাখা হয়.',
  },
  {
    en: 'This keeps the starred frame of each burst and deletes the rest.',
    ar: 'يحتفظ هذا بالإطار المميز بنجمة في كل مجموعة من الصور المتتابعة ويحذف الباقي.',
    he: 'פעולה זו שומרת את הפריים המסומן בכוכב בכל רצף ומוחקת את השאר.',
    hi: 'यह हर बर्स्ट का स्टार किया गया फ़्रेम रखता है और बाकी हटा देता है.',
    bn: 'এটি প্রতিটি বার্স্টের স্টার দেওয়া ফ্রেম রাখে এবং বাকিগুলি মুছে দেয়.',
  },

  // --- Burst cleaner: result ---
  {
    en: '1 burst cleaned down to a single photo.',
    ar: 'تم تنظيف مجموعة صور متتابعة واحدة لتصل إلى صورة واحدة.',
    he: 'רצף אחד נוקה לתמונה אחת.',
    hi: 'एक बर्स्ट साफ़ करके एक ही फ़ोटो रखी गई.',
    bn: 'একটি বার্স্ট পরিষ্কার করে একটি ফটো রাখা হয়েছে.',
  },
  {
    en: '%lld bursts cleaned down to single photos.',
    ar: 'تم تنظيف %lld مجموعات صور متتابعة حتى صورة واحدة لكل منها.',
    he: '%lld רצפים נוקו לתמונה אחת כל אחד.',
    hi: '%lld बर्स्ट साफ़ करके एक-एक फ़ोटो रखी गईं.',
    bn: '%lld বার্স্ট পরিষ্কার করে একটি করে ফটো রাখা হয়েছে.',
  },

  // --- Errors ---
  {
    en: 'Album not found.',
    ar: 'لم يُعثر على الألبوم.',
    he: 'האלבום לא נמצא.',
    hi: 'एल्बम नहीं मिला.',
    bn: 'অ্যালবাম পাওয়া যায়নি.',
  },
  {
    en: 'Failed to create album.',
    ar: 'تعذر إنشاء الألبوم.',
    he: 'יצירת האלבום נכשלה.',
    hi: 'एल्बम बनाया नहीं जा सका.',
    bn: 'অ্যালবাম তৈরি করা যায়নি.',
  },
  {
    en: "Couldn't modify the album. Please try again.",
    ar: 'تعذر تعديل الألبوم. حاول مرة أخرى.',
    he: 'לא ניתן היה לשנות את האלבום. נסה שוב.',
    hi: 'एल्बम बदला नहीं जा सका. कृपया फिर से प्रयास करें.',
    bn: 'অ্যালবাম বদলানো যায়নি. আবার চেষ্টা করুন.',
  },
  {
    en: 'Nothing was deleted.',
    ar: 'لم يُحذف أي شيء.',
    he: 'שום דבר לא נמחק.',
    hi: 'कुछ भी नहीं हटाया गया.',
    bn: 'কিছুই মোছা হয়নি.',
  },
  {
    en: 'Live Photo not found.',
    ar: 'لم يُعثر على Live Photo.',
    he: 'Live Photo לא נמצא.',
    hi: 'Live Photo नहीं मिला.',
    bn: 'Live Photo পাওয়া যায়নি.',
  },
  {
    en: 'Could not find still image in Live Photo.',
    ar: 'تعذر العثور على صورة ثابتة في Live Photo.',
    he: 'לא נמצאה תמונת סטילס בתוך Live Photo.',
    hi: 'Live Photo में स्थिर छवि नहीं मिली.',
    bn: 'Live Photo-তে স্থির ছবি পাওয়া যায়নি.',
  },
  {
    en: 'Invalid image data.',
    ar: 'بيانات الصورة غير صالحة.',
    he: 'נתוני תמונה לא תקינים.',
    hi: 'छवि डेटा अमान्य है.',
    bn: 'ছবির ডেটা অবৈধ.',
  },
  {
    en: 'Timed out loading the photo (it may still be in iCloud). Please try again.',
    ar: 'انتهت المهلة أثناء تحميل الصورة (قد تكون لا تزال في iCloud). حاول مرة أخرى.',
    he: 'פסק הזמן בטעינת התמונה (ייתכן שהיא עדיין ב-iCloud). נסה שוב.',
    hi: 'फ़ोटो लोड करते समय समय समाप्त हो गया (यह अभी भी iCloud में हो सकती है). कृपया फिर से प्रयास करें.',
    bn: 'ফটো লোড করতে সময় শেষ হয়ে গেছে (এটি এখনও iCloud-এ থাকতে পারে). আবার চেষ্টা করুন.',
  },
  {
    en: 'The compressed copy is missing from your library.',
    ar: 'النسخة المضغوطة مفقودة من مكتبتك.',
    he: 'העותק המכווץ חסר מהספרייה שלך.',
    hi: 'कंप्रेस की गई कॉपी आपकी लाइब्रेरी में नहीं है.',
    bn: 'কমপ্রেস করা কপি আপনার লাইব্রেরিতে নেই.',
  },
  {
    en: 'The converted still is missing from your library.',
    ar: 'الصورة الثابتة المحوَّلة مفقودة من مكتبتك.',
    he: 'התמונה הסטטית המומרת חסרה מהספרייה שלך.',
    hi: 'कन्वर्ट की गई स्थिर छवि आपकी लाइब्रेरी में नहीं है.',
    bn: 'রূপান্তরিত স্থির ছবিটি আপনার লাইব্রেরিতে নেই.',
  },
  {
    en: 'Copies kept. Both versions are in your library; delete either one in Photos.',
    ar: 'تم الاحتفاظ بالنسخ. النسختان موجودتان في مكتبتك؛ احذف أيًّا منهما في «الصور».',
    he: 'העותקים נשמרו. שתי הגרסאות נמצאות בספרייה שלך; מחק אחת מהן בתמונות.',
    hi: 'कॉपियाँ रखी गईं. दोनों वर्शन आपकी लाइब्रेरी में हैं; फ़ोटो में इनमें से कोई एक हटाएँ.',
    bn: 'কপিগুলি রাখা হয়েছে. দুটি সংস্করণই আপনার লাইব্রেরিতে আছে; ফটো-তে যেকোনও একটি মুছে দিন.',
  },
  {
    en: "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.",
    ar: 'تم حذف %lld من أصل %lld عنصرًا. تعذر حذف %lld. حاول مرة أخرى.',
    he: 'נמחקו %lld מתוך %lld פריטים. %lld לא ניתן היה למחוק. נסה שוב.',
    hi: '%lld में से %lld आइटम हटाए गए. %lld हटाए नहीं जा सके. फिर से प्रयास करें.',
    bn: '%lldটির মধ্যে %lld আইটেম মোছা হয়েছে. %lld মোছা যায়নি. আবার চেষ্টা করুন.',
  },
  {
    en: 'Your library changed. Scan again before searching.',
    ar: 'تغيّرت مكتبتك. أعد الفحص قبل البحث.',
    he: 'הספרייה שלך השתנתה. סרוק שוב לפני החיפוש.',
    hi: 'आपकी लाइब्रेरी बदल गई. खोजने से पहले फिर से स्कैन करें.',
    bn: 'আপনার লাইব্রেরি বদলে গেছে. খোঁজার আগে আবার স্ক্যান করুন.',
  },
  {
    en: 'Removed changed or unavailable photos. Scan again to include new or edited photos.',
    ar: 'تمت إزالة الصور المتغيرة أو غير المتاحة. أعد الفحص لتضمين الصور الجديدة أو المعدّلة.',
    he: 'תמונות ששונו או שאינן זמינות הוסרו. סרוק שוב כדי לכלול תמונות חדשות או ערוכות.',
    hi: 'बदली हुई या अनुपलब्ध फ़ोटो हटा दी गईं. नई या एडिट की गई फ़ोटो शामिल करने के लिए फिर से स्कैन करें.',
    bn: 'বদলে যাওয়া বা অনুপলব্ধ ফটো সরানো হয়েছে. নতুন বা এডিট করা ফটো যোগ করতে আবার স্ক্যান করুন.',
  },

  // --- Storage dashboard and permission screen ---
  {
    en: 'Recently Deleted',
    ar: 'المحذوفة مؤخرًا',
    he: 'נמחקו לאחרונה',
    hi: 'हाल ही में हटाए गए',
    bn: 'সম্প্রতি মোছা',
  },
  {
    en: 'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.',
    ar: 'تعود المساحة عند تفريغها. في «الصور»، افتح «الألبومات»، ثم «المحذوفة مؤخرًا».',
    he: 'המקום מתפנה כשמרוקנים אותה. בתמונות, פתח את אלבומים ואז את "נמחקו לאחרונה".',
    hi: 'इसे खाली करने पर जगह वापस आती है. फ़ोटो में, एल्बम खोलें, फिर हाल ही में हटाए गए.',
    bn: 'এটি খালি করলে জায়গা ফিরে আসে. ফটো-তে অ্যালবাম খুলুন, তারপর সম্প্রতি মোছা.',
  },
  {
    en: 'Manage Apps & System Storage',
    ar: 'إدارة التطبيقات وتخزين النظام',
    he: 'ניהול אפליקציות ואחסון המערכת',
    hi: 'ऐप्स और सिस्टम स्टोरेज प्रबंधित करें',
    bn: 'অ্যাপ ও সিস্টেম স্টোরেজ পরিচালনা করুন',
  },
  {
    en: 'Open Settings ▸ General ▸ iPhone Storage',
    ar: 'افتح «الإعدادات» ▸ «عام» ▸ «مساحة تخزين iPhone»',
    he: 'פתח את הגדרות ▸ כללי ▸ אחסון iPhone',
    hi: 'सेटिंग्स ▸ सामान्य ▸ iPhone स्टोरेज खोलें',
    bn: 'সেটিংস ▸ সাধারণ ▸ iPhone স্টোরেজ খুলুন',
  },
  {
    en: 'Library figures below cover only the photos you selected; device totals cover the whole device.',
    ar: 'الأرقام أدناه تغطي فقط الصور التي اخترتها؛ أما إجماليات الجهاز فتغطي الجهاز بأكمله.',
    he: 'הנתונים שלהלן מתייחסים רק לתמונות שבחרת; סיכומי המכשיר מכסים את המכשיר כולו.',
    hi: 'नीचे दिए आँकड़े केवल उन्हीं फ़ोटो को कवर करते हैं जो आपने चुनी हैं; डिवाइस के आँकड़े पूरे डिवाइस को कवर करते हैं.',
    bn: 'নিচের সংখ্যাগুলি শুধু আপনি বেছে নেওয়া ফটো বোঝায়; ডিভাইসের সংখ্যা পুরো ডিভাইস বোঝায়.',
  },
  {
    en: 'Find exact and near-duplicate photos',
    ar: 'العثور على الصور المكررة تمامًا وشبه المكررة',
    he: 'איתור תמונות כפולות וכמעט כפולות',
    hi: 'हूबहू और लगभग डुप्लिकेट फ़ोटो ढूँढें',
    bn: 'হুবহু ও প্রায়-ডুপ্লিকেট ফটো খুঁজুন',
  },
  {
    en: 'Spot blurry, dark, and overexposed shots',
    ar: 'اكتشاف الصور الضبابية والداكنة والمفرطة في الإضاءة',
    he: 'איתור צילומים מטושטשים, כהים וחשופים מדי',
    hi: 'धुंधली, अँधेरी और ज़्यादा रोशनी वाली फ़ोटो पहचानें',
    bn: 'ঝাপসা, অন্ধকার ও অতিরিক্ত আলোর ফটো চিহ্নিত করুন',
  },
  {
    en: 'Surface the biggest files taking up space',
    ar: 'إظهار أكبر الملفات التي تستهلك المساحة',
    he: 'הצגת הקבצים הגדולים ביותר שתופסים מקום',
    hi: 'सबसे बड़ी जगह लेने वाली फ़ाइलें दिखाएँ',
    bn: 'সবচেয়ে বেশি জায়গা নেওয়া ফাইল দেখান',
  },
  {
    en: 'Delete only what you review and approve',
    ar: 'احذف فقط ما تراجعه وتوافق عليه',
    he: 'מחיקת רק מה שסקרת ואישרת',
    hi: 'केवल वही हटाएँ जिसे आप देखकर मंज़ूरी दें',
    bn: 'শুধু আপনি যেটি দেখে অনুমোদন করবেন সেটিই মুছুন',
  },

  // --- Activity and savings ---
  {
    en: 'items, all time',
    ar: 'عناصر، منذ البداية',
    he: 'פריטים, מכל הזמנים',
    hi: 'आइटम, अब तक',
    bn: 'আইটেম, এখন পর্যন্ত',
  },
  { en: 'this month', ar: 'هذا الشهر', he: 'החודש', hi: 'इस महीने', bn: 'এই মাসে' },
  { en: 'Size unknown', ar: 'الحجم غير معروف', he: 'גודל לא ידוע', hi: 'आकार अज्ञात', bn: 'আকার অজানা' },
  {
    en: 'Size unavailable',
    ar: 'الحجم غير متاح',
    he: 'גודל לא זמין',
    hi: 'आकार उपलब्ध नहीं',
    bn: 'আকার পাওয়া যাচ্ছে না',
  },
  {
    en: 'cleaned up since you started using TidyByte',
    ar: 'تم تنظيفها منذ أن بدأت استخدام TidyByte',
    he: 'נוקו מאז שהתחלת להשתמש ב-TidyByte',
    hi: 'TidyByte इस्तेमाल करना शुरू करने के बाद से साफ़ किया गया',
    bn: 'TidyByte ব্যবহার শুরু করার পর থেকে পরিষ্কার করা হয়েছে',
  },
  {
    en: "Nothing measurable yet. Items stored only in iCloud don't report a size.",
    ar: 'لا يوجد شيء قابل للقياس بعد. العناصر المخزنة في iCloud فقط لا تُبلغ عن حجمها.',
    he: 'אין עדיין מה למדוד. פריטים המאוחסנים רק ב-iCloud לא מדווחים גודל.',
    hi: 'अभी कुछ मापने लायक नहीं है. केवल iCloud में रखे आइटम आकार नहीं बताते.',
    bn: 'এখনও পরিমাপ করার মতো কিছু নেই. শুধু iCloud-এ রাখা আইটেম আকার জানায় না.',
  },

  // --- Rate prompt and feedback ---
  {
    en: 'Enjoying TidyByte?',
    ar: 'هل تستمتع بـTidyByte؟',
    he: 'נהנה מ-TidyByte?',
    hi: 'TidyByte पसंद आ रहा है?',
    bn: 'TidyByte ভালো লাগছে?',
  },
  {
    en: 'Thanks for the support',
    ar: 'شكرًا لدعمك',
    he: 'תודה על התמיכה',
    hi: 'साथ देने के लिए धन्यवाद',
    bn: 'সহযোগিতার জন্য ধন্যবাদ',
  },
  {
    en: 'What should we fix?',
    ar: 'ما الذي يجب أن نصلحه؟',
    he: 'מה כדאי שנתקן?',
    hi: 'हमें क्या ठीक करना चाहिए?',
    bn: 'আমাদের কী ঠিক করা উচিত?',
  },
  {
    en: 'Tell us what got in the way.',
    ar: 'أخبرنا بما أعاقك.',
    he: 'ספר לנו מה הפריע.',
    hi: 'बताइए किस चीज़ ने रोका.',
    bn: 'বলুন কোনটা বাধা হয়ে দাঁড়িয়েছে.',
  },
  {
    en: 'Send Feedback',
    ar: 'إرسال الملاحظات',
    he: 'שלח משוב',
    hi: 'फ़ीडबैक भेजें',
    bn: 'ফিডব্যাক পাঠান',
  },
  { en: 'Yes', ar: 'نعم', he: 'כן', hi: 'हाँ', bn: 'হ্যাঁ' },
  { en: 'Not really', ar: 'ليس تمامًا', he: 'לא ממש', hi: 'ज़्यादा नहीं', bn: 'তেমন নয়' },
  { en: 'Not now', ar: 'ليس الآن', he: 'לא עכשיו', hi: 'अभी नहीं', bn: 'এখন নয়' },
  {
    en: 'Your rating helps other people find TidyByte.',
    ar: 'تقييمك يساعد الآخرين على اكتشاف TidyByte.',
    he: 'הדירוג שלך עוזר לאחרים למצוא את TidyByte.',
    hi: 'आपकी रेटिंग से दूसरों को TidyByte ढूँढने में मदद मिलती है.',
    bn: 'আপনার রেটিং অন্য মানুষকে TidyByte খুঁজে পেতে সাহায্য করে.',
  },
  { en: 'You just %@.', ar: 'لقد %@.', he: 'זה עתה %@.', hi: 'आपने अभी %@.', bn: 'এইমাত্র %@.' },
  {
    en: "The message couldn't be sent. Try again, or email us at %@.",
    ar: 'تعذر إرسال الرسالة. حاول مرة أخرى، أو راسلنا على %@.',
    he: 'לא ניתן לשלוח את ההודעה. נסה שוב, או כתוב לנו לכתובת %@.',
    hi: 'संदेश भेजा नहीं जा सका. फिर से प्रयास करें, या हमें %@ पर ईमेल करें.',
    bn: 'বার্তাটি পাঠানো যায়নি. আবার চেষ্টা করুন, বা %@-এ আমাদের ইমেল করুন.',
  },
  {
    en: 'No mail account is set up on this device. Email us at %@.',
    ar: 'لا يوجد حساب بريد مُعدّ على هذا الجهاز. راسلنا على %@.',
    he: 'לא מוגדר חשבון דואר במכשיר הזה. כתוב לנו לכתובת %@.',
    hi: 'इस डिवाइस पर कोई मेल खाता सेट नहीं है. हमें %@ पर ईमेल करें.',
    bn: 'এই ডিভাইসে কোনও মেল অ্যাকাউন্ট সেট করা নেই. %@-এ আমাদের ইমেল করুন.',
  },

  // --- Share text ---
  { en: 'I just %@', ar: 'لقد %@', he: 'הרגע %@', hi: 'मैंने अभी %@', bn: 'এইমাত্র %@' },
  {
    en: "I'm cleaning up my photo library",
    ar: 'أنظّف مكتبة صوري',
    he: 'אני מנקה את ספריית התמונות שלי',
    hi: 'मेरी फ़ोटो लाइब्रेरी की सफ़ाई जारी है',
    bn: 'আমি আমার ফটো লাইব্রেরি পরিষ্কার করছি',
  },
  {
    en: '%@ with TidyByte — a private, on-device photo cleanup app. %@',
    ar: '%@ باستخدام TidyByte — تطبيق خاص لتنظيف الصور على جهازك. %@',
    he: '%@ עם TidyByte — אפליקציה פרטית לניקוי תמונות, על המכשיר. %@',
    hi: '%@ — TidyByte के साथ, एक निजी, डिवाइस पर ही चलने वाला फ़ोटो क्लीनअप ऐप. %@',
    bn: '%@ — TidyByte দিয়ে একটি ব্যক্তিগত, ডিভাইসেই চলা ফটো পরিষ্কার অ্যাপ. %@',
  },

  // --- Misc ---
  {
    en: 'Min size: %@',
    ar: 'الحد الأدنى للحجم: %@',
    he: 'גודל מינימלי: %@',
    hi: 'न्यूनतम आकार: %@',
    bn: 'সর্বনিম্ন আকার: %@',
  },
  {
    en: 'Swipe history cleared',
    ar: 'تم مسح سجل السحب',
    he: 'היסטוריית ההחלקות נוקתה',
    hi: 'स्वाइप इतिहास साफ़ किया गया',
    bn: 'সোয়াইপ ইতিহাস সাফ করা হয়েছে',
  },
  {
    en: 'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.',
    ar: 'سيطلب iOS منك التأكيد. تنتقل العناصر المحذوفة إلى «المحذوفة مؤخرًا» في «الصور»، حيث يمكنك استعادتها خلال 30 يومًا.',
    he: 'iOS יבקש ממך לאשר. פריטים שנמחקו עוברים אל "נמחקו לאחרונה" בתמונות, שם ניתן לשחזר אותם במשך 30 ימים.',
    hi: 'iOS आपसे पुष्टि करने को कहेगा. हटाए गए आइटम फ़ोटो में हाल ही में हटाए गए में जाते हैं, जहाँ आप उन्हें 30 दिनों तक बहाल कर सकते हैं.',
    bn: 'iOS আপনাকে নিশ্চিত করতে বলবে. মুছে ফেলা আইটেম ফটো অ্যাপের সম্প্রতি মোছা-য় যায়, যেখান থেকে 30 দিন পর্যন্ত ফিরিয়ে আনা যায়.',
  },
];

/**
 * 13 plural keys. Key is the English singular; each value carries exactly the
 * CLDR categories the language uses, in the order the file already writes them.
 */
const PLURALS = [
  {
    en: 'cleared %lld photo',
    ar: {
      zero: 'تم تنظيف %lld صور',
      one: 'تم تنظيف %lld صورة',
      two: 'تم تنظيف %lld صورتين',
      few: 'تم تنظيف %lld صور',
      many: 'تم تنظيف %lld صورةً',
      other: 'تم تنظيف %lld صورة',
    },
    he: {
      one: 'נוקתה %lld תמונה',
      two: 'נוקו %lld תמונות',
      other: 'נוקו %lld תמונות',
    },
    hi: {
      one: '%lld फ़ोटो साफ़ की',
      other: '%lld फ़ोटो साफ़ कीं',
    },
    bn: {
      one: '%lld ফটো মুছে ফেলা হয়েছে',
      other: '%lld ফটো মুছে ফেলা হয়েছে',
    },
  },
  {
    en: 'cleared %lld blurry photo',
    ar: {
      zero: 'تم تنظيف %lld صور ضبابية',
      one: 'تم تنظيف %lld صورة ضبابية',
      two: 'تم تنظيف %lld صورتين ضبابيتين',
      few: 'تم تنظيف %lld صور ضبابية',
      many: 'تم تنظيف %lld صورةً ضبابيةً',
      other: 'تم تنظيف %lld صورة ضبابية',
    },
    he: {
      one: 'נוקתה %lld תמונה מטושטשת',
      two: 'נוקו %lld תמונות מטושטשות',
      other: 'נוקו %lld תמונות מטושטשות',
    },
    hi: {
      one: '%lld धुंधली फ़ोटो साफ़ की',
      other: '%lld धुंधली फ़ोटो साफ़ कीं',
    },
    bn: {
      one: '%lld ঝাপসা ফটো মুছে ফেলা হয়েছে',
      other: '%lld ঝাপসা ফটো মুছে ফেলা হয়েছে',
    },
  },
  {
    en: 'cleared %lld screenshot',
    ar: {
      zero: 'تم تنظيف %lld لقطات شاشة',
      one: 'تم تنظيف %lld لقطة شاشة',
      two: 'تم تنظيف %lld لقطتي شاشة',
      few: 'تم تنظيف %lld لقطات شاشة',
      many: 'تم تنظيف %lld لقطة شاشة',
      other: 'تم تنظيف %lld لقطة شاشة',
    },
    he: {
      one: 'נוקה %lld צילום מסך',
      two: 'נוקו %lld צילומי מסך',
      other: 'נוקו %lld צילומי מסך',
    },
    hi: {
      one: '%lld स्क्रीनशॉट साफ़ किया',
      other: '%lld स्क्रीनशॉट साफ़ किए',
    },
    bn: {
      one: '%lld স্ক্রিনশট মুছে ফেলা হয়েছে',
      other: '%lld স্ক্রিনশট মুছে ফেলা হয়েছে',
    },
  },
  {
    en: 'cleared %lld large file',
    ar: {
      zero: 'تم تنظيف %lld ملفات كبيرة',
      one: 'تم تنظيف %lld ملف كبير',
      two: 'تم تنظيف %lld ملفين كبيرين',
      few: 'تم تنظيف %lld ملفات كبيرة',
      many: 'تم تنظيف %lld ملفًا كبيرًا',
      other: 'تم تنظيف %lld ملف كبير',
    },
    he: {
      one: 'נוקה %lld קובץ גדול',
      two: 'נוקו %lld קבצים גדולים',
      other: 'נוקו %lld קבצים גדולים',
    },
    hi: {
      one: '%lld बड़ी फ़ाइल साफ़ की',
      other: '%lld बड़ी फ़ाइलें साफ़ कीं',
    },
    bn: {
      one: '%lld বড় ফাইল মুছে ফেলা হয়েছে',
      other: '%lld বড় ফাইল মুছে ফেলা হয়েছে',
    },
  },
  {
    en: 'cleared %lld burst frame',
    ar: {
      zero: 'تم تنظيف %lld إطارات متتابعة',
      one: 'تم تنظيف %lld إطار متتابع',
      two: 'تم تنظيف %lld إطارين متتابعين',
      few: 'تم تنظيف %lld إطارات متتابعة',
      many: 'تم تنظيف %lld إطارًا متتابعًا',
      other: 'تم تنظيف %lld إطار متتابع',
    },
    he: {
      one: 'נוקה %lld פריים מרצף',
      two: 'נוקו %lld פריימים מרצף',
      other: 'נוקו %lld פריימים מרצף',
    },
    hi: {
      one: '%lld बर्स्ट फ़्रेम साफ़ किया',
      other: '%lld बर्स्ट फ़्रेम साफ़ किए',
    },
    bn: {
      one: '%lld বার্স্ট ফ্রেম মুছে ফেলা হয়েছে',
      other: '%lld বার্স্ট ফ্রেম মুছে ফেলা হয়েছে',
    },
  },
  {
    en: 'cleared %lld item (%@)',
    ar: {
      zero: 'تم تنظيف %lld عناصر (%@)',
      one: 'تم تنظيف %lld عنصر (%@)',
      two: 'تم تنظيف %lld عنصرين (%@)',
      few: 'تم تنظيف %lld عناصر (%@)',
      many: 'تم تنظيف %lld عنصرًا (%@)',
      other: 'تم تنظيف %lld عنصر (%@)',
    },
    he: {
      one: 'נוקה %lld פריט (%@)',
      two: 'נוקו %lld פריטים (%@)',
      other: 'נוקו %lld פריטים (%@)',
    },
    hi: {
      one: '%lld आइटम साफ़ किया (%@)',
      other: '%lld आइटम साफ़ किए (%@)',
    },
    bn: {
      one: '%lld আইটেম মুছে ফেলা হয়েছে (%@)',
      other: '%lld আইটেম মুছে ফেলা হয়েছে (%@)',
    },
  },
  {
    en: 'removed %lld duplicate',
    ar: {
      zero: 'تمت إزالة %lld مكررات',
      one: 'تمت إزالة %lld مكرر',
      two: 'تمت إزالة %lld مكررين',
      few: 'تمت إزالة %lld مكررات',
      many: 'تمت إزالة %lld مكررًا',
      other: 'تمت إزالة %lld مكرر',
    },
    he: {
      one: 'הוסר %lld כפול',
      two: 'הוסרו %lld כפולים',
      other: 'הוסרו %lld כפולים',
    },
    hi: {
      one: '%lld डुप्लिकेट हटाया',
      other: '%lld डुप्लिकेट हटाए',
    },
    bn: {
      one: '%lld ডুপ্লিকেট সরানো হয়েছে',
      other: '%lld ডুপ্লিকেট সরানো হয়েছে',
    },
  },
  {
    en: 'removed %lld similar photo',
    ar: {
      zero: 'تمت إزالة %lld صور مشابهة',
      one: 'تمت إزالة %lld صورة مشابهة',
      two: 'تمت إزالة %lld صورتين مشابهتين',
      few: 'تمت إزالة %lld صور مشابهة',
      many: 'تمت إزالة %lld صورةً مشابهةً',
      other: 'تمت إزالة %lld صورة مشابهة',
    },
    he: {
      one: 'הוסרה %lld תמונה דומה',
      two: 'הוסרו %lld תמונות דומות',
      other: 'הוסרו %lld תמונות דומות',
    },
    hi: {
      one: '%lld मिलती-जुलती फ़ोटो हटाई',
      other: '%lld मिलती-जुलती फ़ोटो हटाईं',
    },
    bn: {
      one: '%lld একইরকম ফটো সরানো হয়েছে',
      other: '%lld একইরকম ফটো সরানো হয়েছে',
    },
  },
  {
    en: 'compressed %lld photo',
    ar: {
      zero: 'تم ضغط %lld صور',
      one: 'تم ضغط %lld صورة',
      two: 'تم ضغط %lld صورتين',
      few: 'تم ضغط %lld صور',
      many: 'تم ضغط %lld صورةً',
      other: 'تم ضغط %lld صورة',
    },
    he: {
      one: 'כווצה %lld תמונה',
      two: 'כווצו %lld תמונות',
      other: 'כווצו %lld תמונות',
    },
    hi: {
      one: '%lld फ़ोटो कंप्रेस की',
      other: '%lld फ़ोटो कंप्रेस कीं',
    },
    bn: {
      one: '%lld ফটো কমপ্রেস করা হয়েছে',
      other: '%lld ফটো কমপ্রেস করা হয়েছে',
    },
  },
  {
    en: 'compressed %lld video',
    ar: {
      zero: 'تم ضغط %lld فيديوهات',
      one: 'تم ضغط %lld فيديو',
      two: 'تم ضغط %lld فيديوهين',
      few: 'تم ضغط %lld فيديوهات',
      many: 'تم ضغط %lld فيديو',
      other: 'تم ضغط %lld فيديو',
    },
    he: {
      one: 'כווץ %lld סרטון',
      two: 'כווצו %lld סרטונים',
      other: 'כווצו %lld סרטונים',
    },
    hi: {
      one: '%lld वीडियो कंप्रेस किया',
      other: '%lld वीडियो कंप्रेस किए',
    },
    bn: {
      one: '%lld ভিডিও কমপ্রেস করা হয়েছে',
      other: '%lld ভিডিও কমপ্রেস করা হয়েছে',
    },
  },
  {
    en: 'cleaned %lld burst photo',
    ar: {
      zero: 'تم تنظيف %lld صور متتابعة',
      one: 'تم تنظيف %lld صورة متتابعة',
      two: 'تم تنظيف %lld صورتين متتابعتين',
      few: 'تم تنظيف %lld صور متتابعة',
      many: 'تم تنظيف %lld صورةً متتابعةً',
      other: 'تم تنظيف %lld صورة متتابعة',
    },
    he: {
      one: 'נוקתה %lld תמונת רצף',
      two: 'נוקו %lld תמונות רצף',
      other: 'נוקו %lld תמונות רצף',
    },
    hi: {
      one: '%lld बर्स्ट फ़ोटो साफ़ की',
      other: '%lld बर्स्ट फ़ोटो साफ़ कीं',
    },
    bn: {
      one: '%lld বার্স্ট ফটো পরিষ্কার করা হয়েছে',
      other: '%lld বার্স্ট ফটো পরিষ্কার করা হয়েছে',
    },
  },
  {
    en: 'converted %lld Live Photo',
    ar: {
      zero: 'تم تحويل %lld Live Photo',
      one: 'تم تحويل %lld Live Photo',
      two: 'تم تحويل %lld Live Photo',
      few: 'تم تحويل %lld Live Photo',
      many: 'تم تحويل %lld Live Photo',
      other: 'تم تحويل %lld Live Photo',
    },
    he: {
      one: 'הומר %lld Live Photo',
      two: 'הומרו %lld Live Photo',
      other: 'הומרו %lld Live Photo',
    },
    hi: {
      one: '%lld Live Photo कन्वर्ट किया',
      other: '%lld Live Photo कन्वर्ट किए',
    },
    bn: {
      one: '%lld Live Photo রূপান্তর করা হয়েছে',
      other: '%lld Live Photo রূপান্তর করা হয়েছে',
    },
  },
  {
    en: 'reviewed %lld item',
    ar: {
      zero: 'تمت مراجعة %lld عناصر',
      one: 'تمت مراجعة %lld عنصر',
      two: 'تمت مراجعة %lld عنصرين',
      few: 'تمت مراجعة %lld عناصر',
      many: 'تمت مراجعة %lld عنصرًا',
      other: 'تمت مراجعة %lld عنصر',
    },
    he: {
      one: 'נסקר %lld פריט',
      two: 'נסקרו %lld פריטים',
      other: 'נסקרו %lld פריטים',
    },
    hi: {
      one: '%lld आइटम देखा',
      other: '%lld आइटम देखे',
    },
    bn: {
      one: '%lld আইটেম দেখা হয়েছে',
      other: '%lld আইটেম দেখা হয়েছে',
    },
  },
];

const fail = (message) => {
  console.error(`FAIL: ${message}`);
  process.exit(1);
};

const BOUNDARY = '\n  },\n  "plurals"';
const HEADER = '{\n  "strings": {\n';
const TAIL = '  }\n}\n';

if (PLAIN.length !== 80) fail(`PLAIN has ${PLAIN.length} entries, expected 80`);
if (PLURALS.length !== 13) fail(`PLURALS has ${PLURALS.length} entries, expected 13`);

for (const lang of LANGS) {
  const path = join(DIR, `${lang}.json`);
  const raw = readFileSync(path, 'utf8');
  const parsed = JSON.parse(raw);

  // Snapshot the pre-existing state so the verifier can prove nothing moved.
  writeFileSync(
    `/tmp/batch8-before-${lang}.json`,
    `${JSON.stringify({ strings: parsed.strings, plurals: parsed.plurals }, null, 2)}\n`,
  );

  const existing = Object.keys(parsed.strings);
  const sortedExisting = [...existing].sort();
  if (!existing.every((key, index) => key === sortedExisting[index])) {
    fail(`${lang}.json: existing keys are not in codePoint order`);
  }

  const boundary = raw.indexOf(BOUNDARY);
  if (!raw.startsWith(HEADER) || boundary === -1) fail(`${lang}.json: unexpected file layout`);
  if (!raw.endsWith(TAIL)) fail(`${lang}.json: unexpected file tail`);

  // --- plain keys ---
  const additions = {};
  for (const entry of PLAIN) {
    const value = entry[lang];
    if (typeof value !== 'string' || value.length === 0) {
      fail(`${lang}: missing plain value for ${JSON.stringify(entry.en)}`);
    }
    if (entry.en in parsed.strings) fail(`${lang}: plain key already present: ${JSON.stringify(entry.en)}`);
    additions[entry.en] = value;
  }

  const merged = { ...parsed.strings, ...additions };
  const keys = Object.keys(merged).sort();
  const stringsBody = keys
    .map((key) => `    ${JSON.stringify(key)}: ${JSON.stringify(merged[key])}`)
    .join(',\n');

  // --- plural keys ---
  const pluralAdditions = [];
  for (const entry of PLURALS) {
    const categories = entry[lang];
    if (!categories || typeof categories !== 'object') {
      fail(`${lang}: missing plural value for ${JSON.stringify(entry.en)}`);
    }
    if (entry.en in parsed.plurals) fail(`${lang}: plural key already present: ${JSON.stringify(entry.en)}`);
    const body = Object.entries(categories)
      .map(([category, value]) => `      ${JSON.stringify(category)}: ${JSON.stringify(value)}`)
      .join(',\n');
    pluralAdditions.push(`    ${JSON.stringify(entry.en)}: {\n${body}\n    }`);
  }

  const head = HEADER + stringsBody + raw.slice(boundary);
  const headWithoutTail = head.slice(0, head.length - TAIL.length);
  const out = `${headWithoutTail},\n${pluralAdditions.join(',\n')}\n${TAIL}`;

  writeFileSync(path, out);

  const written = JSON.parse(readFileSync(path, 'utf8'));
  console.log(
    `${lang}: strings ${existing.length} -> ${Object.keys(written.strings).length}, ` +
      `plurals ${Object.keys(parsed.plurals).length} -> ${Object.keys(written.plurals).length}`,
  );
}
