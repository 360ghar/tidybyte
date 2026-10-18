// Batch 7 insertion: 57 new keys into mr/gu/pa/ta.
// Textual insertion so the hand-formatted `plurals` block is never re-serialized.
//
// NOTE: `_batch7-brief.md` enumerates 56 keys but the batch is 57 (495 -> 552).
// The missing entry is the `PhotoCompressionError.encodeFailed` case,
// "Failed to re-encode the photo.", which sits in the same converted
// `errorDescription` switch as the other seven compression-error keys and is
// absent from every translation file.
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))

const translations = {
  mr: {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Screen Time किंवा डिव्हाइस-व्यवस्थापनाची मर्यादा फोटो प्रवेश रोखत आहे. सेटिंग्जमधील फोटो स्विच हे बदलू शकत नाही — आधी ती मर्यादा हटवावी लागेल.",
    "A lens smudge may have reduced image clarity.": "लेन्सवरील डागामुळे प्रतिमेची स्पष्टता कमी झाली असू शकते.",
    "Allow Photo Access?": "फोटो प्रवेशाची परवानगी द्यायची?",
    "Already compressed": "आधीच कंप्रेस केलेले",
    "Cancelled.": "रद्द केले.",
    "Choose albums or change your filters.": "अल्बम निवडा किंवा फिल्टर बदला.",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "व्हिडिओ लोड करता आला नाही (तो अजून iCloud मध्ये असू शकतो). पुन्हा प्रयत्न करा.",
    "Dark": "गडद",
    "Export failed: %@": "एक्सपोर्ट करता आले नाही: %@",
    "Exported file was empty.": "एक्सपोर्ट केलेली फाइल रिकामी होती.",
    "Failed to create export session.": "एक्सपोर्ट सेशन तयार करता आले नाही.",
    "Failed to load the photo.": "फोटो लोड करता आला नाही.",
    "Failed to read file size.": "फाइलचा आकार वाचता आला नाही.",
    "Failed to re-encode the photo.": "फोटो पुन्हा एन्कोड करता आला नाही.",
    "Light": "हलका",
    "Local AI could not interpret this search.": "स्थानिक AI हा शोध समजू शकले नाही.",
    "Local AI is unavailable.": "स्थानिक AI उपलब्ध नाही.",
    "No matching photos": "जुळणारे फोटो नाहीत",
    "No photos in this category.": "या श्रेणीत फोटो नाहीत.",
    "No screen recordings were found.": "कोणतेही स्क्रीन रेकॉर्डिंग आढळले नाहीत.",
    "Not Now": "आता नको",
    "Nothing to free on iPhone": "iPhone वर मोकळे करण्यासारखे काही नाही",
    "Open TidyByte to refresh": "रिफ्रेश करण्यासाठी TidyByte उघडा",
    "Photo Access Is Off": "फोटो प्रवेश बंद आहे",
    "Photo Access Is On": "फोटो प्रवेश सुरू आहे",
    "Photo Access Is Restricted": "फोटो प्रवेश मर्यादित आहे",
    "Photo not found.": "फोटो आढळला नाही.",
    "Photo size unknown (iCloud-only) — skipped.": "फोटोचा आकार माहीत नाही (फक्त iCloud मध्ये) — वगळला.",
    "Review whether you still need this screen recording.": "हे स्क्रीन रेकॉर्डिंग अजून हवे आहे का ते तपासा.",
    "Review whether you still need this screenshot.": "हा स्क्रीनशॉट अजून हवा आहे का ते तपासा.",
    "Save failed: %@": "सेव्ह करता आले नाही: %@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "शोध फक्त दिसणाऱ्या सामग्रीसाठी आहे, उदा. समुद्रकिनाऱ्यावरचे कुत्रे. तारखा, ठिकाणे, नावे आणि मजकूर अनुक्रमित केले जात नाहीत.",
    "Searching labels across all scanned categories.": "सर्व स्कॅन केलेल्या श्रेणींमध्ये लेबल शोधत आहे.",
    "Size unknown (iCloud-only) — skipped": "आकार माहीत नाही (फक्त iCloud मध्ये) — वगळले",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "या स्कॅनमध्ये काही मागितलेल्या संकल्पना आढळल्या नाहीत. सोपा सामग्री-शोध वापरून पहा.",
    "Submit a content search or try different words.": "सामग्री-शोध सबमिट करा किंवा वेगळे शब्द वापरून पहा.",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "हे शब्द समर्थित लेबल शोध तयार करत नाहीत. कुत्रा किंवा समुद्रकिनारा यांसारखी दिसणारी सामग्री वापरून पहा. लेबल शोध तारखा, नावे किंवा वगळणी वापरू शकत नाही.",
    "This item can't be compressed as a photo.": "हा आयटम फोटो म्हणून कंप्रेस करता येत नाही.",
    "This item uses %@; review whether you need it.": "हा आयटम %@ वापरतो; त्याची गरज आहे का ते तपासा.",
    "This language is not supported by local AI.": "या भाषेला स्थानिक AI चा आधार नाही.",
    "This photo has very high brightness.": "या फोटोची चमक खूप जास्त आहे.",
    "This photo has very low brightness.": "या फोटोची चमक खूप कमी आहे.",
    "This photo may be out of focus.": "हा फोटो फोकसबाहेर असू शकतो.",
    "This photo received a low visual-quality score.": "या फोटोला दृश्य-गुणवत्तेचा कमी गुण मिळाला.",
    "TidyByte Needs Your Photos": "TidyByte ला तुमच्या फोटोंची गरज आहे",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "TidyByte फक्त तुम्ही निवडलेले फोटो पाहू शकते. उरलेल्या लायब्ररीचे पुनरावलोकन करायचे असेल तेव्हा अधिक फोटो जोडा.",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByte या डिव्हाइसवर तुमच्या लायब्ररीचे पुनरावलोकन करू शकते. काहीही अपलोड होत नाही आणि तुमच्या मंजुरीशिवाय काहीही बदलत नाही.",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByte या डिव्हाइसवर तुमच्या लायब्ररीचे पुनरावलोकन करून काय स्वच्छ करण्यासारखे आहे ते शोधते. काहीही अपलोड होत नाही आणि तुमच्या मंजुरीशिवाय काहीही बदलत नाही. पुढे iOS प्रवेश मागेल.",
    "Unknown error": "अज्ञात त्रुटी",
    "Up to %@ to free on iPhone": "iPhone वर %@ पर्यंत मोकळे करता येईल",
    "Updated %lldd ago": "%lld दि पूर्वी अपडेट केले",
    "Use 300 characters or fewer.": "300 किंवा कमी अक्षरे वापरा.",
    "Using label search across scanned photos.": "स्कॅन केलेल्या फोटोंमध्ये लेबल शोध वापरत आहे.",
    "Video not found.": "व्हिडिओ आढळला नाही.",
    "Video size unknown (iCloud-only) — skipped.": "व्हिडिओचा आकार माहीत नाही (फक्त iCloud मध्ये) — वगळला.",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOS फोटो प्रवेशासाठी फक्त एकदाच विचारते आणि ही तीच वेळ आहे. त्यानंतर TidyByte या डिव्हाइसवर तुमच्या लायब्ररीचे पुनरावलोकन करते. काहीही अपलोड होत नाही आणि तुमच्या पुनरावलोकनाशिवाय काहीही बदलत नाही.",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOS TidyByte ला तुमच्या लायब्ररीतून प्रवेश देत नाही आणि ते पुन्हा विचारणार नाही. परत जाण्याचा एकमेव मार्ग सेटिंग्ज आहे — तिथे फोटो प्रवेश सुरू करा आणि इथले सर्व पुन्हा काम करू लागेल.",
  },
  gu: {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Screen Time અથવા ડિવાઇસ-મેનેજમેન્ટની મર્યાદા ફોટો ઍક્સેસ રોકે છે. સેટિંગ્સમાંનું ફોટો સ્વિચ તેને બદલી શકતું નથી — પહેલા તે મર્યાદા દૂર કરવી પડશે.",
    "A lens smudge may have reduced image clarity.": "લેન્સ પરના ડાઘને કારણે છબીની સ્પષ્ટતા ઘટી હોઈ શકે છે.",
    "Allow Photo Access?": "ફોટો ઍક્સેસની મંજૂરી આપવી?",
    "Already compressed": "પહેલેથી જ કોમ્પ્રેસ કરેલું",
    "Cancelled.": "રદ કર્યું.",
    "Choose albums or change your filters.": "આલ્બમ પસંદ કરો અથવા ફિલ્ટર બદલો.",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "વિડિયો લોડ કરી શકાયો નથી (તે હજી iCloud માં હોઈ શકે છે). ફરી પ્રયાસ કરો.",
    "Dark": "ઘેરું",
    "Export failed: %@": "એક્સપોર્ટ કરી શકાયું નથી: %@",
    "Exported file was empty.": "એક્સપોર્ટ કરેલી ફાઇલ ખાલી હતી.",
    "Failed to create export session.": "એક્સપોર્ટ સેશન બનાવી શકાયું નથી.",
    "Failed to load the photo.": "ફોટો લોડ કરી શકાયો નથી.",
    "Failed to read file size.": "ફાઇલની સાઇઝ વાંચી શકાઈ નથી.",
    "Failed to re-encode the photo.": "ફોટો ફરી એન્કોડ કરી શકાયો નથી.",
    "Light": "હળવું",
    "Local AI could not interpret this search.": "સ્થાનિક AI આ શોધ સમજી શક્યું નથી.",
    "Local AI is unavailable.": "સ્થાનિક AI ઉપલબ્ધ નથી.",
    "No matching photos": "કોઈ મળતા ફોટા નથી",
    "No photos in this category.": "આ શ્રેણીમાં ફોટા નથી.",
    "No screen recordings were found.": "કોઈ સ્ક્રીન રેકોર્ડિંગ મળ્યાં નથી.",
    "Not Now": "હમણાં નહીં",
    "Nothing to free on iPhone": "iPhone પર ખાલી કરવા જેવું કંઈ નથી",
    "Open TidyByte to refresh": "રિફ્રેશ કરવા TidyByte ખોલો",
    "Photo Access Is Off": "ફોટો ઍક્સેસ બંધ છે",
    "Photo Access Is On": "ફોટો ઍક્સેસ ચાલુ છે",
    "Photo Access Is Restricted": "ફોટો ઍક્સેસ પ્રતિબંધિત છે",
    "Photo not found.": "ફોટો મળ્યો નથી.",
    "Photo size unknown (iCloud-only) — skipped.": "ફોટાની સાઇઝ અજાણી (ફક્ત iCloud માં) — છોડી દીધો.",
    "Review whether you still need this screen recording.": "આ સ્ક્રીન રેકોર્ડિંગ હજી જોઈએ છે કે નહીં તે તપાસો.",
    "Review whether you still need this screenshot.": "આ સ્ક્રીનશોટ હજી જોઈએ છે કે નહીં તે તપાસો.",
    "Save failed: %@": "સાચવી શકાયું નથી: %@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "શોધ ફક્ત દેખાતી સામગ્રી માટે છે, જેમ કે દરિયાકિનારે કૂતરા. તારીખો, સ્થળો, નામો અને લખાણ અનુક્રમિત થતાં નથી.",
    "Searching labels across all scanned categories.": "બધી સ્કેન કરેલી શ્રેણીઓમાં લેબલ શોધી રહ્યું છે.",
    "Size unknown (iCloud-only) — skipped": "સાઇઝ અજાણી (ફક્ત iCloud માં) — છોડી દીધું",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "આ સ્કેનમાં માંગેલી કેટલીક વિભાવનાઓ મળી નથી. સરળ સામગ્રી શોધ અજમાવો.",
    "Submit a content search or try different words.": "સામગ્રી શોધ સબમિટ કરો અથવા બીજા શબ્દો અજમાવો.",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "આ શબ્દો સમર્થિત લેબલ શોધ બનાવતા નથી. કૂતરો કે દરિયાકિનારો જેવી દેખાતી સામગ્રી અજમાવો. લેબલ શોધ તારીખો, નામો કે બાકાત રાખવાને ટેકો આપતી નથી.",
    "This item can't be compressed as a photo.": "આ આઇટમને ફોટા તરીકે કોમ્પ્રેસ કરી શકાતી નથી.",
    "This item uses %@; review whether you need it.": "આ આઇટમ %@ વાપરે છે; તેની જરૂર છે કે નહીં તે તપાસો.",
    "This language is not supported by local AI.": "આ ભાષાને સ્થાનિક AI નો આધાર નથી.",
    "This photo has very high brightness.": "આ ફોટાની ચમક બહુ વધારે છે.",
    "This photo has very low brightness.": "આ ફોટાની ચમક બહુ ઓછી છે.",
    "This photo may be out of focus.": "આ ફોટો ફોકસ બહાર હોઈ શકે છે.",
    "This photo received a low visual-quality score.": "આ ફોટાને દૃશ્ય-ગુણવત્તાનો ઓછો સ્કોર મળ્યો.",
    "TidyByte Needs Your Photos": "TidyByte ને તમારા ફોટા જોઈએ છે",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "TidyByte ફક્ત તમે પસંદ કરેલા ફોટા જોઈ શકે છે. બાકીની લાઇબ્રેરીની સમીક્ષા કરવી હોય ત્યારે વધુ ફોટા ઉમેરો.",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByte આ ડિવાઇસ પર તમારી લાઇબ્રેરીની સમીક્ષા કરી શકે છે. કંઈ પણ અપલોડ થતું નથી અને તમારી મંજૂરી વિના કંઈ બદલાતું નથી.",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByte આ ડિવાઇસ પર તમારી લાઇબ્રેરીની સમીક્ષા કરીને શું સાફ કરવા લાયક છે તે શોધે છે. કંઈ પણ અપલોડ થતું નથી અને તમારી મંજૂરી વિના કંઈ બદલાતું નથી. હવે iOS ઍક્સેસ માગશે.",
    "Unknown error": "અજાણી ભૂલ",
    "Up to %@ to free on iPhone": "iPhone પર %@ સુધી ખાલી કરી શકાય",
    "Updated %lldd ago": "%lld દિ પહેલાં અપડેટ થયું",
    "Use 300 characters or fewer.": "300 કે તેથી ઓછા અક્ષરો વાપરો.",
    "Using label search across scanned photos.": "સ્કેન કરેલા ફોટામાં લેબલ શોધ વાપરી રહ્યું છે.",
    "Video not found.": "વિડિયો મળ્યો નથી.",
    "Video size unknown (iCloud-only) — skipped.": "વિડિયોની સાઇઝ અજાણી (ફક્ત iCloud માં) — છોડી દીધો.",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOS ફોટો ઍક્સેસ માટે ફક્ત એક જ વાર પૂછે છે અને આ તે જ વાર છે. પછી TidyByte આ ડિવાઇસ પર તમારી લાઇબ્રેરીની સમીક્ષા કરે છે. કંઈ પણ અપલોડ થતું નથી અને તમારી સમીક્ષા વિના કંઈ બદલાતું નથી.",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOS TidyByte ને તમારી લાઇબ્રેરીમાંથી અટકાવે છે અને હવે ફરી પૂછશે નહીં. પાછા આવવાનો એક જ રસ્તો સેટિંગ્સ છે — ત્યાં ફોટો ઍક્સેસ ચાલુ કરો અને અહીં બધું ફરી કામ કરવા લાગશે.",
  },
  pa: {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Screen Time ਜਾਂ ਡੀਵਾਈਸ-ਪ੍ਰਬੰਧਨ ਦੀ ਪਾਬੰਦੀ ਫ਼ੋਟੋ ਪਹੁੰਚ ਨੂੰ ਰੋਕ ਰਹੀ ਹੈ. ਸੈਟਿੰਗਾਂ ਵਿੱਚਲਾ ਫ਼ੋਟੋ ਸਵਿੱਚ ਇਸਨੂੰ ਬਦਲ ਨਹੀਂ ਸਕਦਾ — ਪਹਿਲਾਂ ਉਹ ਪਾਬੰਦੀ ਹਟਾਉਣੀ ਪਵੇਗੀ.",
    "A lens smudge may have reduced image clarity.": "ਲੈਂਸ ਉੱਤੇ ਧੱਬੇ ਕਾਰਨ ਤਸਵੀਰ ਦੀ ਸਪਸ਼ਟਤਾ ਘੱਟ ਹੋ ਸਕਦੀ ਹੈ.",
    "Allow Photo Access?": "ਫ਼ੋਟੋ ਪਹੁੰਚ ਦੀ ਆਗਿਆ ਦੇਣੀ ਹੈ?",
    "Already compressed": "ਪਹਿਲਾਂ ਹੀ ਕੰਪ੍ਰੈਸ ਕੀਤੀ",
    "Cancelled.": "ਰੱਦ ਕੀਤਾ.",
    "Choose albums or change your filters.": "ਐਲਬਮਾਂ ਚੁਣੋ ਜਾਂ ਫ਼ਿਲਟਰ ਬਦਲੋ.",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "ਵੀਡੀਓ ਲੋਡ ਨਹੀਂ ਹੋ ਸਕਿਆ (ਇਹ ਹਾਲੇ ਵੀ iCloud ਵਿੱਚ ਹੋ ਸਕਦਾ ਹੈ). ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "Dark": "ਗੂੜ੍ਹਾ",
    "Export failed: %@": "ਐਕਸਪੋਰਟ ਨਹੀਂ ਹੋ ਸਕਿਆ: %@",
    "Exported file was empty.": "ਐਕਸਪੋਰਟ ਕੀਤੀ ਫ਼ਾਈਲ ਖਾਲੀ ਸੀ.",
    "Failed to create export session.": "ਐਕਸਪੋਰਟ ਸੈਸ਼ਨ ਨਹੀਂ ਬਣਾਇਆ ਜਾ ਸਕਿਆ.",
    "Failed to load the photo.": "ਫ਼ੋਟੋ ਲੋਡ ਨਹੀਂ ਹੋ ਸਕੀ.",
    "Failed to read file size.": "ਫ਼ਾਈਲ ਦਾ ਆਕਾਰ ਪੜ੍ਹਿਆ ਨਹੀਂ ਜਾ ਸਕਿਆ.",
    "Failed to re-encode the photo.": "ਫ਼ੋਟੋ ਦੁਬਾਰਾ ਐਨਕੋਡ ਨਹੀਂ ਹੋ ਸਕੀ.",
    "Light": "ਹਲਕਾ",
    "Local AI could not interpret this search.": "ਸਥਾਨਕ AI ਇਸ ਖੋਜ ਨੂੰ ਸਮਝ ਨਹੀਂ ਸਕਿਆ.",
    "Local AI is unavailable.": "ਸਥਾਨਕ AI ਉਪਲਬਧ ਨਹੀਂ ਹੈ.",
    "No matching photos": "ਕੋਈ ਮੇਲ ਖਾਂਦੀ ਫ਼ੋਟੋ ਨਹੀਂ",
    "No photos in this category.": "ਇਸ ਸ਼੍ਰੇਣੀ ਵਿੱਚ ਕੋਈ ਫ਼ੋਟੋ ਨਹੀਂ.",
    "No screen recordings were found.": "ਕੋਈ ਸਕਰੀਨ ਰਿਕਾਰਡਿੰਗ ਨਹੀਂ ਮਿਲੀ.",
    "Not Now": "ਹੁਣ ਨਹੀਂ",
    "Nothing to free on iPhone": "iPhone ਉੱਤੇ ਖਾਲੀ ਕਰਨ ਲਈ ਕੁਝ ਨਹੀਂ",
    "Open TidyByte to refresh": "ਰਿਫ਼ਰੈਸ਼ ਕਰਨ ਲਈ TidyByte ਖੋਲ੍ਹੋ",
    "Photo Access Is Off": "ਫ਼ੋਟੋ ਪਹੁੰਚ ਬੰਦ ਹੈ",
    "Photo Access Is On": "ਫ਼ੋਟੋ ਪਹੁੰਚ ਚਾਲੂ ਹੈ",
    "Photo Access Is Restricted": "ਫ਼ੋਟੋ ਪਹੁੰਚ ਸੀਮਤ ਹੈ",
    "Photo not found.": "ਫ਼ੋਟੋ ਨਹੀਂ ਮਿਲੀ.",
    "Photo size unknown (iCloud-only) — skipped.": "ਫ਼ੋਟੋ ਦਾ ਆਕਾਰ ਅਣਜਾਣ (ਸਿਰਫ਼ iCloud ਵਿੱਚ) — ਛੱਡੀ ਗਈ.",
    "Review whether you still need this screen recording.": "ਇਹ ਸਕਰੀਨ ਰਿਕਾਰਡਿੰਗ ਹਾਲੇ ਵੀ ਲੋੜੀਂਦੀ ਹੈ ਕਿ ਨਹੀਂ, ਵੇਖੋ.",
    "Review whether you still need this screenshot.": "ਇਹ ਸਕਰੀਨਸ਼ਾਟ ਹਾਲੇ ਵੀ ਲੋੜੀਂਦਾ ਹੈ ਕਿ ਨਹੀਂ, ਵੇਖੋ.",
    "Save failed: %@": "ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਿਆ: %@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "ਖੋਜ ਸਿਰਫ਼ ਦਿਖਣ ਵਾਲੀ ਸਮੱਗਰੀ ਲਈ ਹੈ, ਜਿਵੇਂ ਸਮੁੰਦਰ ਕੰਢੇ ਕੁੱਤੇ. ਤਾਰੀਖਾਂ, ਥਾਵਾਂ, ਨਾਮ ਅਤੇ ਲਿਖਤ ਸੂਚੀਬੱਧ ਨਹੀਂ ਹੁੰਦੇ.",
    "Searching labels across all scanned categories.": "ਸਾਰੀਆਂ ਸਕੈਨ ਕੀਤੀਆਂ ਸ਼੍ਰੇਣੀਆਂ ਵਿੱਚ ਲੇਬਲ ਖੋਜ ਚੱਲ ਰਹੀ ਹੈ.",
    "Size unknown (iCloud-only) — skipped": "ਆਕਾਰ ਅਣਜਾਣ (ਸਿਰਫ਼ iCloud ਵਿੱਚ) — ਛੱਡੀ ਗਈ",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "ਇਸ ਸਕੈਨ ਵਿੱਚ ਮੰਗੇ ਕੁਝ ਵਿਚਾਰ ਨਹੀਂ ਮਿਲੇ. ਸੌਖੀ ਸਮੱਗਰੀ ਖੋਜ ਅਜ਼ਮਾਓ.",
    "Submit a content search or try different words.": "ਸਮੱਗਰੀ ਖੋਜ ਭੇਜੋ ਜਾਂ ਹੋਰ ਸ਼ਬਦ ਅਜ਼ਮਾਓ.",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "ਇਹ ਸ਼ਬਦ ਸਮਰਥਿਤ ਲੇਬਲ ਖੋਜ ਨਹੀਂ ਬਣਾਉਂਦੇ. ਕੁੱਤਾ ਜਾਂ ਸਮੁੰਦਰ ਕੰਢਾ ਵਰਗੀ ਦਿਖਣ ਵਾਲੀ ਸਮੱਗਰੀ ਅਜ਼ਮਾਓ. ਲੇਬਲ ਖੋਜ ਤਾਰੀਖਾਂ, ਨਾਮ ਜਾਂ ਬਾਹਰ ਰੱਖਣ ਦਾ ਸਮਰਥਨ ਨਹੀਂ ਕਰਦੀ.",
    "This item can't be compressed as a photo.": "ਇਹ ਆਈਟਮ ਫ਼ੋਟੋ ਵਜੋਂ ਕੰਪ੍ਰੈਸ ਨਹੀਂ ਕੀਤੀ ਜਾ ਸਕਦੀ.",
    "This item uses %@; review whether you need it.": "ਇਹ ਆਈਟਮ %@ ਵਰਤਦੀ ਹੈ; ਇਸਦੀ ਲੋੜ ਹੈ ਕਿ ਨਹੀਂ, ਵੇਖੋ.",
    "This language is not supported by local AI.": "ਇਸ ਭਾਸ਼ਾ ਨੂੰ ਸਥਾਨਕ AI ਦਾ ਸਮਰਥਨ ਨਹੀਂ ਹੈ.",
    "This photo has very high brightness.": "ਇਸ ਫ਼ੋਟੋ ਦੀ ਚਮਕ ਬਹੁਤ ਵੱਧ ਹੈ.",
    "This photo has very low brightness.": "ਇਸ ਫ਼ੋਟੋ ਦੀ ਚਮਕ ਬਹੁਤ ਘੱਟ ਹੈ.",
    "This photo may be out of focus.": "ਇਹ ਫ਼ੋਟੋ ਫੋਕਸ ਤੋਂ ਬਾਹਰ ਹੋ ਸਕਦੀ ਹੈ.",
    "This photo received a low visual-quality score.": "ਇਸ ਫ਼ੋਟੋ ਨੂੰ ਦਿੱਖ-ਗੁਣਵੱਤਾ ਦਾ ਘੱਟ ਸਕੋਰ ਮਿਲਿਆ.",
    "TidyByte Needs Your Photos": "TidyByte ਨੂੰ ਤੁਹਾਡੀਆਂ ਫ਼ੋਟੋਆਂ ਦੀ ਲੋੜ ਹੈ",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "TidyByte ਸਿਰਫ਼ ਉਹ ਫ਼ੋਟੋਆਂ ਦੇਖ ਸਕਦਾ ਹੈ ਜੋ ਤੁਸੀਂ ਚੁਣੀਆਂ. ਬਾਕੀ ਲਾਇਬ੍ਰੇਰੀ ਦੀ ਸਮੀਖਿਆ ਕਰਨ ਲਈ ਜਦੋਂ ਚਾਹੋ ਹੋਰ ਫ਼ੋਟੋਆਂ ਸ਼ਾਮਲ ਕਰੋ.",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByte ਇਸ ਡੀਵਾਈਸ ਉੱਤੇ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਦੀ ਸਮੀਖਿਆ ਕਰ ਸਕਦਾ ਹੈ. ਕੁਝ ਵੀ ਅੱਪਲੋਡ ਨਹੀਂ ਹੁੰਦਾ ਅਤੇ ਤੁਹਾਡੀ ਮਨਜ਼ੂਰੀ ਤੋਂ ਬਿਨਾਂ ਕੁਝ ਨਹੀਂ ਬਦਲਦਾ.",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByte ਇਸ ਡੀਵਾਈਸ ਉੱਤੇ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਦੀ ਸਮੀਖਿਆ ਕਰਕੇ ਲੱਭਦਾ ਹੈ ਕਿ ਕੀ ਸਾਫ਼ ਕਰਨ ਯੋਗ ਹੈ. ਕੁਝ ਵੀ ਅੱਪਲੋਡ ਨਹੀਂ ਹੁੰਦਾ ਅਤੇ ਤੁਹਾਡੀ ਮਨਜ਼ੂਰੀ ਤੋਂ ਬਿਨਾਂ ਕੁਝ ਨਹੀਂ ਬਦਲਦਾ. ਅੱਗੇ iOS ਪਹੁੰਚ ਮੰਗੇਗਾ.",
    "Unknown error": "ਅਣਜਾਣ ਗਲਤੀ",
    "Up to %@ to free on iPhone": "iPhone ਉੱਤੇ %@ ਤੱਕ ਖਾਲੀ ਕੀਤਾ ਜਾ ਸਕਦਾ ਹੈ",
    "Updated %lldd ago": "%lld ਦਿ ਪਹਿਲਾਂ ਅੱਪਡੇਟ ਕੀਤਾ",
    "Use 300 characters or fewer.": "300 ਜਾਂ ਇਸ ਤੋਂ ਘੱਟ ਅੱਖਰ ਵਰਤੋ.",
    "Using label search across scanned photos.": "ਸਕੈਨ ਕੀਤੀਆਂ ਫ਼ੋਟੋਆਂ ਵਿੱਚ ਲੇਬਲ ਖੋਜ ਵਰਤੀ ਜਾ ਰਹੀ ਹੈ.",
    "Video not found.": "ਵੀਡੀਓ ਨਹੀਂ ਮਿਲਿਆ.",
    "Video size unknown (iCloud-only) — skipped.": "ਵੀਡੀਓ ਦਾ ਆਕਾਰ ਅਣਜਾਣ (ਸਿਰਫ਼ iCloud ਵਿੱਚ) — ਛੱਡਿਆ ਗਿਆ.",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOS ਫ਼ੋਟੋ ਪਹੁੰਚ ਲਈ ਸਿਰਫ਼ ਇੱਕ ਵਾਰ ਪੁੱਛਦਾ ਹੈ ਅਤੇ ਇਹ ਉਹੀ ਵਾਰ ਹੈ. ਫਿਰ TidyByte ਇਸ ਡੀਵਾਈਸ ਉੱਤੇ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਦੀ ਸਮੀਖਿਆ ਕਰਦਾ ਹੈ. ਕੁਝ ਵੀ ਅੱਪਲੋਡ ਨਹੀਂ ਹੁੰਦਾ ਅਤੇ ਤੁਹਾਡੀ ਸਮੀਖਿਆ ਤੋਂ ਬਿਨਾਂ ਕੁਝ ਨਹੀਂ ਬਦਲਦਾ.",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOS TidyByte ਨੂੰ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਤੋਂ ਰੋਕ ਰਿਹਾ ਹੈ ਅਤੇ ਹੁਣ ਦੁਬਾਰਾ ਨਹੀਂ ਪੁੱਛੇਗਾ. ਵਾਪਸ ਆਉਣ ਦਾ ਇੱਕੋ ਰਾਹ ਸੈਟਿੰਗਾਂ ਹੈ — ਉੱਥੇ ਫ਼ੋਟੋ ਪਹੁੰਚ ਚਾਲੂ ਕਰੋ ਅਤੇ ਇੱਥੇ ਸਭ ਕੁਝ ਫਿਰ ਕੰਮ ਕਰਨ ਲੱਗੇਗਾ.",
  },
  ta: {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Screen Time அல்லது சாதன-நிர்வாகக் கட்டுப்பாடு புகைப்பட அணுகலைத் தடுக்கிறது. அமைப்புகளில் உள்ள புகைப்படம் சுவிட்ச் அதை மாற்ற முடியாது — அந்தக் கட்டுப்பாட்டை முதலில் நீக்க வேண்டும்.",
    "A lens smudge may have reduced image clarity.": "லென்ஸில் உள்ள கறையால் படத்தின் தெளிவு குறைந்திருக்கலாம்.",
    "Allow Photo Access?": "புகைப்பட அணுகலை அனுமதிக்கவா?",
    "Already compressed": "ஏற்கனவே சுருக்கப்பட்டது",
    "Cancelled.": "ரத்து செய்யப்பட்டது.",
    "Choose albums or change your filters.": "ஆல்பங்களைத் தேர்ந்தெடுக்கவும் அல்லது வடிகட்டிகளை மாற்றவும்.",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "வீடியோவை ஏற்ற முடியவில்லை (அது இன்னும் iCloud-இல் இருக்கலாம்). மீண்டும் முயற்சி செய்யுங்கள்.",
    "Dark": "இருள்",
    "Export failed: %@": "ஏற்றுமதி தோல்வியடைந்தது: %@",
    "Exported file was empty.": "ஏற்றுமதி செய்யப்பட்ட கோப்பு காலியாக இருந்தது.",
    "Failed to create export session.": "ஏற்றுமதி அமர்வை உருவாக்க முடியவில்லை.",
    "Failed to load the photo.": "புகைப்படத்தை ஏற்ற முடியவில்லை.",
    "Failed to read file size.": "கோப்பு அளவைப் படிக்க முடியவில்லை.",
    "Failed to re-encode the photo.": "புகைப்படத்தை மீண்டும் என்கோட் செய்ய முடியவில்லை.",
    "Light": "ஒளி",
    "Local AI could not interpret this search.": "உள்ளூர் AI இந்தத் தேடலைப் புரிந்துகொள்ள முடியவில்லை.",
    "Local AI is unavailable.": "உள்ளூர் AI கிடைக்கவில்லை.",
    "No matching photos": "பொருந்தும் புகைப்படங்கள் இல்லை",
    "No photos in this category.": "இந்த வகையில் புகைப்படங்கள் இல்லை.",
    "No screen recordings were found.": "திரைப் பதிவுகள் எதுவும் கிடைக்கவில்லை.",
    "Not Now": "இப்போது வேண்டாம்",
    "Nothing to free on iPhone": "iPhone-இல் காலி செய்ய எதுவும் இல்லை",
    "Open TidyByte to refresh": "புதுப்பிக்க TidyByte-ஐத் திற",
    "Photo Access Is Off": "புகைப்பட அணுகல் அணைக்கப்பட்டுள்ளது",
    "Photo Access Is On": "புகைப்பட அணுகல் இயக்கத்தில் உள்ளது",
    "Photo Access Is Restricted": "புகைப்பட அணுகல் வரம்புக்குட்பட்டுள்ளது",
    "Photo not found.": "புகைப்படம் கிடைக்கவில்லை.",
    "Photo size unknown (iCloud-only) — skipped.": "புகைப்பட அளவு தெரியவில்லை (iCloud-இல் மட்டும்) — தவிர்க்கப்பட்டது.",
    "Review whether you still need this screen recording.": "இந்தத் திரைப் பதிவு இன்னும் உங்களுக்குத் தேவையா எனப் பாருங்கள்.",
    "Review whether you still need this screenshot.": "இந்த ஸ்கிரீன்ஷாட் இன்னும் உங்களுக்குத் தேவையா எனப் பாருங்கள்.",
    "Save failed: %@": "சேமிக்க முடியவில்லை: %@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "தேடல் கண்ணுக்குத் தெரியும் உள்ளடக்கத்திற்கு மட்டுமே, உதாரணமாக கடற்கரையில் நாய்கள். தேதிகள், இடங்கள், பெயர்கள், எழுத்து ஆகியவை குறியிடப்படுவதில்லை.",
    "Searching labels across all scanned categories.": "ஸ்கேன் செய்யப்பட்ட அனைத்து வகைகளிலும் லேபிள்கள் தேடப்படுகின்றன.",
    "Size unknown (iCloud-only) — skipped": "அளவு தெரியவில்லை (iCloud-இல் மட்டும்) — தவிர்க்கப்பட்டது",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "இந்த ஸ்கேனில் கேட்ட சில கருத்துகள் கிடைக்கவில்லை. எளிமையான உள்ளடக்கத் தேடலை முயற்சி செய்யுங்கள்.",
    "Submit a content search or try different words.": "உள்ளடக்கத் தேடலைச் சமர்ப்பிக்கவும் அல்லது வேறு வார்த்தைகளை முயற்சி செய்யவும்.",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "இந்த வார்த்தைகள் ஆதரிக்கப்படும் லேபிள் தேடலை உருவாக்கவில்லை. நாய் அல்லது கடற்கரை போன்ற கண்ணுக்குத் தெரியும் உள்ளடக்கத்தை முயற்சி செய்யுங்கள். லேபிள் தேடல் தேதிகள், பெயர்கள், விலக்கல்களை ஆதரிக்காது.",
    "This item can't be compressed as a photo.": "இந்த உருப்படியை புகைப்படமாகச் சுருக்க முடியாது.",
    "This item uses %@; review whether you need it.": "இந்த உருப்படி %@ பயன்படுத்துகிறது; உங்களுக்கு இது தேவையா எனப் பாருங்கள்.",
    "This language is not supported by local AI.": "இந்த மொழிக்கு உள்ளூர் AI ஆதரவு இல்லை.",
    "This photo has very high brightness.": "இந்தப் புகைப்படத்தின் ஒளிர்வு மிக அதிகம்.",
    "This photo has very low brightness.": "இந்தப் புகைப்படத்தின் ஒளிர்வு மிகக் குறைவு.",
    "This photo may be out of focus.": "இந்தப் புகைப்படம் கவனம் விலகி இருக்கலாம்.",
    "This photo received a low visual-quality score.": "இந்தப் புகைப்படத்திற்குக் காட்சித் தர மதிப்பெண் குறைவாக இருந்தது.",
    "TidyByte Needs Your Photos": "TidyByte-க்கு உங்கள் புகைப்படங்கள் தேவை",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "நீங்கள் தேர்ந்தெடுத்த புகைப்படங்களை மட்டுமே TidyByte பார்க்க முடியும். மீதமுள்ள நூலகத்தை மதிப்பாய்வு செய்ய வேண்டும்போது மேலும் புகைப்படங்களைச் சேர்க்கலாம்.",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByte இந்தச் சாதனத்தில் உங்கள் நூலகத்தை மதிப்பாய்வு செய்ய முடியும். எதுவும் பதிவேற்றப்படாது, உங்கள் ஒப்புதல் இல்லாமல் எதுவும் மாறாது.",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByte இந்தச் சாதனத்தில் உங்கள் நூலகத்தை மதிப்பாய்வு செய்து, சுத்தம் செய்யத் தகுந்தவை எவை எனக் கண்டறியும். எதுவும் பதிவேற்றப்படாது, உங்கள் ஒப்புதல் இல்லாமல் எதுவும் மாறாது. அடுத்து iOS அணுகலைக் கேட்கும்.",
    "Unknown error": "தெரியாத பிழை",
    "Up to %@ to free on iPhone": "iPhone-இல் %@ வரை காலி செய்யலாம்",
    "Updated %lldd ago": "%lld நா முன்பு புதுப்பிக்கப்பட்டது",
    "Use 300 characters or fewer.": "300 அல்லது அதற்குக் குறைவான எழுத்துகளைப் பயன்படுத்துங்கள்.",
    "Using label search across scanned photos.": "ஸ்கேன் செய்த புகைப்படங்களில் லேபிள் தேடல் பயன்படுத்தப்படுகிறது.",
    "Video not found.": "வீடியோ கிடைக்கவில்லை.",
    "Video size unknown (iCloud-only) — skipped.": "வீடியோ அளவு தெரியவில்லை (iCloud-இல் மட்டும்) — தவிர்க்கப்பட்டது.",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOS புகைப்பட அணுகலை ஒரே ஒரு முறை மட்டுமே கேட்கும், அதுவே இது. பின்னர் TidyByte இந்தச் சாதனத்தில் உங்கள் நூலகத்தை மதிப்பாய்வு செய்யும். எதுவும் பதிவேற்றப்படாது, உங்கள் மதிப்பாய்வு இல்லாமல் எதுவும் மாறாது.",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOS TidyByte-ஐ உங்கள் நூலகத்திலிருந்து தடுக்கிறது, இனி மீண்டும் கேட்காது. திரும்ப வழி அமைப்புகள் மட்டுமே — அங்கே புகைப்பட அணுகலை இயக்கினால் இங்குள்ள அனைத்தும் மீண்டும் வேலை செய்யத் தொடங்கும்.",
  },
}

