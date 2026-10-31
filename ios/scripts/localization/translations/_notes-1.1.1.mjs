#!/usr/bin/env node
/**
 * Release notes for 1.1.1, in all 21 storefront locales.
 *
 * 1.1.1 is the release that finally ships the Duo work and the review fixes.
 * Live 1.1.0 is build 7, uploaded before either landed, so its published notes
 * stop at the language release — the Duo sentence in the 1.1.0 draft never went
 * live. From a user's point of view both are new here, which is why the Duo line
 * still leads.
 *
 * Two sentences are reused verbatim rather than retranslated, so the store copy
 * keeps saying the same thing in the same words:
 *   - the Duo line -> the closing sentence of the 1.1.0 notes, which was already
 *     translated into every locale and is still accurate. It says "built for",
 *     not "tested on"; see docs/duo-readiness.md, which records what has and has
 *     not been demonstrated on a Duo.
 *   - the privacy line -> the closing clause of the 1.0.5 notes, unchanged
 *     since, so "no account, no ads, no subscription" reads the same as it
 *     always has in that language.
 *
 * "TidyByte" and "iPhone Duo" stay Latin in every language, as elsewhere in the
 * listing. "Keep" / "रखें" / "Conserver" is quoted as the on-screen stamp word
 * each locale already uses.
 *
 * App Store Connect allows 4000 characters; every value below is far under.
 *
 * Machine-drafted, like the rest of the store copy: reviewed translations
 * carried forward, not a native review pass.
 *
 * Run from the repo root: node scripts/localization/translations/_notes-1.1.1.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const LISTINGS = join(ROOT, 'docs', 'appstore', 'listings.json');
const LIMIT = 4000;

const NOTES = {
  en: 'Now built for iPhone Duo: same cleanup, adapted to both displays. This update also fixes what a full review found: in Arabic and Hebrew a swipe could show Keep while deleting the photo, switching language mid-session could discard deletions you had not confirmed, and several labels stayed in English. Everything still runs on your device: no account, no ads, no subscription.',
  hi: 'अब iPhone Duo के लिए भी बनाया गया: वही सफ़ाई, दोनों डिस्प्ले के अनुसार ढली हुई। यह अपडेट पूरी समीक्षा में मिली गड़बड़ियाँ भी ठीक करता है: अरबी और हिब्रू में स्वाइप करने पर फ़ोटो मिटते हुए भी "रखें" दिख सकता था, सेशन के बीच भाषा बदलने से आपकी बिना पुष्टि की गई डिलीशन हट सकती थीं, और कई लेबल अंग्रेज़ी में ही रह गए थे। सब कुछ अब भी आपके डिवाइस पर ही चलता है: कोई अकाउंट नहीं, कोई विज्ञापन नहीं, कोई सब्सक्रिप्शन नहीं।',
  bn: 'এখন iPhone Duo-র জন্যও তৈরি: একই পরিষ্কার, দুটি ডিসপ্লের সাথে খাপ খাওয়া। এই আপডেটটি পূর্ণ পর্যালোচনায় পাওয়া সমস্যাগুলোও ঠিক করে: আরবি ও হিব্রুতে সোয়াইপ করলে ছবি মুছে যাওয়ার সময়ও "রাখুন" দেখাতে পারত, সেশনের মাঝে ভাষা বদলালে আপনার নিশ্চিত না করা ডিলিশন হারিয়ে যেতে পারত, আর বেশ কিছু লেবেল ইংরেজিতেই থেকে গিয়েছিল। সবকিছু এখনও আপনার ডিভাইসেই চলে: অ্যাকাউন্ট নেই, বিজ্ঞাপন নেই, সাবস্ক্রিপশন নেই।',
  ta: 'இப்போது iPhone Duo-க்கும் உருவாக்கப்பட்டது: அதே சுத்தம், இரு திரைகளுக்கும் ஏற்றது. இந்தப் புதுப்பிப்பு முழு மதிப்பாய்வில் கண்ட சிக்கல்களையும் சரிசெய்கிறது: அரபிக் மற்றும் எபிரேயத்தில் ஸ்வைப் செய்யும்போது படம் நீக்கப்பட்டாலும் "வைத்திரு" காட்டப்படலாம், அமர்வின் நடுவே மொழியை மாற்றினால் நீங்கள் உறுதிப்படுத்தாத நீக்கங்கள் இழக்கப்படலாம், பல லேபிள்கள் ஆங்கிலத்திலேயே இருந்தன. எல்லாமே இன்னும் உங்கள் சாதனத்திலேயே இயங்குகிறது: கணக்கு இல்லை, விளம்பரங்கள் இல்லை, சந்தா இல்லை.',
  te: 'ఇప్పుడు iPhone Duo కోసం కూడా నిర్మించబడింది: అదే క్లీన్అప్, రెండు డిస్ప్లేలకు సరిపోయేలా. ఈ అప్‌డేట్ పూర్తి సమీక్షలో దొరికిన సమస్యలను కూడా సరిచేస్తుంది: అరబిక్ మరియు హిబ్రూలో స్వైప్ చేసినప్పుడు ఫోటో తొలగుతున్నా "ఉంచు" కనిపించవచ్చు, సెషన్ మధ్యలో భాష మార్చితే మీరు నిర్ధారించని డిలీషన్లు పోవచ్చు, అనేక లేబుళ్లు ఇంగ్లీషులోనే ఉండిపోయాయి. అంతా ఇప్పటిలాగే మీ పరికరంలోనే నడుస్తుంది: ఖాతా లేదు, ప్రకటనలు లేవు, సబ్‌స్క్రిప్షన్ లేదు.',
  mr: 'आता iPhone Duo साठीही तयार: तीच साफसफाई, दोन्ही डिस्प्लेला जुळणारी. हा अपडेट पूर्ण पुनरावलोकनात आढळलेल्या चुका दुरुस्त करतो: अरबी आणि हिब्रूमध्ये स्वाइप करताना फोटो हटत असूनही "ठेवा" दिसू शकत होते, सेशनच्या मध्ये भाषा बदलल्यास तुम्ही पुष्टी न केलेले डिलीशन हरवू शकत होते, आणि अनेक लेबल इंग्रजीतच राहिली होती. सर्व काही अजूनही तुमच्या डिव्हाइसवरच चालते: खाते नाही, जाहिराती नाहीत, सदस्यता नाही.',
  gu: 'હવે iPhone Duo માટે પણ બનાવેલું: એ જ સફાઈ, બંને ડિસ્પ્લેને અનુરૂપ. આ અપડેટ સંપૂર્ણ સમીક્ષામાં મળેલી ખામીઓ પણ સુધારે છે: અરબી અને હિબ્રૂમાં સ્વાઇપ કરતી વખતે ફોટો ડિલીટ થતો હોવા છતાં "રાખો" દેખાઈ શકતું, સેશન વચ્ચે ભાષા બદલવાથી તમે પુષ્ટિ ન કરેલા ડિલીશન ખોવાઈ શકતા, અને ઘણા લેબલ અંગ્રેજીમાં જ રહી ગયા હતા. બધું હજી પણ તમારા ડિવાઇસ પર ચાલે છે: ખાતું નહીં, જાહેરાત નહીં, સબ્સ્ક્રિપ્શન નહીં.',
  kn: 'ಈಗ iPhone Duo ಗಾಗಿಯೂ ನಿರ್ಮಿಸಲಾಗಿದೆ: ಅದೇ ಸ್ವಚ್ಛತೆ, ಎರಡೂ ಡಿಸ್ಪ್ಲೇಗಳಿಗೆ ಹೊಂದಿಕೊಳ್ಳುತ್ತದೆ. ಈ ಅಪ್‌ಡೇಟ್ ಪೂರ್ಣ ಪರಿಶೀಲನೆಯಲ್ಲಿ ಕಂಡ ಸಮಸ್ಯೆಗಳನ್ನೂ ಸರಿಪಡಿಸುತ್ತದೆ: ಅರೇಬಿಕ್ ಮತ್ತು ಹೀಬ್ರೂನಲ್ಲಿ ಸ್ವೈಪ್ ಮಾಡುವಾಗ ಫೋಟೋ ಅಳಿಸುತ್ತಿದ್ದರೂ "ಇಟ್ಟುಕೊ" ಕಾಣಿಸಬಹುದಿತ್ತು, ಅಧಿವೇಶನದ ಮಧ್ಯೆ ಭಾಷೆ ಬದಲಿಸಿದರೆ ನೀವು ದೃಢೀಕರಿಸದ ಡಿಲೀಶನ್‌ಗಳು ಹೋಗಬಹುದಿತ್ತು, ಮತ್ತು ಹಲವು ಲೇಬಲ್‌ಗಳು ಇಂಗ್ಲಿಷ್‌ನಲ್ಲೇ ಉಳಿದಿದ್ದವು. ಎಲ್ಲವೂ ಹಿಂದಿನಂತೆ ನಿಮ್ಮ ಸಾಧನದಲ್ಲೇ ನಡೆಯುತ್ತದೆ: ಖಾತೆ ಇಲ್ಲ, ಜಾಹೀರಾತುಗಳಿಲ್ಲ, ಚಂದಾದಾರಿಕೆ ಇಲ್ಲ.',
  ml: 'ഇപ്പോൾ iPhone Duo-യ്ക്കും വേണ്ടി നിർമ്മിച്ചത്: അതേ ക്ലീനപ്പ്, രണ്ട് ഡിസ്പ്ലേകൾക്കും ഇണങ്ങുന്നത്. ഈ അപ്‌ഡേറ്റ് പൂർണ്ണ പരിശോധനയിൽ കണ്ട പിഴവുകളും തിരുത്തുന്നു: അറബിക്, ഹീബ്രുവിൽ സ്വൈപ്പ് ചെയ്യുമ്പോൾ ഫോട്ടോ മായ്ക്കപ്പെടുമ്പോഴും "നിലനിർത്തുക" കാണിച്ചേക്കാം, സെഷനിനിടയിൽ ഭാഷ മാറ്റിയാൽ നിങ്ങൾ സ്ഥിരീകരിക്കാത്ത ഡിലീഷനുകൾ നഷ്ടപ്പെടാം, ഒപ്പം പല ലേബലുകളും ഇംഗ്ലീഷിൽ തന്നെ തുടർന്നു. എല്ലാം മുൻപത്തെപ്പോലെ നിങ്ങളുടെ ഉപകരണത്തിൽ തന്നെ പ്രവർത്തിക്കുന്നു: അക്കൗണ്ടില്ല, പരസ്യങ്ങളില്ല, സബ്‌സ്‌ക്രിപ്ഷനില്ല.',
  pa: 'ਹੁਣ iPhone Duo ਲਈ ਵੀ ਬਣਾਇਆ ਗਿਆ: ਉਹੀ ਸਫ਼ਾਈ, ਦੋਵੇਂ ਡਿਸਪਲੇ ਲਈ ਢੁਕਵੀਂ। ਇਹ ਅੱਪਡੇਟ ਪੂਰੀ ਸਮੀਖਿਆ ਵਿੱਚ ਮਿਲੀਆਂ ਖਾਮੀਆਂ ਵੀ ਠੀਕ ਕਰਦਾ ਹੈ: ਅਰਬੀ ਅਤੇ ਹਿਬਰੂ ਵਿੱਚ ਸਵਾਈਪ ਕਰਨ ਵੇਲੇ ਫ਼ੋਟੋ ਮਿਟਦੇ ਹੋਏ ਵੀ "ਰੱਖੋ" ਦਿਖ ਸਕਦਾ ਸੀ, ਸੈਸ਼ਨ ਵਿਚਕਾਰ ਭਾਸ਼ਾ ਬਦਲਣ ਨਾਲ ਤੁਹਾਡੇ ਪੱਕੇ ਨਾ ਕੀਤੇ ਡਿਲੀਸ਼ਨ ਹਟ ਸਕਦੇ ਸਨ, ਅਤੇ ਕਈ ਲੇਬਲ ਅੰਗਰੇਜ਼ੀ ਵਿੱਚ ਹੀ ਰਹਿ ਗਏ ਸਨ। ਸਭ ਕੁਝ ਹਾਲੇ ਵੀ ਤੁਹਾਡੇ ਡੀਵਾਈਸ ਉੱਤੇ ਚੱਲਦਾ ਹੈ: ਕੋਈ ਖਾਤਾ ਨਹੀਂ, ਕੋਈ ਇਸ਼ਤਿਹਾਰ ਨਹੀਂ, ਕੋਈ ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਨਹੀਂ।',
  es: 'Ahora también para iPhone Duo: la misma limpieza, adaptada a sus dos pantallas. Esta actualización también corrige lo que encontró una revisión completa: en árabe y hebreo, un deslizamiento podía mostrar "Conservar" mientras borraba la foto, cambiar de idioma a mitad de sesión podía descartar eliminaciones sin confirmar, y varias etiquetas seguían en inglés. Todo sigue funcionando en tu dispositivo: sin cuenta, sin anuncios, sin suscripción.',
  fr: "Désormais aussi sur iPhone Duo : le même nettoyage, adapté à ses deux écrans. Cette mise à jour corrige aussi ce qu'a révélé une revue complète : en arabe et en hébreu, un glissement pouvait afficher « Conserver » tout en supprimant la photo, changer de langue en cours de session pouvait perdre des suppressions non confirmées, et plusieurs libellés restaient en anglais. Tout tourne toujours sur votre appareil : aucun compte, aucune pub, aucun abonnement.",
  de: 'Jetzt auch für iPhone Duo: dasselbe Aufräumen, an beide Displays angepasst. Dieses Update behebt außerdem, was eine vollständige Prüfung gefunden hat: Auf Arabisch und Hebräisch konnte ein Wisch „Behalten“ anzeigen und das Foto trotzdem löschen, ein Sprachwechsel mitten in der Sitzung konnte unbestätigte Löschungen verwerfen, und mehrere Beschriftungen blieben englisch. Alles läuft weiterhin auf deinem Gerät: kein Konto, keine Werbung, kein Abo.',
  'pt-BR': 'Agora também no iPhone Duo: a mesma limpeza, adaptada às duas telas. Esta atualização também corrige o que uma revisão completa encontrou: em árabe e hebraico, um deslize podia mostrar "Manter" enquanto apagava a foto, trocar de idioma no meio da sessão podia descartar exclusões não confirmadas, e vários rótulos continuavam em inglês. Tudo continua rodando no seu dispositivo: sem conta, sem anúncios, sem assinatura.',
  it: 'Ora anche su iPhone Duo: la stessa pulizia, adattata a entrambi gli schermi. Questo aggiornamento corregge anche ciò che ha trovato una revisione completa: in arabo ed ebraico uno scorrimento poteva mostrare "Conserva" mentre eliminava la foto, cambiare lingua a metà sessione poteva annullare eliminazioni non confermate, e diverse etichette restavano in inglese. Tutto continua a girare sul tuo dispositivo: nessun account, nessuna pubblicità, nessun abbonamento.',
  ja: 'iPhone Duo にも対応：同じ整理を、2つのディスプレイに合わせて。今回のアップデートでは、全体レビューで見つかった問題も修正しました。アラビア語とヘブライ語では、スワイプで写真が削除されるのに「保持」と表示されることがあり、セッション中に言語を切り替えると未確認の削除が失われることがあり、一部のラベルが英語のままでした。処理はすべて端末内のまま：アカウント不要、広告なし、サブスクなし。',
  ko: '이제 iPhone Duo도 지원: 같은 정리를 두 화면에 맞춰 제공합니다. 이번 업데이트는 전체 점검에서 발견된 문제도 함께 해결합니다. 아랍어와 히브리어에서는 사진이 삭제되는데도 "유지"로 표시될 수 있었고, 세션 도중 언어를 바꾸면 확인하지 않은 삭제가 사라질 수 있었으며, 일부 레이블이 영어로 남아 있었습니다. 모든 처리는 여전히 기기 안에서: 계정 없음, 광고 없음, 구독 없음.',
  'zh-Hans': '现已支持 iPhone Duo：同样的清理，适配两块屏幕。本次更新还修复了全面复查中发现的问题：在阿拉伯语和希伯来语下，滑动可能显示“保留”却删除了照片；在会话中途切换语言可能丢失未确认的删除；还有多处标签仍是英文。所有处理依然在你的设备上：无需账号、没有广告、没有订阅。',
  ru: 'Теперь и для iPhone Duo: та же очистка, адаптированная под оба экрана. Это обновление также исправляет то, что нашла полная проверка: в арабском и иврите свайп мог показать «Оставить», удаляя фото, смена языка посреди сеанса могла сбросить неподтверждённые удаления, а часть подписей оставалась на английском. Всё по-прежнему работает на вашем устройстве: без аккаунта, без рекламы, без подписки.',
  ar: 'الآن أيضًا على iPhone Duo: التنظيف نفسه، مهيّأ للشاشتين. يصلح هذا التحديث أيضًا ما كشفته المراجعة الشاملة: في العربية والعبرية كان السحب قد يعرض «إبقاء» بينما يحذف الصورة، وتغيير اللغة أثناء الجلسة كان قد يُلغي حذفًا لم تؤكده، وبقيت عدة تسميات بالإنجليزية. كل شيء ما زال يعمل على جهازك: لا حساب، لا إعلانات، لا اشتراك.',
  he: 'כעת גם ב-iPhone Duo: אותו ניקוי, מותאם לשני המסכים. העדכון הזה מתקן גם את מה שבדיקה מלאה מצאה: בערבית ובעברית החלקה יכלה להציג ״שמור״ ובמקביל למחוק את התמונה, החלפת שפה באמצע השיחה יכלה לבטל מחיקות שלא אושרו, וכמה תוויות נשארו באנגלית. הכול עדיין רץ במכשיר שלכם: בלי חשבון, בלי פרסומות, בלי מנוי.',
};

const listings = JSON.parse(readFileSync(LISTINGS, 'utf8'));
const languages = Object.keys(listings).filter((key) => !key.startsWith('_'));

// Measure everything before writing, so an over-length value cannot land.
let bad = 0;
for (const language of languages) {
  const value = NOTES[language];
  if (value === undefined) {
    console.error(`FAIL: no release notes for ${language}`);
    bad += 1;
    continue;
  }
  const length = [...value].length;
  if (length > LIMIT) {
    console.error(`FAIL: ${language} is ${length} chars, limit is ${LIMIT}`);
    bad += 1;
  }
}
if (bad > 0) {
  console.error(`\n${bad} problem(s). Nothing written.`);
  process.exit(1);
}

for (const language of languages) {
  const before = listings[language].whatsNew;
  listings[language].whatsNew = NOTES[language];
  const length = [...NOTES[language]].length;
  const changed = before === NOTES[language] ? '  (unchanged)' : '';
  console.log(`${language.padEnd(9)} ${String(length).padStart(4)}/${LIMIT}${changed}`);
}

writeFileSync(LISTINGS, `${JSON.stringify(listings, null, 2)}\n`);
console.log(`\n${languages.length} release note(s) written.`);
