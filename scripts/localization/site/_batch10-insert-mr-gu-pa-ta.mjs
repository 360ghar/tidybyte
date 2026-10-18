// Batch 10 — writes the website landing-page translations for mr, gu, pa, ta.
//
// Run: node scripts/localization/site/_batch10-insert-mr-gu-pa-ta.mjs
//
// The 108 keys are the English strings extracted from src/content/pages/index.html
// by extract-site-strings.mjs. The translation objects below are keyed by the
// exact English string, and this script asserts the key set matches the source
// exactly before writing anything, so a typo in a key fails loudly instead of
// silently shipping an English string on the live site.
//
// HTML entities (&mdash; &amp; &middot; &rarr;) are kept where the language uses
// them. No &rsquo; is needed in these four languages: none of them writes the
// English apostrophe, and the possessive is expressed with a particle.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SOURCE = join(here, 'site-strings.json');
const OUT_DIR = join(here, 'site-translations');

const source = JSON.parse(readFileSync(SOURCE, 'utf8'));
const sourceStrings = source.strings;

const translations = {};

translations.mr = {
  '01 &mdash; How it works': '01 &mdash; हे कसे चालते',
  '02 &mdash; Cleanup toolkit': '02 &mdash; क्लीनअप साधने',
  '03 &mdash; Storage dashboard': '03 &mdash; स्टोरेज डॅशबोर्ड',
  '04 &mdash; Privacy': '04 &mdash; गोपनीयता',
  '05 &mdash; Open source': '05 &mdash; ओपन सोर्स',
  '06 &mdash; FAQ': '06 &mdash; सामान्य प्रश्न',
  '07 &mdash; Get the app': '07 &mdash; अ‍ॅप मिळवा',
  '64 GB': '64 GB',
  'A donut chart of your library by type, plus the largest files.':
    'प्रकारानुसार तुमच्या लायब्ररीचा डोनट चार्ट, आणि सर्वात मोठ्या फाइल्स.',
  'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
    'तुमचे स्टोरेज कुठे जाते हे दाखवणारा थेट डोनट चार्ट &mdash; फोटो, व्हिडिओ, स्क्रीनशॉट, Live Photos, इतर. टॅप करता येणाऱ्या तुकड्यांतून तुम्ही मोकळी करू शकता अशा नेमक्या आयटमपर्यंत पोहोचता येते.',
  'A swipe session in progress &mdash; one photo, one decision.':
    'सुरू असलेले स्वाइप सत्र &mdash; एक फोटो, एक निर्णय.',
  'AI photo search': 'AI फोटो शोध',
  'Activity &amp; savings': 'क्रियाकलाप आणि बचत',
  'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
    'सर्व प्रक्रिया डिव्हाइसवरच, Apple च्या Vision आणि Photos फ्रेमवर्क्स वापरून होते.',
  'Are deleted photos gone immediately?': 'हटवलेले फोटो लगेच निघून जातात का?',
  'Blurry photos': 'अस्पष्ट फोटो',
  'Burst photos': 'बर्स्ट फोटो',
  'Chat media': 'चॅट मीडिया',
  'Clay illustration of a teal vault keeping smiling photo cards safe.':
    'हसत्या फोटो कार्ड्स सुरक्षित ठेवणाऱ्या टील रंगाच्या तिजोरीचे क्ले चित्र.',
  'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
    'हिरव्या टेकड्यांवर फोन फोटो कार्ड्स वर्गीकरण ट्रेमध्ये टाकत असल्याचे क्ले-शैलीतील चित्र.',
  'Clean your library in minutes.': 'तुमची लायब्ररी काही मिनिटांत साफ करा.',
  'Cleanup history': 'क्लीनअप इतिहास',
  'Clear them in one pass': 'एकाच फेरीत साफ करा',
  'Clear what WhatsApp and Telegram saved.':
    'WhatsApp आणि Telegram ने साठवलेले साफ करा.',
  'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
    'एकदा पुष्टी करा आणि जागा परत मिळते. हटवलेले फोटो अलीकडे हटवलेले मध्ये 30 दिवस थांबतात.',
  'Convert to stills to save space.': 'जागा वाचवण्यासाठी स्थिर फोटोंमध्ये बदला.',
  'Describe a photo in plain words, find it on-device.':
    'फोटोचे वर्णन साध्या शब्दांत करा, तो डिव्हाइसवरच सापडेल.',
  'Does TidyByte support iPad?': 'TidyByte iPad ला सपोर्ट करते का?',
  'Does TidyByte upload my photos?': 'TidyByte माझे फोटो अपलोड करते का?',
  'Download TidyByte Free': 'TidyByte Free डाउनलोड करा',
  Duplicates: 'डुप्लिकेट',
  'Every delete and compression decision, recorded on-device and reviewable.':
    'प्रत्येक हटवण्याचा आणि कंप्रेसचा निर्णय डिव्हाइसवर नोंदवला जातो आणि पाहता येतो.',
  'Every kind of clutter, handled.': 'प्रत्येक प्रकारची अव्यवस्था, हाताळलेली.',
  'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
    'अगदी सारखे डुप्लिकेट फाइल डेटाच्या SHA-256 हॅशने जुळवले जातात. जवळपासचे डुप्लिकेट दिसायला सारखे फोटो शोधण्यासाठी Apple Vision फीचर प्रिंट्स वापरतात.',
  'Find exact copies, byte-for-byte.': 'अगदी सारख्या प्रती शोधा, बाइट-बाइट.',
  'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
    'मोफत &middot; iPhone &amp; iPad &middot; iOS 17+',
  'Frequently asked questions.': 'वारंवार विचारले जाणारे प्रश्न.',
  'Group near-identical shots.': 'जवळपास सारखे फोटो एकत्र करा.',
  'How are duplicates detected?': 'डुप्लिकेट कसे ओळखले जातात?',
  'How do I report a bug or request a feature?':
    'बग कसा कळवावा किंवा नवीन सुविधा कशी मागावी?',
  'How it works': 'हे कसे चालते',
  'Is there a free trial or subscription?': 'मोफत ट्रायल किंवा सदस्यता आहे का?',
  'Large files': 'मोठ्या फाइल्स',
  'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
    'डावीकडे हटवा, उजवीकडे ठेवा. काहीही बदलण्यापूर्वी प्रत्येक निवड पुनरावलोकन यादीत जाते.',
  'Live Photos': 'Live Photos',
  'New in 1.0.5 &mdash; on-device AI photo search':
    '1.0.5 मधील नवीन &mdash; डिव्हाइसवरच AI फोटो शोध',
  'No account': 'खाते नाही',
  'No account to create. No subscription to manage. Just one swipe at a time.':
    'तयार करायला खाते नाही. सांभाळायला सदस्यता नाही. फक्त एका वेळी एक स्वाइप.',
  'No ads': 'जाहिराती नाहीत',
  'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
    'अ‍ॅनालिटिक्स SDK नाही, बॅकएंड नाही, तृतीय-पक्ष स्क्रिप्ट नाही, ट्रॅकिंग नाही &mdash; कुठेही.',
  'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
    'कोणतेही क्लीनअप साधन मूळ फाइलला हात लावत नाही. पुन्हा एन्कोड करणारी एकमेव क्रिया म्हणजे तुम्ही स्वतः उघडलेले व्हिडिओ कंप्रेशन किंवा फोटो कंप्रेशन साधन, आणि प्रीसेट तुम्ही निवडता.',
  'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
    'नाही. सर्व प्रक्रिया तुमच्या iPhone वरच, Apple च्या Photos आणि Vision फ्रेमवर्क्स वापरून होते &mdash; अ‍ॅनालिटिक्स SDK नाही, बॅकएंड नाही, ट्रॅकिंग नाही.',
  'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
    'एक कार्ड. एक निर्णय. तुमची कॉफी थंड होण्याआधीच तुम्ही वर्षानुवर्षांचे फोटो साफ कराल.',
  'Open an issue on': 'इश्यू उघडा',
  Other: 'इतर',
  'Photo compression': 'फोटो कंप्रेशन',
  'Photos never leave your phone': 'फोटो कधीही तुमचा फोन सोडत नाहीत',
  'Pick the best from a sequence.': 'क्रमातील सर्वोत्तम फोटो निवडा.',
  'Pick where to start': 'कुठून सुरुवात करायची ते निवडा',
  'Re-encode photos to reclaim space.': 'जागा परत मिळवण्यासाठी फोटो पुन्हा एन्कोड करा.',
  'Read every line that touches your photos.': 'तुमच्या फोटोंना हात लावणारी प्रत्येक ओळ वाचा.',
  'Read the privacy policy': 'गोपनीयता धोरण वाचा',
  'Round up and clear them in one pass.': 'त्यांना गोळा करा आणि एकाच फेरीत साफ करा.',
  'Screen recordings': 'स्क्रीन रेकॉर्डिंग',
  Screenshots: 'स्क्रीनशॉट',
  'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
    'स्क्रीनशॉट, डुप्लिकेट, अस्पष्ट फोटो किंवा तुमची संपूर्ण लायब्ररी. प्रत्येक साधन फोटो कार्ड्सचा डेक उघडते.',
  'See exactly what&rsquo;s using your space.': 'तुमची जागा नेमकी कशावर खर्च होते ते पाहा.',
  'See how it works': 'हे कसे चालते ते पाहा',
  'See what changed &rarr;': 'काय बदलले ते पाहा &rarr;',
  'Shrink videos, keep them watchable.': 'व्हिडिओ लहान करा, पाहण्यासारखे ठेवा.',
  'Similar photos': 'समान फोटो',
  'Smart categories': 'स्मार्ट श्रेणी',
  'Sort by content type, browse faster.': 'सामग्रीच्या प्रकारानुसार क्रमवारी लावा, वेगाने पाहा.',
  'Spot out-of-focus and shaky shots.': 'अस्पष्ट आणि हलत्या हाताने घेतलेले फोटो शोधा.',
  'Storage breakdown': 'स्टोरेज विभाजन',
  Support: 'सपोर्ट',
  'Surface the biggest space hogs.': 'सर्वाधिक जागा घेणारे समोर आणा.',
  'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
    'डावीकडे स्वाइप करा म्हणजे हटवा, उजवीकडे स्वाइप करा म्हणजे ठेवा &mdash; आणि काही मिनिटांत गिगाबाइट्स मोकळे करा. डुप्लिकेट, स्क्रीनशॉट, चॅट मीडिया, अस्पष्ट फोटो आणि प्रचंड मोठे व्हिडिओ हाताळले जातात, फोटो कंप्रेस होतात, 100% डिव्हाइसवर. जाहिराती नाहीत, सदस्यता नाही, खाते नाही.',
  'Swipe to decide': 'स्वाइप करून ठरवा',
  'The best free iPhone storage cleaner and photo cleaner.':
    'iPhone साठी सर्वोत्तम मोफत स्टोरेज क्लीनर आणि फोटो क्लीनर.',
  'The largest files nobody remembers making.': 'कुणालाच आठवत नसलेल्या सर्वात मोठ्या फाइल्स.',
  'The swipe, explained.': 'स्वाइप, सोप्या भाषेत.',
  'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
    'ते iOS च्या अलीकडे हटवलेले अ‍ॅल्बममध्ये जातात, तिथे कायमचे हटण्यापूर्वी 30 दिवस राहतात &mdash; Photos अ‍ॅपमधून हटवल्यासारखेच.',
  'TidyByte in numbers': 'आकड्यांत TidyByte',
  'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
    'TidyByte MIT परवानाधीन आहे. सोर्स वाचा, दावे तपासा, इश्यू नोंदवा.',
  'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
    'TidyByte मोफत आहे, कोणतीही इन-अ‍ॅप खरेदी नाही आणि पेवॉल नाही. प्रत्येक सुविधा प्रत्येक वापरकर्त्यासाठी उपलब्ध आहे. पाहा',
  'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
    'फोटो, व्हिडिओ, स्क्रीनशॉट, Live Photos आणि इतरांचा डोनट चार्ट असलेला TidyByte स्टोरेज डॅशबोर्ड.',
  'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
    'स्क्रीनवर एक फोटो कार्ड आणि खाली हटवा व ठेवा बटणे असलेले TidyByte स्वाइप सत्र.',
  'TidyByte swipe-review screen mid-session.':
    'सत्राच्या मध्यातील TidyByte स्वाइप-पुनरावलोकन स्क्रीन.',
  'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
    'TidyByte तुमच्या संपूर्ण लायब्ररीसह चालते, फक्त iCloud मध्ये साठवलेल्या आयटमसह. सिस्टम गरजेनुसार ते डाउनलोड करते; तुम्ही वाट न पाहता स्वाइप करून पुढेही जाऊ शकता.',
  'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
    'बारा क्लीनअप साधने, स्टोरेजची माहिती, क्लीनअप इतिहास आणि डिव्हाइसवरच AI शोध &mdash; सर्व तुमच्या डिव्हाइसवर चालतात. कोणत्याही एकावर टॅप करा आणि ते कसे चालते ते पाहा.',
  'Video compression': 'व्हिडिओ कंप्रेशन',
  Videos: 'व्हिडिओ',
  'View on GitHub &rarr;': 'GitHub वर पाहा &rarr;',
  'We can&rsquo;t see your photos. We don&rsquo;t want to.':
    'आम्ही तुमचे फोटो पाहू शकत नाही. पाहायचेही नाही.',
  'What about iCloud-only photos?': 'फक्त iCloud मध्ये असलेल्या फोटोंबद्दल काय?',
  'Will it lower the quality of my photos?': 'त्यामुळे माझ्या फोटोंचा दर्जा कमी होईल का?',
  'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
    'हो. TidyByte हे युनिव्हर्सल अ‍ॅप आहे जे iPhone आणि iPad वर नेहमीप्रमाणे चालते. प्रत्येक क्लीनअप साधन दोन्हीवर चालते, स्वाइप इंटरफेस iPad च्या मोठ्या स्क्रीनला जुळतो, आणि iPad सर्व दिशा सपोर्ट करते.',
  'Your photos never leave your phone.': 'तुमचे फोटो कधीही तुमचा फोन सोडत नाहीत.',
  'bytes uploaded, ever': 'कधीही अपलोड झालेले बाइट्स',
  'cleanup tools': 'क्लीनअप साधने',
  'how it compares to subscription photo cleaners':
    'सदस्यता घेणाऱ्या फोटो क्लीनरशी त्याची तुलना कशी होते',
  'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
    'हिशेब ठेवते: तुम्ही काय साफ केले, 30 दिवसांचा चार्ट आणि मोकळी केलेली एकूण जागा. Home Screen विजेट आणि Siri शॉर्टकट थेट क्लीनअपमध्ये घेऊन जातात.',
  'open source, MIT': 'ओपन सोर्स, MIT',
  'or use the contact form on the': 'किंवा संपर्क फॉर्म वापरा',
  'page.': 'पानावर.',
  'photo library': 'फोटो लायब्ररी',
  'to own it outright': 'पूर्ण मालकी मिळवण्यासाठी',
};