const langs = ['mr', 'gu', 'pa', 'ta']
const EXPECTED_ADDITIONS = 57
const problems = []

for (const lang of langs) {
  const path = join(dir, `${lang}.json`)
  const before = readFileSync(path, 'utf8')
  const parsedBefore = JSON.parse(before)
  const priorStrings = { ...parsedBefore.strings }
  const additions = translations[lang]

  if (Object.keys(additions).length !== EXPECTED_ADDITIONS) {
    problems.push(`${lang}: expected ${EXPECTED_ADDITIONS} additions, got ${Object.keys(additions).length}`)
    continue
  }
  for (const k of Object.keys(additions)) {
    if (k in priorStrings) problems.push(`${lang}: key already existed: ${k}`)
    if (!additions[k] || !additions[k].trim()) problems.push(`${lang}: empty translation for: ${k}`)
  }

  const merged = { ...priorStrings, ...additions }
  const entries = Object.keys(merged)
    .sort()
    .map((k) => `    ${JSON.stringify(k)}: ${JSON.stringify(merged[k])}`)
    .join(',\n')
  const block = `  "strings": {\n${entries}\n  }`

  const start = before.indexOf('  "strings": {')
  if (start === -1) { problems.push(`${lang}: strings block not found`); continue }
  const end = before.indexOf('\n  },', start)
  if (end === -1) { problems.push(`${lang}: strings block end not found`); continue }
  if (!before.slice(end + 5, end + 5 + 15).startsWith('\n  "plurals"')) {
    problems.push(`${lang}: unexpected text after strings block: ${JSON.stringify(before.slice(end + 5, end + 40))}`)
    continue
  }

  const after = before.slice(0, start) + block + before.slice(end + 4)
  const reparsed = JSON.parse(after)

  // invariants
  const priorKeys = Object.keys(priorStrings)
  if (Object.keys(reparsed.strings).length !== priorKeys.length + EXPECTED_ADDITIONS) {
    problems.push(`${lang}: key count ${Object.keys(reparsed.strings).length} != ${priorKeys.length + EXPECTED_ADDITIONS}`)
  }
  for (const k of priorKeys) {
    if (reparsed.strings[k] !== priorStrings[k]) problems.push(`${lang}: pre-existing key changed: ${k}`)
  }
  if (JSON.stringify(reparsed.plurals) !== JSON.stringify(parsedBefore.plurals)) {
    problems.push(`${lang}: plurals section changed`)
  }
  if (!after.endsWith('\n')) problems.push(`${lang}: lost trailing newline`)

  if (problems.length) continue

  writeFileSync(path, after)
  console.log(`${lang}: ${priorKeys.length} -> ${Object.keys(reparsed.strings).length} keys (plurals untouched)`)
}

if (problems.length) {
  console.error('\nPROBLEMS:')
  for (const p of problems) console.error(' -', p)
  process.exit(1)
}
console.log('\nall four files written, invariants hold')
