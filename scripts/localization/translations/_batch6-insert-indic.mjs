// Batch 6 insertion: 64 new keys into mr/gu/pa/ta.
// Textual insertion so the hand-formatted `plurals` block is never re-serialized.
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))

const translations = {
  mr: {
    "Access to Your Photos": "तुमच्या फोटोंमध्ये प्रवेश",
    "All Clear": "सर्व ठीक",
    "Analyzing photos...": "फोटोंचे विश्लेषण होत आहे...",
    "Compressed photos and videos will appear here.": "कंप्रेस केलेले फोटो आणि व्हिडिओ इथे दिसतील.",
    "Deletion Error": "हटवताना त्रुटी",
    "Detect Low-Quality Photos": "कमी दर्जाचे फोटो ओळखा",
    "File Size": "फाइलचा आकार",
    "Find Duplicate Photos": "डुप्लिकेट फोटो शोधा",
    "Find Similar Photos": "समान फोटो शोधा",
    "Find blurry, too dark, and overexposed photos.": "अस्पष्ट, खूप गडद आणि खूप तेजस्वी फोटो शोधा.",
    "Group photos into memes, documents, food, pets, nature, selfies and media saved from other apps.": "फोटो मीम, दस्तऐवज, अन्न, पाळीव प्राणी, निसर्ग, सेल्फी आणि इतर अ‍ॅप्समधून सेव्ह केलेल्या मीडियामध्ये गटबद्ध करा.",
    "Grouping similar photos...": "समान फोटो गटबद्ध करत आहे...",
    "Groups photos taken within %lld seconds of each other.": "एकमेकांच्या %lld सेकंदांच्या आत घेतलेले फोटो गटबद्ध करते.",
    "No Albums": "अल्बम नाहीत",
    "No Burst Photos": "बर्स्ट फोटो नाहीत",
    "No Duplicates Found": "डुप्लिकेट आढळले नाहीत",
    "No History": "इतिहास नाही",
    "No Large Photos": "मोठे फोटो नाहीत",
    "No Live Photos": "Live Photos नाहीत",
    "No Media": "मीडिया नाही",
    "No Photos": "फोटो नाहीत",
    "No Savings Yet": "अजून बचत नाही",
    "No Screenshots": "स्क्रीनशॉट नाहीत",
    "No Similar Photos Found": "समान फोटो आढळले नाहीत",
    "No Videos": "व्हिडिओ नाहीत",
    "No albums with photos were found.": "फोटो असलेले कोणतेही अल्बम आढळले नाहीत.",
    "No issues found in this category.": "या श्रेणीत कोणतीही अडचण आढळली नाही.",
    "No matching media": "जुळणारे मीडिया नाही",
    "No more Live Photos": "आणखी Live Photos नाहीत",
    "No more items": "आणखी आयटम नाहीत",
    "No photos over 2 MB are left to compress. HEIC photos are already small.": "कंप्रेस करण्यासाठी 2 MB पेक्षा मोठे फोटो उरलेले नाहीत. HEIC फोटो आधीच लहान असतात.",
    "Not Enough Space": "पुरेशी जागा नाही",
    "Nothing Leaves Your Device": "काहीही तुमचे डिव्हाइस सोडत नाही",
    "Nothing to Sort": "क्रमवारी लावण्यासारखे काही नाही",
    "Organize by Content": "सामग्रीनुसार व्यवस्थित करा",
    "Resolution": "रिझोल्यूशन",
    "Review one photo at a time. Swipe left to delete, right to keep, or up to file it into an album — and undo anything by mistake.": "एका वेळी एक फोटो पहा. हटवण्यासाठी डावीकडे, ठेवण्यासाठी उजवीकडे किंवा अल्बममध्ये ठेवण्यासाठी वर स्वाइप करा — आणि चुकून केलेले काहीही पूर्ववत करा.",
    "Scan Again": "पुन्हा स्कॅन करा",
    "Scan your library for exact and visually similar duplicates.": "अगदी सारखे आणि दिसण्यात सारखे डुप्लिकेट शोधण्यासाठी तुमच्या लायब्ररीचे स्कॅन करा.",
    "Scanning for duplicates...": "डुप्लिकेट शोधण्यासाठी स्कॅन करत आहे...",
    "Scans your library and sorts photos by what's in them": "तुमच्या लायब्ररीचे स्कॅन करते आणि फोटोमध्ये काय आहे त्यानुसार क्रमवारी लावते",
    "Scans your library for out-of-focus and poorly lit photos": "फोकसबाहेर आणि कमी प्रकाशातील फोटो शोधण्यासाठी तुमच्या लायब्ररीचे स्कॅन करते",
    "Scans your library for photos taken close together": "जवळपास घेतलेले फोटो शोधण्यासाठी तुमच्या लायब्ररीचे स्कॅन करते",
    "Scans your whole library for duplicates": "तुमच्या संपूर्ण लायब्ररीत डुप्लिकेट शोधते",
    "Show All Photos": "सर्व फोटो दाखवा",
    "Something went wrong": "काहीतरी चूक झाली",
    "Sorting photos...": "फोटोंची क्रमवारी लावत आहे...",
    "Space you free up with any cleanup tool shows up here.": "कोणत्याही क्लीनअप साधनाने तुम्ही मोकळी केलेली जागा इथे दिसते.",
    "Start Analysis": "विश्लेषण सुरू करा",
    "Start Scan": "स्कॅन सुरू करा",
    "Swipe Through Your Library": "तुमच्या लायब्ररीतून स्वाइप करा",
    "There isn't enough free space to compress the selected photos. Free up some space and try again.": "निवडलेले फोटो कंप्रेस करण्यासाठी पुरेशी मोकळी जागा नाही. थोडी जागा मोकळी करा आणि पुन्हा प्रयत्न करा.",
    "There isn't enough free space to compress the selected videos. Free up some space and try again.": "निवडलेले व्हिडिओ कंप्रेस करण्यासाठी पुरेशी मोकळी जागा नाही. थोडी जागा मोकळी करा आणि पुन्हा प्रयत्न करा.",
    "TidyByte has no account and no servers. Every scan, comparison, and analysis runs right here on this device.": "TidyByte मध्ये खाते नाही आणि सर्व्हर नाहीत. प्रत्येक स्कॅन, तुलना आणि विश्लेषण इथेच या डिव्हाइसवर चालते.",
    "TidyByte reads your library to find duplicates, blurry shots, and oversized files. It only ever changes what you approve. iOS will ask for permission next.": "डुप्लिकेट, अस्पष्ट फोटो आणि खूप मोठ्या फाइल्स शोधण्यासाठी TidyByte तुमच्या लायब्ररीतून वाचते. तुम्ही मंजूर केलेलेच ते बदलते. पुढे iOS परवानगी विचारेल.",
    "We couldn't sort any photos into categories.": "आम्हाला कोणतेही फोटो श्रेणींमध्ये वर्गीकृत करता आले नाहीत.",
    "You don't have any Live Photos in your library.": "तुमच्या लायब्ररीत कोणतेही Live Photos नाहीत.",
    "You don't have any burst photo groups.": "तुमच्याकडे बर्स्ट फोटोंचे कोणतेही गट नाहीत.",
    "You don't have any photos to compress.": "कंप्रेस करण्यासाठी तुमच्याकडे कोणतेही फोटो नाहीत.",
    "You don't have any screenshots in your library.": "तुमच्या लायब्ररीत कोणतेही स्क्रीनशॉट नाहीत.",
    "You don't have any videos in your library.": "तुमच्या लायब्ररीत कोणतेही व्हिडिओ नाहीत.",
    "Your library is empty.": "तुमची लायब्ररी रिकामी आहे.",
    "Your library looks clean!": "तुमची लायब्ररी स्वच्छ दिसते!",
    "Your photo library is clean!": "तुमची फोटो लायब्ररी स्वच्छ आहे!",
  },
  gu: {
    "Access to Your Photos": "તમારા ફોટા માટે ઍક્સેસ",
    "All Clear": "બધું બરાબર",
    "Analyzing photos...": "ફોટાનું વિશ્લેષણ થઈ રહ્યું છે...",
    "Compressed photos and videos will appear here.": "કોમ્પ્રેસ કરેલા ફોટા અને વિડિયો અહીં દેખાશે.",
    "Deletion Error": "કાઢી નાખવામાં ભૂલ",
    "Detect Low-Quality Photos": "નીચી ગુણવત્તાવાળા ફોટા શોધી કાઢો",
    "File Size": "ફાઇલ સાઇઝ",
    "Find Duplicate Photos": "ડુપ્લિકેટ ફોટા શોધો",
    "Find Similar Photos": "સમાન ફોટા શોધો",
    "Find blurry, too dark, and overexposed photos.": "ઝાંખા, બહુ ઘેરા અને બહુ તેજસ્વી ફોટા શોધો.",
    "Group photos into memes, documents, food, pets, nature, selfies and media saved from other apps.": "ફોટાને મીમ્સ, દસ્તાવેજો, ખોરાક, પાળતુ પ્રાણી, પ્રકૃતિ, સેલ્ફી અને બીજી એપ્સમાંથી સાચવેલા મીડિયામાં ગોઠવો.",
    "Grouping similar photos...": "સમાન ફોટાને જૂથમાં ગોઠવી રહ્યું છે...",
    "Groups photos taken within %lld seconds of each other.": "એકબીજાથી %lld સેકંડની અંદર લીધેલા ફોટાને જૂથમાં ગોઠવે છે.",
    "No Albums": "કોઈ આલ્બમ નથી",
    "No Burst Photos": "કોઈ બર્સ્ટ ફોટા નથી",
    "No Duplicates Found": "કોઈ ડુપ્લિકેટ મળ્યા નથી",
    "No History": "કોઈ ઇતિહાસ નથી",
    "No Large Photos": "કોઈ મોટા ફોટા નથી",
    "No Live Photos": "કોઈ Live Photos નથી",
    "No Media": "કોઈ મીડિયા નથી",
    "No Photos": "કોઈ ફોટા નથી",
    "No Savings Yet": "હજી બચત નથી",
    "No Screenshots": "કોઈ સ્ક્રીનશોટ નથી",
    "No Similar Photos Found": "કોઈ સમાન ફોટા મળ્યા નથી",
    "No Videos": "કોઈ વિડિયો નથી",
    "No albums with photos were found.": "ફોટા ધરાવતું કોઈ આલ્બમ મળ્યું નથી.",
    "No issues found in this category.": "આ શ્રેણીમાં કોઈ સમસ્યા મળી નથી.",
    "No matching media": "કોઈ મળતું મીડિયા નથી",
    "No more Live Photos": "વધુ Live Photos નથી",
    "No more items": "વધુ આઇટમ નથી",
    "No photos over 2 MB are left to compress. HEIC photos are already small.": "કોમ્પ્રેસ કરવા માટે 2 MB થી મોટા ફોટા બાકી નથી. HEIC ફોટા પહેલેથી જ નાના હોય છે.",
    "Not Enough Space": "પૂરતી જગ્યા નથી",
    "Nothing Leaves Your Device": "કંઈ પણ તમારું ડિવાઇસ છોડતું નથી",
    "Nothing to Sort": "ગોઠવવા માટે કંઈ નથી",
    "Organize by Content": "સામગ્રી પ્રમાણે ગોઠવો",
    "Resolution": "રિઝોલ્યુશન",
    "Review one photo at a time. Swipe left to delete, right to keep, or up to file it into an album — and undo anything by mistake.": "એક સમયે એક ફોટો જુઓ. કાઢી નાખવા માટે ડાબે, રાખવા માટે જમણે અથવા આલ્બમમાં મૂકવા માટે ઉપર સ્વાઇપ કરો — અને ભૂલથી કંઈ કરી નાખ્યું હોય તો પાછું લાવો.",
    "Scan Again": "ફરી સ્કેન કરો",
    "Scan your library for exact and visually similar duplicates.": "એકદમ સરખા અને દેખાવમાં સરખા ડુપ્લિકેટ માટે તમારી લાઇબ્રેરી સ્કેન કરો.",
    "Scanning for duplicates...": "ડુપ્લિકેટ માટે સ્કેન થઈ રહ્યું છે...",
    "Scans your library and sorts photos by what's in them": "તમારી લાઇબ્રેરી સ્કેન કરે છે અને ફોટામાં શું છે તે પ્રમાણે ગોઠવે છે",
    "Scans your library for out-of-focus and poorly lit photos": "ફોકસ બહાર અને ઓછા પ્રકાશવાળા ફોટા માટે તમારી લાઇબ્રેરી સ્કેન કરે છે",
    "Scans your library for photos taken close together": "નજીકમાં લેવાયેલા ફોટા માટે તમારી લાઇબ્રેરી સ્કેન કરે છે",
    "Scans your whole library for duplicates": "તમારી આખી લાઇબ્રેરીમાં ડુપ્લિકેટ શોધે છે",
    "Show All Photos": "બધા ફોટા બતાવો",
    "Something went wrong": "કંઈક ખોટું થયું",
    "Sorting photos...": "ફોટા ગોઠવી રહ્યું છે...",
    "Space you free up with any cleanup tool shows up here.": "કોઈપણ ક્લીનઅપ ટૂલથી તમે ખાલી કરેલી જગ્યા અહીં દેખાય છે.",
    "Start Analysis": "વિશ્લેષણ શરૂ કરો",
    "Start Scan": "સ્કેન શરૂ કરો",
    "Swipe Through Your Library": "તમારી લાઇબ્રેરીમાં સ્વાઇપ કરો",
    "There isn't enough free space to compress the selected photos. Free up some space and try again.": "પસંદ કરેલા ફોટા કોમ્પ્રેસ કરવા માટે પૂરતી ખાલી જગ્યા નથી. થોડી જગ્યા ખાલી કરો અને ફરી પ્રયાસ કરો.",
    "There isn't enough free space to compress the selected videos. Free up some space and try again.": "પસંદ કરેલા વિડિયો કોમ્પ્રેસ કરવા માટે પૂરતી ખાલી જગ્યા નથી. થોડી જગ્યા ખાલી કરો અને ફરી પ્રયાસ કરો.",
    "TidyByte has no account and no servers. Every scan, comparison, and analysis runs right here on this device.": "TidyByte માં એકાઉન્ટ નથી અને સર્વર નથી. દરેક સ્કેન, સરખામણી અને વિશ્લેષણ અહીં આ ડિવાઇસ પર જ થાય છે.",
    "TidyByte reads your library to find duplicates, blurry shots, and oversized files. It only ever changes what you approve. iOS will ask for permission next.": "ડુપ્લિકેટ, ઝાંખા ફોટા અને બહુ મોટી ફાઇલો શોધવા માટે TidyByte તમારી લાઇબ્રેરી વાંચે છે. તમે મંજૂરી આપો તે જ તે બદલે છે. હવે iOS પરવાનગી માગશે.",
    "We couldn't sort any photos into categories.": "અમે કોઈ ફોટાને શ્રેણીઓમાં ગોઠવી શક્યા નથી.",
    "You don't have any Live Photos in your library.": "તમારી લાઇબ્રેરીમાં કોઈ Live Photos નથી.",
    "You don't have any burst photo groups.": "તમારી પાસે બર્સ્ટ ફોટાનું કોઈ જૂથ નથી.",
    "You don't have any photos to compress.": "કોમ્પ્રેસ કરવા માટે તમારી પાસે કોઈ ફોટા નથી.",
    "You don't have any screenshots in your library.": "તમારી લાઇબ્રેરીમાં કોઈ સ્ક્રીનશોટ નથી.",
    "You don't have any videos in your library.": "તમારી લાઇબ્રેરીમાં કોઈ વિડિયો નથી.",
    "Your library is empty.": "તમારી લાઇબ્રેરી ખાલી છે.",
    "Your library looks clean!": "તમારી લાઇબ્રેરી સ્વચ્છ લાગે છે!",
    "Your photo library is clean!": "તમારી ફોટો લાઇબ્રેરી સ્વચ્છ છે!",
  },
  pa: {
    "Access to Your Photos": "ਤੁਹਾਡੀਆਂ ਫ਼ੋਟੋਆਂ ਤੱਕ ਪਹੁੰਚ",
    "All Clear": "ਸਭ ਠੀਕ",
    "Analyzing photos...": "ਫ਼ੋਟੋਆਂ ਦਾ ਵਿਸ਼ਲੇਸ਼ਣ ਹੋ ਰਿਹਾ ਹੈ...",
    "Compressed photos and videos will appear here.": "ਕੰਪਰੈਸ ਕੀਤੀਆਂ ਫ਼ੋਟੋਆਂ ਅਤੇ ਵੀਡੀਓ ਇੱਥੇ ਦਿਖਣਗੇ.",
    "Deletion Error": "ਮਿਟਾਉਣ ਵਿੱਚ ਗਲਤੀ",
    "Detect Low-Quality Photos": "ਘਟੀਆ ਗੁਣਵੱਤਾ ਵਾਲੀਆਂ ਫ਼ੋਟੋਆਂ ਪਛਾਣੋ",
    "File Size": "ਫ਼ਾਈਲ ਦਾ ਆਕਾਰ",
    "Find Duplicate Photos": "ਡੁਪਲੀਕੇਟ ਫ਼ੋਟੋਆਂ ਲੱਭੋ",
    "Find Similar Photos": "ਸਮਾਨ ਫ਼ੋਟੋਆਂ ਲੱਭੋ",
    "Find blurry, too dark, and overexposed photos.": "ਧੁੰਦਲੀਆਂ, ਬਹੁਤ ਗੂੜ੍ਹੀਆਂ ਅਤੇ ਬਹੁਤ ਰੌਸ਼ਨ ਫ਼ੋਟੋਆਂ ਲੱਭੋ.",
    "Group photos into memes, documents, food, pets, nature, selfies and media saved from other apps.": "ਫ਼ੋਟੋਆਂ ਨੂੰ ਮੀਮਜ਼, ਦਸਤਾਵੇਜ਼, ਖਾਣਾ, ਪਾਲਤੂ ਜਾਨਵਰ, ਕੁਦਰਤ, ਸੈਲਫ਼ੀਆਂ ਅਤੇ ਹੋਰ ਐਪਾਂ ਤੋਂ ਸੇਵ ਕੀਤੇ ਮੀਡੀਆ ਵਿੱਚ ਵੰਡੋ.",
    "Grouping similar photos...": "ਸਮਾਨ ਫ਼ੋਟੋਆਂ ਨੂੰ ਇੱਕ ਗਰੁੱਪ ਵਿੱਚ ਪਾਇਆ ਜਾ ਰਿਹਾ ਹੈ...",
    "Groups photos taken within %lld seconds of each other.": "ਇੱਕ ਦੂਜੇ ਤੋਂ %lld ਸਕਿੰਟ ਦੇ ਅੰਦਰ ਖਿੱਚੀਆਂ ਫ਼ੋਟੋਆਂ ਨੂੰ ਇੱਕ ਗਰੁੱਪ ਵਿੱਚ ਰੱਖਦੀ ਹੈ.",
    "No Albums": "ਕੋਈ ਐਲਬਮ ਨਹੀਂ",
    "No Burst Photos": "ਕੋਈ ਬਰਸਟ ਫ਼ੋਟੋ ਨਹੀਂ",
    "No Duplicates Found": "ਕੋਈ ਡੁਪਲੀਕੇਟ ਨਹੀਂ ਮਿਲਿਆ",
    "No History": "ਕੋਈ ਇਤਿਹਾਸ ਨਹੀਂ",
    "No Large Photos": "ਕੋਈ ਵੱਡੀ ਫ਼ੋਟੋ ਨਹੀਂ",
    "No Live Photos": "ਕੋਈ Live Photos ਨਹੀਂ",
    "No Media": "ਕੋਈ ਮੀਡੀਆ ਨਹੀਂ",
    "No Photos": "ਕੋਈ ਫ਼ੋਟੋ ਨਹੀਂ",
    "No Savings Yet": "ਹਾਲੇ ਕੋਈ ਬਚਤ ਨਹੀਂ",
    "No Screenshots": "ਕੋਈ ਸਕਰੀਨਸ਼ਾਟ ਨਹੀਂ",
    "No Similar Photos Found": "ਕੋਈ ਸਮਾਨ ਫ਼ੋਟੋ ਨਹੀਂ ਮਿਲੀ",
    "No Videos": "ਕੋਈ ਵੀਡੀਓ ਨਹੀਂ",
    "No albums with photos were found.": "ਫ਼ੋਟੋਆਂ ਵਾਲੀ ਕੋਈ ਐਲਬਮ ਨਹੀਂ ਮਿਲੀ.",
    "No issues found in this category.": "ਇਸ ਸ਼੍ਰੇਣੀ ਵਿੱਚ ਕੋਈ ਸਮੱਸਿਆ ਨਹੀਂ ਮਿਲੀ.",
    "No matching media": "ਕੋਈ ਮੇਲ ਖਾਂਦਾ ਮੀਡੀਆ ਨਹੀਂ",
    "No more Live Photos": "ਹੋਰ Live Photos ਨਹੀਂ",
    "No more items": "ਹੋਰ ਆਈਟਮਾਂ ਨਹੀਂ",
    "No photos over 2 MB are left to compress. HEIC photos are already small.": "ਕੰਪਰੈਸ ਕਰਨ ਲਈ 2 MB ਤੋਂ ਵੱਡੀਆਂ ਫ਼ੋਟੋਆਂ ਨਹੀਂ ਬਚੀਆਂ. HEIC ਫ਼ੋਟੋਆਂ ਪਹਿਲਾਂ ਹੀ ਛੋਟੀਆਂ ਹੁੰਦੀਆਂ ਹਨ.",
    "Not Enough Space": "ਲੋੜੀਂਦੀ ਥਾਂ ਨਹੀਂ",
    "Nothing Leaves Your Device": "ਕੁਝ ਵੀ ਤੁਹਾਡੇ ਡੀਵਾਈਸ ਤੋਂ ਬਾਹਰ ਨਹੀਂ ਜਾਂਦਾ",
    "Nothing to Sort": "ਲੜੀਬੱਧ ਕਰਨ ਲਈ ਕੁਝ ਨਹੀਂ",
    "Organize by Content": "ਸਮੱਗਰੀ ਅਨੁਸਾਰ ਸੰਗਠਿਤ ਕਰੋ",
    "Resolution": "ਰੈਜ਼ੋਲਿਊਸ਼ਨ",
    "Review one photo at a time. Swipe left to delete, right to keep, or up to file it into an album — and undo anything by mistake.": "ਇੱਕ ਵਾਰ ਵਿੱਚ ਇੱਕ ਫ਼ੋਟੋ ਵੇਖੋ. ਮਿਟਾਉਣ ਲਈ ਖੱਬੇ, ਰੱਖਣ ਲਈ ਸੱਜੇ ਜਾਂ ਐਲਬਮ ਵਿੱਚ ਪਾਉਣ ਲਈ ਉੱਪਰ ਸਵਾਈਪ ਕਰੋ — ਅਤੇ ਗਲਤੀ ਨਾਲ ਕੀਤਾ ਕੁਝ ਵੀ ਵਾਪਸ ਲਵੋ.",
    "Scan Again": "ਦੁਬਾਰਾ ਸਕੈਨ ਕਰੋ",
    "Scan your library for exact and visually similar duplicates.": "ਬਿਲਕੁਲ ਸਮਾਨ ਅਤੇ ਦਿੱਖ ਵਿੱਚ ਸਮਾਨ ਡੁਪਲੀਕੇਟ ਲਈ ਆਪਣੀ ਲਾਇਬ੍ਰੇਰੀ ਸਕੈਨ ਕਰੋ.",
    "Scanning for duplicates...": "ਡੁਪਲੀਕੇਟ ਲਈ ਸਕੈਨ ਚੱਲ ਰਹੀ ਹੈ...",
    "Scans your library and sorts photos by what's in them": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਸਕੈਨ ਕਰਦੀ ਹੈ ਅਤੇ ਫ਼ੋਟੋਆਂ ਵਿੱਚ ਕੀ ਹੈ ਉਸ ਅਨੁਸਾਰ ਲੜੀਬੱਧ ਕਰਦੀ ਹੈ",
    "Scans your library for out-of-focus and poorly lit photos": "ਧੁੰਦਲੀਆਂ ਅਤੇ ਘੱਟ ਰੌਸ਼ਨੀ ਵਾਲੀਆਂ ਫ਼ੋਟੋਆਂ ਲਈ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਸਕੈਨ ਕਰਦੀ ਹੈ",
    "Scans your library for photos taken close together": "ਨੇੜੇ-ਨੇੜੇ ਖਿੱਚੀਆਂ ਫ਼ੋਟੋਆਂ ਲਈ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਸਕੈਨ ਕਰਦੀ ਹੈ",
    "Scans your whole library for duplicates": "ਤੁਹਾਡੀ ਪੂਰੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਡੁਪਲੀਕੇਟ ਲੱਭਦੀ ਹੈ",
    "Show All Photos": "ਸਾਰੀਆਂ ਫ਼ੋਟੋਆਂ ਦਿਖਾਓ",
    "Something went wrong": "ਕੁਝ ਗੜਬੜ ਹੋ ਗਈ",
    "Sorting photos...": "ਫ਼ੋਟੋਆਂ ਲੜੀਬੱਧ ਕੀਤੀਆਂ ਜਾ ਰਹੀਆਂ ਹਨ...",
    "Space you free up with any cleanup tool shows up here.": "ਕਿਸੇ ਵੀ ਸਫ਼ਾਈ ਟੂਲ ਨਾਲ ਤੁਸੀਂ ਖਾਲੀ ਕੀਤੀ ਥਾਂ ਇੱਥੇ ਦਿਖਦੀ ਹੈ.",
    "Start Analysis": "ਵਿਸ਼ਲੇਸ਼ਣ ਸ਼ੁਰੂ ਕਰੋ",
    "Start Scan": "ਸਕੈਨ ਸ਼ੁਰੂ ਕਰੋ",
    "Swipe Through Your Library": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਸਵਾਈਪ ਕਰੋ",
    "There isn't enough free space to compress the selected photos. Free up some space and try again.": "ਚੁਣੀਆਂ ਫ਼ੋਟੋਆਂ ਨੂੰ ਕੰਪਰੈਸ ਕਰਨ ਲਈ ਲੋੜੀਂਦੀ ਖਾਲੀ ਥਾਂ ਨਹੀਂ ਹੈ. ਕੁਝ ਥਾਂ ਖਾਲੀ ਕਰੋ ਅਤੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "There isn't enough free space to compress the selected videos. Free up some space and try again.": "ਚੁਣੇ ਵੀਡੀਓ ਨੂੰ ਕੰਪਰੈਸ ਕਰਨ ਲਈ ਲੋੜੀਂਦੀ ਖਾਲੀ ਥਾਂ ਨਹੀਂ ਹੈ. ਕੁਝ ਥਾਂ ਖਾਲੀ ਕਰੋ ਅਤੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "TidyByte has no account and no servers. Every scan, comparison, and analysis runs right here on this device.": "TidyByte ਦਾ ਕੋਈ ਖਾਤਾ ਅਤੇ ਕੋਈ ਸਰਵਰ ਨਹੀਂ ਹੈ. ਹਰ ਸਕੈਨ, ਤੁਲਨਾ ਅਤੇ ਵਿਸ਼ਲੇਸ਼ਣ ਇੱਥੇ ਇਸੇ ਡੀਵਾਈਸ ਉੱਤੇ ਚੱਲਦਾ ਹੈ.",
    "TidyByte reads your library to find duplicates, blurry shots, and oversized files. It only ever changes what you approve. iOS will ask for permission next.": "ਡੁਪਲੀਕੇਟ, ਧੁੰਦਲੀਆਂ ਫ਼ੋਟੋਆਂ ਅਤੇ ਬਹੁਤ ਵੱਡੀਆਂ ਫ਼ਾਈਲਾਂ ਲੱਭਣ ਲਈ TidyByte ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਪੜ੍ਹਦਾ ਹੈ. ਇਹ ਸਿਰਫ਼ ਉਹੀ ਬਦਲਦਾ ਹੈ ਜਿਸਦੀ ਤੁਸੀਂ ਮਨਜ਼ੂਰੀ ਦਿੰਦੇ ਹੋ. ਅੱਗੇ iOS ਆਗਿਆ ਮੰਗੇਗਾ.",
    "We couldn't sort any photos into categories.": "ਅਸੀਂ ਕੋਈ ਵੀ ਫ਼ੋਟੋ ਸ਼੍ਰੇਣੀਆਂ ਵਿੱਚ ਨਹੀਂ ਪਾ ਸਕੇ.",
    "You don't have any Live Photos in your library.": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਕੋਈ Live Photos ਨਹੀਂ ਹੈ.",
    "You don't have any burst photo groups.": "ਤੁਹਾਡੇ ਕੋਲ ਬਰਸਟ ਫ਼ੋਟੋਆਂ ਦਾ ਕੋਈ ਗਰੁੱਪ ਨਹੀਂ ਹੈ.",
    "You don't have any photos to compress.": "ਕੰਪਰੈਸ ਕਰਨ ਲਈ ਤੁਹਾਡੇ ਕੋਲ ਕੋਈ ਫ਼ੋਟੋ ਨਹੀਂ ਹੈ.",
    "You don't have any screenshots in your library.": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਕੋਈ ਸਕਰੀਨਸ਼ਾਟ ਨਹੀਂ ਹੈ.",
    "You don't have any videos in your library.": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਕੋਈ ਵੀਡੀਓ ਨਹੀਂ ਹੈ.",
    "Your library is empty.": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਖਾਲੀ ਹੈ.",
    "Your library looks clean!": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਸਾਫ਼ ਲੱਗਦੀ ਹੈ!",
    "Your photo library is clean!": "ਤੁਹਾਡੀ ਫ਼ੋਟੋ ਲਾਇਬ੍ਰੇਰੀ ਸਾਫ਼ ਹੈ!",
  },
  ta: {
    "Access to Your Photos": "உங்கள் புகைப்படங்களுக்கான அணுகல்",
    "All Clear": "எல்லாம் சரி",
    "Analyzing photos...": "புகைப்படங்கள் பகுப்பாய்வு செய்யப்படுகின்றன...",
    "Compressed photos and videos will appear here.": "சுருக்கிய புகைப்படங்களும் வீடியோக்களும் இங்கே தோன்றும்.",
    "Deletion Error": "நீக்குவதில் பிழை",
    "Detect Low-Quality Photos": "தரம் குறைந்த புகைப்படங்களைக் கண்டறி",
    "File Size": "கோப்பு அளவு",
    "Find Duplicate Photos": "நகல் புகைப்படங்களைக் கண்டறி",
    "Find Similar Photos": "ஒத்த புகைப்படங்களைக் கண்டறி",
    "Find blurry, too dark, and overexposed photos.": "மங்கலான, மிக இருண்ட மற்றும் மிக ஒளிர்வான புகைப்படங்களைக் கண்டறி.",
    "Group photos into memes, documents, food, pets, nature, selfies and media saved from other apps.": "புகைப்படங்களை மீம்கள், ஆவணங்கள், உணவு, செல்லப்பிராணிகள், இயற்கை, செல்ஃபிகள் மற்றும் பிற ஆப்களிலிருந்து சேமித்த மீடியா என வகைப்படுத்து.",
    "Grouping similar photos...": "ஒத்த புகைப்படங்கள் குழுவாக்கப்படுகின்றன...",
    "Groups photos taken within %lld seconds of each other.": "ஒன்றுக்கொன்று %lld விநாடிகளுக்குள் எடுக்கப்பட்ட புகைப்படங்களை ஒரே குழுவாக்கும்.",
    "No Albums": "ஆல்பங்கள் இல்லை",
    "No Burst Photos": "பர்ஸ்ட் புகைப்படங்கள் இல்லை",
    "No Duplicates Found": "நகல்கள் எதுவும் கிடைக்கவில்லை",
    "No History": "வரலாறு இல்லை",
    "No Large Photos": "பெரிய புகைப்படங்கள் இல்லை",
    "No Live Photos": "Live Photos இல்லை",
    "No Media": "மீடியா இல்லை",
    "No Photos": "புகைப்படங்கள் இல்லை",
    "No Savings Yet": "இன்னும் சேமிப்பு இல்லை",
    "No Screenshots": "ஸ்கிரீன்ஷாட்கள் இல்லை",
    "No Similar Photos Found": "ஒத்த புகைப்படங்கள் எதுவும் கிடைக்கவில்லை",
    "No Videos": "வீடியோக்கள் இல்லை",
    "No albums with photos were found.": "புகைப்படங்கள் உள்ள ஆல்பங்கள் எதுவும் கிடைக்கவில்லை.",
    "No issues found in this category.": "இந்த வகையில் எந்தப் பிரச்சினையும் கிடைக்கவில்லை.",
    "No matching media": "பொருந்தும் மீடியா இல்லை",
    "No more Live Photos": "மேலும் Live Photos இல்லை",
    "No more items": "மேலும் உருப்படிகள் இல்லை",
    "No photos over 2 MB are left to compress. HEIC photos are already small.": "சுருக்குவதற்கு 2 MB-க்கு மேல் புகைப்படங்கள் எதுவும் மீதமில்லை. HEIC புகைப்படங்கள் ஏற்கனவே சிறியவை.",
    "Not Enough Space": "போதுமான இடம் இல்லை",
    "Nothing Leaves Your Device": "எதுவும் உங்கள் சாதனத்தை விட்டு வெளியேறாது",
    "Nothing to Sort": "வரிசைப்படுத்த எதுவும் இல்லை",
    "Organize by Content": "உள்ளடக்கத்தின்படி ஒழுங்குபடுத்து",
    "Resolution": "தெளிவுத்திறன்",
    "Review one photo at a time. Swipe left to delete, right to keep, or up to file it into an album — and undo anything by mistake.": "ஒரு நேரத்தில் ஒரு புகைப்படத்தைப் பாருங்கள். நீக்க இடது பக்கம், வைத்திருக்க வலது பக்கம், ஆல்பத்தில் சேர்க்க மேல் பக்கம் ஸ்வைப் செய்யுங்கள் — தவறுதலாகச் செய்த எதையும் மீளச் செய்யுங்கள்.",
    "Scan Again": "மீண்டும் ஸ்கேன் செய்",
    "Scan your library for exact and visually similar duplicates.": "சரியான மற்றும் காட்சியில் ஒத்த நகல்களுக்காக உங்கள் நூலகத்தை ஸ்கேன் செய்.",
    "Scanning for duplicates...": "நகல்களுக்காக ஸ்கேன் செய்யப்படுகிறது...",
    "Scans your library and sorts photos by what's in them": "உங்கள் நூலகத்தை ஸ்கேன் செய்து, புகைப்படங்களில் இருப்பதைப் பொறுத்து வரிசைப்படுத்தும்",
    "Scans your library for out-of-focus and poorly lit photos": "கவனம் விலகிய மற்றும் குறைந்த வெளிச்சமுள்ள புகைப்படங்களுக்காக உங்கள் நூலகத்தை ஸ்கேன் செய்யும்",
    "Scans your library for photos taken close together": "நெருக்கமாக எடுத்த புகைப்படங்களுக்காக உங்கள் நூலகத்தை ஸ்கேன் செய்யும்",
    "Scans your whole library for duplicates": "உங்கள் முழு நூலகத்திலும் நகல்களைத் தேடும்",
    "Show All Photos": "எல்லா புகைப்படங்களையும் காட்டு",
    "Something went wrong": "ஏதோ தவறு நடந்தது",
    "Sorting photos...": "புகைப்படங்கள் வரிசைப்படுத்தப்படுகின்றன...",
    "Space you free up with any cleanup tool shows up here.": "எந்தச் சுத்தம் கருவியிலும் நீங்கள் காலி செய்யும் இடம் இங்கே தோன்றும்.",
    "Start Analysis": "பகுப்பாய்வைத் தொடங்கு",
    "Start Scan": "ஸ்கேனைத் தொடங்கு",
    "Swipe Through Your Library": "உங்கள் நூலகத்தில் ஸ்வைப் செய்யுங்கள்",
    "There isn't enough free space to compress the selected photos. Free up some space and try again.": "தேர்ந்தெடுத்த புகைப்படங்களைச் சுருக்குவதற்குப் போதுமான காலி இடம் இல்லை. சிறிது இடத்தைக் காலி செய்து மீண்டும் முயற்சி செய்யுங்கள்.",
    "There isn't enough free space to compress the selected videos. Free up some space and try again.": "தேர்ந்தெடுத்த வீடியோக்களைச் சுருக்குவதற்குப் போதுமான காலி இடம் இல்லை. சிறிது இடத்தைக் காலி செய்து மீண்டும் முயற்சி செய்யுங்கள்.",
    "TidyByte has no account and no servers. Every scan, comparison, and analysis runs right here on this device.": "TidyByte-க்குக் கணக்கும் இல்லை, சர்வர்களும் இல்லை. ஒவ்வொரு ஸ்கேன், ஒப்பீடு மற்றும் பகுப்பாய்வும் இங்கே இந்தச் சாதனத்திலேயே நடக்கிறது.",
    "TidyByte reads your library to find duplicates, blurry shots, and oversized files. It only ever changes what you approve. iOS will ask for permission next.": "நகல்கள், மங்கலான புகைப்படங்கள் மற்றும் மிகப் பெரிய கோப்புகளைக் கண்டறிய TidyByte உங்கள் நூலகத்தைப் படிக்கிறது. நீங்கள் ஒப்புக்கொண்டதை மட்டுமே அது மாற்றும். அடுத்து iOS அனுமதி கேட்கும்.",
    "We couldn't sort any photos into categories.": "எந்தப் புகைப்படத்தையும் வகைகளாக வரிசைப்படுத்த முடியவில்லை.",
    "You don't have any Live Photos in your library.": "உங்கள் நூலகத்தில் Live Photos எதுவும் இல்லை.",
    "You don't have any burst photo groups.": "உங்களிடம் பர்ஸ்ட் புகைப்படக் குழுக்கள் எதுவும் இல்லை.",
    "You don't have any photos to compress.": "சுருக்குவதற்கு உங்களிடம் புகைப்படங்கள் எதுவும் இல்லை.",
    "You don't have any screenshots in your library.": "உங்கள் நூலகத்தில் ஸ்கிரீன்ஷாட்கள் எதுவும் இல்லை.",
    "You don't have any videos in your library.": "உங்கள் நூலகத்தில் வீடியோக்கள் எதுவும் இல்லை.",
    "Your library is empty.": "உங்கள் நூலகம் காலியாக உள்ளது.",
    "Your library looks clean!": "உங்கள் நூலகம் சுத்தமாகத் தெரிகிறது!",
    "Your photo library is clean!": "உங்கள் புகைப்பட நூலகம் சுத்தமாக உள்ளது!",
  },
}

const langs = ['mr', 'gu', 'pa', 'ta']
const problems = []

for (const lang of langs) {
  const path = join(dir, `${lang}.json`)
  const before = readFileSync(path, 'utf8')
  const parsedBefore = JSON.parse(before)
  const priorStrings = { ...parsedBefore.strings }
  const additions = translations[lang]

  if (Object.keys(additions).length !== 64) {
    problems.push(`${lang}: expected 64 additions, got ${Object.keys(additions).length}`)
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
  if (Object.keys(reparsed.strings).length !== priorKeys.length + 64) {
    problems.push(`${lang}: key count ${Object.keys(reparsed.strings).length} != ${priorKeys.length + 64}`)
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