translations.gu = {
  '01 &mdash; How it works': '01 &mdash; તે કેવી રીતે કામ કરે છે',
  '02 &mdash; Cleanup toolkit': '02 &mdash; ક્લીનઅપ ટૂલકિટ',
  '03 &mdash; Storage dashboard': '03 &mdash; સ્ટોરેજ ડેશબોર્ડ',
  '04 &mdash; Privacy': '04 &mdash; ગોપનીયતા',
  '05 &mdash; Open source': '05 &mdash; ઓપન સોર્સ',
  '06 &mdash; FAQ': '06 &mdash; સામાન્ય પ્રશ્નો',
  '07 &mdash; Get the app': '07 &mdash; એપ મેળવો',
  '64 GB': '64 GB',
  'A donut chart of your library by type, plus the largest files.':
    'પ્રકાર પ્રમાણે તમારી લાઇબ્રેરીનો ડોનટ ચાર્ટ, સાથે સૌથી મોટી ફાઇલો.',
  'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
    'તમારું સ્ટોરેજ ક્યાં જાય છે તે દર્શાવતો જીવંત ડોનટ ચાર્ટ &mdash; ફોટા, વિડિયો, સ્ક્રીનશોટ, Live Photos, અન્ય. ટૅપ કરી શકાય તેવા ટુકડા તમે ખાલી કરી શકો તેવી ચોક્કસ આઇટમો સુધી લઈ જાય છે.',
  'A swipe session in progress &mdash; one photo, one decision.':
    'ચાલુ સ્વાઇપ સત્ર &mdash; એક ફોટો, એક નિર્ણય.',
  'AI photo search': 'AI ફોટો શોધ',
  'Activity &amp; savings': 'પ્રવૃત્તિ અને બચત',
  'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
    'બધી પ્રક્રિયા ડિવાઇસ પર જ થાય છે, Apple ના Vision અને Photos ફ્રેમવર્ક વાપરીને.',
  'Are deleted photos gone immediately?': 'કાઢી નાખેલા ફોટા તરત જ જતા રહે છે?',
  'Blurry photos': 'ઝાંખા ફોટા',
  'Burst photos': 'બર્સ્ટ ફોટા',
  'Chat media': 'ચેટ મીડિયા',
  'Clay illustration of a teal vault keeping smiling photo cards safe.':
    'હસતા ફોટો કાર્ડ સુરક્ષિત રાખતી ટીલ રંગની તિજોરીનું ક્લે ચિત્ર.',
  'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
    'લીલા ટેકરાઓ પર ફોન ફોટો કાર્ડને ગોઠવણી ટ્રેમાં નાખતો હોય તેવું ક્લે-શૈલીનું ચિત્ર.',
  'Clean your library in minutes.': 'તમારી લાઇબ્રેરી થોડી મિનિટોમાં સાફ કરો.',
  'Cleanup history': 'ક્લીનઅપ ઇતિહાસ',
  'Clear them in one pass': 'એક જ ફેરમાં સાફ કરો',
  'Clear what WhatsApp and Telegram saved.':
    'WhatsApp અને Telegram એ સંગ્રહેલું સાફ કરો.',
  'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
    'એક વાર પુષ્ટિ કરો અને જગ્યા પાછી આવે છે. કાઢી નાખેલા ફોટા તાજેતરમાં કાઢી નાખેલા માં 30 દિવસ રાહ જુએ છે.',
  'Convert to stills to save space.': 'જગ્યા બચાવવા સ્થિર ફોટામાં ફેરવો.',
  'Describe a photo in plain words, find it on-device.':
    'ફોટાનું વર્ણન સાદા શબ્દોમાં કરો, તે ડિવાઇસ પર જ મળશે.',
  'Does TidyByte support iPad?': 'TidyByte iPad ને સપોર્ટ કરે છે?',
  'Does TidyByte upload my photos?': 'TidyByte મારા ફોટા અપલોડ કરે છે?',
  'Download TidyByte Free': 'TidyByte Free ડાઉનલોડ કરો',
  Duplicates: 'ડુપ્લિકેટ',
  'Every delete and compression decision, recorded on-device and reviewable.':
    'દરેક કાઢી નાખવાનો અને કોમ્પ્રેસનો નિર્ણય ડિવાઇસ પર નોંધાય છે અને જોઈ શકાય છે.',
  'Every kind of clutter, handled.': 'દરેક પ્રકારની અવ્યવસ્થા, હાથ ધરાયેલી.',
  'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
    'એકદમ સરખા ડુપ્લિકેટ ફાઇલ ડેટાના SHA-256 હેશથી મળે છે. નજીકના ડુપ્લિકેટ દેખાવમાં સરખા ફોટા શોધવા Apple Vision ફીચર પ્રિન્ટ વાપરે છે.',
  'Find exact copies, byte-for-byte.': 'એકદમ સરખી નકલો શોધો, બાઇટ-બાઇટ.',
  'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
    'મફત &middot; iPhone &amp; iPad &middot; iOS 17+',
  'Frequently asked questions.': 'વારંવાર પૂછાતા પ્રશ્નો.',
  'Group near-identical shots.': 'લગભગ સરખા ફોટા એકસાથે ગોઠવો.',
  'How are duplicates detected?': 'ડુપ્લિકેટ કેવી રીતે શોધાય છે?',
  'How do I report a bug or request a feature?':
    'બગ કેવી રીતે જણાવવો કે નવી સુવિધા કેવી રીતે માંગવી?',
  'How it works': 'તે કેવી રીતે કામ કરે છે',
  'Is there a free trial or subscription?': 'મફત ટ્રાયલ કે સબ્સ્ક્રિપ્શન છે?',
  'Large files': 'મોટી ફાઇલો',
  'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
    'ડાબે કાઢી નાખે છે, જમણે રાખે છે. કંઈપણ બદલાય તે પહેલાં દરેક પસંદગી સમીક્ષા યાદીમાં જાય છે.',
  'Live Photos': 'Live Photos',
  'New in 1.0.5 &mdash; on-device AI photo search':
    '1.0.5 માં નવું &mdash; ડિવાઇસ પર જ AI ફોટો શોધ',
  'No account': 'ખાતું નહીં',
  'No account to create. No subscription to manage. Just one swipe at a time.':
    'બનાવવા માટે ખાતું નહીં. સંભાળવા માટે સબ્સ્ક્રિપ્શન નહીં. ફક્ત એક સમયે એક સ્વાઇપ.',
  'No ads': 'જાહેરાત નહીં',
  'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
    'એનાલિટિક્સ SDK નહીં, બેકએન્ડ નહીં, તૃતીય-પક્ષ સ્ક્રિપ્ટ નહીં, ટ્રેકિંગ નહીં &mdash; ક્યાંય.',
  'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
    'કોઈ ક્લીનઅપ ટૂલ મૂળ ફાઇલને અડતું નથી. ફરી એન્કોડ કરતું એકમાત્ર ટૂલ તમે જાતે ખોલો તે વિડિયો કોમ્પ્રેશન કે ફોટો કોમ્પ્રેશન છે, અને પ્રીસેટ તમે પસંદ કરો છો.',
  'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
    'ના. બધી પ્રક્રિયા તમારા iPhone પર જ થાય છે, Apple ના Photos અને Vision ફ્રેમવર્ક વાપરીને &mdash; એનાલિટિક્સ SDK નહીં, બેકએન્ડ નહીં, ટ્રેકિંગ નહીં.',
  'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
    'એક કાર્ડ. એક નિર્ણય. તમારી કોફી ઠંડી થાય તે પહેલાં તમે વર્ષોના ફોટા સાફ કરી નાખશો.',
  'Open an issue on': 'ઇશ્યૂ ખોલો',
  Other: 'અન્ય',
  'Photo compression': 'ફોટો કોમ્પ્રેશન',
  'Photos never leave your phone': 'ફોટા ક્યારેય તમારો ફોન છોડતા નથી',
  'Pick the best from a sequence.': 'ક્રમમાંથી શ્રેષ્ઠ ફોટો પસંદ કરો.',
  'Pick where to start': 'ક્યાંથી શરૂ કરવું તે પસંદ કરો',
  'Re-encode photos to reclaim space.': 'જગ્યા પાછી મેળવવા ફોટા ફરી એન્કોડ કરો.',
  'Read every line that touches your photos.': 'તમારા ફોટાને અડતી દરેક લાઇન વાંચો.',
  'Read the privacy policy': 'ગોપનીયતા નીતિ વાંચો',
  'Round up and clear them in one pass.': 'એક જ ફેરમાં તેમને ભેગા કરો અને સાફ કરો.',
  'Screen recordings': 'સ્ક્રીન રેકોર્ડિંગ',
  Screenshots: 'સ્ક્રીનશોટ',
  'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
    'સ્ક્રીનશોટ, ડુપ્લિકેટ, ઝાંખા ફોટા કે તમારી આખી લાઇબ્રેરી. દરેક ટૂલ ફોટો કાર્ડનો ડેક ખોલે છે.',
  'See exactly what&rsquo;s using your space.': 'તમારી જગ્યા બરાબર શેમાં વપરાય છે તે જુઓ.',
  'See how it works': 'તે કેવી રીતે કામ કરે છે તે જુઓ',
  'See what changed &rarr;': 'શું બદલાયું તે જુઓ &rarr;',
  'Shrink videos, keep them watchable.': 'વિડિયો નાના કરો, જોવાલાયક રાખો.',
  'Similar photos': 'સમાન ફોટા',
  'Smart categories': 'સ્માર્ટ કેટેગરી',
  'Sort by content type, browse faster.': 'સામગ્રીના પ્રકાર પ્રમાણે ગોઠવો, ઝડપથી જુઓ.',
  'Spot out-of-focus and shaky shots.': 'ઝાંખા અને ધ્રૂજતા ફોટા શોધો.',
  'Storage breakdown': 'સ્ટોરેજ વિભાજન',
  Support: 'સપોર્ટ',
  'Surface the biggest space hogs.': 'સૌથી વધુ જગ્યા ખાવાનારા સામે લાવો.',
  'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
    'ડાબે સ્વાઇપ કરો એટલે કાઢી નાખો, જમણે સ્વાઇપ કરો એટલે રાખો &mdash; અને થોડી મિનિટોમાં ગીગાબાઇટ ખાલી કરો. ડુપ્લિકેટ, સ્ક્રીનશોટ, ચેટ મીડિયા, ઝાંખા ફોટા અને વધુ પડતા મોટા વિડિયો સંભાળ્યા, ફોટા કોમ્પ્રેસ થયા, 100% ડિવાઇસ પર. જાહેરાત નહીં, સબ્સ્ક્રિપ્શન નહીં, ખાતું નહીં.',
  'Swipe to decide': 'સ્વાઇપ કરીને નક્કી કરો',
  'The best free iPhone storage cleaner and photo cleaner.':
    'iPhone માટે શ્રેષ્ઠ મફત સ્ટોરેજ ક્લીનર અને ફોટો ક્લીનર.',
  'The largest files nobody remembers making.': 'કોઈને યાદ ન રહ્યું હોય તેવી સૌથી મોટી ફાઇલો.',
  'The swipe, explained.': 'સ્વાઇપ, સરળ ભાષામાં.',
  'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
    'તે iOS ના તાજેતરમાં કાઢી નાખેલા આલ્બમમાં જાય છે, જ્યાં કાયમ કાઢી નાખતા પહેલાં 30 દિવસ રહે છે &mdash; Photos એપમાંથી કાઢી નાખ્યા જેવું જ.',
  'TidyByte in numbers': 'આંકડામાં TidyByte',
  'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
    'TidyByte MIT લાઇસન્સ હેઠળ છે. સોર્સ વાંચો, દાવા ચકાસો, ઇશ્યૂ ફાઇલ કરો.',
  'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
    'TidyByte મફત છે, કોઈ ઇન-એપ ખરીદી નહીં અને પેવોલ નહીં. દરેક સુવિધા દરેક વપરાશકર્તા માટે ઉપલબ્ધ છે. જુઓ',
  'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
    'ફોટા, વિડિયો, સ્ક્રીનશોટ, Live Photos અને અન્યના ડોનટ ચાર્ટ સાથેનું TidyByte સ્ટોરેજ ડેશબોર્ડ.',
  'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
    'સ્ક્રીન પર એક ફોટો કાર્ડ અને નીચે કાઢી નાખો તથા રાખો બટન સાથેનું TidyByte સ્વાઇપ સત્ર.',
  'TidyByte swipe-review screen mid-session.':
    'સત્રની વચ્ચેની TidyByte સ્વાઇપ-સમીક્ષા સ્ક્રીન.',
  'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
    'TidyByte તમારી આખી લાઇબ્રેરી સાથે કામ કરે છે, ફક્ત iCloud માં સંગ્રહેલી આઇટમો સહિત. સિસ્ટમ જરૂર પડે ત્યારે તે ડાઉનલોડ કરે છે; તમે રાહ જોયા વગર સ્વાઇપ કરીને આગળ પણ જઈ શકો છો.',
  'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
    'બાર ક્લીનઅપ ટૂલ, સ્ટોરેજની સમજ, ક્લીનઅપ ઇતિહાસ અને ડિવાઇસ પર જ AI શોધ &mdash; બધું તમારા ડિવાઇસ પર ચાલે છે. કોઈ પણ એક પર ટૅપ કરો અને તે કેવી રીતે કામ કરે છે તે જુઓ.',
  'Video compression': 'વિડિયો કોમ્પ્રેશન',
  Videos: 'વિડિયો',
  'View on GitHub &rarr;': 'GitHub પર જુઓ &rarr;',
  'We can&rsquo;t see your photos. We don&rsquo;t want to.':
    'અમે તમારા ફોટા જોઈ શકતા નથી. જોવા પણ નથી માંગતા.',
  'What about iCloud-only photos?': 'ફક્ત iCloud માં રહેલા ફોટા વિશે શું?',
  'Will it lower the quality of my photos?': 'તે મારા ફોટાની ગુણવત્તા ઘટાડશે?',
  'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
    'હા. TidyByte એ યુનિવર્સલ એપ છે જે iPhone અને iPad પર જન્મજાત ચાલે છે. દરેક ક્લીનઅપ ટૂલ બંને પર કામ કરે છે, સ્વાઇપ ઇન્ટરફેસ iPad ની મોટી સ્ક્રીન સાથે ગોઠવાય છે, અને iPad બધી દિશાઓને સપોર્ટ કરે છે.',
  'Your photos never leave your phone.': 'તમારા ફોટા ક્યારેય તમારો ફોન છોડતા નથી.',
  'bytes uploaded, ever': 'ક્યારેય અપલોડ થયેલા બાઇટ',
  'cleanup tools': 'ક્લીનઅપ ટૂલ',
  'how it compares to subscription photo cleaners':
    'સબ્સ્ક્રિપ્શન ફોટો ક્લીનર સાથે તેની સરખામણી કેવી છે',
  'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
    'હિસાબ રાખે છે: તમે સાફ કરેલું બધું, 30 દિવસનો ચાર્ટ, અને ખાલી કરેલી કુલ જગ્યા. Home Screen વિજેટ અને Siri શોર્ટકટ સીધા ક્લીનઅપમાં લઈ જાય છે.',
  'open source, MIT': 'ઓપન સોર્સ, MIT',
  'or use the contact form on the': 'અથવા સંપર્ક ફોર્મ વાપરો',
  'page.': 'પૃષ્ઠ પર.',
  'photo library': 'ફોટો લાઇબ્રેરી',
  'to own it outright': 'પૂરેપૂરી માલિકી માટે',
};

