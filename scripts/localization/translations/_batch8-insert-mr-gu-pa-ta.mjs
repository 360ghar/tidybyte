// Batch 8 insertion: 80 plain keys + 13 plural keys into mr/gu/pa/ta.
//
// Textual insertion, like the batch-7 script: the `strings` block is rebuilt
// sorted, and the hand-formatted `plurals` block keeps its existing layout with
// the 13 new entries appended in `_plural-keys.json` order (the existing 51 are
// already that file's prefix, so the file's own order is preserved).
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const langs = ['mr', 'gu', 'pa', 'ta']
const EXPECTED_PLAIN = 80
const EXPECTED_PLURALS = 13

// ---------------------------------------------------------------- plain keys
const PLAIN = {
  mr: {
    "Worst Shots": "सर्वात खराब शॉट्स",
    "Review low-scoring photos, lowest first": "कमी गुण मिळालेले फोटो तपासा, सर्वात कमी गुणांचे आधी",
    "Photos you haven't reviewed yet": "अजून तपासले नसलेले फोटो",
    "Every photo and video in your library": "तुमच्या लायब्ररीतील प्रत्येक फोटो आणि व्हिडिओ",
    "Review photos and videos taken on or before a date": "एका तारखेला किंवा त्यापूर्वी काढलेले फोटो आणि व्हिडिओ तपासा",
    "Photos not organized into your albums": "तुमच्या अल्बममध्ये न मांडलेले फोटो",
    "Specific Album": "विशिष्ट अल्बम",
    "Review photos from a specific album": "विशिष्ट अल्बममधील फोटो तपासा",
    "Marked for deletion. Nothing is deleted until you confirm at the end.": "हटवण्यासाठी चिन्हांकित. तुम्ही शेवटी पुष्टी करेपर्यंत काहीही हटवले जात नाही.",
    "Delete is off until the photo loads.": "फोटो लोड होईपर्यंत हटवा बंद असतो.",
    "Pinch or double-tap a photo to inspect it": "फोटो निरखण्यासाठी पिंच करा किंवा दोनदा टॅप करा",
    "That photo can't be undone anymore.": "तो फोटो आता पूर्ववत करता येणार नाही.",
    "Undo your newer actions first to reach that photo.": "त्या फोटोपर्यंत पोहोचण्यासाठी आधी तुमच्या नवीन क्रिया पूर्ववत करा.",
    "Your library changed during analysis. Try Worst Shots again.": "विश्लेषणादरम्यान तुमची लायब्ररी बदलली. सर्वात खराब शॉट्स पुन्हा वापरून पहा.",
    "No photo is waiting to be filed. Dismiss and try again.": "अल्बममध्ये ठेवण्यासाठी कोणताही फोटो बाकी नाही. बंद करा आणि पुन्हा प्रयत्न करा.",
    "Still adding — please wait a moment and try again.": "अजून जोडत आहे — कृपया थोडा वेळ थांबा आणि पुन्हा प्रयत्न करा.",
    "Couldn't save your changes. Please try again.": "तुमचे बदल सेव्ह करता आले नाहीत. कृपया पुन्हा प्रयत्न करा.",
    "Added to albums": "अल्बममध्ये जोडले",
    "Moved to Recently Deleted": "अलीकडे हटवलेले मध्ये हलवले",
    "Kept": "ठेवले",
    "Skipped": "वगळले",
    "Deleted": "हटवले",
    "Kept: your choice": "ठेवले: तुमची निवड",
    "Kept: your pick in Photos": "ठेवले: फोटो अ‍ॅपमधील तुमची निवड",
    "Kept: iPhone's pick": "ठेवले: iPhone ची निवड",
    "Kept: favorite": "ठेवले: आवडते",
    "Kept: highest resolution": "ठेवले: सर्वाधिक रिझोल्यूशन",
    "Kept: last frame": "ठेवले: शेवटची फ्रेम",
    "Kept: auto pick": "ठेवले: स्वयंचलित निवड",
    " Favorites are kept.": " आवडते ठेवले जातात.",
    "This keeps the starred frame of each burst and deletes the rest.": "हे प्रत्येक बर्स्टमधील तारांकित फ्रेम ठेवते आणि बाकीच्या हटवते.",
    "1 burst cleaned down to a single photo.": "1 बर्स्ट एका फोटोपर्यंत स्वच्छ केला.",
    "%lld bursts cleaned down to single photos.": "%lld बर्स्ट एका फोटोपर्यंत स्वच्छ केले.",
    "Album not found.": "अल्बम आढळला नाही.",
    "Failed to create album.": "अल्बम तयार करता आला नाही.",
    "Couldn't modify the album. Please try again.": "अल्बम बदलता आला नाही. कृपया पुन्हा प्रयत्न करा.",
    "Nothing was deleted.": "काहीही हटवले नाही.",
    "Live Photo not found.": "Live Photo आढळला नाही.",
    "Could not find still image in Live Photo.": "Live Photo मध्ये स्थिर प्रतिमा आढळली नाही.",
    "Invalid image data.": "अवैध प्रतिमा डेटा.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.": "फोटो लोड करताना वेळ संपला (तो अजून iCloud मध्ये असू शकतो). कृपया पुन्हा प्रयत्न करा.",
    "The compressed copy is missing from your library.": "कंप्रेस केलेली प्रत तुमच्या लायब्ररीत नाही.",
    "The converted still is missing from your library.": "रूपांतरित केलेली स्थिर प्रतिमा तुमच्या लायब्ररीत नाही.",
    "Copies kept. Both versions are in your library; delete either one in Photos.": "प्रती ठेवल्या. दोन्ही आवृत्त्या तुमच्या लायब्ररीत आहेत; कोणतीही एक फोटो अ‍ॅपमध्ये हटवा.",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.": "%lld पैकी %lld आयटम हटवले. %lld हटवता आले नाहीत. पुन्हा प्रयत्न करा.",
    "Your library changed. Scan again before searching.": "तुमची लायब्ररी बदलली. शोधण्यापूर्वी पुन्हा स्कॅन करा.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.": "बदललेले किंवा उपलब्ध नसलेले फोटो वगळले. नवीन किंवा संपादित फोटो समाविष्ट करण्यासाठी पुन्हा स्कॅन करा.",
    "Recently Deleted": "अलीकडे हटवलेले",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.": "ते रिकामे केल्यावर जागा परत मिळते. फोटो अ‍ॅपमध्ये अल्बम उघडा, नंतर अलीकडे हटवलेले.",
    "Manage Apps & System Storage": "अ‍ॅप्स आणि सिस्टम स्टोरेज व्यवस्थापित करा",
    "Open Settings ▸ General ▸ iPhone Storage": "सेटिंग्ज ▸ सामान्य ▸ iPhone स्टोरेज उघडा",
    "Library figures below cover only the photos you selected; device totals cover the whole device.": "खालील लायब्ररी आकडे फक्त तुम्ही निवडलेल्या फोटोंसाठी आहेत; डिव्हाइसचे एकूण आकडे संपूर्ण डिव्हाइससाठी आहेत.",
    "Find exact and near-duplicate photos": "अगदी सारखे आणि जवळपास सारखे डुप्लिकेट फोटो शोधा",
    "Spot blurry, dark, and overexposed shots": "अस्पष्ट, गडद आणि खूप तेजस्वी फोटो ओळखा",
    "Surface the biggest files taking up space": "सर्वाधिक जागा घेणाऱ्या मोठ्या फाइल्स दाखवा",
    "Delete only what you review and approve": "तुम्ही तपासून मंजूर केलेलेच हटवा",
    "items, all time": "आयटम, आतापर्यंत",
    "this month": "या महिन्यात",
    "Size unknown": "आकार माहीत नाही",
    "Size unavailable": "आकार उपलब्ध नाही",
    "cleaned up since you started using TidyByte": "TidyByte वापरायला सुरू केल्यापासून स्वच्छ केलेले",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.": "अजून मोजण्यासारखे काही नाही. फक्त iCloud मध्ये साठवलेले आयटम आकार सांगत नाहीत.",
    "Enjoying TidyByte?": "TidyByte आवडत आहे का?",
    "Thanks for the support": "पाठिंब्याबद्दल धन्यवाद",
    "What should we fix?": "आम्ही काय सुधारावे?",
    "Tell us what got in the way.": "कशामुळे अडचण आली ते सांगा.",
    "Send Feedback": "अभिप्राय पाठवा",
    "Yes": "होय",
    "Not really": "फारसे नाही",
    "Not now": "आता नको",
    "Your rating helps other people find TidyByte.": "तुमची रेटिंग इतरांना TidyByte शोधण्यात मदत करते.",
    "You just %@.": "तुम्ही नुकतेच %@.",
    "The message couldn't be sent. Try again, or email us at %@.": "संदेश पाठवता आला नाही. पुन्हा प्रयत्न करा किंवा %@ वर ईमेल करा.",
    "No mail account is set up on this device. Email us at %@.": "या डिव्हाइसवर मेल खाते सेट केलेले नाही. %@ वर ईमेल करा.",
    "I just %@": "मी नुकतेच %@",
    "I'm cleaning up my photo library": "मी माझी फोटो लायब्ररी स्वच्छ करत आहे",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@": "%@ TidyByte सोबत — एक खाजगी, डिव्हाइसवर चालणारे फोटो क्लीनअप अ‍ॅप. %@",
    "Min size: %@": "किमान आकार: %@",
    "Swipe history cleared": "स्वाइप इतिहास साफ केला",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.": "iOS तुम्हाला पुष्टी करायला सांगेल. हटवलेले आयटम फोटो अ‍ॅपमधील अलीकडे हटवलेले मध्ये जातात, जिथे तुम्ही ते 30 दिवसांपर्यंत पुन्हा मिळवू शकता.",
  },
  gu: {
    "Worst Shots": "સૌથી ખરાબ શોટ",
    "Review low-scoring photos, lowest first": "ઓછા સ્કોરવાળા ફોટાની સમીક્ષા કરો, સૌથી ઓછા પહેલા",
    "Photos you haven't reviewed yet": "તમે હજી સમીક્ષા ન કરી હોય તેવા ફોટા",
    "Every photo and video in your library": "તમારી લાઇબ્રેરીનો દરેક ફોટો અને વિડિયો",
    "Review photos and videos taken on or before a date": "એક તારીખે કે તે પહેલાં લીધેલા ફોટા અને વિડિયોની સમીક્ષા કરો",
    "Photos not organized into your albums": "તમારા આલ્બમમાં ગોઠવેલા ન હોય તેવા ફોટા",
    "Specific Album": "ચોક્કસ આલ્બમ",
    "Review photos from a specific album": "ચોક્કસ આલ્બમના ફોટાની સમીક્ષા કરો",
    "Marked for deletion. Nothing is deleted until you confirm at the end.": "કાઢી નાખવા માટે ચિહ્નિત. તમે અંતે પુષ્ટિ કરો ત્યાં સુધી કંઈ કાઢી નાખવામાં આવતું નથી.",
    "Delete is off until the photo loads.": "ફોટો લોડ થાય ત્યાં સુધી કાઢી નાખો બંધ છે.",
    "Pinch or double-tap a photo to inspect it": "ફોટો નજીકથી જોવા પિંચ કરો અથવા બે વાર ટૅપ કરો",
    "That photo can't be undone anymore.": "એ ફોટો હવે પૂર્વવત્ કરી શકાશે નહીં.",
    "Undo your newer actions first to reach that photo.": "એ ફોટો સુધી પહોંચવા પહેલાં તમારી નવી ક્રિયાઓ પૂર્વવત્ કરો.",
    "Your library changed during analysis. Try Worst Shots again.": "વિશ્લેષણ દરમિયાન તમારી લાઇબ્રેરી બદલાઈ. સૌથી ખરાબ શોટ ફરી અજમાવો.",
    "No photo is waiting to be filed. Dismiss and try again.": "આલ્બમમાં મૂકવા માટે કોઈ ફોટો બાકી નથી. બંધ કરો અને ફરી પ્રયાસ કરો.",
    "Still adding — please wait a moment and try again.": "હજી ઉમેરી રહ્યાં છીએ — થોડી વાર રાહ જુઓ અને ફરી પ્રયાસ કરો.",
    "Couldn't save your changes. Please try again.": "તમારા ફેરફારો સાચવી શકાયા નથી. ફરી પ્રયાસ કરો.",
    "Added to albums": "આલ્બમમાં ઉમેર્યું",
    "Moved to Recently Deleted": "તાજેતરમાં કાઢી નાખેલા માં ખસેડ્યું",
    "Kept": "રાખ્યું",
    "Skipped": "છોડી દીધું",
    "Deleted": "કાઢી નાખ્યું",
    "Kept: your choice": "રાખ્યું: તમારી પસંદ",
    "Kept: your pick in Photos": "રાખ્યું: ફોટા એપમાં તમારી પસંદ",
    "Kept: iPhone's pick": "રાખ્યું: iPhone ની પસંદ",
    "Kept: favorite": "રાખ્યું: પસંદ",
    "Kept: highest resolution": "રાખ્યું: સૌથી વધુ રિઝોલ્યુશન",
    "Kept: last frame": "રાખ્યું: છેલ્લી ફ્રેમ",
    "Kept: auto pick": "રાખ્યું: સ્વચાલિત પસંદ",
    " Favorites are kept.": " પસંદ રાખવામાં આવે છે.",
    "This keeps the starred frame of each burst and deletes the rest.": "આ દરેક બર્સ્ટની તારાંકિત ફ્રેમ રાખે છે અને બાકીની કાઢી નાખે છે.",
    "1 burst cleaned down to a single photo.": "1 બર્સ્ટ એક જ ફોટા સુધી સાફ થયો.",
    "%lld bursts cleaned down to single photos.": "%lld બર્સ્ટ એક-એક ફોટા સુધી સાફ થયા.",
    "Album not found.": "આલ્બમ મળ્યું નથી.",
    "Failed to create album.": "આલ્બમ બનાવી શકાયું નથી.",
    "Couldn't modify the album. Please try again.": "આલ્બમ બદલી શકાયું નથી. ફરી પ્રયાસ કરો.",
    "Nothing was deleted.": "કંઈ કાઢી નાખવામાં આવ્યું નથી.",
    "Live Photo not found.": "Live Photo મળ્યો નથી.",
    "Could not find still image in Live Photo.": "Live Photo માં સ્થિર ઇમેજ મળી નથી.",
    "Invalid image data.": "અમાન્ય ઇમેજ ડેટા.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.": "ફોટો લોડ કરવામાં સમય પૂરો થયો (તે હજી iCloud માં હોઈ શકે છે). ફરી પ્રયાસ કરો.",
    "The compressed copy is missing from your library.": "કોમ્પ્રેસ કરેલી કૉપી તમારી લાઇબ્રેરીમાં નથી.",
    "The converted still is missing from your library.": "કન્વર્ટ કરેલું સ્ટિલ તમારી લાઇબ્રેરીમાં નથી.",
    "Copies kept. Both versions are in your library; delete either one in Photos.": "કૉપી રાખી. બંને આવૃત્તિ તમારી લાઇબ્રેરીમાં છે; ફોટા એપમાંથી કોઈ એક કાઢી નાખો.",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.": "%lld માંથી %lld આઇટમ કાઢી નાખ્યા. %lld કાઢી નાખી શકાયા નથી. ફરી પ્રયાસ કરો.",
    "Your library changed. Scan again before searching.": "તમારી લાઇબ્રેરી બદલાઈ. શોધતા પહેલાં ફરી સ્કેન કરો.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.": "બદલાયેલા કે ઉપલબ્ધ ન હોય તેવા ફોટા દૂર કર્યા. નવા કે એડિટ કરેલા ફોટા સામેલ કરવા ફરી સ્કેન કરો.",
    "Recently Deleted": "તાજેતરમાં કાઢી નાખેલા",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.": "તે ખાલી થાય ત્યારે જગ્યા પાછી મળે છે. ફોટા એપમાં આલ્બમ ખોલો, પછી તાજેતરમાં કાઢી નાખેલા.",
    "Manage Apps & System Storage": "એપ્સ અને સિસ્ટમ સ્ટોરેજનું સંચાલન કરો",
    "Open Settings ▸ General ▸ iPhone Storage": "સેટિંગ્સ ▸ સામાન્ય ▸ iPhone સ્ટોરેજ ખોલો",
    "Library figures below cover only the photos you selected; device totals cover the whole device.": "નીચેના લાઇબ્રેરી આંકડા ફક્ત તમે પસંદ કરેલા ફોટા માટે છે; ડિવાઇસના કુલ આંકડા આખા ડિવાઇસ માટે છે.",
    "Find exact and near-duplicate photos": "એકદમ સરખા અને લગભગ સરખા ડુપ્લિકેટ ફોટા શોધો",
    "Spot blurry, dark, and overexposed shots": "ઝાંખા, ઘેરા અને બહુ તેજસ્વી શોટ પકડો",
    "Surface the biggest files taking up space": "સૌથી વધુ જગ્યા લેતી મોટી ફાઇલો દર્શાવો",
    "Delete only what you review and approve": "તમે સમીક્ષા કરીને મંજૂર કરો તે જ કાઢી નાખો",
    "items, all time": "આઇટમ, અત્યાર સુધી",
    "this month": "આ મહિને",
    "Size unknown": "સાઇઝ અજાણી",
    "Size unavailable": "સાઇઝ ઉપલબ્ધ નથી",
    "cleaned up since you started using TidyByte": "TidyByte વાપરવાનું શરૂ કર્યું ત્યારથી સાફ કર્યું",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.": "હજી માપી શકાય એવું કંઈ નથી. ફક્ત iCloud માં સંગ્રહાયેલા આઇટમ સાઇઝ જણાવતા નથી.",
    "Enjoying TidyByte?": "TidyByte ગમી રહી છે?",
    "Thanks for the support": "ટેકા બદલ આભાર",
    "What should we fix?": "અમે શું સુધારવું જોઈએ?",
    "Tell us what got in the way.": "કઈ વસ્તુ અડચણરૂપ બની તે જણાવો.",
    "Send Feedback": "પ્રતિસાદ મોકલો",
    "Yes": "હા",
    "Not really": "એવું નહીં",
    "Not now": "હમણાં નહીં",
    "Your rating helps other people find TidyByte.": "તમારું રેટિંગ બીજાને TidyByte શોધવામાં મદદ કરે છે.",
    "You just %@.": "તમે હમણાં જ %@.",
    "The message couldn't be sent. Try again, or email us at %@.": "સંદેશ મોકલી શકાયો નથી. ફરી પ્રયાસ કરો અથવા %@ પર ઇમેઇલ કરો.",
    "No mail account is set up on this device. Email us at %@.": "આ ડિવાઇસ પર મેઇલ એકાઉન્ટ સેટ કરેલું નથી. %@ પર ઇમેઇલ કરો.",
    "I just %@": "મેં હમણાં જ %@",
    "I'm cleaning up my photo library": "મારી ફોટો લાઇબ્રેરી સાફ થઈ રહી છે",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@": "%@ TidyByte સાથે — એક ખાનગી, ડિવાઇસ પર જ ચાલતી ફોટો ક્લીનઅપ એપ. %@",
    "Min size: %@": "ન્યૂનતમ સાઇઝ: %@",
    "Swipe history cleared": "સ્વાઇપ ઇતિહાસ સાફ કર્યો",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.": "iOS તમને પુષ્ટિ કરવા કહેશે. કાઢી નાખેલા આઇટમ ફોટા એપમાંના તાજેતરમાં કાઢી નાખેલા માં જાય છે, જ્યાં તમે તેને 30 દિવસ સુધી પાછા લાવી શકો છો.",
  },
  pa: {
    "Worst Shots": "ਸਭ ਤੋਂ ਮਾੜੇ ਸ਼ਾਟ",
    "Review low-scoring photos, lowest first": "ਘੱਟ ਸਕੋਰ ਵਾਲੀਆਂ ਫ਼ੋਟੋਆਂ ਦੀ ਸਮੀਖਿਆ ਕਰੋ, ਸਭ ਤੋਂ ਘੱਟ ਪਹਿਲਾਂ",
    "Photos you haven't reviewed yet": "ਉਹ ਫ਼ੋਟੋਆਂ ਜੋ ਤੁਸੀਂ ਹਾਲੇ ਸਮੀਖਿਆ ਨਹੀਂ ਕੀਤੀਆਂ",
    "Every photo and video in your library": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਦੀ ਹਰ ਫ਼ੋਟੋ ਅਤੇ ਵੀਡੀਓ",
    "Review photos and videos taken on or before a date": "ਕਿਸੇ ਤਾਰੀਖ਼ ਨੂੰ ਜਾਂ ਉਸ ਤੋਂ ਪਹਿਲਾਂ ਖਿੱਚੀਆਂ ਫ਼ੋਟੋਆਂ ਅਤੇ ਵੀਡੀਓ ਦੀ ਸਮੀਖਿਆ ਕਰੋ",
    "Photos not organized into your albums": "ਤੁਹਾਡੀਆਂ ਐਲਬਮਾਂ ਵਿੱਚ ਨਾ ਰੱਖੀਆਂ ਫ਼ੋਟੋਆਂ",
    "Specific Album": "ਖ਼ਾਸ ਐਲਬਮ",
    "Review photos from a specific album": "ਕਿਸੇ ਖ਼ਾਸ ਐਲਬਮ ਦੀਆਂ ਫ਼ੋਟੋਆਂ ਦੀ ਸਮੀਖਿਆ ਕਰੋ",
    "Marked for deletion. Nothing is deleted until you confirm at the end.": "ਮਿਟਾਉਣ ਲਈ ਨਿਸ਼ਾਨਬੱਧ. ਜਦੋਂ ਤੱਕ ਤੁਸੀਂ ਅੰਤ ਵਿੱਚ ਪੁਸ਼ਟੀ ਨਹੀਂ ਕਰਦੇ, ਕੁਝ ਵੀ ਮਿਟਦਾ ਨਹੀਂ.",
    "Delete is off until the photo loads.": "ਫ਼ੋਟੋ ਲੋਡ ਹੋਣ ਤੱਕ ਮਿਟਾਉਣਾ ਬੰਦ ਹੈ.",
    "Pinch or double-tap a photo to inspect it": "ਫ਼ੋਟੋ ਨੂੰ ਧਿਆਨ ਨਾਲ ਵੇਖਣ ਲਈ ਪਿੰਚ ਕਰੋ ਜਾਂ ਦੋ ਵਾਰ ਟੈਪ ਕਰੋ",
    "That photo can't be undone anymore.": "ਉਹ ਫ਼ੋਟੋ ਹੁਣ ਵਾਪਸ ਨਹੀਂ ਲਿਆਂਦੀ ਜਾ ਸਕਦੀ.",
    "Undo your newer actions first to reach that photo.": "ਉਸ ਫ਼ੋਟੋ ਤੱਕ ਪਹੁੰਚਣ ਲਈ ਪਹਿਲਾਂ ਆਪਣੀਆਂ ਨਵੀਆਂ ਕਾਰਵਾਈਆਂ ਵਾਪਸ ਲਓ.",
    "Your library changed during analysis. Try Worst Shots again.": "ਵਿਸ਼ਲੇਸ਼ਣ ਦੌਰਾਨ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਬਦਲ ਗਈ. ਸਭ ਤੋਂ ਮਾੜੇ ਸ਼ਾਟ ਦੁਬਾਰਾ ਅਜ਼ਮਾਓ.",
    "No photo is waiting to be filed. Dismiss and try again.": "ਐਲਬਮ ਵਿੱਚ ਰੱਖਣ ਲਈ ਕੋਈ ਫ਼ੋਟੋ ਬਾਕੀ ਨਹੀਂ. ਬੰਦ ਕਰੋ ਅਤੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "Still adding — please wait a moment and try again.": "ਹਾਲੇ ਸ਼ਾਮਲ ਕਰ ਰਹੇ ਹਾਂ — ਕਿਰਪਾ ਕਰਕੇ ਥੋੜ੍ਹੀ ਦੇਰ ਉਡੀਕੋ ਅਤੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "Couldn't save your changes. Please try again.": "ਤੁਹਾਡੇ ਬਦਲਾਅ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕੇ. ਕਿਰਪਾ ਕਰਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "Added to albums": "ਐਲਬਮਾਂ ਵਿੱਚ ਸ਼ਾਮਲ ਕੀਤੀਆਂ",
    "Moved to Recently Deleted": "ਹਾਲ ਹੀ ਵਿੱਚ ਮਿਟਾਏ ਵਿੱਚ ਭੇਜੀਆਂ",
    "Kept": "ਰੱਖੇ",
    "Skipped": "ਛੱਡੇ",
    "Deleted": "ਮਿਟਾਏ",
    "Kept: your choice": "ਰੱਖੀ: ਤੁਹਾਡੀ ਚੋਣ",
    "Kept: your pick in Photos": "ਰੱਖੀ: ਫ਼ੋਟੋਜ਼ ਵਿੱਚ ਤੁਹਾਡੀ ਚੋਣ",
    "Kept: iPhone's pick": "ਰੱਖੀ: iPhone ਦੀ ਚੋਣ",
    "Kept: favorite": "ਰੱਖੀ: ਪਸੰਦੀਦਾ",
    "Kept: highest resolution": "ਰੱਖੀ: ਸਭ ਤੋਂ ਵੱਧ ਰੈਜ਼ੋਲਿਊਸ਼ਨ",
    "Kept: last frame": "ਰੱਖੀ: ਆਖ਼ਰੀ ਫਰੇਮ",
    "Kept: auto pick": "ਰੱਖੀ: ਆਟੋ ਚੋਣ",
    " Favorites are kept.": " ਪਸੰਦੀਦਾ ਰੱਖੇ ਜਾਂਦੇ ਹਨ.",
    "This keeps the starred frame of each burst and deletes the rest.": "ਇਹ ਹਰ ਬਰਸਟ ਦੀ ਤਾਰਾ ਲੱਗੀ ਫਰੇਮ ਰੱਖਦਾ ਹੈ ਅਤੇ ਬਾਕੀ ਮਿਟਾ ਦਿੰਦਾ ਹੈ.",
    "1 burst cleaned down to a single photo.": "1 ਬਰਸਟ ਇੱਕ ਹੀ ਫ਼ੋਟੋ ਤੱਕ ਸਾਫ਼ ਹੋਇਆ.",
    "%lld bursts cleaned down to single photos.": "%lld ਬਰਸਟ ਇੱਕ-ਇੱਕ ਫ਼ੋਟੋ ਤੱਕ ਸਾਫ਼ ਹੋਏ.",
    "Album not found.": "ਐਲਬਮ ਨਹੀਂ ਮਿਲੀ.",
    "Failed to create album.": "ਐਲਬਮ ਬਣਾਈ ਨਹੀਂ ਜਾ ਸਕੀ.",
    "Couldn't modify the album. Please try again.": "ਐਲਬਮ ਬਦਲੀ ਨਹੀਂ ਜਾ ਸਕੀ. ਕਿਰਪਾ ਕਰਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "Nothing was deleted.": "ਕੁਝ ਵੀ ਮਿਟਾਇਆ ਨਹੀਂ ਗਿਆ.",
    "Live Photo not found.": "Live Photo ਨਹੀਂ ਮਿਲੀ.",
    "Could not find still image in Live Photo.": "Live Photo ਵਿੱਚ ਸਥਿਰ ਤਸਵੀਰ ਨਹੀਂ ਮਿਲੀ.",
    "Invalid image data.": "ਅਵੈਧ ਤਸਵੀਰ ਡਾਟਾ.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.": "ਫ਼ੋਟੋ ਲੋਡ ਕਰਨ ਵਿੱਚ ਸਮਾਂ ਖ਼ਤਮ ਹੋ ਗਿਆ (ਇਹ ਹਾਲੇ ਵੀ iCloud ਵਿੱਚ ਹੋ ਸਕਦੀ ਹੈ). ਕਿਰਪਾ ਕਰਕੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "The compressed copy is missing from your library.": "ਕੰਪ੍ਰੈਸ ਕੀਤੀ ਕਾਪੀ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਨਹੀਂ ਹੈ.",
    "The converted still is missing from your library.": "ਬਦਲੀ ਗਈ ਸਥਿਰ ਫ਼ੋਟੋ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਨਹੀਂ ਹੈ.",
    "Copies kept. Both versions are in your library; delete either one in Photos.": "ਕਾਪੀਆਂ ਰੱਖੀਆਂ. ਦੋਵੇਂ ਰੂਪ ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਵਿੱਚ ਹਨ; ਫ਼ੋਟੋਜ਼ ਵਿੱਚੋਂ ਕੋਈ ਇੱਕ ਮਿਟਾ ਦਿਓ.",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.": "%lld ਵਿੱਚੋਂ %lld ਆਈਟਮ ਮਿਟਾਈਆਂ. %lld ਮਿਟਾਈਆਂ ਨਹੀਂ ਜਾ ਸਕੀਆਂ. ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ.",
    "Your library changed. Scan again before searching.": "ਤੁਹਾਡੀ ਲਾਇਬ੍ਰੇਰੀ ਬਦਲ ਗਈ. ਖੋਜਣ ਤੋਂ ਪਹਿਲਾਂ ਦੁਬਾਰਾ ਸਕੈਨ ਕਰੋ.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.": "ਬਦਲੀਆਂ ਜਾਂ ਉਪਲਬਧ ਨਾ ਹੋਣ ਵਾਲੀਆਂ ਫ਼ੋਟੋਆਂ ਹਟਾਈਆਂ. ਨਵੀਆਂ ਜਾਂ ਸੰਪਾਦਿਤ ਫ਼ੋਟੋਆਂ ਸ਼ਾਮਲ ਕਰਨ ਲਈ ਦੁਬਾਰਾ ਸਕੈਨ ਕਰੋ.",
    "Recently Deleted": "ਹਾਲ ਹੀ ਵਿੱਚ ਮਿਟਾਏ",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.": "ਇਹ ਖਾਲੀ ਹੋਣ 'ਤੇ ਥਾਂ ਵਾਪਸ ਆਉਂਦੀ ਹੈ. ਫ਼ੋਟੋਜ਼ ਵਿੱਚ ਐਲਬਮਾਂ ਖੋਲ੍ਹੋ, ਫਿਰ ਹਾਲ ਹੀ ਵਿੱਚ ਮਿਟਾਏ.",
    "Manage Apps & System Storage": "ਐਪਾਂ ਅਤੇ ਸਿਸਟਮ ਸਟੋਰੇਜ ਦਾ ਪ੍ਰਬੰਧ ਕਰੋ",
    "Open Settings ▸ General ▸ iPhone Storage": "ਸੈਟਿੰਗਾਂ ▸ ਜਨਰਲ ▸ iPhone ਸਟੋਰੇਜ ਖੋਲ੍ਹੋ",
    "Library figures below cover only the photos you selected; device totals cover the whole device.": "ਹੇਠਾਂ ਦਿੱਤੇ ਲਾਇਬ੍ਰੇਰੀ ਅੰਕੜੇ ਸਿਰਫ਼ ਤੁਹਾਡੀਆਂ ਚੁਣੀਆਂ ਫ਼ੋਟੋਆਂ ਲਈ ਹਨ; ਡੀਵਾਈਸ ਦੇ ਕੁੱਲ ਅੰਕੜੇ ਪੂਰੇ ਡੀਵਾਈਸ ਲਈ ਹਨ.",
    "Find exact and near-duplicate photos": "ਬਿਲਕੁਲ ਸਮਾਨ ਅਤੇ ਲਗਭਗ ਸਮਾਨ ਡੁਪਲੀਕੇਟ ਫ਼ੋਟੋਆਂ ਲੱਭੋ",
    "Spot blurry, dark, and overexposed shots": "ਧੁੰਦਲੀਆਂ, ਗੂੜ੍ਹੀਆਂ ਅਤੇ ਬਹੁਤ ਰੌਸ਼ਨ ਫ਼ੋਟੋਆਂ ਪਛਾਣੋ",
    "Surface the biggest files taking up space": "ਸਭ ਤੋਂ ਵੱਧ ਥਾਂ ਲੈਣ ਵਾਲੀਆਂ ਵੱਡੀਆਂ ਫ਼ਾਈਲਾਂ ਦਿਖਾਓ",
    "Delete only what you review and approve": "ਸਿਰਫ਼ ਉਹੀ ਮਿਟਾਓ ਜਿਸਦੀ ਤੁਸੀਂ ਸਮੀਖਿਆ ਕਰਕੇ ਮਨਜ਼ੂਰੀ ਦਿੰਦੇ ਹੋ",
    "items, all time": "ਆਈਟਮਾਂ, ਹੁਣ ਤੱਕ",
    "this month": "ਇਸ ਮਹੀਨੇ",
    "Size unknown": "ਆਕਾਰ ਅਣਜਾਣ",
    "Size unavailable": "ਆਕਾਰ ਉਪਲਬਧ ਨਹੀਂ",
    "cleaned up since you started using TidyByte": "TidyByte ਵਰਤਣਾ ਸ਼ੁਰੂ ਕਰਨ ਤੋਂ ਬਾਅਦ ਸਾਫ਼ ਕੀਤਾ",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.": "ਹਾਲੇ ਮਾਪਣ ਯੋਗ ਕੁਝ ਨਹੀਂ. ਸਿਰਫ਼ iCloud ਵਿੱਚ ਸੰਭਾਲੀਆਂ ਆਈਟਮਾਂ ਆਕਾਰ ਨਹੀਂ ਦੱਸਦੀਆਂ.",
    "Enjoying TidyByte?": "TidyByte ਪਸੰਦ ਆ ਰਹੀ ਹੈ?",
    "Thanks for the support": "ਸਾਥ ਲਈ ਧੰਨਵਾਦ",
    "What should we fix?": "ਅਸੀਂ ਕੀ ਠੀਕ ਕਰੀਏ?",
    "Tell us what got in the way.": "ਦੱਸੋ ਕੀ ਰੁਕਾਵਟ ਬਣਿਆ.",
    "Send Feedback": "ਫੀਡਬੈਕ ਭੇਜੋ",
    "Yes": "ਹਾਂ",
    "Not really": "ਬਹੁਤਾ ਨਹੀਂ",
    "Not now": "ਹੁਣ ਨਹੀਂ",
    "Your rating helps other people find TidyByte.": "ਤੁਹਾਡੀ ਰੇਟਿੰਗ ਹੋਰਾਂ ਨੂੰ TidyByte ਲੱਭਣ ਵਿੱਚ ਮਦਦ ਕਰਦੀ ਹੈ.",
    "You just %@.": "ਤੁਸੀਂ ਹੁਣੇ %@.",
    "The message couldn't be sent. Try again, or email us at %@.": "ਸੁਨੇਹਾ ਭੇਜਿਆ ਨਹੀਂ ਜਾ ਸਕਿਆ. ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ ਜਾਂ ਸਾਨੂੰ %@ ਉੱਤੇ ਈਮੇਲ ਕਰੋ.",
    "No mail account is set up on this device. Email us at %@.": "ਇਸ ਡੀਵਾਈਸ ਉੱਤੇ ਕੋਈ ਮੇਲ ਖਾਤਾ ਸੈੱਟ ਨਹੀਂ ਹੈ. ਸਾਨੂੰ %@ ਉੱਤੇ ਈਮੇਲ ਕਰੋ.",
    "I just %@": "ਮੈਂ ਹੁਣੇ %@",
    "I'm cleaning up my photo library": "ਮੇਰੀ ਫ਼ੋਟੋ ਲਾਇਬ੍ਰੇਰੀ ਸਾਫ਼ ਹੋ ਰਹੀ ਹੈ",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@": "%@ TidyByte ਨਾਲ — ਇੱਕ ਨਿੱਜੀ, ਡੀਵਾਈਸ ਉੱਤੇ ਹੀ ਚੱਲਣ ਵਾਲੀ ਫ਼ੋਟੋ ਸਫ਼ਾਈ ਐਪ. %@",
    "Min size: %@": "ਘੱਟੋ-ਘੱਟ ਆਕਾਰ: %@",
    "Swipe history cleared": "ਸਵਾਈਪ ਇਤਿਹਾਸ ਸਾਫ਼ ਕੀਤਾ",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.": "iOS ਤੁਹਾਨੂੰ ਪੁਸ਼ਟੀ ਕਰਨ ਲਈ ਕਹੇਗਾ. ਮਿਟਾਈਆਂ ਆਈਟਮਾਂ ਫ਼ੋਟੋਜ਼ ਵਿੱਚ ਹਾਲ ਹੀ ਵਿੱਚ ਮਿਟਾਏ ਵਿੱਚ ਜਾਂਦੀਆਂ ਹਨ, ਜਿੱਥੇ ਤੁਸੀਂ ਉਨ੍ਹਾਂ ਨੂੰ 30 ਦਿਨਾਂ ਲਈ ਬਹਾਲ ਕਰ ਸਕਦੇ ਹੋ.",
  },
  ta: {
    "Worst Shots": "மோசமான படங்கள்",
    "Review low-scoring photos, lowest first": "குறைந்த மதிப்பெண் பெற்ற புகைப்படங்களைப் பாருங்கள், மிகக் குறைவானவை முதலில்",
    "Photos you haven't reviewed yet": "நீங்கள் இன்னும் பார்க்காத புகைப்படங்கள்",
    "Every photo and video in your library": "உங்கள் நூலகத்தில் உள்ள ஒவ்வொரு புகைப்படமும் வீடியோவும்",
    "Review photos and videos taken on or before a date": "ஒரு தேதியில் அல்லது அதற்கு முன் எடுத்த புகைப்படங்களையும் வீடியோக்களையும் பாருங்கள்",
    "Photos not organized into your albums": "உங்கள் ஆல்பங்களில் சேர்க்கப்படாத புகைப்படங்கள்",
    "Specific Album": "குறிப்பிட்ட ஆல்பம்",
    "Review photos from a specific album": "குறிப்பிட்ட ஆல்பத்தின் புகைப்படங்களைப் பாருங்கள்",
    "Marked for deletion. Nothing is deleted until you confirm at the end.": "நீக்குவதற்குக் குறிக்கப்பட்டது. இறுதியில் நீங்கள் உறுதிப்படுத்தும் வரை எதுவும் நீக்கப்படாது.",
    "Delete is off until the photo loads.": "புகைப்படம் ஏற்றப்படும் வரை நீக்கு முடக்கப்பட்டுள்ளது.",
    "Pinch or double-tap a photo to inspect it": "புகைப்படத்தை உற்றுப் பார்க்க இரு விரல்களால் பெரிதாக்கவும் அல்லது இருமுறை தட்டவும்",
    "That photo can't be undone anymore.": "அந்தப் புகைப்படத்தை இனி மீளச் செய்ய முடியாது.",
    "Undo your newer actions first to reach that photo.": "அந்தப் புகைப்படத்தை அடைய முதலில் உங்கள் புதிய செயல்களை மீளச் செய்யவும்.",
    "Your library changed during analysis. Try Worst Shots again.": "பரிசோதனையின் போது உங்கள் நூலகம் மாறியது. மோசமான படங்களை மீண்டும் முயற்சிக்கவும்.",
    "No photo is waiting to be filed. Dismiss and try again.": "ஆல்பத்தில் சேர்க்க காத்திருக்கும் புகைப்படம் எதுவும் இல்லை. நிராகரித்து மீண்டும் முயற்சிக்கவும்.",
    "Still adding — please wait a moment and try again.": "இன்னும் சேர்க்கிறது — சிறிது நேரம் காத்திருந்து மீண்டும் முயற்சிக்கவும்.",
    "Couldn't save your changes. Please try again.": "உங்கள் மாற்றங்களைச் சேமிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.",
    "Added to albums": "ஆல்பங்களில் சேர்க்கப்பட்டது",
    "Moved to Recently Deleted": "சமீபத்தில் நீக்கியவை-க்கு நகர்த்தப்பட்டது",
    "Kept": "வைக்கப்பட்டது",
    "Skipped": "தவிர்க்கப்பட்டது",
    "Deleted": "நீக்கப்பட்டது",
    "Kept: your choice": "வைக்கப்பட்டது: உங்கள் தேர்வு",
    "Kept: your pick in Photos": "வைக்கப்பட்டது: புகைப்படங்களில் உங்கள் தேர்வு",
    "Kept: iPhone's pick": "வைக்கப்பட்டது: iPhone தேர்வு",
    "Kept: favorite": "வைக்கப்பட்டது: பிடித்தவை",
    "Kept: highest resolution": "வைக்கப்பட்டது: அதிக தெளிவுத்திறன்",
    "Kept: last frame": "வைக்கப்பட்டது: கடைசி சட்டகம்",
    "Kept: auto pick": "வைக்கப்பட்டது: தானியங்கி தேர்வு",
    " Favorites are kept.": " பிடித்தவை வைக்கப்படும்.",
    "This keeps the starred frame of each burst and deletes the rest.": "இது ஒவ்வொரு பர்ஸ்டின் நட்சத்திரமிட்ட சட்டகத்தை வைத்துக்கொண்டு மற்றவற்றை நீக்கும்.",
    "1 burst cleaned down to a single photo.": "1 பர்ஸ்ட் ஒரே புகைப்படமாகச் சுத்தம் செய்யப்பட்டது.",
    "%lld bursts cleaned down to single photos.": "%lld பர்ஸ்ட்கள் தலா ஒரு புகைப்படமாகச் சுத்தம் செய்யப்பட்டன.",
    "Album not found.": "ஆல்பம் கிடைக்கவில்லை.",
    "Failed to create album.": "ஆல்பத்தை உருவாக்க முடியவில்லை.",
    "Couldn't modify the album. Please try again.": "ஆல்பத்தை மாற்ற முடியவில்லை. மீண்டும் முயற்சிக்கவும்.",
    "Nothing was deleted.": "எதுவும் நீக்கப்படவில்லை.",
    "Live Photo not found.": "Live Photo கிடைக்கவில்லை.",
    "Could not find still image in Live Photo.": "Live Photo-இல் நிலைப் படம் கிடைக்கவில்லை.",
    "Invalid image data.": "தவறான படத் தரவு.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.": "புகைப்படத்தை ஏற்றும்போது நேரம் முடிந்தது (அது இன்னும் iCloud-இல் இருக்கலாம்). மீண்டும் முயற்சிக்கவும்.",
    "The compressed copy is missing from your library.": "சுருக்கப்பட்ட நகல் உங்கள் நூலகத்தில் இல்லை.",
    "The converted still is missing from your library.": "மாற்றப்பட்ட நிலைப்படம் உங்கள் நூலகத்தில் இல்லை.",
    "Copies kept. Both versions are in your library; delete either one in Photos.": "நகல்கள் வைக்கப்பட்டன. இரண்டு பதிப்புகளும் உங்கள் நூலகத்தில் உள்ளன; புகைப்படங்களில் ஏதேனும் ஒன்றை நீக்கவும்.",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.": "%lld-இல் %lld உருப்படிகள் நீக்கப்பட்டன. %lld நீக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.",
    "Your library changed. Scan again before searching.": "உங்கள் நூலகம் மாறியது. தேடுவதற்கு முன் மீண்டும் ஸ்கேன் செய்யவும்.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.": "மாறிய அல்லது கிடைக்காத புகைப்படங்கள் அகற்றப்பட்டன. புதிய அல்லது திருத்தப்பட்ட புகைப்படங்களைச் சேர்க்க மீண்டும் ஸ்கேன் செய்யவும்.",
    "Recently Deleted": "சமீபத்தில் நீக்கியவை",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.": "அது காலி செய்யப்படும்போது இடம் திரும்பும். புகைப்படங்களில் ஆல்பங்களைத் திறந்து, பின் சமீபத்தில் நீக்கியவை என்பதைத் திறக்கவும்.",
    "Manage Apps & System Storage": "ஆப்கள் & சிஸ்டம் சேமிப்பை நிர்வகி",
    "Open Settings ▸ General ▸ iPhone Storage": "அமைப்புகள் ▸ பொது ▸ iPhone சேமிப்பு என்பதைத் திற",
    "Library figures below cover only the photos you selected; device totals cover the whole device.": "கீழே உள்ள நூலக எண்ணிக்கை நீங்கள் தேர்ந்தெடுத்த புகைப்படங்களுக்கு மட்டுமே; சாதனத்தின் மொத்த எண்ணிக்கை முழு சாதனத்திற்கும்.",
    "Find exact and near-duplicate photos": "சரியான மற்றும் கிட்டத்தட்ட ஒத்த நகல் புகைப்படங்களைக் கண்டறி",
    "Spot blurry, dark, and overexposed shots": "மங்கலான, இருண்ட மற்றும் அதிக ஒளியுள்ள படங்களைக் கண்டறி",
    "Surface the biggest files taking up space": "அதிக இடத்தை எடுக்கும் பெரிய கோப்புகளைக் காட்டு",
    "Delete only what you review and approve": "நீங்கள் பார்த்து ஒப்புக்கொண்டதை மட்டும் நீக்கு",
    "items, all time": "உருப்படிகள், இதுவரை",
    "this month": "இந்த மாதம்",
    "Size unknown": "அளவு தெரியவில்லை",
    "Size unavailable": "அளவு கிடைக்கவில்லை",
    "cleaned up since you started using TidyByte": "TidyByte-ஐப் பயன்படுத்தத் தொடங்கியதிலிருந்து சுத்தம் செய்யப்பட்டது",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.": "இன்னும் அளவிடக்கூடியது எதுவும் இல்லை. iCloud-இல் மட்டும் சேமிக்கப்பட்ட உருப்படிகள் அளவைத் தெரிவிக்காது.",
    "Enjoying TidyByte?": "TidyByte பிடித்திருக்கிறதா?",
    "Thanks for the support": "ஆதரவுக்கு நன்றி",
    "What should we fix?": "நாங்கள் எதைச் சரிசெய்ய வேண்டும்?",
    "Tell us what got in the way.": "எது தடையாக இருந்தது என்று சொல்லுங்கள்.",
    "Send Feedback": "கருத்தை அனுப்பு",
    "Yes": "ஆம்",
    "Not really": "அப்படியில்லை",
    "Not now": "இப்போது வேண்டாம்",
    "Your rating helps other people find TidyByte.": "உங்கள் மதிப்பீடு மற்றவர்கள் TidyByte-ஐக் கண்டறிய உதவுகிறது.",
    "You just %@.": "நீங்கள் இப்போதுதான் %@.",
    "The message couldn't be sent. Try again, or email us at %@.": "செய்தியை அனுப்ப முடியவில்லை. மீண்டும் முயற்சிக்கவும் அல்லது %@-க்கு எங்களுக்கு மின்னஞ்சல் அனுப்பவும்.",
    "No mail account is set up on this device. Email us at %@.": "இந்தச் சாதனத்தில் மெயில் கணக்கு அமைக்கப்படவில்லை. %@-க்கு எங்களுக்கு மின்னஞ்சல் அனுப்பவும்.",
    "I just %@": "நான் இப்போதுதான் %@",
    "I'm cleaning up my photo library": "நான் என் புகைப்பட நூலகத்தைச் சுத்தம் செய்கிறேன்",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@": "%@ TidyByte உடன் — தனியுரிமை கொண்ட, சாதனத்திலேயே இயங்கும் புகைப்பட சுத்தம் செய்யும் ஆப். %@",
    "Min size: %@": "குறைந்தபட்ச அளவு: %@",
    "Swipe history cleared": "ஸ்வைப் வரலாறு அழிக்கப்பட்டது",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.": "iOS உறுதிப்படுத்தக் கேட்கும். நீக்கிய உருப்படிகள் புகைப்படங்களின் சமீபத்தில் நீக்கியவை-க்குச் செல்லும், அங்கு 30 நாட்களுக்கு மீட்டெடுக்கலாம்.",
  },
}

