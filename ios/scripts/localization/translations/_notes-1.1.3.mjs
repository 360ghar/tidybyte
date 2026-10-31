#!/usr/bin/env node
/**
 * Release notes for 1.1.3, in all 21 storefront locales.
 *
 * 1.1.3 replaces 1.1.2, which was withdrawn from review before it started, so
 * these notes carry both: the large-library speed fixes (#6-#8), the photo
 * access recovery (#11), and the Recently Deleted notice fix (#10).
 *
 * The photo-access text is the 1.1.2 note verbatim, and the privacy line is the
 * 1.1.1 one, so both read the same as before in every language. Only the speed
 * sentence and the notice sentence are new. "TidyByte" and "iOS" stay Latin.
 *
 * App Store Connect allows 4000 characters; every value below is far under.
 *
 * Machine-drafted, like the rest of the store copy: not a native review pass.
 *
 * Run from the repo root: node scripts/localization/translations/_notes-1.1.3.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const LISTINGS = join(ROOT, 'docs', 'appstore', 'listings.json');
const LIMIT = 4000;

const NOTES = {
  en: "Faster on large libraries: the first swipe card now appears in about a second, photos load while the app scans, and Storage and Cleanup open much sooner. If your photos did not load, or albums looked empty, TidyByte now tells you why. When iOS shares no photos with the app, or a permission is stuck, you get the exact steps to fix it, with buttons for Settings, choosing photos, and trying again. The Recently Deleted notice no longer hides under the tab bar. Everything still runs on your device: no account, no ads, no subscription.",
  hi: "बड़ी लाइब्रेरी पर अब और तेज़: पहला स्वाइप कार्ड लगभग एक सेकंड में दिखता है, ऐप के स्कैन करते समय भी फ़ोटो लोड होती हैं, और स्टोरेज व क्लीनअप बहुत जल्दी खुलते हैं। अगर आपकी फ़ोटो लोड नहीं होती थीं या एल्बम खाली दिखते थे, तो TidyByte अब बताता है कि ऐसा क्यों है। जब iOS ऐप के साथ कोई फ़ोटो साझा नहीं करता या कोई अनुमति अटक जाती है, तो आपको इसे ठीक करने के सटीक चरण मिलते हैं, साथ में सेटिंग्स खोलने, फ़ोटो चुनने और फिर से कोशिश करने के बटन। \"हाल ही में हटाए गए\" सूचना अब टैब बार के नीचे नहीं छिपती। सब कुछ अब भी आपके डिवाइस पर ही चलता है: कोई अकाउंट नहीं, कोई विज्ञापन नहीं, कोई सब्सक्रिप्शन नहीं।",
  bn: "বড় লাইব্রেরিতে এখন আরও দ্রুত: প্রথম সোয়াইপ কার্ড প্রায় এক সেকেন্ডে দেখা যায়, অ্যাপ স্ক্যান করার সময়ও ছবি লোড হয়, আর স্টোরেজ ও ক্লিনআপ অনেক তাড়াতাড়ি খোলে। আপনার ছবি লোড না হলে বা অ্যালবাম খালি দেখালে, TidyByte এখন কারণটি জানায়। iOS যখন অ্যাপের সাথে কোনো ছবি শেয়ার করে না, বা কোনো অনুমতি আটকে থাকে, তখন আপনি এটি ঠিক করার সঠিক ধাপগুলো পান, সাথে সেটিংস খোলা, ছবি বেছে নেওয়া এবং আবার চেষ্টা করার বোতাম। \"সম্প্রতি মোছা\" বিজ্ঞপ্তি আর ট্যাব বারের নিচে লুকিয়ে থাকে না। সবকিছু এখনও আপনার ডিভাইসেই চলে: অ্যাকাউন্ট নেই, বিজ্ঞাপন নেই, সাবস্ক্রিপশন নেই।",
  ta: "பெரிய நூலகங்களில் இப்போது வேகமாக: முதல் ஸ்வைப் அட்டை சுமார் ஒரு வினாடியில் தோன்றும், ஆப் ஸ்கேன் செய்யும்போதும் படங்கள் ஏற்றப்படும், சேமிப்பகமும் சுத்தமும் மிக விரைவில் திறக்கும். உங்கள் படங்கள் ஏற்றப்படவில்லை அல்லது ஆல்பங்கள் காலியாகத் தெரிந்தால், TidyByte இப்போது அதன் காரணத்தைச் சொல்கிறது. iOS எந்தப் படத்தையும் ஆப்புடன் பகிராதபோது அல்லது ஒரு அனுமதி சிக்கிக்கொண்டால், அதைச் சரிசெய்யும் சரியான படிகள் கிடைக்கும், அமைப்புகள், படங்களைத் தேர்வுசெய்தல், மீண்டும் முயற்சித்தல் ஆகியவற்றுக்கான பொத்தான்களுடன். \"சமீபத்தில் நீக்கப்பட்டவை\" அறிவிப்பு இனி டேப் பட்டியின் கீழ் மறைவதில்லை. எல்லாமே இன்னும் உங்கள் சாதனத்திலேயே இயங்குகிறது: கணக்கு இல்லை, விளம்பரங்கள் இல்லை, சந்தா இல்லை.",
  te: "పెద్ద లైబ్రరీలలో ఇప్పుడు మరింత వేగంగా: మొదటి స్వైప్ కార్డ్ దాదాపు ఒక సెకనులో కనిపిస్తుంది, యాప్ స్కాన్ చేస్తున్నప్పుడూ ఫోటోలు లోడ్ అవుతాయి, స్టోరేజ్, క్లీన్అప్ చాలా త్వరగా తెరుచుకుంటాయి. మీ ఫోటోలు లోడ్ కాకపోయినా, ఆల్బమ్‌లు ఖాళీగా కనిపించినా, TidyByte ఇప్పుడు కారణం చెబుతుంది. iOS యాప్‌తో ఏ ఫోటోనూ పంచుకోనప్పుడు లేదా ఒక అనుమతి నిలిచిపోయినప్పుడు, దాన్ని సరిచేసే ఖచ్చితమైన దశలు మీకు కనిపిస్తాయి, సెట్టింగ్‌లు, ఫోటోలను ఎంచుకోవడం, మళ్లీ ప్రయత్నించడం కోసం బటన్‌లతో. \"ఇటీవల తొలగించినవి\" నోటీసు ఇకపై ట్యాబ్ బార్ కింద దాగదు. అంతా ఇప్పటిలాగే మీ పరికరంలోనే నడుస్తుంది: ఖాతా లేదు, ప్రకటనలు లేవు, సబ్‌స్క్రిప్షన్ లేదు.",
  mr: "मोठ्या लायब्ररीवर आता अधिक वेगवान: पहिले स्वाइप कार्ड सुमारे एका सेकंदात दिसते, ॲप स्कॅन करत असतानाही फोटो लोड होतात, आणि स्टोरेज व क्लीनअप खूप लवकर उघडतात. तुमचे फोटो लोड होत नसतील किंवा अल्बम रिकामे दिसत असतील, तर TidyByte आता त्याचे कारण सांगते. iOS ॲपसोबत एकही फोटो शेअर करत नसेल किंवा एखादी परवानगी अडकली असेल, तर ती दुरुस्त करण्याच्या नेमक्या पायऱ्या मिळतात, सोबत सेटिंग्ज, फोटो निवडणे आणि पुन्हा प्रयत्न करण्यासाठी बटणे. \"अलीकडे हटवलेले\" सूचना आता टॅब बारखाली लपत नाही. सर्व काही अजूनही तुमच्या डिव्हाइसवरच चालते: खाते नाही, जाहिराती नाहीत, सदस्यता नाही.",
  gu: "મોટી લાઇબ્રેરી પર હવે વધુ ઝડપી: પહેલું સ્વાઇપ કાર્ડ લગભગ એક સેકન્ડમાં દેખાય છે, ઍપ સ્કેન કરતી હોય ત્યારે પણ ફોટા લોડ થાય છે, અને સ્ટોરેજ તથા ક્લીનઅપ ઘણા જલદી ખૂલે છે. જો તમારા ફોટા લોડ ન થતા હોય અથવા આલ્બમ ખાલી દેખાતા હોય, તો TidyByte હવે તેનું કારણ જણાવે છે. જ્યારે iOS ઍપ સાથે કોઈ ફોટો શેર ન કરે અથવા કોઈ પરવાનગી અટકી જાય, ત્યારે તમને તેને સુધારવાના ચોક્કસ પગલાં મળે છે, સાથે સેટિંગ્સ, ફોટા પસંદ કરવા અને ફરી પ્રયાસ કરવા માટેના બટન. \"તાજેતરમાં ડિલીટ કરેલા\" સૂચના હવે ટૅબ બાર નીચે છુપાતી નથી. બધું હજી પણ તમારા ડિવાઇસ પર ચાલે છે: ખાતું નહીં, જાહેરાત નહીં, સબ્સ્ક્રિપ્શન નહીં.",
  kn: "ದೊಡ್ಡ ಲೈಬ್ರರಿಗಳಲ್ಲಿ ಈಗ ಇನ್ನಷ್ಟು ವೇಗ: ಮೊದಲ ಸ್ವೈಪ್ ಕಾರ್ಡ್ ಸುಮಾರು ಒಂದು ಸೆಕೆಂಡಿನಲ್ಲಿ ಕಾಣಿಸುತ್ತದೆ, ಆ್ಯಪ್ ಸ್ಕ್ಯಾನ್ ಮಾಡುತ್ತಿರುವಾಗಲೂ ಫೋಟೋಗಳು ಲೋಡ್ ಆಗುತ್ತವೆ, ಸ್ಟೋರೇಜ್ ಮತ್ತು ಕ್ಲೀನಪ್ ಬಹಳ ಬೇಗ ತೆರೆಯುತ್ತವೆ. ನಿಮ್ಮ ಫೋಟೋಗಳು ಲೋಡ್ ಆಗದಿದ್ದರೆ ಅಥವಾ ಆಲ್ಬಮ್‌ಗಳು ಖಾಲಿಯಾಗಿ ಕಂಡರೆ, TidyByte ಈಗ ಅದರ ಕಾರಣವನ್ನು ತಿಳಿಸುತ್ತದೆ. iOS ಆ್ಯಪ್‌ನೊಂದಿಗೆ ಯಾವುದೇ ಫೋಟೋ ಹಂಚಿಕೊಳ್ಳದಿದ್ದಾಗ ಅಥವಾ ಒಂದು ಅನುಮತಿ ಸಿಲುಕಿಕೊಂಡಾಗ, ಅದನ್ನು ಸರಿಪಡಿಸುವ ನಿಖರ ಹಂತಗಳು ನಿಮಗೆ ಸಿಗುತ್ತವೆ, ಸೆಟ್ಟಿಂಗ್‌ಗಳು, ಫೋಟೋಗಳ ಆಯ್ಕೆ ಮತ್ತು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಲು ಬಟನ್‌ಗಳೊಂದಿಗೆ. \"ಇತ್ತೀಚೆಗೆ ಅಳಿಸಿದವು\" ಸೂಚನೆ ಇನ್ನು ಟ್ಯಾಬ್ ಬಾರ್ ಕೆಳಗೆ ಮರೆಯಾಗುವುದಿಲ್ಲ. ಎಲ್ಲವೂ ಹಿಂದಿನಂತೆ ನಿಮ್ಮ ಸಾಧನದಲ್ಲೇ ನಡೆಯುತ್ತದೆ: ಖಾತೆ ಇಲ್ಲ, ಜಾಹೀರಾತುಗಳಿಲ್ಲ, ಚಂದಾದಾರಿಕೆ ಇಲ್ಲ.",
  ml: "വലിയ ലൈബ്രറികളിൽ ഇപ്പോൾ കൂടുതൽ വേഗം: ആദ്യ സ്വൈപ്പ് കാർഡ് ഏകദേശം ഒരു സെക്കൻഡിൽ കാണാം, ആപ്പ് സ്കാൻ ചെയ്യുമ്പോഴും ഫോട്ടോകൾ ലോഡ് ആകും, സ്റ്റോറേജും ക്ലീനപ്പും വളരെ വേഗം തുറക്കും. നിങ്ങളുടെ ഫോട്ടോകൾ ലോഡ് ആകുന്നില്ലെങ്കിലോ ആൽബങ്ങൾ ശൂന്യമായി കാണുന്നുവെങ്കിലോ, TidyByte ഇപ്പോൾ അതിന്റെ കാരണം പറയുന്നു. iOS ആപ്പുമായി ഒരു ഫോട്ടോയും പങ്കിടാത്തപ്പോഴോ ഒരു അനുമതി കുടുങ്ങിയപ്പോഴോ, അത് പരിഹരിക്കാനുള്ള കൃത്യമായ ഘട്ടങ്ങൾ നിങ്ങൾക്ക് ലഭിക്കും, ക്രമീകരണങ്ങൾ, ഫോട്ടോകൾ തിരഞ്ഞെടുക്കൽ, വീണ്ടും ശ്രമിക്കൽ എന്നിവയ്ക്കുള്ള ബട്ടണുകൾക്കൊപ്പം. \"അടുത്തിടെ ഇല്ലാതാക്കിയവ\" അറിയിപ്പ് ഇനി ടാബ് ബാറിന് താഴെ മറയില്ല. എല്ലാം മുൻപത്തെപ്പോലെ നിങ്ങളുടെ ഉപകരണത്തിൽ തന്നെ പ്രവർത്തിക്കുന്നു: അക്കൗണ്ടില്ല, പരസ്യങ്ങളില്ല, സബ്‌സ്‌ക്രിപ്ഷനില്ല.",
  pa: "ਵੱਡੀਆਂ ਲਾਇਬ੍ਰੇਰੀਆਂ ਉੱਤੇ ਹੁਣ ਹੋਰ ਤੇਜ਼: ਪਹਿਲਾ ਸਵਾਈਪ ਕਾਰਡ ਲਗਭਗ ਇੱਕ ਸਕਿੰਟ ਵਿੱਚ ਦਿਖਦਾ ਹੈ, ਐਪ ਦੇ ਸਕੈਨ ਕਰਦੇ ਸਮੇਂ ਵੀ ਫ਼ੋਟੋਆਂ ਲੋਡ ਹੁੰਦੀਆਂ ਹਨ, ਅਤੇ ਸਟੋਰੇਜ ਤੇ ਕਲੀਨਅੱਪ ਬਹੁਤ ਜਲਦੀ ਖੁੱਲ੍ਹਦੇ ਹਨ। ਜੇ ਤੁਹਾਡੀਆਂ ਫ਼ੋਟੋਆਂ ਲੋਡ ਨਹੀਂ ਹੁੰਦੀਆਂ ਸਨ ਜਾਂ ਐਲਬਮ ਖਾਲੀ ਦਿਖਦੇ ਸਨ, ਤਾਂ TidyByte ਹੁਣ ਇਸ ਦਾ ਕਾਰਨ ਦੱਸਦਾ ਹੈ। ਜਦੋਂ iOS ਐਪ ਨਾਲ ਕੋਈ ਫ਼ੋਟੋ ਸਾਂਝੀ ਨਹੀਂ ਕਰਦਾ ਜਾਂ ਕੋਈ ਇਜਾਜ਼ਤ ਅਟਕ ਜਾਂਦੀ ਹੈ, ਤਾਂ ਤੁਹਾਨੂੰ ਇਸ ਨੂੰ ਠੀਕ ਕਰਨ ਦੇ ਸਹੀ ਕਦਮ ਮਿਲਦੇ ਹਨ, ਨਾਲ ਸੈਟਿੰਗਾਂ, ਫ਼ੋਟੋਆਂ ਚੁਣਨ ਅਤੇ ਮੁੜ ਕੋਸ਼ਿਸ਼ ਕਰਨ ਲਈ ਬਟਨ। \"ਹਾਲ ਹੀ ਵਿੱਚ ਮਿਟਾਏ\" ਸੂਚਨਾ ਹੁਣ ਟੈਬ ਬਾਰ ਹੇਠਾਂ ਨਹੀਂ ਲੁਕਦੀ। ਸਭ ਕੁਝ ਹਾਲੇ ਵੀ ਤੁਹਾਡੇ ਡੀਵਾਈਸ ਉੱਤੇ ਚੱਲਦਾ ਹੈ: ਕੋਈ ਖਾਤਾ ਨਹੀਂ, ਕੋਈ ਇਸ਼ਤਿਹਾਰ ਨਹੀਂ, ਕੋਈ ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਨਹੀਂ।",
  es: "Más rápida con bibliotecas grandes: la primera tarjeta aparece en un segundo aproximadamente, las fotos cargan mientras la app analiza la biblioteca, y Almacenamiento y Limpieza se abren mucho antes. Si tus fotos no cargaban o los álbumes aparecían vacíos, TidyByte ahora te dice por qué. Cuando iOS no comparte ninguna foto con la app, o un permiso se queda atascado, verás los pasos exactos para solucionarlo, con botones para Ajustes, elegir fotos y volver a intentarlo. El aviso de Eliminado recientemente ya no queda oculto bajo la barra de pestañas. Todo sigue funcionando en tu dispositivo: sin cuenta, sin anuncios, sin suscripción.",
  fr: "Plus rapide sur les grandes photothèques : la première carte s'affiche en une seconde environ, les photos se chargent pendant l'analyse, et Stockage et Nettoyage s'ouvrent bien plus tôt. Si vos photos ne se chargeaient pas ou si les albums semblaient vides, TidyByte vous dit maintenant pourquoi. Quand iOS ne partage aucune photo avec l'app, ou qu'une autorisation reste bloquée, vous obtenez les étapes exactes pour corriger le problème, avec des boutons pour Réglages, choisir des photos et réessayer. L'avis Supprimés récemment ne se cache plus sous la barre d'onglets. Tout tourne toujours sur votre appareil : aucun compte, aucune pub, aucun abonnement.",
  de: "Schneller bei großen Mediatheken: Die erste Swipe-Karte erscheint nach etwa einer Sekunde, Fotos laden schon während des Scans, und Speicher und Aufräumen öffnen sich viel früher. Wenn deine Fotos nicht geladen wurden oder Alben leer aussahen, sagt dir TidyByte jetzt, warum. Wenn iOS keine Fotos mit der App teilt oder eine Berechtigung hängt, bekommst du die genauen Schritte zur Behebung, mit Tasten für Einstellungen, Fotoauswahl und einen neuen Versuch. Der Hinweis zu „Zuletzt gelöscht“ verschwindet nicht mehr unter der Tableiste. Alles läuft weiterhin auf deinem Gerät: kein Konto, keine Werbung, kein Abo.",
  'pt-BR': "Mais rápido em bibliotecas grandes: o primeiro cartão aparece em cerca de um segundo, as fotos carregam enquanto o app analisa a biblioteca, e Armazenamento e Limpeza abrem muito antes. Se suas fotos não carregavam ou os álbuns pareciam vazios, o TidyByte agora diz o motivo. Quando o iOS não compartilha nenhuma foto com o app, ou uma permissão fica travada, você vê os passos exatos para resolver, com botões para Ajustes, escolher fotos e tentar de novo. O aviso de Apagados recentemente não fica mais escondido sob a barra de abas. Tudo continua rodando no seu dispositivo: sem conta, sem anúncios, sem assinatura.",
  it: "Più veloce con librerie grandi: la prima scheda compare in circa un secondo, le foto si caricano mentre l'app analizza la libreria, e Spazio e Pulizia si aprono molto prima. Se le tue foto non si caricavano o gli album sembravano vuoti, TidyByte ora ti dice perché. Quando iOS non condivide nessuna foto con l'app, o un permesso resta bloccato, trovi i passaggi esatti per risolvere, con pulsanti per Impostazioni, scegliere le foto e riprovare. L'avviso di Eliminati di recente non resta più nascosto sotto la barra dei pannelli. Tutto continua a girare sul tuo dispositivo: nessun account, nessuna pubblicità, nessun abbonamento.",
  ja: "大きなライブラリでも高速に：最初のスワイプカードが約1秒で表示され、スキャン中も写真が読み込まれ、「ストレージ」と「クリーンアップ」もずっと早く開きます。写真が読み込まれない、アルバムが空に見える場合に、TidyByte がその理由を表示するようになりました。iOS がアプリと写真を共有していないときや、アクセス許可が止まっているときは、解決するための具体的な手順と、「設定」「写真を選択」「再試行」のボタンを表示します。「最近削除した項目」の通知がタブバーの下に隠れなくなりました。処理はすべて端末内のまま：アカウント不要、広告なし、サブスクなし。",
  ko: "큰 보관함에서도 더 빨라졌습니다: 첫 스와이프 카드가 약 1초 만에 나타나고, 앱이 스캔하는 동안에도 사진이 로드되며, 저장 공간과 정리 화면이 훨씬 빨리 열립니다. 사진이 불러와지지 않거나 앨범이 비어 보였다면, 이제 TidyByte가 그 이유를 알려 줍니다. iOS가 앱과 사진을 하나도 공유하지 않거나 권한이 멈춰 있을 때, 해결하는 정확한 단계와 함께 설정, 사진 선택, 다시 시도 버튼을 보여 줍니다. \"최근 삭제된 항목\" 알림이 더 이상 탭 막대 아래에 가려지지 않습니다. 모든 처리는 여전히 기기 안에서: 계정 없음, 광고 없음, 구독 없음.",
  'zh-Hans': "大型图库更快了：第一张滑动卡片约 1 秒即可出现，扫描期间照片也能正常加载，“存储空间”和“清理”打开也快得多。如果你的照片无法加载，或相簿显示为空，TidyByte 现在会告诉你原因。当 iOS 没有与 App 共享任何照片，或某项权限卡住时，你会看到解决问题的具体步骤，以及“设置”、“选择照片”和“重试”按钮。“最近删除”提示不再被标签栏遮挡。所有处理依然在你的设备上：无需账号、没有广告、没有订阅。",
  ru: "Быстрее на больших медиатеках: первая карточка появляется примерно за секунду, фото загружаются прямо во время сканирования, а «Хранилище» и «Очистка» открываются гораздо раньше. Если фото не загружались или альбомы выглядели пустыми, TidyByte теперь объясняет почему. Когда iOS не открывает приложению ни одного фото или разрешение «зависло», вы видите точные шаги для исправления и кнопки «Настройки», «Выбрать фото» и «Повторить». Уведомление «Недавно удалённые» больше не прячется под панелью вкладок. Всё по-прежнему работает на вашем устройстве: без аккаунта, без рекламы, без подписки.",
  ar: "أسرع مع المكتبات الكبيرة: تظهر أول بطاقة سحب خلال ثانية تقريبًا، وتُحمَّل الصور أثناء الفحص، ويُفتح التخزين والتنظيف أسرع بكثير. إذا لم تُحمَّل صورك أو بدت الألبومات فارغة، يخبرك TidyByte الآن بالسبب. عندما لا يشارك iOS أي صورة مع التطبيق، أو تتعطل إحدى الأذونات، تظهر لك الخطوات الدقيقة لإصلاح ذلك، مع أزرار للإعدادات واختيار الصور والمحاولة مجددًا. لم يعد إشعار «المحذوفة مؤخرًا» مختبئًا تحت شريط علامات التبويب. كل شيء ما زال يعمل على جهازك: لا حساب، لا إعلانات، لا اشتراك.",
  he: "מהיר יותר בספריות גדולות: כרטיס ההחלקה הראשון מופיע תוך כשנייה, התמונות נטענות גם בזמן הסריקה, ו״אחסון״ ו״ניקוי״ נפתחים הרבה יותר מהר. אם התמונות לא נטענו או שהאלבומים נראו ריקים, TidyByte מסביר עכשיו למה. כש-iOS לא משתף אף תמונה עם האפליקציה, או שהרשאה נתקעה, תקבלו את השלבים המדויקים לתיקון, עם כפתורים להגדרות, לבחירת תמונות ולניסיון חוזר. ההודעה על ״נמחקו לאחרונה״ כבר לא מסתתרת מתחת לסרגל הלשוניות. הכול עדיין רץ במכשיר שלכם: בלי חשבון, בלי פרסומות, בלי מנוי.",
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