translations.pa = {
  '01 &mdash; How it works': '01 &mdash; ਇਹ ਕਿਵੇਂ ਕੰਮ ਕਰਦਾ ਹੈ',
  '02 &mdash; Cleanup toolkit': '02 &mdash; ਸਫ਼ਾਈ ਟੂਲਕਿਟ',
  '03 &mdash; Storage dashboard': '03 &mdash; ਸਟੋਰੇਜ ਡੈਸ਼ਬੋਰਡ',
  '04 &mdash; Privacy': '04 &mdash; ਨਿੱਜਤਾ',
  '05 &mdash; Open source': '05 &mdash; ਓਪਨ ਸੋਰਸ',
  '06 &mdash; FAQ': '06 &mdash; ਆਮ ਸਵਾਲ',
  '07 &mdash; Get the app': '07 &mdash; ਐਪ ਲਓ',
  '64 GB': '64 GB',
  'A donut chart of your library by type, plus the largest files.':
    'ਕਿਸਮ ਅਨੁਸਾਰ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਦਾ ਡੋਨਟ ਚਾਰਟ, ਨਾਲ ਹੀ ਸਭ ਤੋਂ ਵੱਡੀਆਂ ਫ਼ਾਈਲਾਂ.',
  'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
    'ਤੁਹਾਡਾ ਸਟੋਰੇਜ ਕਿੱਥੇ ਜਾਂਦਾ ਹੈ ਦਿਖਾਉਣ ਵਾਲਾ ਲਾਈਵ ਡੋਨਟ ਚਾਰਟ &mdash; ਫ਼ੋਟੋ, ਵੀਡੀਓ, ਸਕਰੀਨਸ਼ਾਟ, Live Photos, ਹੋਰ. ਟੈਪ ਕਰਨ ਯੋਗ ਹਿੱਸੇ ਉਨ੍ਹਾਂ ਖ਼ਾਸ ਆਈਟਮਾਂ ਤੱਕ ਲੈ ਜਾਂਦੇ ਹਨ ਜੋ ਤੁਸੀਂ ਖਾਲੀ ਕਰ ਸਕਦੇ ਹੋ.',
  'A swipe session in progress &mdash; one photo, one decision.':
    'ਚੱਲ ਰਿਹਾ ਸਵਾਈਪ ਸੈਸ਼ਨ &mdash; ਇੱਕ ਫ਼ੋਟੋ, ਇੱਕ ਫ਼ੈਸਲਾ.',
  'AI photo search': 'AI ਫ਼ੋਟੋ ਖੋਜ',
  'Activity &amp; savings': 'ਗਤੀਵਿਧੀ ਅਤੇ ਬਚਤ',
  'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
    'ਸਾਰੀ ਪ੍ਰਕਿਰਿਆ ਡੀਵਾਈਸ ਉੱਤੇ ਹੀ ਹੁੰਦੀ ਹੈ, Apple ਦੇ Vision ਅਤੇ Photos ਫ਼ਰੇਮਵਰਕ ਵਰਤ ਕੇ.',
  'Are deleted photos gone immediately?': 'ਮਿਟਾਈਆਂ ਫ਼ੋਟੋਆਂ ਤੁਰੰਤ ਚਲੀਆਂ ਜਾਂਦੀਆਂ ਹਨ?',
  'Blurry photos': 'ਧੁੰਦਲੀਆਂ ਫ਼ੋਟੋਆਂ',
  'Burst photos': 'ਬਰਸਟ ਫ਼ੋਟੋਆਂ',
  'Chat media': 'ਚੈਟ ਮੀਡੀਆ',
  'Clay illustration of a teal vault keeping smiling photo cards safe.':
    'ਮੁਸਕਰਾਉਂਦੇ ਫ਼ੋਟੋ ਕਾਰਡਾਂ ਨੂੰ ਸੁਰੱਖਿਅਤ ਰੱਖਦੀ ਟੀਲ ਰੰਗ ਦੀ ਤਿਜੋਰੀ ਦਾ ਕਲੇ ਚਿੱਤਰ.',
  'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
    'ਹਰੀਆਂ ਪਹਾੜੀਆਂ ਉੱਤੇ ਫ਼ੋਨ ਫ਼ੋਟੋ ਕਾਰਡ ਛਾਂਟੀ ਟ੍ਰੇ ਵਿੱਚ ਸੁੱਟਦਾ ਹੋਇਆ ਕਲੇ-ਸ਼ੈਲੀ ਦਾ ਚਿੱਤਰ.',
  'Clean your library in minutes.': 'ਆਪਣੀ ਲਾਇਬ੍ਰੇਰੀ ਕੁਝ ਮਿੰਟਾਂ ਵਿੱਚ ਸਾਫ਼ ਕਰੋ.',
  'Cleanup history': 'ਸਫ਼ਾਈ ਇਤਿਹਾਸ',
  'Clear them in one pass': 'ਇੱਕੋ ਵਾਰ ਵਿੱਚ ਸਾਫ਼ ਕਰੋ',
  'Clear what WhatsApp and Telegram saved.':
    'WhatsApp ਅਤੇ Telegram ਨੇ ਸੰਭਾਲਿਆ ਸਾਫ਼ ਕਰੋ.',
  'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
    'ਇੱਕ ਵਾਰ ਪੁਸ਼ਟੀ ਕਰੋ ਅਤੇ ਥਾਂ ਵਾਪਸ ਆ ਜਾਂਦੀ ਹੈ. ਮਿਟਾਈਆਂ ਫ਼ੋਟੋਆਂ ਹਾਲ ਹੀ ਵਿੱਚ ਮਿਟਾਏ ਵਿੱਚ 30 ਦਿਨ ਉਡੀਕਦੀਆਂ ਹਨ.',
  'Convert to stills to save space.': 'ਥਾਂ ਬਚਾਉਣ ਲਈ ਸਥਿਰ ਫ਼ੋਟੋਆਂ ਵਿੱਚ ਬਦਲੋ.',
  'Describe a photo in plain words, find it on-device.':
    'ਫ਼ੋਟੋ ਦਾ ਵਰਣਨ ਸਾਦੇ ਸ਼ਬਦਾਂ ਵਿੱਚ ਕਰੋ, ਉਹ ਡੀਵਾਈਸ ਉੱਤੇ ਹੀ ਮਿਲੇਗੀ.',
  'Does TidyByte support iPad?': 'TidyByte iPad ਨੂੰ ਸਪੋਰਟ ਕਰਦਾ ਹੈ?',
  'Does TidyByte upload my photos?': 'TidyByte ਮੇਰੀਆਂ ਫ਼ੋਟੋਆਂ ਅੱਪਲੋਡ ਕਰਦਾ ਹੈ?',
  'Download TidyByte Free': 'TidyByte Free ਡਾਊਨਲੋਡ ਕਰੋ',
  Duplicates: 'ਡੁਪਲੀਕੇਟ',
  'Every delete and compression decision, recorded on-device and reviewable.':
    'ਹਰ ਮਿਟਾਉਣ ਅਤੇ ਕੰਪਰੈਸ ਦਾ ਫ਼ੈਸਲਾ ਡੀਵਾਈਸ ਉੱਤੇ ਦਰਜ ਹੁੰਦਾ ਹੈ ਅਤੇ ਵੇਖਿਆ ਜਾ ਸਕਦਾ ਹੈ.',
  'Every kind of clutter, handled.': 'ਹਰ ਕਿਸਮ ਦੀ ਗੜਬੜ, ਸੰਭਾਲੀ ਗਈ.',
  'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
    'ਬਿਲਕੁਲ ਇੱਕੋ ਜਿਹੇ ਡੁਪਲੀਕੇਟ ਫ਼ਾਈਲ ਡਾਟਾ ਦੇ SHA-256 ਹੈਸ਼ ਨਾਲ ਮਿਲਾਏ ਜਾਂਦੇ ਹਨ. ਨੇੜਲੇ ਡੁਪਲੀਕੇਟ ਦਿਖਣ ਵਿੱਚ ਮਿਲਦੀਆਂ ਫ਼ੋਟੋਆਂ ਲੱਭਣ ਲਈ Apple Vision ਫ਼ੀਚਰ ਪ੍ਰਿੰਟ ਵਰਤਦੇ ਹਨ.',
  'Find exact copies, byte-for-byte.': 'ਬਿਲਕੁਲ ਇੱਕੋ ਜਿਹੀਆਂ ਕਾਪੀਆਂ ਲੱਭੋ, ਬਾਈਟ-ਬਾਈਟ.',
  'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
    'ਮੁਫ਼ਤ &middot; iPhone &amp; iPad &middot; iOS 17+',
  'Frequently asked questions.': 'ਆਮ ਪੁੱਛੇ ਜਾਂਦੇ ਸਵਾਲ.',
  'Group near-identical shots.': 'ਲਗਭਗ ਇੱਕੋ ਜਿਹੀਆਂ ਫ਼ੋਟੋਆਂ ਇਕੱਠੀਆਂ ਕਰੋ.',
  'How are duplicates detected?': 'ਡੁਪਲੀਕੇਟ ਕਿਵੇਂ ਲੱਭੇ ਜਾਂਦੇ ਹਨ?',
  'How do I report a bug or request a feature?':
    'ਬੱਗ ਕਿਵੇਂ ਦੱਸਾਂ ਜਾਂ ਨਵੀਂ ਸੁਵਿਧਾ ਕਿਵੇਂ ਮੰਗਾਂ?',
  'How it works': 'ਇਹ ਕਿਵੇਂ ਕੰਮ ਕਰਦਾ ਹੈ',
  'Is there a free trial or subscription?': 'ਮੁਫ਼ਤ ਟਰਾਇਲ ਜਾਂ ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਹੈ?',
  'Large files': 'ਵੱਡੀਆਂ ਫ਼ਾਈਲਾਂ',
  'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
    'ਖੱਬੇ ਮਿਟਾਉਂਦਾ ਹੈ, ਸੱਜੇ ਰੱਖਦਾ ਹੈ. ਕੁਝ ਵੀ ਬਦਲਣ ਤੋਂ ਪਹਿਲਾਂ ਹਰ ਫ਼ੈਸਲਾ ਸਮੀਖਿਆ ਸੂਚੀ ਵਿੱਚ ਜਾਂਦਾ ਹੈ.',
  'Live Photos': 'Live Photos',
  'New in 1.0.5 &mdash; on-device AI photo search':
    '1.0.5 ਵਿੱਚ ਨਵਾਂ &mdash; ਡੀਵਾਈਸ ਉੱਤੇ ਹੀ AI ਫ਼ੋਟੋ ਖੋਜ',
  'No account': 'ਕੋਈ ਖਾਤਾ ਨਹੀਂ',
  'No account to create. No subscription to manage. Just one swipe at a time.':
    'ਬਣਾਉਣ ਲਈ ਕੋਈ ਖਾਤਾ ਨਹੀਂ. ਸੰਭਾਲਣ ਲਈ ਕੋਈ ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਨਹੀਂ. ਬੱਸ ਇੱਕ ਵੇਲੇ ਇੱਕ ਸਵਾਈਪ.',
  'No ads': 'ਕੋਈ ਇਸ਼ਤਿਹਾਰ ਨਹੀਂ',
  'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
    'ਕੋਈ ਐਨਾਲਿਟਿਕਸ SDK ਨਹੀਂ, ਕੋਈ ਬੈਕਐਂਡ ਨਹੀਂ, ਕੋਈ ਤੀਜੀ-ਧਿਰ ਸਕ੍ਰਿਪਟ ਨਹੀਂ, ਕੋਈ ਟਰੈਕਿੰਗ ਨਹੀਂ &mdash; ਕਿਤੇ ਵੀ.',
  'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
    'ਕੋਈ ਵੀ ਸਫ਼ਾਈ ਟੂਲ ਅਸਲ ਫ਼ਾਈਲਾਂ ਨੂੰ ਛੂਹਦਾ ਨਹੀਂ. ਦੁਬਾਰਾ ਐਨਕੋਡ ਕਰਨ ਵਾਲਾ ਸਿਰਫ਼ ਉਹ ਟੂਲ ਹੈ ਜੋ ਤੁਸੀਂ ਖ਼ੁਦ ਖੋਲ੍ਹੋ — ਵੀਡੀਓ ਕੰਪਰੈਸ਼ਨ ਜਾਂ ਫ਼ੋਟੋ ਕੰਪਰੈਸ਼ਨ — ਅਤੇ ਪ੍ਰੀਸੈਟ ਤੁਸੀਂ ਚੁਣਦੇ ਹੋ.',
  'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
    'ਨਹੀਂ. ਸਾਰੀ ਪ੍ਰਕਿਰਿਆ ਤੁਹਾਡੇ iPhone ਉੱਤੇ ਹੀ ਹੁੰਦੀ ਹੈ, Apple ਦੇ Photos ਅਤੇ Vision ਫ਼ਰੇਮਵਰਕ ਵਰਤ ਕੇ &mdash; ਕੋਈ ਐਨਾਲਿਟਿਕਸ SDK ਨਹੀਂ, ਕੋਈ ਬੈਕਐਂਡ ਨਹੀਂ, ਕੋਈ ਟਰੈਕਿੰਗ ਨਹੀਂ.',
  'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
    'ਇੱਕ ਕਾਰਡ. ਇੱਕ ਫ਼ੈਸਲਾ. ਤੁਹਾਡੀ ਕੌਫ਼ੀ ਠੰਢੀ ਹੋਣ ਤੋਂ ਪਹਿਲਾਂ ਤੁਸੀਂ ਸਾਲਾਂ ਦੀਆਂ ਫ਼ੋਟੋਆਂ ਸਾਫ਼ ਕਰ ਦਿਓਗੇ.',
  'Open an issue on': 'ਇਸ਼ੂ ਖੋਲ੍ਹੋ',
  Other: 'ਹੋਰ',
  'Photo compression': 'ਫ਼ੋਟੋ ਕੰਪਰੈਸ਼ਨ',
  'Photos never leave your phone': 'ਫ਼ੋਟੋਆਂ ਕਦੇ ਵੀ ਤੁਹਾਡਾ ਫ਼ੋਨ ਨਹੀਂ ਛੱਡਦੀਆਂ',
  'Pick the best from a sequence.': 'ਲੜੀ ਵਿੱਚੋਂ ਸਭ ਤੋਂ ਵਧੀਆ ਫ਼ੋਟੋ ਚੁਣੋ.',
  'Pick where to start': 'ਕਿੱਥੋਂ ਸ਼ੁਰੂ ਕਰਨਾ ਹੈ ਚੁਣੋ',
  'Re-encode photos to reclaim space.': 'ਥਾਂ ਵਾਪਸ ਲੈਣ ਲਈ ਫ਼ੋਟੋਆਂ ਦੁਬਾਰਾ ਐਨਕੋਡ ਕਰੋ.',
  'Read every line that touches your photos.': 'ਤੁਹਾਡੀਆਂ ਫ਼ੋਟੋਆਂ ਨੂੰ ਛੂਹਣ ਵਾਲੀ ਹਰ ਲਾਈਨ ਪੜ੍ਹੋ.',
  'Read the privacy policy': 'ਪਰਦੇਦਾਰੀ ਨੀਤੀ ਪੜ੍ਹੋ',
  'Round up and clear them in one pass.': 'ਇਕੱਠੀਆਂ ਕਰੋ ਅਤੇ ਇੱਕੋ ਵਾਰ ਵਿੱਚ ਸਾਫ਼ ਕਰੋ.',
  'Screen recordings': 'ਸਕਰੀਨ ਰਿਕਾਰਡਿੰਗਾਂ',
  Screenshots: 'ਸਕਰੀਨਸ਼ਾਟ',
  'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
    'ਸਕਰੀਨਸ਼ਾਟ, ਡੁਪਲੀਕੇਟ, ਧੁੰਦਲੀਆਂ ਫ਼ੋਟੋਆਂ ਜਾਂ ਤੁਹਾਡੀ ਪੂਰੀ ਲਾਇਬ੍ਰੇਰੀ. ਹਰ ਟੂਲ ਫ਼ੋਟੋ ਕਾਰਡਾਂ ਦਾ ਡੈੱਕ ਖੋਲ੍ਹਦਾ ਹੈ.',
  'See exactly what&rsquo;s using your space.': 'ਵੇਖੋ ਤੁਹਾਡੀ ਥਾਂ ਅਸਲ ਵਿੱਚ ਕੀ ਵਰਤ ਰਿਹਾ ਹੈ.',
  'See how it works': 'ਇਹ ਕਿਵੇਂ ਕੰਮ ਕਰਦਾ ਹੈ ਵੇਖੋ',
  'See what changed &rarr;': 'ਕੀ ਬਦਲਿਆ ਵੇਖੋ &rarr;',
  'Shrink videos, keep them watchable.': 'ਵੀਡੀਓ ਛੋਟੇ ਕਰੋ, ਵੇਖਣ ਯੋਗ ਰੱਖੋ.',
  'Similar photos': 'ਸਮਾਨ ਫ਼ੋਟੋਆਂ',
  'Smart categories': 'ਸਮਾਰਟ ਸ਼੍ਰੇਣੀਆਂ',
  'Sort by content type, browse faster.': 'ਸਮੱਗਰੀ ਦੀ ਕਿਸਮ ਅਨੁਸਾਰ ਲਗਾਓ, ਤੇਜ਼ੀ ਨਾਲ ਵੇਖੋ.',
  'Spot out-of-focus and shaky shots.': 'ਧੁੰਦਲੀਆਂ ਅਤੇ ਕੰਬਦੀਆਂ ਫ਼ੋਟੋਆਂ ਲੱਭੋ.',
  'Storage breakdown': 'ਸਟੋਰੇਜ ਵੰਡ',
  Support: 'ਸਪੋਰਟ',
  'Surface the biggest space hogs.': 'ਸਭ ਤੋਂ ਵੱਧ ਥਾਂ ਖਾਣ ਵਾਲੇ ਸਾਹਮਣੇ ਲਿਆਓ.',
  'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
    'ਖੱਬੇ ਸਵਾਈਪ ਕਰੋ ਤਾਂ ਮਿਟਾਓ, ਸੱਜੇ ਸਵਾਈਪ ਕਰੋ ਤਾਂ ਰੱਖੋ &mdash; ਅਤੇ ਕੁਝ ਮਿੰਟਾਂ ਵਿੱਚ ਗੀਗਾਬਾਈਟ ਖਾਲੀ ਕਰੋ. ਡੁਪਲੀਕੇਟ, ਸਕਰੀਨਸ਼ਾਟ, ਚੈਟ ਮੀਡੀਆ, ਧੁੰਦਲੀਆਂ ਫ਼ੋਟੋਆਂ ਅਤੇ ਬਹੁਤ ਵੱਡੇ ਵੀਡੀਓ ਸੰਭਾਲੇ, ਫ਼ੋਟੋਆਂ ਕੰਪਰੈਸ ਕੀਤੀਆਂ, 100% ਡੀਵਾਈਸ ਉੱਤੇ. ਕੋਈ ਇਸ਼ਤਿਹਾਰ ਨਹੀਂ, ਕੋਈ ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਨਹੀਂ, ਕੋਈ ਖਾਤਾ ਨਹੀਂ.',
  'Swipe to decide': 'ਸਵਾਈਪ ਕਰਕੇ ਫ਼ੈਸਲਾ ਕਰੋ',
  'The best free iPhone storage cleaner and photo cleaner.':
    'iPhone ਲਈ ਸਭ ਤੋਂ ਵਧੀਆ ਮੁਫ਼ਤ ਸਟੋਰੇਜ ਕਲੀਨਰ ਅਤੇ ਫ਼ੋਟੋ ਕਲੀਨਰ.',
  'The largest files nobody remembers making.': 'ਉਹ ਵੱਡੀਆਂ ਫ਼ਾਈਲਾਂ ਜੋ ਕਿਸੇ ਨੂੰ ਯਾਦ ਨਹੀਂ ਕਿ ਕਦੋਂ ਬਣੀਆਂ.',
  'The swipe, explained.': 'ਸਵਾਈਪ, ਸੌਖੇ ਸ਼ਬਦਾਂ ਵਿੱਚ.',
  'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
    'ਇਹ iOS ਦੇ ਹਾਲ ਹੀ ਵਿੱਚ ਮਿਟਾਏ ਐਲਬਮ ਵਿੱਚ ਜਾਂਦੀਆਂ ਹਨ, ਜਿੱਥੇ ਪੱਕੇ ਤੌਰ ਉੱਤੇ ਹਟਣ ਤੋਂ ਪਹਿਲਾਂ 30 ਦਿਨ ਰਹਿੰਦੀਆਂ ਹਨ &mdash; ਬਿਲਕੁਲ Photos ਐਪ ਵਿੱਚੋਂ ਮਿਟਾਉਣ ਵਾਂਗ.',
  'TidyByte in numbers': 'ਅੰਕੜਿਆਂ ਵਿੱਚ TidyByte',
  'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
    'TidyByte MIT ਲਾਇਸੰਸ ਹੇਠ ਹੈ. ਸੋਰਸ ਪੜ੍ਹੋ, ਦਾਅਵੇ ਜਾਂਚੋ, ਇਸ਼ੂ ਦਰਜ ਕਰੋ.',
  'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
    'TidyByte ਮੁਫ਼ਤ ਹੈ, ਕੋਈ ਇਨ-ਐਪ ਖਰੀਦ ਨਹੀਂ ਅਤੇ ਕੋਈ ਪੇਵਾਲ ਨਹੀਂ. ਹਰ ਸੁਵਿਧਾ ਹਰ ਵਰਤੋਂਕਾਰ ਲਈ ਉਪਲਬਧ ਹੈ. ਵੇਖੋ',
  'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
    'TidyByte ਸਟੋਰੇਜ ਡੈਸ਼ਬੋਰਡ, ਜਿਸ ਵਿੱਚ ਫ਼ੋਟੋ, ਵੀਡੀਓ, ਸਕਰੀਨਸ਼ਾਟ, Live Photos ਅਤੇ ਹੋਰ ਦਾ ਡੋਨਟ ਚਾਰਟ ਹੈ.',
  'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
    'TidyByte ਸਵਾਈਪ ਸੈਸ਼ਨ, ਸਕਰੀਨ ਉੱਤੇ ਇੱਕ ਫ਼ੋਟੋ ਕਾਰਡ ਅਤੇ ਹੇਠਾਂ ਮਿਟਾਓ ਤੇ ਰੱਖੋ ਬਟਨ.',
  'TidyByte swipe-review screen mid-session.': 'ਸੈਸ਼ਨ ਵਿਚਕਾਰ TidyByte ਸਵਾਈਪ-ਸਮੀਖਿਆ ਸਕਰੀਨ.',
  'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
    'TidyByte ਤੁਹਾਡੀ ਪੂਰੀ ਲਾਇਬ੍ਰੇਰੀ ਨਾਲ ਕੰਮ ਕਰਦਾ ਹੈ, ਸਿਰਫ਼ iCloud ਵਿੱਚ ਸੰਭਾਲੀਆਂ ਆਈਟਮਾਂ ਸਮੇਤ. ਸਿਸਟਮ ਲੋੜ ਅਨੁਸਾਰ ਉਹਨਾਂ ਨੂੰ ਡਾਊਨਲੋਡ ਕਰਦਾ ਹੈ; ਤੁਸੀਂ ਬਿਨਾਂ ਉਡੀਕੇ ਸਵਾਈਪ ਕਰਕੇ ਅੱਗੇ ਵੀ ਜਾ ਸਕਦੇ ਹੋ.',
  'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
    'ਬਾਰਾਂ ਸਫ਼ਾਈ ਟੂਲ, ਨਾਲ ਹੀ ਸਟੋਰੇਜ ਦੀ ਜਾਣਕਾਰੀ, ਸਫ਼ਾਈ ਇਤਿਹਾਸ ਅਤੇ ਡੀਵਾਈਸ ਉੱਤੇ ਹੀ AI ਖੋਜ &mdash; ਸਭ ਤੁਹਾਡੇ ਡੀਵਾਈਸ ਉੱਤੇ ਚੱਲਦੇ ਹਨ. ਕਿਸੇ ਵੀ ਇੱਕ ਉੱਤੇ ਟੈਪ ਕਰੋ ਅਤੇ ਵੇਖੋ ਇਹ ਕਿਵੇਂ ਕੰਮ ਕਰਦਾ ਹੈ.',
  'Video compression': 'ਵੀਡੀਓ ਕੰਪਰੈਸ਼ਨ',
  Videos: 'ਵੀਡੀਓ',
  'View on GitHub &rarr;': 'GitHub ਉੱਤੇ ਵੇਖੋ &rarr;',
  'We can&rsquo;t see your photos. We don&rsquo;t want to.':
    'ਅਸੀਂ ਤੁਹਾਡੀਆਂ ਫ਼ੋਟੋਆਂ ਨਹੀਂ ਵੇਖ ਸਕਦੇ. ਵੇਖਣਾ ਵੀ ਨਹੀਂ ਚਾਹੁੰਦੇ.',
  'What about iCloud-only photos?': 'ਸਿਰਫ਼ iCloud ਵਾਲੀਆਂ ਫ਼ੋਟੋਆਂ ਬਾਰੇ ਕੀ?',
  'Will it lower the quality of my photos?': 'ਕੀ ਇਹ ਮੇਰੀਆਂ ਫ਼ੋਟੋਆਂ ਦੀ ਕੁਆਲਿਟੀ ਘਟਾਏਗਾ?',
  'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
    'ਹਾਂ. TidyByte ਇੱਕ ਯੂਨੀਵਰਸਲ ਐਪ ਹੈ ਜੋ iPhone ਅਤੇ iPad ਉੱਤੇ ਨੈਟਿਵ ਚੱਲਦੀ ਹੈ. ਹਰ ਸਫ਼ਾਈ ਟੂਲ ਦੋਵਾਂ ਉੱਤੇ ਕੰਮ ਕਰਦਾ ਹੈ, ਸਵਾਈਪ ਇੰਟਰਫ਼ੇਸ iPad ਦੀ ਵੱਡੀ ਸਕਰੀਨ ਨਾਲ ਢਲ ਜਾਂਦਾ ਹੈ, ਅਤੇ iPad ਸਾਰੀਆਂ ਦਿਸ਼ਾਵਾਂ ਨੂੰ ਸਪੋਰਟ ਕਰਦਾ ਹੈ.',
  'Your photos never leave your phone.': 'ਤੁਹਾਡੀਆਂ ਫ਼ੋਟੋਆਂ ਕਦੇ ਵੀ ਤੁਹਾਡਾ ਫ਼ੋਨ ਨਹੀਂ ਛੱਡਦੀਆਂ.',
  'bytes uploaded, ever': 'ਕਦੇ ਵੀ ਅੱਪਲੋਡ ਹੋਏ ਬਾਈਟ',
  'cleanup tools': 'ਸਫ਼ਾਈ ਟੂਲ',
  'how it compares to subscription photo cleaners':
    'ਸਬਸਕ੍ਰਿਪਸ਼ਨ ਫ਼ੋਟੋ ਕਲੀਨਰਾਂ ਨਾਲ ਇਹ ਕਿਵੇਂ ਤੁਲਨਾ ਕਰਦਾ ਹੈ',
  'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
    'ਹਿਸਾਬ ਰੱਖਦੀ ਹੈ: ਤੁਸੀਂ ਜੋ ਸਾਫ਼ ਕੀਤਾ, 30 ਦਿਨਾਂ ਦਾ ਚਾਰਟ, ਅਤੇ ਖਾਲੀ ਕੀਤੀ ਕੁੱਲ ਥਾਂ. Home Screen ਵਿਜੇਟ ਅਤੇ Siri ਸ਼ਾਰਟਕਟ ਸਿੱਧਾ ਸਫ਼ਾਈ ਵਿੱਚ ਲੈ ਜਾਂਦੇ ਹਨ.',
  'open source, MIT': 'ਓਪਨ ਸੋਰਸ, MIT',
  'or use the contact form on the': 'ਜਾਂ ਸੰਪਰਕ ਫਾਰਮ ਵਰਤੋ',
  'page.': 'ਪੰਨੇ ਉੱਤੇ.',
  'photo library': 'ਫ਼ੋਟੋ ਲਾਇਬ੍ਰੇਰੀ',
  'to own it outright': 'ਪੂਰੀ ਮਾਲਕੀ ਲਈ',
};