// ------------------------------------------------------------- plural keys
// Order must match the tail of `_plural-keys.json`.
const PLURALS = {
  mr: {
    "cleared %lld photo": { one: "%lld फोटो स्वच्छ केला", other: "%lld फोटो स्वच्छ केले" },
    "cleared %lld blurry photo": { one: "%lld अस्पष्ट फोटो स्वच्छ केला", other: "%lld अस्पष्ट फोटो स्वच्छ केले" },
    "cleared %lld screenshot": { one: "%lld स्क्रीनशॉट स्वच्छ केला", other: "%lld स्क्रीनशॉट स्वच्छ केले" },
    "cleared %lld large file": { one: "%lld मोठी फाइल स्वच्छ केली", other: "%lld मोठ्या फाइल्स स्वच्छ केल्या" },
    "cleared %lld burst frame": { one: "%lld बर्स्ट फ्रेम स्वच्छ केली", other: "%lld बर्स्ट फ्रेम स्वच्छ केल्या" },
    "cleared %lld item (%@)": { one: "%lld आयटम स्वच्छ केला (%@)", other: "%lld आयटम स्वच्छ केले (%@)" },
    "removed %lld duplicate": { one: "%lld डुप्लिकेट हटवला", other: "%lld डुप्लिकेट हटवले" },
    "removed %lld similar photo": { one: "%lld समान फोटो हटवला", other: "%lld समान फोटो हटवले" },
    "compressed %lld photo": { one: "%lld फोटो कंप्रेस केला", other: "%lld फोटो कंप्रेस केले" },
    "compressed %lld video": { one: "%lld व्हिडिओ कंप्रेस केला", other: "%lld व्हिडिओ कंप्रेस केले" },
    "cleaned %lld burst photo": { one: "%lld बर्स्ट फोटो स्वच्छ केला", other: "%lld बर्स्ट फोटो स्वच्छ केले" },
    "converted %lld Live Photo": { one: "%lld Live Photo स्टिलमध्ये रूपांतरित केला", other: "%lld Live Photos स्टिलमध्ये रूपांतरित केले" },
    "reviewed %lld item": { one: "%lld आयटम तपासला", other: "%lld आयटम तपासले" },
  },
  gu: {
    "cleared %lld photo": { one: "%lld ફોટો સાફ કર્યો", other: "%lld ફોટા સાફ કર્યા" },
    "cleared %lld blurry photo": { one: "%lld ઝાંખો ફોટો સાફ કર્યો", other: "%lld ઝાંખા ફોટા સાફ કર્યા" },
    "cleared %lld screenshot": { one: "%lld સ્ક્રીનશોટ સાફ કર્યો", other: "%lld સ્ક્રીનશોટ સાફ કર્યા" },
    "cleared %lld large file": { one: "%lld મોટી ફાઇલ સાફ કરી", other: "%lld મોટી ફાઇલો સાફ કરી" },
    "cleared %lld burst frame": { one: "%lld બર્સ્ટ ફ્રેમ સાફ કરી", other: "%lld બર્સ્ટ ફ્રેમ સાફ કરી" },
    "cleared %lld item (%@)": { one: "%lld આઇટમ સાફ કર્યું (%@)", other: "%lld આઇટમો સાફ કર્યા (%@)" },
    "removed %lld duplicate": { one: "%lld ડુપ્લિકેટ દૂર કર્યું", other: "%lld ડુપ્લિકેટ દૂર કર્યા" },
    "removed %lld similar photo": { one: "%lld સમાન ફોટો દૂર કર્યો", other: "%lld સમાન ફોટા દૂર કર્યા" },
    "compressed %lld photo": { one: "%lld ફોટો કોમ્પ્રેસ કર્યો", other: "%lld ફોટા કોમ્પ્રેસ કર્યા" },
    "compressed %lld video": { one: "%lld વિડિયો કોમ્પ્રેસ કર્યો", other: "%lld વિડિયો કોમ્પ્રેસ કર્યા" },
    "cleaned %lld burst photo": { one: "%lld બર્સ્ટ ફોટો સાફ કર્યો", other: "%lld બર્સ્ટ ફોટા સાફ કર્યા" },
    "converted %lld Live Photo": { one: "%lld Live Photo સ્ટિલમાં કન્વર્ટ કર્યો", other: "%lld Live Photos સ્ટિલમાં કન્વર્ટ કર્યા" },
    "reviewed %lld item": { one: "%lld આઇટમની સમીક્ષા કરી", other: "%lld આઇટમોની સમીક્ષા કરી" },
  },
  pa: {
    "cleared %lld photo": { one: "%lld ਫ਼ੋਟੋ ਸਾਫ਼ ਕੀਤੀ", other: "%lld ਫ਼ੋਟੋਆਂ ਸਾਫ਼ ਕੀਤੀਆਂ" },
    "cleared %lld blurry photo": { one: "%lld ਧੁੰਦਲੀ ਫ਼ੋਟੋ ਸਾਫ਼ ਕੀਤੀ", other: "%lld ਧੁੰਦਲੀਆਂ ਫ਼ੋਟੋਆਂ ਸਾਫ਼ ਕੀਤੀਆਂ" },
    "cleared %lld screenshot": { one: "%lld ਸਕਰੀਨਸ਼ਾਟ ਸਾਫ਼ ਕੀਤਾ", other: "%lld ਸਕਰੀਨਸ਼ਾਟ ਸਾਫ਼ ਕੀਤੇ" },
    "cleared %lld large file": { one: "%lld ਵੱਡੀ ਫ਼ਾਈਲ ਸਾਫ਼ ਕੀਤੀ", other: "%lld ਵੱਡੀਆਂ ਫ਼ਾਈਲਾਂ ਸਾਫ਼ ਕੀਤੀਆਂ" },
    "cleared %lld burst frame": { one: "%lld ਬਰਸਟ ਫਰੇਮ ਸਾਫ਼ ਕੀਤੀ", other: "%lld ਬਰਸਟ ਫਰੇਮ ਸਾਫ਼ ਕੀਤੀਆਂ" },
    "cleared %lld item (%@)": { one: "%lld ਆਈਟਮ ਸਾਫ਼ ਕੀਤੀ (%@)", other: "%lld ਆਈਟਮਾਂ ਸਾਫ਼ ਕੀਤੀਆਂ (%@)" },
    "removed %lld duplicate": { one: "%lld ਡੁਪਲੀਕੇਟ ਹਟਾਇਆ", other: "%lld ਡੁਪਲੀਕੇਟ ਹਟਾਏ" },
    "removed %lld similar photo": { one: "%lld ਸਮਾਨ ਫ਼ੋਟੋ ਹਟਾਈ", other: "%lld ਸਮਾਨ ਫ਼ੋਟੋਆਂ ਹਟਾਈਆਂ" },
    "compressed %lld photo": { one: "%lld ਫ਼ੋਟੋ ਕੰਪ੍ਰੈਸ ਕੀਤੀ", other: "%lld ਫ਼ੋਟੋਆਂ ਕੰਪ੍ਰੈਸ ਕੀਤੀਆਂ" },
    "compressed %lld video": { one: "%lld ਵੀਡੀਓ ਕੰਪ੍ਰੈਸ ਕੀਤਾ", other: "%lld ਵੀਡੀਓ ਕੰਪ੍ਰੈਸ ਕੀਤੇ" },
    "cleaned %lld burst photo": { one: "%lld ਬਰਸਟ ਫ਼ੋਟੋ ਸਾਫ਼ ਕੀਤੀ", other: "%lld ਬਰਸਟ ਫ਼ੋਟੋਆਂ ਸਾਫ਼ ਕੀਤੀਆਂ" },
    "converted %lld Live Photo": { one: "%lld Live Photo ਸਥਿਰ ਫ਼ੋਟੋ ਵਿੱਚ ਬਦਲੀ", other: "%lld Live Photos ਸਥਿਰ ਫ਼ੋਟੋਆਂ ਵਿੱਚ ਬਦਲੀਆਂ" },
    "reviewed %lld item": { one: "%lld ਆਈਟਮ ਦੀ ਸਮੀਖਿਆ ਕੀਤੀ", other: "%lld ਆਈਟਮਾਂ ਦੀ ਸਮੀਖਿਆ ਕੀਤੀ" },
  },
  ta: {
    "cleared %lld photo": { one: "%lld புகைப்படம் சுத்தம் செய்யப்பட்டது", other: "%lld புகைப்படங்கள் சுத்தம் செய்யப்பட்டன" },
    "cleared %lld blurry photo": { one: "%lld மங்கலான புகைப்படம் சுத்தம் செய்யப்பட்டது", other: "%lld மங்கலான புகைப்படங்கள் சுத்தம் செய்யப்பட்டன" },
    "cleared %lld screenshot": { one: "%lld ஸ்கிரீன்ஷாட் சுத்தம் செய்யப்பட்டது", other: "%lld ஸ்கிரீன்ஷாட்கள் சுத்தம் செய்யப்பட்டன" },
    "cleared %lld large file": { one: "%lld பெரிய கோப்பு சுத்தம் செய்யப்பட்டது", other: "%lld பெரிய கோப்புகள் சுத்தம் செய்யப்பட்டன" },
    "cleared %lld burst frame": { one: "%lld பர்ஸ்ட் சட்டகம் சுத்தம் செய்யப்பட்டது", other: "%lld பர்ஸ்ட் சட்டகங்கள் சுத்தம் செய்யப்பட்டன" },
    "cleared %lld item (%@)": { one: "%lld உருப்படி சுத்தம் செய்யப்பட்டது (%@)", other: "%lld உருப்படிகள் சுத்தம் செய்யப்பட்டன (%@)" },
    "removed %lld duplicate": { one: "%lld நகல் அகற்றப்பட்டது", other: "%lld நகல்கள் அகற்றப்பட்டன" },
    "removed %lld similar photo": { one: "%lld ஒத்த புகைப்படம் அகற்றப்பட்டது", other: "%lld ஒத்த புகைப்படங்கள் அகற்றப்பட்டன" },
    "compressed %lld photo": { one: "%lld புகைப்படம் சுருக்கப்பட்டது", other: "%lld புகைப்படங்கள் சுருக்கப்பட்டன" },
    "compressed %lld video": { one: "%lld வீடியோ சுருக்கப்பட்டது", other: "%lld வீடியோக்கள் சுருக்கப்பட்டன" },
    "cleaned %lld burst photo": { one: "%lld பர்ஸ்ட் புகைப்படம் சுத்தம் செய்யப்பட்டது", other: "%lld பர்ஸ்ட் புகைப்படங்கள் சுத்தம் செய்யப்பட்டன" },
    "converted %lld Live Photo": { one: "%lld Live Photo நிலைப்படமாக மாற்றப்பட்டது", other: "%lld Live Photos நிலைப்படங்களாக மாற்றப்பட்டன" },
    "reviewed %lld item": { one: "%lld உருப்படி மதிப்பாய்வு செய்யப்பட்டது", other: "%lld உருப்படிகள் மதிப்பாய்வு செய்யப்பட்டன" },
  },
}

