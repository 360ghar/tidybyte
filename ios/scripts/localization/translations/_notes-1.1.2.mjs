#!/usr/bin/env node
/**
 * Release notes for 1.1.2, in all 21 storefront locales.
 *
 * 1.1.2 is the photo-access recovery release (#11): an empty library under
 * limited access, or under a stuck full-access permission, now shows its cause
 * and the steps to fix it instead of "All Caught Up!" and "No Albums".
 *
 * The privacy line is reused verbatim from _notes-1.1.1.mjs, so "no account, no
 * ads, no subscription" reads the same as it always has in that language.
 * "TidyByte" and "iOS" stay Latin in every language.
 *
 * App Store Connect allows 4000 characters; every value below is far under.
 *
 * Machine-drafted, like the rest of the store copy: not a native review pass.
 *
 * Run from the repo root: node scripts/localization/translations/_notes-1.1.2.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const LISTINGS = join(ROOT, 'docs', 'appstore', 'listings.json');
const LIMIT = 4000;

const NOTES = {
  en: 'If your photos did not load, or albums looked empty, TidyByte now tells you why. When iOS shares no photos with the app, or a permission is stuck, you get the exact steps to fix it, with buttons for Settings, choosing photos, and trying again. Everything still runs on your device: no account, no ads, no subscription.',
  hi: 'अगर आपकी फ़ोटो लोड नहीं होती थीं या एल्बम खाली दिखते थे, तो TidyByte अब बताता है कि ऐसा क्यों है। जब iOS ऐप के साथ कोई फ़ोटो साझा नहीं करता या कोई अनुमति अटक जाती है, तो आपको इसे ठीक करने के सटीक चरण मिलते हैं, साथ में सेटिंग्स खोलने, फ़ोटो चुनने और फिर से कोशिश करने के बटन। सब कुछ अब भी आपके डिवाइस पर ही चलता है: कोई अकाउंट नहीं, कोई विज्ञापन नहीं, कोई सब्सक्रिप्शन नहीं।',
  bn: 'আপনার ছবি লোড না হলে বা অ্যালবাম খালি দেখালে, TidyByte এখন কারণটি জানায়। iOS যখন অ্যাপের সাথে কোনো ছবি শেয়ার করে না, বা কোনো অনুমতি আটকে থাকে, তখন আপনি এটি ঠিক করার সঠিক ধাপগুলো পান, সাথে সেটিংস খোলা, ছবি বেছে নেওয়া এবং আবার চেষ্টা করার বোতাম। সবকিছু এখনও আপনার ডিভাইসেই চলে: অ্যাকাউন্ট নেই, বিজ্ঞাপন নেই, সাবস্ক্রিপশন নেই।',
  ta: 'உங்கள் படங்கள் ஏற்றப்படவில்லை அல்லது ஆல்பங்கள் காலியாகத் தெரிந்தால், TidyByte இப்போது அதன் காரணத்தைச் சொல்கிறது. iOS எந்தப் படத்தையும் ஆப்புடன் பகிராதபோது அல்லது ஒரு அனுமதி சிக்கிக்கொண்டால், அதைச் சரிசெய்யும் சரியான படிகள் கிடைக்கும், அமைப்புகள், படங்களைத் தேர்வுசெய்தல், மீண்டும் முயற்சித்தல் ஆகியவற்றுக்கான பொத்தான்களுடன். எல்லாமே இன்னும் உங்கள் சாதனத்திலேயே இயங்குகிறது: கணக்கு இல்லை, விளம்பரங்கள் இல்லை, சந்தா இல்லை.',
  te: 'మీ ఫోటోలు లోడ్ కాకపోయినా, ఆల్బమ్‌లు ఖాళీగా కనిపించినా, TidyByte ఇప్పుడు కారణం చెబుతుంది. iOS యాప్‌తో ఏ ఫోటోనూ పంచుకోనప్పుడు లేదా ఒక అనుమతి నిలిచిపోయినప్పుడు, దాన్ని సరిచేసే ఖచ్చితమైన దశలు మీకు కనిపిస్తాయి, సెట్టింగ్‌లు, ఫోటోలను ఎంచుకోవడం, మళ్లీ ప్రయత్నించడం కోసం బటన్‌లతో. అంతా ఇప్పటిలాగే మీ పరికరంలోనే నడుస్తుంది: ఖాతా లేదు, ప్రకటనలు లేవు, సబ్‌స్క్రిప్షన్ లేదు.',
  mr: 'तुमचे फोटो लोड होत नसतील किंवा अल्बम रिकामे दिसत असतील, तर TidyByte आता त्याचे कारण सांगते. iOS ॲपसोबत एकही फोटो शेअर करत नसेल किंवा एखादी परवानगी अडकली असेल, तर ती दुरुस्त करण्याच्या नेमक्या पायऱ्या मिळतात, सोबत सेटिंग्ज, फोटो निवडणे आणि पुन्हा प्रयत्न करण्यासाठी बटणे. सर्व काही अजूनही तुमच्या डिव्हाइसवरच चालते: खाते नाही, जाहिराती नाहीत, सदस्यता नाही.',
  gu: 'જો તમારા ફોટા લોડ ન થતા હોય અથવા આલ્બમ ખાલી દેખાતા હોય, તો TidyByte હવે તેનું કારણ જણાવે છે. જ્યારે iOS ઍપ સાથે કોઈ ફોટો શેર ન કરે અથવા કોઈ પરવાનગી અટકી જાય, ત્યારે તમને તેને સુધારવાના ચોક્કસ પગલાં મળે છે, સાથે સેટિંગ્સ, ફોટા પસંદ કરવા અને ફરી પ્રયાસ કરવા માટેના બટન. બધું હજી પણ તમારા ડિવાઇસ પર ચાલે છે: ખાતું નહીં, જાહેરાત નહીં, સબ્સ્ક્રિપ્શન નહીં.',
  kn: 'ನಿಮ್ಮ ಫೋಟೋಗಳು ಲೋಡ್ ಆಗದಿದ್ದರೆ ಅಥವಾ ಆಲ್ಬಮ್‌ಗಳು ಖಾಲಿಯಾಗಿ ಕಂಡರೆ, TidyByte ಈಗ ಅದರ ಕಾರಣವನ್ನು ತಿಳಿಸುತ್ತದೆ. iOS ಆ್ಯಪ್‌ನೊಂದಿಗೆ ಯಾವುದೇ ಫೋಟೋ ಹಂಚಿಕೊಳ್ಳದಿದ್ದಾಗ ಅಥವಾ ಒಂದು ಅನುಮತಿ ಸಿಲುಕಿಕೊಂಡಾಗ, ಅದನ್ನು ಸರಿಪಡಿಸುವ ನಿಖರ ಹಂತಗಳು ನಿಮಗೆ ಸಿಗುತ್ತವೆ, ಸೆಟ್ಟಿಂಗ್‌ಗಳು, ಫೋಟೋಗಳ ಆಯ್ಕೆ ಮತ್ತು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಲು ಬಟನ್‌ಗಳೊಂದಿಗೆ. ಎಲ್ಲವೂ ಹಿಂದಿನಂತೆ ನಿಮ್ಮ ಸಾಧನದಲ್ಲೇ ನಡೆಯುತ್ತದೆ: ಖಾತೆ ಇಲ್ಲ, ಜಾಹೀರಾತುಗಳಿಲ್ಲ, ಚಂದಾದಾರಿಕೆ ಇಲ್ಲ.',
  ml: 'നിങ്ങളുടെ ഫോട്ടോകൾ ലോഡ് ആകുന്നില്ലെങ്കിലോ ആൽബങ്ങൾ ശൂന്യമായി കാണുന്നുവെങ്കിലോ, TidyByte ഇപ്പോൾ അതിന്റെ കാരണം പറയുന്നു. iOS ആപ്പുമായി ഒരു ഫോട്ടോയും പങ്കിടാത്തപ്പോഴോ ഒരു അനുമതി കുടുങ്ങിയപ്പോഴോ, അത് പരിഹരിക്കാനുള്ള കൃത്യമായ ഘട്ടങ്ങൾ നിങ്ങൾക്ക് ലഭിക്കും, ക്രമീകരണങ്ങൾ, ഫോട്ടോകൾ തിരഞ്ഞെടുക്കൽ, വീണ്ടും ശ്രമിക്കൽ എന്നിവയ്ക്കുള്ള ബട്ടണുകൾക്കൊപ്പം. എല്ലാം മുൻപത്തെപ്പോലെ നിങ്ങളുടെ ഉപകരണത്തിൽ തന്നെ പ്രവർത്തിക്കുന്നു: അക്കൗണ്ടില്ല, പരസ്യങ്ങളില്ല, സബ്‌സ്‌ക്രിപ്ഷനില്ല.',
  pa: 'ਜੇ ਤੁਹਾਡੀਆਂ ਫ਼ੋਟੋਆਂ ਲੋਡ ਨਹੀਂ ਹੁੰਦੀਆਂ ਸਨ ਜਾਂ ਐਲਬਮ ਖਾਲੀ ਦਿਖਦੇ ਸਨ, ਤਾਂ TidyByte ਹੁਣ ਇਸ ਦਾ ਕਾਰਨ ਦੱਸਦਾ ਹੈ। ਜਦੋਂ iOS ਐਪ ਨਾਲ ਕੋਈ ਫ਼ੋਟੋ ਸਾਂਝੀ ਨਹੀਂ ਕਰਦਾ ਜਾਂ ਕੋਈ ਇਜਾਜ਼ਤ ਅਟਕ ਜਾਂਦੀ ਹੈ, ਤਾਂ ਤੁਹਾਨੂੰ ਇਸ ਨੂੰ ਠੀਕ ਕਰਨ ਦੇ ਸਹੀ ਕਦਮ ਮਿਲਦੇ ਹਨ, ਨਾਲ ਸੈਟਿੰਗਾਂ, ਫ਼ੋਟੋਆਂ ਚੁਣਨ ਅਤੇ ਮੁੜ ਕੋਸ਼ਿਸ਼ ਕਰਨ ਲਈ ਬਟਨ। ਸਭ ਕੁਝ ਹਾਲੇ ਵੀ ਤੁਹਾਡੇ ਡੀਵਾਈਸ ਉੱਤੇ ਚੱਲਦਾ ਹੈ: ਕੋਈ ਖਾਤਾ ਨਹੀਂ, ਕੋਈ ਇਸ਼ਤਿਹਾਰ ਨਹੀਂ, ਕੋਈ ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਨਹੀਂ।',
  es: 'Si tus fotos no cargaban o los álbumes aparecían vacíos, TidyByte ahora te dice por qué. Cuando iOS no comparte ninguna foto con la app, o un permiso se queda atascado, verás los pasos exactos para solucionarlo, con botones para Ajustes, elegir fotos y volver a intentarlo. Todo sigue funcionando en tu dispositivo: sin cuenta, sin anuncios, sin suscripción.',
  fr: "Si vos photos ne se chargeaient pas ou si les albums semblaient vides, TidyByte vous dit maintenant pourquoi. Quand iOS ne partage aucune photo avec l'app, ou qu'une autorisation reste bloquée, vous obtenez les étapes exactes pour corriger le problème, avec des boutons pour Réglages, choisir des photos et réessayer. Tout tourne toujours sur votre appareil : aucun compte, aucune pub, aucun abonnement.",
  de: 'Wenn deine Fotos nicht geladen wurden oder Alben leer aussahen, sagt dir TidyByte jetzt, warum. Wenn iOS keine Fotos mit der App teilt oder eine Berechtigung hängt, bekommst du die genauen Schritte zur Behebung, mit Tasten für Einstellungen, Fotoauswahl und einen neuen Versuch. Alles läuft weiterhin auf deinem Gerät: kein Konto, keine Werbung, kein Abo.',
  'pt-BR': 'Se suas fotos não carregavam ou os álbuns pareciam vazios, o TidyByte agora diz o motivo. Quando o iOS não compartilha nenhuma foto com o app, ou uma permissão fica travada, você vê os passos exatos para resolver, com botões para Ajustes, escolher fotos e tentar de novo. Tudo continua rodando no seu dispositivo: sem conta, sem anúncios, sem assinatura.',
  it: "Se le tue foto non si caricavano o gli album sembravano vuoti, TidyByte ora ti dice perché. Quando iOS non condivide nessuna foto con l'app, o un permesso resta bloccato, trovi i passaggi esatti per risolvere, con pulsanti per Impostazioni, scegliere le foto e riprovare. Tutto continua a girare sul tuo dispositivo: nessun account, nessuna pubblicità, nessun abbonamento.",
  ja: '写真が読み込まれない、アルバムが空に見える場合に、TidyByte がその理由を表示するようになりました。iOS がアプリと写真を共有していないときや、アクセス許可が止まっているときは、解決するための具体的な手順と、「設定」「写真を選択」「再試行」のボタンを表示します。処理はすべて端末内のまま：アカウント不要、広告なし、サブスクなし。',
  ko: '사진이 불러와지지 않거나 앨범이 비어 보였다면, 이제 TidyByte가 그 이유를 알려 줍니다. iOS가 앱과 사진을 하나도 공유하지 않거나 권한이 멈춰 있을 때, 해결하는 정확한 단계와 함께 설정, 사진 선택, 다시 시도 버튼을 보여 줍니다. 모든 처리는 여전히 기기 안에서: 계정 없음, 광고 없음, 구독 없음.',
  'zh-Hans': '如果你的照片无法加载，或相簿显示为空，TidyByte 现在会告诉你原因。当 iOS 没有与 App 共享任何照片，或某项权限卡住时，你会看到解决问题的具体步骤，以及“设置”、“选择照片”和“重试”按钮。所有处理依然在你的设备上：无需账号、没有广告、没有订阅。',
  ru: 'Если фото не загружались или альбомы выглядели пустыми, TidyByte теперь объясняет почему. Когда iOS не открывает приложению ни одного фото или разрешение «зависло», вы видите точные шаги для исправления и кнопки «Настройки», «Выбрать фото» и «Повторить». Всё по-прежнему работает на вашем устройстве: без аккаунта, без рекламы, без подписки.',
  ar: 'إذا لم تُحمَّل صورك أو بدت الألبومات فارغة، يخبرك TidyByte الآن بالسبب. عندما لا يشارك iOS أي صورة مع التطبيق، أو تتعطل إحدى الأذونات، تظهر لك الخطوات الدقيقة لإصلاح ذلك، مع أزرار للإعدادات واختيار الصور والمحاولة مجددًا. كل شيء ما زال يعمل على جهازك: لا حساب، لا إعلانات، لا اشتراك.',
  he: 'אם התמונות לא נטענו או שהאלבומים נראו ריקים, TidyByte מסביר עכשיו למה. כש-iOS לא משתף אף תמונה עם האפליקציה, או שהרשאה נתקעה, תקבלו את השלבים המדויקים לתיקון, עם כפתורים להגדרות, לבחירת תמונות ולניסיון חוזר. הכול עדיין רץ במכשיר שלכם: בלי חשבון, בלי פרסומות, בלי מנוי.',
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