translations.ta = {
  '01 &mdash; How it works': '01 &mdash; இது எப்படி வேலை செய்கிறது',
  '02 &mdash; Cleanup toolkit': '02 &mdash; சுத்தக் கருவிகள்',
  '03 &mdash; Storage dashboard': '03 &mdash; சேமிப்பக டாஷ்போர்டு',
  '04 &mdash; Privacy': '04 &mdash; தனியுரிமை',
  '05 &mdash; Open source': '05 &mdash; திறந்த மூலம்',
  '06 &mdash; FAQ': '06 &mdash; அடிக்கடி கேட்கும் கேள்விகள்',
  '07 &mdash; Get the app': '07 &mdash; ஆப்பைப் பெறுங்கள்',
  '64 GB': '64 GB',
  'A donut chart of your library by type, plus the largest files.':
    'வகை வாரியாக உங்கள் நூலகத்தின் டோனட் விளக்கப்படம், மிகப் பெரிய கோப்புகளுடன்.',
  'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
    'உங்கள் சேமிப்பகம் எங்கே செல்கிறது எனக் காட்டும் நேரடி டோனட் விளக்கப்படம் &mdash; புகைப்படங்கள், வீடியோக்கள், ஸ்கிரீன்ஷாட்கள், Live Photos, மற்றவை. தட்டக்கூடிய துண்டுகள் நீங்கள் காலி செய்யக்கூடிய சரியான உருப்படிகளுக்கு அழைத்துச் செல்கின்றன.',
  'A swipe session in progress &mdash; one photo, one decision.':
    'நடந்துகொண்டிருக்கும் ஸ்வைப் அமர்வு &mdash; ஒரு புகைப்படம், ஒரு முடிவு.',
  'AI photo search': 'AI புகைப்படத் தேடல்',
  'Activity &amp; savings': 'செயல்பாடு &amp; சேமிப்பு',
  'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
    'அனைத்து செயலாக்கமும் சாதனத்திலேயே நடக்கிறது, Apple-இன் Vision மற்றும் Photos கட்டமைப்புகளைப் பயன்படுத்தி.',
  'Are deleted photos gone immediately?': 'நீக்கிய புகைப்படங்கள் உடனே போய்விடுமா?',
  'Blurry photos': 'மங்கலான புகைப்படங்கள்',
  'Burst photos': 'பர்ஸ்ட் புகைப்படங்கள்',
  'Chat media': 'அரட்டை மீடியா',
  'Clay illustration of a teal vault keeping smiling photo cards safe.':
    'புன்னகைக்கும் புகைப்பட அட்டைகளைப் பாதுகாக்கும் டீல் நிறப் பெட்டகத்தின் களிமண் ஓவியம்.',
  'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
    'பசுமையான மலைகளில் ஒரு ஃபோன் புகைப்பட அட்டைகளை வகைப்படுத்தும் தட்டில் போடும் களிமண்-பாணி ஓவியம்.',
  'Clean your library in minutes.': 'உங்கள் நூலகத்தை சில நிமிடங்களில் சுத்தம் செய்யுங்கள்.',
  'Cleanup history': 'சுத்த வரலாறு',
  'Clear them in one pass': 'ஒரே முயற்சியில் அவற்றை சுத்தம் செய்யுங்கள்',
  'Clear what WhatsApp and Telegram saved.':
    'WhatsApp மற்றும் Telegram சேமித்ததை சுத்தம் செய்யுங்கள்.',
  'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
    'ஒருமுறை உறுதிப்படுத்துங்கள், இடம் திரும்பி வரும். நீக்கிய படங்கள் சமீபத்தில் நீக்கியவை-இல் 30 நாட்கள் காத்திருக்கும்.',
  'Convert to stills to save space.': 'இடத்தைச் சேமிக்க நிலைப் படங்களாக மாற்றுங்கள்.',
  'Describe a photo in plain words, find it on-device.':
    'ஒரு புகைப்படத்தை எளிய வார்த்தைகளில் விவரியுங்கள், அது சாதனத்திலேயே கிடைக்கும்.',
  'Does TidyByte support iPad?': 'TidyByte iPad-ஐ ஆதரிக்கிறதா?',
  'Does TidyByte upload my photos?': 'TidyByte என் புகைப்படங்களை பதிவேற்றுகிறதா?',
  'Download TidyByte Free': 'TidyByte Free-ஐப் பதிவிறக்குங்கள்',
  Duplicates: 'நகல்கள்',
  'Every delete and compression decision, recorded on-device and reviewable.':
    'ஒவ்வொரு நீக்கம் மற்றும் சுருக்க முடிவும் சாதனத்தில் பதிவாகி, பார்க்கக்கூடியதாக இருக்கும்.',
  'Every kind of clutter, handled.': 'எல்லா வகையான குப்பைகளும், கையாளப்பட்டன.',
  'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
    'சரியான நகல்கள் கோப்புத் தரவின் SHA-256 ஹாஷ் மூலம் பொருத்தப்படுகின்றன. அருகாமை நகல்கள் காட்சியில் ஒத்த படங்களைக் கண்டறிய Apple Vision அம்ச அச்சுகளைப் பயன்படுத்துகின்றன.',
  'Find exact copies, byte-for-byte.': 'சரியான நகல்களை, பைட்-பைட் கண்டறியுங்கள்.',
  'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
    'இலவசம் &middot; iPhone &amp; iPad &middot; iOS 17+',
  'Frequently asked questions.': 'அடிக்கடி கேட்கப்படும் கேள்விகள்.',
  'Group near-identical shots.': 'கிட்டத்தட்ட ஒரே மாதிரியான படங்களை ஒன்றாக்குங்கள்.',
  'How are duplicates detected?': 'நகல்கள் எப்படிக் கண்டறியப்படுகின்றன?',
  'How do I report a bug or request a feature?':
    'பிழையை எப்படிப் புகாரளிப்பது அல்லது புதிய அம்சத்தை எப்படிக் கேட்பது?',
  'How it works': 'இது எப்படி வேலை செய்கிறது',
  'Is there a free trial or subscription?': 'இலவச சோதனை அல்லது சந்தா உள்ளதா?',
  'Large files': 'பெரிய கோப்புகள்',
  'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
    'இடது நீக்கும், வலது வைத்திருக்கும். எதையும் தொடுவதற்கு முன் ஒவ்வொரு தேர்வும் மறுஆய்வுப் பட்டியலில் சேரும்.',
  'Live Photos': 'Live Photos',
  'New in 1.0.5 &mdash; on-device AI photo search':
    '1.0.5-இல் புதியது &mdash; சாதனத்திலேயே AI புகைப்படத் தேடல்',
  'No account': 'கணக்கு தேவையில்லை',
  'No account to create. No subscription to manage. Just one swipe at a time.':
    'உருவாக்க கணக்கு இல்லை. நிர்வகிக்க சந்தா இல்லை. ஒரு நேரத்தில் ஒரு ஸ்வைப் மட்டும்.',
  'No ads': 'விளம்பரங்கள் இல்லை',
  'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
    'பகுப்பாய்வு SDK இல்லை, பின்தளம் இல்லை, மூன்றாம் தரப்பு ஸ்கிரிப்ட் இல்லை, கண்காணிப்பு இல்லை &mdash; எங்கும்.',
  'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
    'எந்த சுத்தக் கருவியும் அசல் கோப்புகளைத் தொடாது. மீண்டும் குறியாக்கம் செய்யும் ஒரே செயல், நீங்கள் திறக்கும் வீடியோ சுருக்கம் அல்லது புகைப்பட சுருக்கக் கருவி மட்டுமே, மேலும் முன்னமைவை நீங்கள் தேர்வு செய்கிறீர்கள்.',
  'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
    'இல்லை. அனைத்து செயலாக்கமும் உங்கள் iPhone-இல் உள்ளூரிலேயே நடக்கிறது, Apple-இன் Photos மற்றும் Vision கட்டமைப்புகளைப் பயன்படுத்தி &mdash; பகுப்பாய்வு SDK இல்லை, பின்தளம் இல்லை, கண்காணிப்பு இல்லை.',
  'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
    'ஒரு அட்டை. ஒரு முடிவு. உங்கள் காபி குளிர்வதற்கு முன்பே பல வருடப் புகைப்படங்களை சுத்தம் செய்வீர்கள்.',
  'Open an issue on': 'இஷ்யூ திறக்கவும்',
  Other: 'மற்றவை',
  'Photo compression': 'புகைப்பட சுருக்கம்',
  'Photos never leave your phone': 'புகைப்படங்கள் உங்கள் ஃபோனை விட்டு வெளியேறாது',
  'Pick the best from a sequence.': 'ஒரு தொடரில் சிறந்ததைத் தேர்ந்தெடுங்கள்.',
  'Pick where to start': 'எங்கே தொடங்குவது எனத் தேர்ந்தெடுங்கள்',
  'Re-encode photos to reclaim space.':
    'இடத்தை மீட்டெடுக்க புகைப்படங்களை மீண்டும் குறியாக்குங்கள்.',
  'Read every line that touches your photos.':
    'உங்கள் புகைப்படங்களைத் தொடும் ஒவ்வொரு வரியையும் படியுங்கள்.',
  'Read the privacy policy': 'தனியுரிமைக் கொள்கையைப் படியுங்கள்',
  'Round up and clear them in one pass.':
    'ஒன்றாக சேகரித்து ஒரே முயற்சியில் சுத்தம் செய்யுங்கள்.',
  'Screen recordings': 'திரைப் பதிவுகள்',
  Screenshots: 'ஸ்கிரீன்ஷாட்கள்',
  'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
    'ஸ்கிரீன்ஷாட்கள், நகல்கள், மங்கலான படங்கள் அல்லது உங்கள் முழு நூலகம். ஒவ்வொரு கருவியும் புகைப்பட அட்டைகளின் தொகுப்பைத் திறக்கிறது.',
  'See exactly what&rsquo;s using your space.':
    'உங்கள் இடத்தை சரியாக எது பயன்படுத்துகிறது என்று பாருங்கள்.',
  'See how it works': 'இது எப்படி வேலை செய்கிறது என்று பாருங்கள்',
  'See what changed &rarr;': 'என்ன மாறியது என்று பாருங்கள் &rarr;',
  'Shrink videos, keep them watchable.':
    'வீடியோக்களைச் சுருக்கி, பார்க்கக்கூடியதாக வைத்திருங்கள்.',
  'Similar photos': 'ஒத்த புகைப்படங்கள்',
  'Smart categories': 'ஸ்மார்ட் வகைகள்',
  'Sort by content type, browse faster.':
    'உள்ளடக்க வகை வாரியாக வரிசைப்படுத்தி, வேகமாகப் பாருங்கள்.',
  'Spot out-of-focus and shaky shots.':
    'கவனம் குறைந்த மற்றும் அசைந்த படங்களைக் கண்டறியுங்கள்.',
  'Storage breakdown': 'சேமிப்பக பிரிவு',
  Support: 'ஆதரவு',
  'Surface the biggest space hogs.':
    'அதிக இடத்தை எடுக்கும் கோப்புகளை முன்னுக்குக் கொண்டு வாருங்கள்.',
  'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
    'இடதுபுறம் ஸ்வைப் செய்தால் நீக்கும், வலதுபுறம் ஸ்வைப் செய்தால் வைத்திருக்கும் &mdash; சில நிமிடங்களில் ஜிகாபைட்டுகளை மீட்டெடுங்கள். நகல்கள், ஸ்கிரீன்ஷாட்கள், அரட்டை மீடியா, மங்கலான படங்கள் மற்றும் மிகப் பெரிய வீடியோக்கள் கையாளப்பட்டன, படங்கள் சுருக்கப்பட்டன, 100% சாதனத்தில். விளம்பரங்கள் இல்லை, சந்தா இல்லை, கணக்கு இல்லை.',
  'Swipe to decide': 'ஸ்வைப் செய்து முடிவு செய்யுங்கள்',
  'The best free iPhone storage cleaner and photo cleaner.':
    'iPhone-க்கான சிறந்த இலவச சேமிப்பக கிளீனர் மற்றும் புகைப்பட கிளீனர்.',
  'The largest files nobody remembers making.': 'யாருக்கும் நினைவில்லாத மிகப் பெரிய கோப்புகள்.',
  'The swipe, explained.': 'ஸ்வைப், எளிமையாக விளக்கப்பட்டது.',
  'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
    'அவை iOS-இன் சமீபத்தில் நீக்கியவை ஆல்பத்திற்குச் செல்கின்றன, அங்கு நிரந்தரமாக அகற்றப்படுவதற்கு முன் 30 நாட்கள் இருக்கும் &mdash; Photos ஆப்-இல் நீக்குவது போலவே.',
  'TidyByte in numbers': 'எண்களில் TidyByte',
  'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
    'TidyByte MIT உரிமத்தில் உள்ளது. மூலக் குறியீட்டைப் படியுங்கள், கூற்றுகளைச் சரிபாருங்கள், இஷ்யூ திறக்கவும்.',
  'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
    'TidyByte இலவசம், ஆப்-உள்ளே வாங்குதல்கள் இல்லை, கட்டணச் சுவர்கள் இல்லை. ஒவ்வொரு அம்சமும் ஒவ்வொரு பயனருக்கும் கிடைக்கிறது. பாருங்கள்',
  'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
    'புகைப்படங்கள், வீடியோக்கள், ஸ்கிரீன்ஷாட்கள், Live Photos மற்றும் மற்றவற்றின் டோனட் விளக்கப்படத்துடன் TidyByte சேமிப்பக டாஷ்போர்டு.',
  'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
    'திரையில் ஒரு புகைப்பட அட்டையும் கீழே நீக்கு மற்றும் வைத்திரு பொத்தான்களும் கொண்ட TidyByte ஸ்வைப் அமர்வு.',
  'TidyByte swipe-review screen mid-session.': 'அமர்வின் நடுவில் TidyByte ஸ்வைப் மறுஆய்வுத் திரை.',
  'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
    'TidyByte உங்கள் முழு நூலகத்துடன் வேலை செய்கிறது, iCloud-இல் மட்டும் சேமிக்கப்பட்ட உருப்படிகள் உட்பட. தேவைப்படும்போது சிஸ்டம் அவற்றைப் பதிவிறக்கும்; காத்திருக்காமல் ஸ்வைப் செய்து செல்லவும் முடியும்.',
  'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
    'பன்னிரண்டு சுத்தக் கருவிகள், சேமிப்பக நுண்ணறிவு, சுத்த வரலாறு மற்றும் சாதனத்திலேயே AI தேடல் &mdash; அனைத்தும் உங்கள் சாதனத்தில் இயங்குகின்றன. எதையாவது தட்டி அது எப்படி வேலை செய்கிறது எனப் பாருங்கள்.',
  'Video compression': 'வீடியோ சுருக்கம்',
  Videos: 'வீடியோக்கள்',
  'View on GitHub &rarr;': 'GitHub-இல் பாருங்கள் &rarr;',
  'We can&rsquo;t see your photos. We don&rsquo;t want to.':
    'உங்கள் புகைப்படங்களை எங்களால் பார்க்க முடியாது. பார்க்கவும் விரும்பவில்லை.',
  'What about iCloud-only photos?': 'iCloud-இல் மட்டும் உள்ள புகைப்படங்கள் என்ன?',
  'Will it lower the quality of my photos?': 'இது என் புகைப்படங்களின் தரத்தைக் குறைக்குமா?',
  'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
    'ஆம். TidyByte என்பது iPhone மற்றும் iPad-இல் இயல்பாக இயங்கும் யுனிவர்சல் ஆப். ஒவ்வொரு சுத்தக் கருவியும் இரண்டிலும் வேலை செய்கிறது, ஸ்வைப் இடைமுகம் iPad-இன் பெரிய திரைக்கு ஏற்ப மாறுகிறது, iPad எல்லா திசைகளையும் ஆதரிக்கிறது.',
  'Your photos never leave your phone.': 'உங்கள் புகைப்படங்கள் உங்கள் ஃபோனை விட்டு வெளியேறாது.',
  'bytes uploaded, ever': 'இதுவரை பதிவேற்றப்பட்ட பைட்டுகள்',
  'cleanup tools': 'சுத்தக் கருவிகள்',
  'how it compares to subscription photo cleaners':
    'சந்தா புகைப்பட கிளீனர்களுடன் இது எப்படி ஒப்பிடப்படுகிறது',
  'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
    'கணக்கு வைக்கிறது: நீங்கள் சுத்தம் செய்த அனைத்தும், 30 நாள் விளக்கப்படம், மற்றும் விடுவிக்கப்பட்ட மொத்த இடம். Home Screen விட்ஜெட் மற்றும் Siri குறுக்குவழிகள் நேரடியாக ஒரு சுத்தத்திற்கு அழைத்துச் செல்லும்.',
  'open source, MIT': 'திறந்த மூலம், MIT',
  'or use the contact form on the': 'அல்லது தொடர்பு படிவத்தைப் பயன்படுத்துங்கள்',
  'page.': 'பக்கத்தில்.',
  'photo library': 'புகைப்பட நூலகம்',
  'to own it outright': 'முழு உரிமைக்காக',
};