// ------------------------------------------------------------------- checks
const problems = []
const pluralOrder = Object.keys(JSON.parse(readFileSync(join(dir, '_plural-keys.json'), 'utf8'))).slice(-EXPECTED_PLURALS)
const englishKeys = Object.keys(PLAIN.mr).sort()

for (const lang of langs) {
  if (Object.keys(PLAIN[lang]).length !== EXPECTED_PLAIN) problems.push(`${lang}: plain table has ${Object.keys(PLAIN[lang]).length} entries, expected ${EXPECTED_PLAIN}`)
  const extra = Object.keys(PLAIN[lang]).filter((k) => !englishKeys.includes(k))
  const missing = englishKeys.filter((k) => !(k in PLAIN[lang]))
  if (extra.length) problems.push(`${lang}: unknown plain keys: ${extra.join(' | ')}`)
  if (missing.length) problems.push(`${lang}: plain keys missing from table: ${missing.join(' | ')}`)
  if (Object.keys(PLURALS[lang]).length !== EXPECTED_PLURALS) problems.push(`${lang}: plural table has ${Object.keys(PLURALS[lang]).length} entries, expected ${EXPECTED_PLURALS}`)
  for (const k of pluralOrder) {
    if (!(k in PLURALS[lang])) problems.push(`${lang}: plural key missing from table: ${k}`)
  }
  for (const k of Object.keys(PLURALS[lang])) {
    if (!pluralOrder.includes(k)) problems.push(`${lang}: unexpected plural key: ${k}`)
  }
}
if (problems.length) {
  console.error('PROBLEMS in translation tables:')
  for (const p of problems) console.error(' -', p)
  process.exit(1)
}

