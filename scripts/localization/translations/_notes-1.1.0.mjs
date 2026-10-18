#!/usr/bin/env node
/**
 * Release notes for 1.1.0, in all 21 storefront locales.
 *
 * The headline is the language release itself, which makes the copy awkward in
 * one specific way: the note has to announce its own language. Written naively
 * ("now available in 20 languages") the translated version reads as if it is
 * telling a Japanese reader about Japanese, which is noise. Each translation
 * below therefore leads with the number and the RTL support, and closes with the
 * privacy line that already exists in that language elsewhere in the listing, so
 * the phrasing matches what users have already seen.
 *
 * Terms reused rather than re-invented, so the store copy stays consistent:
 *   - "no account, no ads, no subscription" -> the closing clause of the
 *     existing 1.0.5 notes in every language.
 *   - "runs on your device" -> the same clause's opening.
 *   - "Siri" stays Latin in every language; Apple does not localize the product
 *     name.
 *   - "TidyByte" is never translated.
 *
 * App Store Connect allows 4000 characters; every value below is far under.
 *
 * Machine-drafted, like the rest of the store copy: reviewed translations
 * carried forward, not a native review pass.
 *
 * Run from the repo root: node scripts/localization/translations/_notes-1.1.0.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const LISTINGS = join(ROOT, 'docs', 'appstore', 'listings.json');
const LIMIT = 4000;

const NOTES = {
  en: 'TidyByte now speaks 20 languages, with full right-to-left layout for Arabic and Hebrew. Dates, sizes and counts follow your region, and Siri shortcuts work in your language. Everything still runs on your device: no account, no ads, no subscription.',
  hi: 'TidyByte अब 20 भाषाओं में उपलब्ध है, अरबी और हिब्रू के लिए पूर्ण दाएँ-से-बाएँ लेआउट के साथ। तारीख़ें, आकार और गिनती आपके क्षेत्र के अनुसार दिखती हैं, और Siri शॉर्टकट आपकी भाषा में काम करते हैं। सब कुछ अब भी आपके डिवाइस पर ही चलता है: कोई अकाउंट नहीं, कोई विज्ञापन नहीं, कोई सब्सक्रिप्शन नहीं।',
  bn: 'TidyByte এখন ২০টি ভাষায় পাওয়া যায়, আরবি ও হিব্রুর জন্য সম্পূর্ণ ডান-থেকে-বাঁ লেআউট সহ। তারিখ, আকার ও গণনা আপনার অঞ্চল অনুযায়ী দেখায়, আর Siri শর্টকাট আপনার ভাষায় কাজ করে। সবকিছু এখনও আপনার ডিভাইসেই চলে: অ্যাকাউন্ট নেই, বিজ্ঞাপন নেই, সাবস্ক্রিপশন নেই।',
  ta: 'TidyByte இப்போது 20 மொழிகளில் கிடைக்கிறது — அரபிக் மற்றும் எபிரேயத்திற்கு முழு வலமிருந்து இடம் வரை அமைப்புடன். தேதிகள், அளவுகள் மற்றும் எண்ணிக்கைகள் உங்கள் பிராந்தியத்தின்படி காட்டப்படும், Siri குறுக்குவழிகள் உங்கள் மொழியில் இயங்கும். எல்லாமே இன்னும் உங்கள் சாதனத்திலேயே இயங்குகிறது: கணக்கு இல்லை, விளம்பரங்கள் இல்லை, சந்தா இல்லை.',
  te: 'TidyByte ఇప్పుడు 20 భాషల్లో అందుబాటులో ఉంది — అరబిక్ మరియు హిబ్రూ కోసం పూర్తి కుడి-నుండి-ఎడమ లేఅవుట్‌తో. తేదీలు, పరిమాణాలు మరియు లెక్కలు మీ ప్రాంతం ప్రకారం చూపబడతాయి, Siri షార్ట్‌కట్‌లు మీ భాషలో పనిచేస్తాయి. అంతా ఇప్పటిలాగే మీ పరికరంలోనే నడుస్తుంది: ఖాతా లేదు, ప్రకటనలు లేవు, సబ్‌స్క్రిప్షన్ లేదు.',
  mr: 'TidyByte आता २० भाषांमध्ये उपलब्ध आहे, अरबी आणि हिब्रूसाठी पूर्ण उजव्या-ते-डाव्या मांडणीसह. तारखा, आकार आणि मोजणी तुमच्या प्रदेशानुसार दिसतात, आणि Siri शॉर्टकट तुमच्या भाषेत चालतात. सर्व काही अजूनही तुमच्या डिव्हाइसवरच चालते: खाते नाही, जाहिराती नाहीत, सदस्यता नाही.',
  gu: 'TidyByte હવે 20 ભાષાઓમાં ઉપલબ્ધ છે, અરબી અને હિબ્રૂ માટે સંપૂર્ણ જમણેથી-ડાબે લેઆઉટ સાથે. તારીખો, કદ અને ગણતરી તમારા પ્રદેશ મુજબ દેખાય છે, અને Siri શોર્ટકટ તમારી ભાષામાં કામ કરે છે. બધું હજી પણ તમારા ડિવાઇસ પર ચાલે છે: ખાતું નહીં, જાહેરાત નહીં, સબ્સ્ક્રિપ્શન નહીં.',
  kn: 'TidyByte ಈಗ 20 ಭಾಷೆಗಳಲ್ಲಿ ಲಭ್ಯವಿದೆ — ಅರೇಬಿಕ್ ಮತ್ತು ಹೀಬ್ರೂಗಾಗಿ ಪೂರ್ಣ ಬಲದಿಂದ-ಎಡಕ್ಕೆ ವಿನ್ಯಾಸದೊಂದಿಗೆ. ದಿನಾಂಕಗಳು, ಗಾತ್ರಗಳು ಮತ್ತು ಎಣಿಕೆಗಳು ನಿಮ್ಮ ಪ್ರದೇಶದ ಪ್ರಕಾರ ಕಾಣುತ್ತವೆ, ಮತ್ತು Siri ಶಾರ್ಟ್‌ಕಟ್‌ಗಳು ನಿಮ್ಮ ಭಾಷೆಯಲ್ಲಿ ಕೆಲಸ ಮಾಡುತ್ತವೆ. ಎಲ್ಲವೂ ಹಿಂದಿನಂತೆ ನಿಮ್ಮ ಸಾಧನದಲ್ಲೇ ನಡೆಯುತ್ತದೆ: ಖಾತೆ ಇಲ್ಲ, ಜಾಹೀರಾತುಗಳಿಲ್ಲ, ಚಂದಾದಾರಿಕೆ ಇಲ್ಲ.',
  ml: 'TidyByte ഇപ്പോൾ 20 ഭാഷകളിൽ ലഭ്യമാണ് — അറബിക്, ഹീബ്രു എന്നിവയ്ക്ക് പൂർണ്ണ വലത്തുനിന്ന്-ഇടത്തേക്കുള്ള ലേഔട്ടോടെ. തീയതികളും വലുപ്പങ്ങളും എണ്ണങ്ങളും നിങ്ങളുടെ പ്രദേശമനുസരിച്ച് കാണിക്കും, Siri കുറുക്കുവഴികൾ നിങ്ങളുടെ ഭാഷയിൽ പ്രവർത്തിക്കും. എല്ലാം മുൻപത്തെപ്പോലെ നിങ്ങളുടെ ഉപകരണത്തിൽ തന്നെ പ്രവർത്തിക്കുന്നു: അക്കൗണ്ടില്ല, പരസ്യങ്ങളില്ല, സബ്‌സ്‌ക്രിപ്ഷനില്ല.',
  pa: 'TidyByte ਹੁਣ 20 ਭਾਸ਼ਾਵਾਂ ਵਿੱਚ ਉਪਲਬਧ ਹੈ, ਅਰਬੀ ਅਤੇ ਹਿਬਰੂ ਲਈ ਪੂਰੇ ਸੱਜੇ-ਤੋਂ-ਖੱਬੇ ਲੇਆਉਟ ਨਾਲ। ਤਾਰੀਖਾਂ, ਆਕਾਰ ਅਤੇ ਗਿਣਤੀ ਤੁਹਾਡੇ ਖੇਤਰ ਅਨੁਸਾਰ ਦਿਖਦੇ ਹਨ, ਅਤੇ Siri ਸ਼ਾਰਟਕੱਟ ਤੁਹਾਡੀ ਭਾਸ਼ਾ ਵਿੱਚ ਕੰਮ ਕਰਦੇ ਹਨ। ਸਭ ਕੁਝ ਹਾਲੇ ਵੀ ਤੁਹਾਡੇ ਡੀਵਾਈਸ ਉੱਤੇ ਚੱਲਦਾ ਹੈ: ਕੋਈ ਖਾਤਾ ਨਹੀਂ, ਕੋਈ ਇਸ਼ਤਿਹਾਰ ਨਹੀਂ, ਕੋਈ ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਨਹੀਂ।',
  es: 'TidyByte ya habla 20 idiomas, con diseño de derecha a izquierda para árabe y hebreo. Las fechas, los tamaños y los recuentos siguen las convenciones de tu región, y los atajos de Siri funcionan en tu idioma. Todo sigue funcionando en tu dispositivo: sin cuenta, sin anuncios, sin suscripción.',
  fr: "TidyByte parle désormais 20 langues, avec une mise en page de droite à gauche complète pour l'arabe et l'hébreu. Les dates, les tailles et les compteurs suivent votre région, et les raccourcis Siri fonctionnent dans votre langue. Tout tourne toujours sur votre appareil : aucun compte, aucune pub, aucun abonnement.",
  de: 'TidyByte spricht jetzt 20 Sprachen, mit vollständigem Rechts-nach-links-Layout für Arabisch und Hebräisch. Datumsangaben, Größen und Zählungen folgen deiner Region, und Siri-Kurzbefehle funktionieren in deiner Sprache. Alles läuft weiterhin auf deinem Gerät: kein Konto, keine Werbung, kein Abo.',
  'pt-BR': 'O TidyByte agora fala 20 idiomas, com layout completo da direita para a esquerda em árabe e hebraico. Datas, tamanhos e contagens seguem a sua região, e os atalhos da Siri funcionam no seu idioma. Tudo continua rodando no seu dispositivo: sem conta, sem anúncios, sem assinatura.',
  it: 'TidyByte ora parla 20 lingue, con layout completo da destra a sinistra per arabo ed ebraico. Date, dimensioni e conteggi seguono la tua regione, e le scorciatoie Siri funzionano nella tua lingua. Tutto continua a girare sul tuo dispositivo: nessun account, nessuna pubblicità, nessun abbonamento.',
  ja: 'TidyByte が 20 言語に対応しました。アラビア語とヘブライ語は右から左へのレイアウトにも完全対応します。日付・サイズ・件数はお使いの地域の形式で表示され、Siri ショートカットもお使いの言語で操作できます。処理はすべて端末内のまま：アカウント不要、広告なし、サブスクなし。',
  ko: 'TidyByte가 이제 20개 언어를 지원합니다. 아랍어와 히브리어는 오른쪽에서 왼쪽 레이아웃까지 완전히 지원합니다. 날짜, 크기, 개수는 사용 중인 지역 형식으로 표시되고 Siri 단축어도 사용하는 언어로 작동합니다. 모든 처리는 여전히 기기 안에서: 계정 없음, 광고 없음, 구독 없음.',
  'zh-Hans': 'TidyByte 现已支持 20 种语言，阿拉伯语和希伯来语还支持完整的从右到左布局。日期、大小和计数均按你所在地区的格式显示，Siri 快捷指令也可用你的语言操作。所有处理依然在你的设备上：无需账号、没有广告、没有订阅。',
  ru: 'TidyByte теперь говорит на 20 языках, с полной поддержкой письма справа налево для арабского и иврита. Даты, размеры и счётчики следуют правилам вашего региона, а команды Siri работают на вашем языке. Всё по-прежнему работает на вашем устройстве: без аккаунта, без рекламы, без подписки.',
  ar: 'يدعم TidyByte الآن 20 لغة، مع تخطيط كامل من اليمين إلى اليسار للعربية والعبرية. تتبع التواريخ والأحجام والأعداد تنسيق منطقتك، وتعمل اختصارات Siri بلغتك. كل شيء ما زال يعمل على جهازك: لا حساب، لا إعلانات، لا اشتراك.',
  he: 'TidyByte תומך כעת ב-20 שפות, עם פריסה מלאה מימין לשמאל לערבית ולעברית. תאריכים, גדלים וספירות מוצגים לפי האזור שלכם, וקיצורי Siri עובדים בשפה שלכם. הכול עדיין רץ במכשיר שלכם: בלי חשבון, בלי פרסומות, בלי מנוי.',
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