// --- Guards -----------------------------------------------------------------

const langs = ['mr', 'gu', 'pa', 'ta'];
const sourceSet = new Set(sourceStrings);
let failures = 0;

for (const lang of langs) {
  const map = translations[lang];
  if (!map) {
    console.error(`FAIL: no data for ${lang}`);
    failures += 1;
    continue;
  }
  const keys = Object.keys(map);
  if (keys.length !== sourceStrings.length) {
    console.error(
      `FAIL: ${lang} has ${keys.length} keys, source has ${sourceStrings.length}`,
    );
    failures += 1;
  }
  const missing = sourceStrings.filter((s) => !(s in map));
  const extra = keys.filter((k) => !sourceSet.has(k));
  if (missing.length) {
    console.error(`FAIL: ${lang} missing ${missing.length} key(s):`);
    for (const m of missing) console.error(`   ${JSON.stringify(m)}`);
    failures += 1;
  }
  if (extra.length) {
    console.error(`FAIL: ${lang} has ${extra.length} key(s) not in source:`);
    for (const e of extra) console.error(`   ${JSON.stringify(e)}`);
    failures += 1;
  }
}

if (failures > 0) {
  console.error(`\n${failures} problem(s); nothing written.`);
  process.exit(1);
}

mkdirSync(OUT_DIR, { recursive: true });

for (const lang of langs) {
  // Key order follows the source file so a diff against it reads in page order.
  const ordered = {};
  for (const s of sourceStrings) ordered[s] = translations[lang][s];
  const path = join(OUT_DIR, `${lang}.json`);
  writeFileSync(path, `${JSON.stringify(ordered, null, 2)}\n`);
  console.log(`written ${path} (${Object.keys(ordered).length} strings)`);
}