// ------------------------------------------------------------------- insert
for (const lang of langs) {
  const path = join(dir, `${lang}.json`)
  const before = readFileSync(path, 'utf8')
  const parsedBefore = JSON.parse(before)
  const priorStrings = { ...parsedBefore.strings }
  const priorPlurals = { ...parsedBefore.plurals }
  const localProblems = []

  for (const k of Object.keys(PLAIN[lang])) {
    if (k in priorStrings) localProblems.push(`plain key already existed: ${k}`)
  }
  for (const k of Object.keys(PLURALS[lang])) {
    if (k in priorPlurals) localProblems.push(`plural key already existed: ${k}`)
  }

  // --- strings block, rebuilt sorted
  const merged = { ...priorStrings, ...PLAIN[lang] }
  const entries = Object.keys(merged)
    .sort()
    .map((k) => `    ${JSON.stringify(k)}: ${JSON.stringify(merged[k])}`)
    .join(',\n')
  const block = `  "strings": {\n${entries}\n  }`

  const start = before.indexOf('  "strings": {')
  if (start === -1) localProblems.push('strings block not found')
  const end = before.indexOf('\n  },', start)
  if (end === -1) localProblems.push('strings block end not found')
  if (start !== -1 && end !== -1 && !before.slice(end + 5, end + 5 + 15).startsWith('\n  "plurals"')) {
    localProblems.push(`unexpected text after strings block: ${JSON.stringify(before.slice(end + 5, end + 40))}`)
  }

  let after = before
  if (localProblems.length === 0) {
    after = before.slice(0, start) + block + before.slice(end + 4)
  }

  // --- plurals block, appended in _plural-keys.json order
  const endMarker = '\n  }\n}\n'
  if (after !== before) {
    if (!after.endsWith(endMarker)) {
      localProblems.push('plurals tail marker not found at end of file')
    } else {
      const appended = pluralOrder
        .map((k) => `    ${JSON.stringify(k)}: {\n      "one": ${JSON.stringify(PLURALS[lang][k].one)},\n      "other": ${JSON.stringify(PLURALS[lang][k].other)}\n    }`)
        .join(',\n')
      after = after.slice(0, -endMarker.length) + ',\n' + appended + endMarker
    }
  }

  if (localProblems.length === 0) {
    const reparsed = JSON.parse(after)
    const priorKeys = Object.keys(priorStrings)
    if (Object.keys(reparsed.strings).length !== priorKeys.length + EXPECTED_PLAIN) {
      localProblems.push(`strings count ${Object.keys(reparsed.strings).length} != ${priorKeys.length + EXPECTED_PLAIN}`)
    }
    for (const k of priorKeys) {
      if (reparsed.strings[k] !== priorStrings[k]) localProblems.push(`pre-existing string changed: ${k}`)
    }
    if (Object.keys(reparsed.plurals).length !== Object.keys(priorPlurals).length + EXPECTED_PLURALS) {
      localProblems.push(`plurals count ${Object.keys(reparsed.plurals).length} != ${Object.keys(priorPlurals).length + EXPECTED_PLURALS}`)
    }
    for (const k of Object.keys(priorPlurals)) {
      if (JSON.stringify(reparsed.plurals[k]) !== JSON.stringify(priorPlurals[k])) localProblems.push(`pre-existing plural changed: ${k}`)
    }
    if (!after.endsWith('\n')) localProblems.push('lost trailing newline')
  }

  if (localProblems.length) {
    console.error(`\n${lang}: NOT written`)
    for (const p of localProblems) console.error(' -', p)
    process.exit(1)
  }

  writeFileSync(path, after)
  console.log(`${lang}: strings ${Object.keys(priorStrings).length} -> ${Object.keys(JSON.parse(after).strings).length}, plurals ${Object.keys(priorPlurals).length} -> ${Object.keys(JSON.parse(after).plurals).length}`)
}
console.log('\nall four files written; invariants hold')
