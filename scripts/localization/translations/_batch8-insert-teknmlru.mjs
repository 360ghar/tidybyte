// Batch 8 insertion for te, kn, ml, ru.
//
// Adds the 80 plain keys to "strings" and the 13 counted keys to "plurals",
// then writes each file back with 2-space indent. Plain keys are re-sorted
// with the file's existing plain UTF-16 code-unit order; plural keys are
// appended in the catalog's own (_plural-keys.json) order.
//
// Run: node _batch8-insert-teknmlru.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------- plain keys

const PLAIN = {
  te: {
    "Worst Shots": "అత్యంత తక్కువ నాణ్యత ఫోటోలు",
    "Review low-scoring photos, lowest first":
      "తక్కువ స్కోరు ఫోటోలను సమీక్షించండి, అత్యంత తక్కువవి ముందుగా",
    "Photos you haven't reviewed yet": "మీరు ఇంకా సమీక్షించని ఫోటోలు",
    "Every photo and video in your library": "మీ లైబ్రరీలోని ప్రతి ఫోటో మరియు వీడియో",
    "Review photos and videos taken on or before a date":
      "ఒక తేదీన లేదా అంతకు ముందు తీసిన ఫోటోలు మరియు వీడియోలను సమీక్షించండి",
    "Photos not organized into your albums": "మీ ఆల్బమ్లలో ఏర్పాటు చేయని ఫోటోలు",
    "Specific Album": "నిర్దిష్ట ఆల్బమ్",
    "Review photos from a specific album": "నిర్దిష్ట ఆల్బమ్ నుండి ఫోటోలను సమీక్షించండి",
    "Marked for deletion. Nothing is deleted until you confirm at the end.":
      "తొలగింపు కోసం గుర్తించబడింది. చివర్లో మీరు నిర్ధారించే వరకు ఏదీ తొలగించబడదు.",
    "Delete is off until the photo loads.":
      "ఫోటో లోడ్ అయ్యే వరకు తొలగింపు ఆఫ్లో ఉంటుంది.",
    "Pinch or double-tap a photo to inspect it":
      "ఫోటోను పరిశీలించడానికి పిన్చ్ చేయండి లేదా రెండుసార్లు నొక్కండి",
    "That photo can't be undone anymore.": "ఆ ఫోటోను ఇక వెనక్కి తీసుకోలేరు.",
    "Undo your newer actions first to reach that photo.":
      "ఆ ఫోటోకు చేరుకోవడానికి ముందు మీ కొత్త చర్యలను వెనక్కి తీసుకోండి.",
    "Your library changed during analysis. Try Worst Shots again.":
      'విశ్లేషణ జరుగుతుండగా మీ లైబ్రరీ మారింది. "అత్యంత తక్కువ నాణ్యత ఫోటోలు" మళ్లీ ప్రయత్నించండి.',
    "No photo is waiting to be filed. Dismiss and try again.":
      "ఫైల్ చేయడానికి ఏ ఫోటో నిరీక్షణలో లేదు. మూసివేసి మళ్లీ ప్రయత్నించండి.",
    "Still adding — please wait a moment and try again.":
      "ఇంకా జోడిస్తోంది — కొద్దిసేపు ఆగి మళ్లీ ప్రయత్నించండి.",
    "Couldn't save your changes. Please try again.":
      "మీ మార్పులను సేవ్ చేయలేకపోయాం. మళ్లీ ప్రయత్నించండి.",
    "Added to albums": "ఆల్బమ్లకు జోడించబడింది",
    "Moved to Recently Deleted": "ఇటీవల తొలగించినవి-కు తరలించబడింది",
    Kept: "ఉంచబడింది",
    Skipped: "దాటవేయబడింది",
    Deleted: "తొలగించబడింది",
    "Kept: your choice": "ఉంచబడింది: మీ ఎంపిక",
    "Kept: your pick in Photos": "ఉంచబడింది: ఫోటోలలో మీరు ఎంచుకున్నది",
    "Kept: iPhone's pick": "ఉంచబడింది: iPhone ఎంపిక",
    "Kept: favorite": "ఉంచబడింది: ఇష్టమైనది",
    "Kept: highest resolution": "ఉంచబడింది: అత్యధిక రిజల్యూషన్",
    "Kept: last frame": "ఉంచబడింది: చివరి ఫ్రేమ్",
    "Kept: auto pick": "ఉంచబడింది: ఆటో ఎంపిక",
    " Favorites are kept.": " ఇష్టమైనవి ఉంచబడతాయి.",
    "This keeps the starred frame of each burst and deletes the rest.":
      "ఇది ప్రతి బరస్ట్లో నక్షత్రం గుర్తు పెట్టిన ఫ్రేమ్ను ఉంచి మిగిలినవి తొలగిస్తుంది.",
    "1 burst cleaned down to a single photo.":
      "1 బరస్ట్ ఒకే ఫోటోకు క్లీన్ చేయబడింది.",
    "%lld bursts cleaned down to single photos.":
      "%lld బరస్ట్లు ఒకే ఫోటోలకు క్లీన్ చేయబడ్డాయి.",
    "Album not found.": "ఆల్బమ్ కనుగొనబడలేదు.",
    "Failed to create album.": "ఆల్బమ్ను సృష్టించలేకపోయాం.",
    "Couldn't modify the album. Please try again.":
      "ఆల్బమ్ను మార్చలేకపోయాం. మళ్లీ ప్రయత్నించండి.",
    "Nothing was deleted.": "ఏదీ తొలగించబడలేదు.",
    "Live Photo not found.": "Live Photo కనుగొనబడలేదు.",
    "Could not find still image in Live Photo.":
      "Live Photoలో స్థిర చిత్రం కనుగొనలేకపోయాం.",
    "Invalid image data.": "చెల్లని చిత్ర డేటా.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.":
      "ఫోటో లోడ్ చేయడంలో సమయం మించిపోయింది (అది ఇంకా iCloudలో ఉండవచ్చు). మళ్లీ ప్రయత్నించండి.",
    "The compressed copy is missing from your library.":
      "కుదించిన కాపీ మీ లైబ్రరీలో లేదు.",
    "The converted still is missing from your library.":
      "మార్చిన స్థిర చిత్రం మీ లైబ్రరీలో లేదు.",
    "Copies kept. Both versions are in your library; delete either one in Photos.":
      "కాపీలు ఉంచబడ్డాయి. రెండు వెర్షన్లు మీ లైబ్రరీలో ఉన్నాయి; ఫోటోలలో ఏదైనా ఒకటి తొలగించండి.",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.":
      "%lld అంశాలు తొలగించబడ్డాయి (మొత్తం %lld అంశాలలో). %lld తొలగించలేకపోయాం. మళ్లీ ప్రయత్నించండి.",
    "Your library changed. Scan again before searching.":
      "మీ లైబ్రరీ మారింది. శోధించే ముందు మళ్లీ స్కాన్ చేయండి.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.":
      "మారిన లేదా అందుబాటులో లేని ఫోటోలు తీసివేయబడ్డాయి. కొత్త లేదా సవరించిన ఫోటోలను చేర్చడానికి మళ్లీ స్కాన్ చేయండి.",
    "Recently Deleted": "ఇటీవల తొలగించినవి",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.":
      "అది ఖాళీ చేయబడినప్పుడు స్థలం తిరిగి వస్తుంది. ఫోటోలలో ఆల్బమ్లు తెరిచి, ఆపై ఇటీవల తొలగించినవి తెరవండి.",
    "Manage Apps & System Storage":
      "యాప్లు & సిస్టమ్ నిల్వను నిర్వహించండి",
    "Open Settings ▸ General ▸ iPhone Storage":
      "సెట్టింగ్లు ▸ సాధారణం ▸ iPhone నిల్వ తెరవండి",
    "Library figures below cover only the photos you selected; device totals cover the whole device.":
      "క్రింది లైబ్రరీ గణాంకాలు మీరు ఎంచుకున్న ఫోటోలకు మాత్రమే వర్తిస్తాయి; పరికర మొత్తాలు మొత్తం పరికరానికి వర్తిస్తాయి.",
    "Find exact and near-duplicate photos":
      "ఖచ్చితమైన మరియు దాదాపు నకిలీ ఫోటోలను కనుగొనండి",
    "Spot blurry, dark, and overexposed shots":
      "అస్పష్టమైన, చీకటిగా ఉన్న మరియు అధిక వెలుతురు ఉన్న షాట్లను గుర్తించండి",
    "Surface the biggest files taking up space":
      "ఎక్కువ స్థలం తీసుకుంటున్న అతిపెద్ద ఫైళ్లను చూపించండి",
    "Delete only what you review and approve":
      "మీరు సమీక్షించి ఆమోదించినవి మాత్రమే తొలగించండి",
    "items, all time": "అంశాలు, మొత్తం కాలం",
    "this month": "ఈ నెల",
    "Size unknown": "పరిమాణం తెలియదు",
    "Size unavailable": "పరిమాణం అందుబాటులో లేదు",
    "cleaned up since you started using TidyByte":
      "మీరు TidyByte వాడటం మొదలుపెట్టినప్పటి నుండి శుభ్రం చేయబడింది",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.":
      "ఇంకా కొలవగలిగినది ఏదీ లేదు. iCloudలో మాత్రమే నిల్వ ఉన్న అంశాలు పరిమాణాన్ని నివేదించవు.",
    "Enjoying TidyByte?": "TidyByte నచ్చుతోందా?",
    "Thanks for the support": "మద్దతుకు ధన్యవాదాలు",
    "What should we fix?": "మేము ఏమి సరిచేయాలి?",
    "Tell us what got in the way.": "ఏది అడ్డుపడిందో మాకు చెప్పండి.",
    "Send Feedback": "అభిప్రాయం పంపండి",
    Yes: "అవును",
    "Not really": "అంతగా లేదు",
    "Not now": "ఇప్పుడు కాదు",
    "Your rating helps other people find TidyByte.":
      "మీ రేటింగ్ ఇతరులు TidyByteను కనుగొనడంలో సహాయపడుతుంది.",
    "You just %@.": "మీరు ఇప్పుడే %@.",
    "The message couldn't be sent. Try again, or email us at %@.":
      "సందేశాన్ని పంపలేకపోయాం. మళ్లీ ప్రయత్నించండి, లేదా %@కు మాకు ఇమెయిల్ చేయండి.",
    "No mail account is set up on this device. Email us at %@.":
      "ఈ పరికరంలో మెయిల్ ఖాతా సెట్ చేయబడలేదు. %@కు మాకు ఇమెయిల్ చేయండి.",
    "I just %@": "నేను ఇప్పుడే %@",
    "I'm cleaning up my photo library": "నేను నా ఫోటో లైబ్రరీని శుభ్రం చేస్తున్నాను",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@":
      "%@ — TidyByteతో, ప్రైవేట్గా పరికరంలోనే పనిచేసే ఫోటో క్లీన్అప్ యాప్. %@",
    "Min size: %@": "కనీస పరిమాణం: %@",
    "Swipe history cleared": "స్వైప్ చరిత్ర క్లియర్ చేయబడింది",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.":
      "iOS మీరు నిర్ధారించాలని అడుగుతుంది. తొలగించిన అంశాలు ఫోటోలలోని ఇటీవల తొలగించినవి-కు వెళ్తాయి, అక్కడ 30 రోజుల పాటు పునరుద్ధరించవచ్చు.",
  },
  kn: {
    "Worst Shots": "ಅತ್ಯಂತ ಕಡಿಮೆ ಗುಣಮಟ್ಟದ ಫೋಟೋಗಳು",
    "Review low-scoring photos, lowest first":
      "ಕಡಿಮೆ ಸ್ಕೋರ್ನ ಫೋಟೋಗಳನ್ನು ಪರಿಶೀಲಿಸಿ, ಅತ್ಯಂತ ಕಡಿಮೆ ಇರುವವು ಮೊದಲು",
    "Photos you haven't reviewed yet": "ನೀವು ಇನ್ನೂ ಪರಿಶೀಲಿಸದ ಫೋಟೋಗಳು",
    "Every photo and video in your library":
      "ನಿಮ್ಮ ಲೈಬ್ರರಿಯಲ್ಲಿನ ಪ್ರತಿ ಫೋಟೋ ಮತ್ತು ವೀಡಿಯೊ",
    "Review photos and videos taken on or before a date":
      "ಒಂದು ದಿನಾಂಕದಂದು ಅಥವಾ ಅದಕ್ಕೂ ಮೊದಲು ತೆಗೆದ ಫೋಟೋಗಳನ್ನು ಮತ್ತು ವೀಡಿಯೊಗಳನ್ನು ಪರಿಶೀಲಿಸಿ",
    "Photos not organized into your albums": "ನಿಮ್ಮ ಆಲ್ಬಮ್ಗಳಲ್ಲಿ ಜೋಡಿಸದ ಫೋಟೋಗಳು",
    "Specific Album": "ನಿರ್ದಿಷ್ಟ ಆಲ್ಬಮ್",
    "Review photos from a specific album":
      "ನಿರ್ದಿಷ್ಟ ಆಲ್ಬಮ್ನಿಂದ ಫೋಟೋಗಳನ್ನು ಪರಿಶೀಲಿಸಿ",
    "Marked for deletion. Nothing is deleted until you confirm at the end.":
      "ಅಳಿಸಲು ಗುರುತಿಸಲಾಗಿದೆ. ಕೊನೆಯಲ್ಲಿ ನೀವು ಖಚಿತಪಡಿಸುವವರೆಗೆ ಏನೂ ಅಳಿಸುವುದಿಲ್ಲ.",
    "Delete is off until the photo loads.":
      "ಫೋಟೋ ಲೋಡ್ ಆಗುವವರೆಗೆ ಅಳಿಸುವಿಕೆ ಆಫ್ ಆಗಿರುತ್ತದೆ.",
    "Pinch or double-tap a photo to inspect it":
      "ಫೋಟೋವನ್ನು ಪರಿಶೀಲಿಸಲು ಪಿಂಚ್ ಮಾಡಿ ಅಥವಾ ಎರಡು ಬಾರಿ ಟ್ಯಾಪ್ ಮಾಡಿ",
    "That photo can't be undone anymore.":
      "ಆ ಫೋಟೋವನ್ನು ಇನ್ನು ಹಿಂತಿರುಗಿಸಲಾಗುವುದಿಲ್ಲ.",
    "Undo your newer actions first to reach that photo.":
      "ಆ ಫೋಟೋ ತಲುಪಲು ಮೊದಲು ನಿಮ್ಮ ಹೊಸ ಕ್ರಿಯೆಗಳನ್ನು ಹಿಂತಿರುಗಿಸಿ.",
    "Your library changed during analysis. Try Worst Shots again.":
      'ವಿಶ್ಲೇಷಣೆ ನಡೆಯುವಾಗ ನಿಮ್ಮ ಲೈಬ್ರರಿ ಬದಲಾಯಿತು. "ಅತ್ಯಂತ ಕಡಿಮೆ ಗುಣಮಟ್ಟದ ಫೋಟೋಗಳು" ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.',
    "No photo is waiting to be filed. Dismiss and try again.":
      "ಜೋಡಿಸಲು ಯಾವ ಫೋಟೋವೂ ಕಾಯುತ್ತಿಲ್ಲ. ಮುಚ್ಚಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
    "Still adding — please wait a moment and try again.":
      "ಇನ್ನೂ ಸೇರಿಸುತ್ತಿದೆ — ಸ್ವಲ್ಪ ಕಾಯಿರಿ ಮತ್ತು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
    "Couldn't save your changes. Please try again.":
      "ನಿಮ್ಮ ಬದಲಾವಣೆಗಳನ್ನು ಉಳಿಸಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
    "Added to albums": "ಆಲ್ಬಮ್ಗಳಿಗೆ ಸೇರಿಸಲಾಗಿದೆ",
    "Moved to Recently Deleted": "ಇತ್ತೀಚೆಗೆ ಅಳಿಸಿದವು ಗೆ ಸರಿಸಲಾಗಿದೆ",
    Kept: "ಇರಿಸಲಾಗಿದೆ",
    Skipped: "ಬಿಟ್ಟುಬಿಡಲಾಗಿದೆ",
    Deleted: "ಅಳಿಸಲಾಗಿದೆ",
    "Kept: your choice": "ಇರಿಸಲಾಗಿದೆ: ನಿಮ್ಮ ಆಯ್ಕೆ",
    "Kept: your pick in Photos":
      "ಇರಿಸಲಾಗಿದೆ: ಫೋಟೋಗಳ ಆ್ಯಪ್ನಲ್ಲಿ ನೀವು ಆಯ್ಕೆ ಮಾಡಿದ್ದು",
    "Kept: iPhone's pick": "ಇರಿಸಲಾಗಿದೆ: iPhone ಆಯ್ಕೆ",
    "Kept: favorite": "ಇರಿಸಲಾಗಿದೆ: ಮೆಚ್ಚಿನದು",
    "Kept: highest resolution": "ಇರಿಸಲಾಗಿದೆ: ಅತ್ಯಧಿಕ ರೆಸಲ್ಯೂಶನ್",
    "Kept: last frame": "ಇರಿಸಲಾಗಿದೆ: ಕೊನೆಯ ಫ್ರೇಮ್",
    "Kept: auto pick": "ಇರಿಸಲಾಗಿದೆ: ಸ್ವಯಂ ಆಯ್ಕೆ",
    " Favorites are kept.": " ಮೆಚ್ಚಿನವು ಇರಿಸಲಾಗುತ್ತವೆ.",
    "This keeps the starred frame of each burst and deletes the rest.":
      "ಇದು ಪ್ರತಿ ಬರ್ಸ್ಟ್ನ ನಕ್ಷತ್ರ ಗುರುತಿನ ಫ್ರೇಮ್ ಅನ್ನು ಇರಿಸಿ ಉಳಿದವನ್ನು ಅಳಿಸುತ್ತದೆ.",
    "1 burst cleaned down to a single photo.":
      "1 ಬರ್ಸ್ಟ್ ಒಂದೇ ಫೋಟೋಗೆ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ.",
    "%lld bursts cleaned down to single photos.":
      "%lld ಬರ್ಸ್ಟ್ಗಳನ್ನು ಒಂದೇ ಫೋಟೋಗಳಿಗೆ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ.",
    "Album not found.": "ಆಲ್ಬಮ್ ಕಂಡುಬಂದಿಲ್ಲ.",
    "Failed to create album.": "ಆಲ್ಬಮ್ ರಚಿಸಲಾಗಲಿಲ್ಲ.",
    "Couldn't modify the album. Please try again.":
      "ಆಲ್ಬಮ್ ಅನ್ನು ಬದಲಾಯಿಸಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
    "Nothing was deleted.": "ಏನೂ ಅಳಿಸಲಾಗಿಲ್ಲ.",
    "Live Photo not found.": "Live Photo ಕಂಡುಬಂದಿಲ್ಲ.",
    "Could not find still image in Live Photo.":
      "Live Photo ನಲ್ಲಿ ಸ್ಟಿಲ್ ಚಿತ್ರ ಕಂಡುಬಂದಿಲ್ಲ.",
    "Invalid image data.": "ಅಮಾನ್ಯ ಚಿತ್ರ ಡೇಟಾ.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.":
      "ಫೋಟೋ ಲೋಡ್ ಮಾಡುವಾಗ ಸಮಯ ಮೀರಿತು (ಅದು ಇನ್ನೂ iCloud ನಲ್ಲಿರಬಹುದು). ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
    "The compressed copy is missing from your library.":
      "ಸಂಕುಚಿಸಿದ ಪ್ರತಿ ನಿಮ್ಮ ಲೈಬ್ರರಿಯಲ್ಲಿಲ್ಲ.",
    "The converted still is missing from your library.":
      "ಪರಿವರ್ತಿಸಿದ ಸ್ಟಿಲ್ ನಿಮ್ಮ ಲೈಬ್ರರಿಯಲ್ಲಿಲ್ಲ.",
    "Copies kept. Both versions are in your library; delete either one in Photos.":
      "ಪ್ರತಿಗಳನ್ನು ಇರಿಸಲಾಗಿದೆ. ಎರಡೂ ಆವೃತ್ತಿಗಳು ನಿಮ್ಮ ಲೈಬ್ರರಿಯಲ್ಲಿವೆ; ಫೋಟೋಗಳ ಆ್ಯಪ್ನಲ್ಲಿ ಒಂದನ್ನು ಅಳಿಸಿ.",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.":
      "%lld ಐಟಂಗಳನ್ನು ಅಳಿಸಲಾಗಿದೆ (ಒಟ್ಟು %lld ಐಟಂಗಳಲ್ಲಿ). %lld ಅಳಿಸಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
    "Your library changed. Scan again before searching.":
      "ನಿಮ್ಮ ಲೈಬ್ರರಿ ಬದಲಾಗಿದೆ. ಹುಡುಕುವ ಮೊದಲು ಮತ್ತೆ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.":
      "ಬದಲಾದ ಅಥವಾ ಲಭ್ಯವಿಲ್ಲದ ಫೋಟೋಗಳನ್ನು ತೆಗೆದುಹಾಕಲಾಗಿದೆ. ಹೊಸ ಅಥವಾ ಸಂಪಾದಿಸಿದ ಫೋಟೋಗಳನ್ನು ಸೇರಿಸಲು ಮತ್ತೆ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ.",
    "Recently Deleted": "ಇತ್ತೀಚೆಗೆ ಅಳಿಸಿದವು",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.":
      "ಅದನ್ನು ಖಾಲಿ ಮಾಡಿದಾಗ ಜಾಗ ಮರಳಿ ಬರುತ್ತದೆ. ಫೋಟೋಗಳ ಆ್ಯಪ್ನಲ್ಲಿ ಆಲ್ಬಮ್ಗಳು ತೆರೆದು, ನಂತರ ಇತ್ತೀಚೆಗೆ ಅಳಿಸಿದವು ತೆರೆಯಿರಿ.",
    "Manage Apps & System Storage":
      "ಆ್ಯಪ್ಗಳು ಮತ್ತು ಸಿಸ್ಟಂ ಸಂಗ್ರಹಣೆ ನಿರ್ವಹಿಸಿ",
    "Open Settings ▸ General ▸ iPhone Storage":
      "ಸೆಟ್ಟಿಂಗ್ಗಳು ▸ ಸಾಮಾನ್ಯ ▸ iPhone ಸಂಗ್ರಹಣೆ ತೆರೆಯಿರಿ",
    "Library figures below cover only the photos you selected; device totals cover the whole device.":
      "ಕೆಳಗಿನ ಲೈಬ್ರರಿ ಅಂಕಿಅಂಶಗಳು ನೀವು ಆಯ್ಕೆಮಾಡಿದ ಫೋಟೋಗಳಿಗೆ ಮಾತ್ರ ಅನ್ವಯಿಸುತ್ತವೆ; ಸಾಧನದ ಒಟ್ಟು ಮೊತ್ತಗಳು ಇಡೀ ಸಾಧನಕ್ಕೆ ಅನ್ವಯಿಸುತ್ತವೆ.",
    "Find exact and near-duplicate photos":
      "ಖಚಿತ ಮತ್ತು ಬಹುತೇಕ ಸಮಾನ ನಕಲಿ ಫೋಟೋಗಳನ್ನು ಹುಡುಕಿ",
    "Spot blurry, dark, and overexposed shots":
      "ಅಸ್ಪಷ್ಟ, ಗಾಢ ಮತ್ತು ಅತಿ ಹೆಚ್ಚು ಬೆಳಕಿನ ಫೋಟೋಗಳನ್ನು ಗುರುತಿಸಿ",
    "Surface the biggest files taking up space":
      "ಜಾಗ ತೆಗೆದುಕೊಳ್ಳುತ್ತಿರುವ ಅತಿದೊಡ್ಡ ಫೈಲ್ಗಳನ್ನು ತೋರಿಸಿ",
    "Delete only what you review and approve":
      "ನೀವು ಪರಿಶೀಲಿಸಿ ಅನುಮೋದಿಸಿದ್ದನ್ನು ಮಾತ್ರ ಅಳಿಸಿ",
    "items, all time": "ಐಟಂಗಳು, ಒಟ್ಟು ಅವಧಿ",
    "this month": "ಈ ತಿಂಗಳು",
    "Size unknown": "ಗಾತ್ರ ತಿಳಿದಿಲ್ಲ",
    "Size unavailable": "ಗಾತ್ರ ಲಭ್ಯವಿಲ್ಲ",
    "cleaned up since you started using TidyByte":
      "ನೀವು TidyByte ಬಳಸಲು ಪ್ರಾರಂಭಿಸಿದಾಗಿನಿಂದ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.":
      "ಇನ್ನೂ ಅಳೆಯಬಹುದಾದದ್ದು ಏನೂ ಇಲ್ಲ. iCloud ನಲ್ಲಿ ಮಾತ್ರ ಸಂಗ್ರಹವಾಗಿರುವ ಐಟಂಗಳು ಗಾತ್ರವನ್ನು ತಿಳಿಸುವುದಿಲ್ಲ.",
    "Enjoying TidyByte?": "TidyByte ಇಷ್ಟವಾಗುತ್ತಿದೆಯೇ?",
    "Thanks for the support": "ಬೆಂಬಲಕ್ಕೆ ಧನ್ಯವಾದಗಳು",
    "What should we fix?": "ನಾವು ಏನನ್ನು ಸರಿಪಡಿಸಬೇಕು?",
    "Tell us what got in the way.": "ಏನು ಅಡ್ಡಿಯಾಯಿತು ಎಂದು ನಮಗೆ ತಿಳಿಸಿ.",
    "Send Feedback": "ಪ್ರತಿಕ್ರಿಯೆ ಕಳುಹಿಸಿ",
    Yes: "ಹೌದು",
    "Not really": "ಹಾಗಿಲ್ಲ",
    "Not now": "ಈಗ ಬೇಡ",
    "Your rating helps other people find TidyByte.":
      "ನಿಮ್ಮ ರೇಟಿಂಗ್ ಇತರರಿಗೆ TidyByte ಹುಡುಕಲು ಸಹಾಯ ಮಾಡುತ್ತದೆ.",
    "You just %@.": "ನೀವು ಈಗತಾನೇ %@.",
    "The message couldn't be sent. Try again, or email us at %@.":
      "ಸಂದೇಶ ಕಳುಹಿಸಲಾಗಲಿಲ್ಲ. ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ, ಅಥವಾ %@ ಗೆ ನಮಗೆ ಇಮೇಲ್ ಮಾಡಿ.",
    "No mail account is set up on this device. Email us at %@.":
      "ಈ ಸಾಧನದಲ್ಲಿ ಇಮೇಲ್ ಖಾತೆ ಸೆಟಪ್ ಆಗಿಲ್ಲ. %@ ಗೆ ನಮಗೆ ಇಮೇಲ್ ಮಾಡಿ.",
    "I just %@": "ನಾನು ಈಗತಾನೇ %@",
    "I'm cleaning up my photo library":
      "ನಾನು ನನ್ನ ಫೋಟೋ ಲೈಬ್ರರಿಯನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸುತ್ತಿದ್ದೇನೆ",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@":
      "%@ — TidyByte ನೊಂದಿಗೆ, ಖಾಸಗಿಯಾಗಿ ನಿಮ್ಮ ಸಾಧನದಲ್ಲೇ ಕೆಲಸ ಮಾಡುವ ಫೋಟೋ ಕ್ಲೀನ್ಅಪ್ ಆ್ಯಪ್. %@",
    "Min size: %@": "ಕನಿಷ್ಠ ಗಾತ್ರ: %@",
    "Swipe history cleared": "ಸ್ವೈಪ್ ಇತಿಹಾಸ ತೆರವುಗೊಳಿಸಲಾಗಿದೆ",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.":
      "iOS ನಿಮ್ಮನ್ನು ಖಚಿತಪಡಿಸಲು ಕೇಳುತ್ತದೆ. ಅಳಿಸಿದ ಐಟಂಗಳು ಫೋಟೋಗಳ ಆ್ಯಪ್ನ ಇತ್ತೀಚೆಗೆ ಅಳಿಸಿದವು ಗೆ ಹೋಗುತ್ತವೆ, ಅಲ್ಲಿ ನೀವು ಅವನ್ನು 30 ದಿನಗಳವರೆಗೆ ಮರುಸ್ಥಾಪಿಸಬಹುದು.",
  },
  ml: {
    "Worst Shots": "ഏറ്റവും മോശം ഫോട്ടോകൾ",
    "Review low-scoring photos, lowest first":
      "കുറഞ്ഞ സ്കോറുള്ള ഫോട്ടോകൾ പരിശോധിക്കുക, ഏറ്റവും കുറഞ്ഞവ ആദ്യം",
    "Photos you haven't reviewed yet": "നിങ്ങൾ ഇതുവരെ പരിശോധിക്കാത്ത ഫോട്ടോകൾ",
    "Every photo and video in your library":
      "നിങ്ങളുടെ ലൈബ്രറിയിലെ ഓരോ ഫോട്ടോയും വീഡിയോയും",
    "Review photos and videos taken on or before a date":
      "ഒരു തീയതിയിലോ അതിനു മുമ്പോ എടുത്ത ഫോട്ടോകളും വീഡിയോകളും പരിശോധിക്കുക",
    "Photos not organized into your albums":
      "നിങ്ങളുടെ ആൽബങ്ങളിൽ ക്രമീകരിക്കാത്ത ഫോട്ടോകൾ",
    "Specific Album": "നിർദിഷ്ട ആൽബം",
    "Review photos from a specific album":
      "ഒരു നിർദിഷ്ട ആൽബത്തിൽ നിന്ന് ഫോട്ടോകൾ പരിശോധിക്കുക",
    "Marked for deletion. Nothing is deleted until you confirm at the end.":
      "ഇല്ലാതാക്കാൻ അടയാളപ്പെടുത്തി. അവസാനം നിങ്ങൾ സ്ഥിരീകരിക്കുന്നതുവരെ ഒന്നും ഇല്ലാതാക്കില്ല.",
    "Delete is off until the photo loads.":
      "ഫോട്ടോ ലോഡ് ആകുന്നതുവരെ ഇല്ലാതാക്കൽ ഓഫ് ആയിരിക്കും.",
    "Pinch or double-tap a photo to inspect it":
      "ഫോട്ടോ പരിശോധിക്കാൻ പിഞ്ച് ചെയ്യുക അല്ലെങ്കിൽ രണ്ടുതവണ ടാപ്പ് ചെയ്യുക",
    "That photo can't be undone anymore.":
      "ആ ഫോട്ടോ ഇനി പഴയപടിയാക്കാനാകില്ല.",
    "Undo your newer actions first to reach that photo.":
      "ആ ഫോട്ടോയിൽ എത്താൻ ആദ്യം നിങ്ങളുടെ പുതിയ നടപടികൾ പഴയപടിയാക്കുക.",
    "Your library changed during analysis. Try Worst Shots again.":
      'വിശകലനം നടക്കുമ്പോൾ നിങ്ങളുടെ ലൈബ്രറി മാറി. "ഏറ്റവും മോശം ഫോട്ടോകൾ" വീണ്ടും ശ്രമിക്കുക.',
    "No photo is waiting to be filed. Dismiss and try again.":
      "ചേർക്കാൻ കാത്തിരിക്കുന്ന ഫോട്ടോ ഒന്നുമില്ല. അടച്ച് വീണ്ടും ശ്രമിക്കുക.",
    "Still adding — please wait a moment and try again.":
      "ഇപ്പോഴും ചേർക്കുന്നു — ഒരു നിമിഷം കാത്തിരുന്ന് വീണ്ടും ശ്രമിക്കുക.",
    "Couldn't save your changes. Please try again.":
      "നിങ്ങളുടെ മാറ്റങ്ങൾ സേവ് ചെയ്യാനായില്ല. വീണ്ടും ശ്രമിക്കുക.",
    "Added to albums": "ആൽബങ്ങളിൽ ചേർത്തു",
    "Moved to Recently Deleted":
      "അടുത്തിടെ ഇല്ലാതാക്കിയവ യിലേക്ക് മാറ്റി",
    Kept: "നിലനിർത്തി",
    Skipped: "ഒഴിവാക്കി",
    Deleted: "ഇല്ലാതാക്കി",
    "Kept: your choice": "നിലനിർത്തി: നിങ്ങളുടെ തിരഞ്ഞെടുപ്പ്",
    "Kept: your pick in Photos":
      "നിലനിർത്തി: ഫോട്ടോകൾ ആപ്പിൽ നിങ്ങൾ തിരഞ്ഞെടുത്തത്",
    "Kept: iPhone's pick": "നിലനിർത്തി: iPhone തിരഞ്ഞെടുത്തത്",
    "Kept: favorite": "നിലനിർത്തി: പ്രിയപ്പെട്ടത്",
    "Kept: highest resolution": "നിലനിർത്തി: ഏറ്റവും ഉയർന്ന റെസല്യൂഷൻ",
    "Kept: last frame": "നിലനിർത്തി: അവസാന ഫ്രെയിം",
    "Kept: auto pick": "നിലനിർത്തി: സ്വയം തിരഞ്ഞെടുത്തത്",
    " Favorites are kept.": " പ്രിയപ്പെട്ടവ നിലനിർത്തുന്നു.",
    "This keeps the starred frame of each burst and deletes the rest.":
      "ഇത് ഓരോ ബർസ്റ്റിന്റെയും നക്ഷത്രമിട്ട ഫ്രെയിം നിലനിർത്തി ബാക്കിയുള്ളവ ഇല്ലാതാക്കും.",
    "1 burst cleaned down to a single photo.":
      "1 ബർസ്റ്റ് ഒരു ഫോട്ടോയിലേക്ക് ക്ലീൻ ചെയ്തു.",
    "%lld bursts cleaned down to single photos.":
      "%lld ബർസ്റ്റുകൾ ഒറ്റ ഫോട്ടോകളിലേക്ക് ക്ലീൻ ചെയ്തു.",
    "Album not found.": "ആൽബം കണ്ടെത്തിയില്ല.",
    "Failed to create album.": "ആൽബം സൃഷ്ടിക്കാനായില്ല.",
    "Couldn't modify the album. Please try again.":
      "ആൽബം മാറ്റാനായില്ല. വീണ്ടും ശ്രമിക്കുക.",
    "Nothing was deleted.": "ഒന്നും ഇല്ലാതാക്കിയിട്ടില്ല.",
    "Live Photo not found.": "Live Photo കണ്ടെത്തിയില്ല.",
    "Could not find still image in Live Photo.":
      "Live Photo-ൽ സ്റ്റിൽ ഇമേജ് കണ്ടെത്താനായില്ല.",
    "Invalid image data.": "അസാധുവായ ഇമേജ് ഡാറ്റ.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.":
      "ഫോട്ടോ ലോഡ് ചെയ്യുന്നതിൽ സമയം കഴിഞ്ഞു (അത് ഇപ്പോഴും iCloud-ൽ ആകാം). വീണ്ടും ശ്രമിക്കുക.",
    "The compressed copy is missing from your library.":
      "കംപ്രസ് ചെയ്ത പകർപ്പ് നിങ്ങളുടെ ലൈബ്രറിയിൽ ഇല്ല.",
    "The converted still is missing from your library.":
      "മാറ്റിയ സ്റ്റിൽ നിങ്ങളുടെ ലൈബ്രറിയിൽ ഇല്ല.",
    "Copies kept. Both versions are in your library; delete either one in Photos.":
      "പകർപ്പുകൾ നിലനിർത്തി. രണ്ട് പതിപ്പുകളും നിങ്ങളുടെ ലൈബ്രറിയിലുണ്ട്; ഫോട്ടോകൾ ആപ്പിൽ ഏതെങ്കിലും ഒന്ന് ഇല്ലാതാക്കുക.",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.":
      "%lld ഇനങ്ങൾ ഇല്ലാതാക്കി (ആകെ %lld ഇനങ്ങളിൽ). %lld ഇല്ലാതാക്കാനായില്ല. വീണ്ടും ശ്രമിക്കുക.",
    "Your library changed. Scan again before searching.":
      "നിങ്ങളുടെ ലൈബ്രറി മാറി. തിരയുന്നതിന് മുമ്പ് വീണ്ടും സ്കാൻ ചെയ്യുക.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.":
      "മാറിയതോ ലഭ്യമല്ലാത്തതോ ആയ ഫോട്ടോകൾ നീക്കി. പുതിയതോ എഡിറ്റ് ചെയ്തതോ ആയ ഫോട്ടോകൾ ഉൾപ്പെടുത്താൻ വീണ്ടും സ്കാൻ ചെയ്യുക.",
    "Recently Deleted": "അടുത്തിടെ ഇല്ലാതാക്കിയവ",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.":
      "അത് ഒഴിവാക്കുമ്പോൾ സ്ഥലം തിരികെ ലഭിക്കും. ഫോട്ടോകൾ ആപ്പിൽ ആൽബങ്ങൾ തുറന്ന്, എന്നിട്ട് അടുത്തിടെ ഇല്ലാതാക്കിയവ തുറക്കുക.",
    "Manage Apps & System Storage":
      "ആപ്പുകളും സിസ്റ്റം സ്റ്റോറേജും നിയന്ത്രിക്കുക",
    "Open Settings ▸ General ▸ iPhone Storage":
      "സെറ്റിംഗ്സ് ▸ ജനറൽ ▸ iPhone സ്റ്റോറേജ് തുറക്കുക",
    "Library figures below cover only the photos you selected; device totals cover the whole device.":
      "താഴെയുള്ള ലൈബ്രറി കണക്കുകൾ നിങ്ങൾ തിരഞ്ഞെടുത്ത ഫോട്ടോകൾക്ക് മാത്രമുള്ളതാണ്; ഉപകരണത്തിന്റെ ആകെത്തുക മുഴുവൻ ഉപകരണത്തിനും ബാധകമാണ്.",
    "Find exact and near-duplicate photos":
      "കൃത്യവും ഏകദേശവുമായ ഡ്യൂപ്ലിക്കേറ്റ് ഫോട്ടോകൾ കണ്ടെത്തുക",
    "Spot blurry, dark, and overexposed shots":
      "മങ്ങിയതും ഇരുണ്ടതും അധിക വെളിച്ചമുള്ളതുമായ ഫോട്ടോകൾ കണ്ടെത്തുക",
    "Surface the biggest files taking up space":
      "സ്ഥലം എടുക്കുന്ന ഏറ്റവും വലിയ ഫയലുകൾ കാണിക്കുക",
    "Delete only what you review and approve":
      "നിങ്ങൾ പരിശോധിച്ച് അംഗീകരിക്കുന്നത് മാത്രം ഇല്ലാതാക്കുക",
    "items, all time": "ഇനങ്ങൾ, എക്കാലവും",
    "this month": "ഈ മാസം",
    "Size unknown": "വലിപ്പം അറിയില്ല",
    "Size unavailable": "വലിപ്പം ലഭ്യമല്ല",
    "cleaned up since you started using TidyByte":
      "നിങ്ങൾ TidyByte ഉപയോഗിച്ചു തുടങ്ങിയതിനു ശേഷം ക്ലീൻ ചെയ്തത്",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.":
      "ഇതുവരെ അളക്കാവുന്നത് ഒന്നുമില്ല. iCloud-ൽ മാത്രം സൂക്ഷിച്ച ഇനങ്ങൾ വലിപ്പം റിപ്പോർട്ട് ചെയ്യുന്നില്ല.",
    "Enjoying TidyByte?": "TidyByte ഇഷ്ടമാകുന്നുണ്ടോ?",
    "Thanks for the support": "പിന്തുണയ്ക്ക് നന്ദി",
    "What should we fix?": "ഞങ്ങൾ എന്ത് ശരിയാക്കണം?",
    "Tell us what got in the way.":
      "എന്താണ് തടസ്സമായതെന്ന് ഞങ്ങളോട് പറയുക.",
    "Send Feedback": "ഫീഡ്ബാക്ക് അയയ്ക്കുക",
    Yes: "അതെ",
    "Not really": "അത്രയല്ല",
    "Not now": "ഇപ്പോൾ വേണ്ട",
    "Your rating helps other people find TidyByte.":
      "നിങ്ങളുടെ റേറ്റിംഗ് മറ്റുള്ളവരെ TidyByte കണ്ടെത്താൻ സഹായിക്കുന്നു.",
    "You just %@.": "നിങ്ങൾ ഇപ്പോൾ %@.",
    "The message couldn't be sent. Try again, or email us at %@.":
      "സന്ദേശം അയയ്ക്കാനായില്ല. വീണ്ടും ശ്രമിക്കുക, അല്ലെങ്കിൽ %@-ലേക്ക് ഞങ്ങൾക്ക് ഇമെയിൽ ചെയ്യുക.",
    "No mail account is set up on this device. Email us at %@.":
      "ഈ ഉപകരണത്തിൽ മെയിൽ അക്കൗണ്ട് സെറ്റ് ചെയ്തിട്ടില്ല. %@-ലേക്ക് ഞങ്ങൾക്ക് ഇമെയിൽ ചെയ്യുക.",
    "I just %@": "ഞാൻ ഇപ്പോൾ %@",
    "I'm cleaning up my photo library":
      "ഞാൻ എന്റെ ഫോട്ടോ ലൈബ്രറി ക്ലീൻ ചെയ്യുന്നു",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@":
      "%@ — TidyByte ഉപയോഗിച്ച്, സ്വകാര്യവും ഉപകരണത്തിൽ തന്നെ പ്രവർത്തിക്കുന്നതുമായ ഫോട്ടോ ക്ലീനപ്പ് ആപ്പ്. %@",
    "Min size: %@": "കുറഞ്ഞ വലിപ്പം: %@",
    "Swipe history cleared": "സ്വൈപ്പ് ചരിത്രം മായ്ച്ചു",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.":
      "iOS നിങ്ങളോട് സ്ഥിരീകരിക്കാൻ ആവശ്യപ്പെടും. ഇല്ലാതാക്കിയ ഇനങ്ങൾ ഫോട്ടോകൾ ആപ്പിലെ അടുത്തിടെ ഇല്ലാതാക്കിയവ യിലേക്ക് പോകുന്നു, അവിടെ നിങ്ങൾക്ക് 30 ദിവസത്തേക്ക് അവ തിരികെ കൊണ്ടുവരാം.",
  },
  ru: {
    "Worst Shots": "Худшие снимки",
    "Review low-scoring photos, lowest first":
      "Просмотрите снимки с низкой оценкой, сначала самые низкие",
    "Photos you haven't reviewed yet": "Снимки, которые вы еще не просмотрели",
    "Every photo and video in your library": "Все фото и видео в вашей медиатеке",
    "Review photos and videos taken on or before a date":
      "Просмотрите фото и видео, снятые в указанную дату или раньше",
    "Photos not organized into your albums":
      "Фото, не распределенные по вашим альбомам",
    "Specific Album": "Определенный альбом",
    "Review photos from a specific album":
      "Просмотрите фото из определенного альбома",
    "Marked for deletion. Nothing is deleted until you confirm at the end.":
      "Помечено для удаления. Ничего не удаляется, пока вы не подтвердите в конце.",
    "Delete is off until the photo loads.":
      "Удаление отключено, пока фото не загрузится.",
    "Pinch or double-tap a photo to inspect it":
      "Сведите пальцы или дважды коснитесь фото, чтобы рассмотреть его",
    "That photo can't be undone anymore.": "Это фото больше нельзя вернуть.",
    "Undo your newer actions first to reach that photo.":
      "Чтобы добраться до этого фото, сначала отмените более поздние действия.",
    "Your library changed during analysis. Try Worst Shots again.":
      "Во время анализа медиатека изменилась. Попробуйте «Худшие снимки» снова.",
    "No photo is waiting to be filed. Dismiss and try again.":
      "Нет фото, ожидающего помещения в альбом. Закройте и повторите попытку.",
    "Still adding — please wait a moment and try again.":
      "Еще добавляется — подождите немного и повторите попытку.",
    "Couldn't save your changes. Please try again.":
      "Не удалось сохранить изменения. Повторите попытку.",
    "Added to albums": "Добавлено в альбомы",
    "Moved to Recently Deleted": "Перемещено в «Недавно удаленные»",
    Kept: "Оставлено",
    Skipped: "Пропущено",
    Deleted: "Удалено",
    "Kept: your choice": "Оставлено: ваш выбор",
    "Kept: your pick in Photos": "Оставлено: ваш выбор в «Фото»",
    "Kept: iPhone's pick": "Оставлено: выбор iPhone",
    "Kept: favorite": "Оставлено: избранное",
    "Kept: highest resolution": "Оставлено: самое высокое разрешение",
    "Kept: last frame": "Оставлено: последний кадр",
    "Kept: auto pick": "Оставлено: авто-выбор",
    " Favorites are kept.": " Избранное остается.",
    "This keeps the starred frame of each burst and deletes the rest.":
      "Так сохраняется помеченный кадр каждой серии, а остальные удаляются.",
    "1 burst cleaned down to a single photo.":
      "1 серия сокращена до одного фото.",
    "%lld bursts cleaned down to single photos.":
      "%lld серий сокращено до одиночных фото.",
    "Album not found.": "Альбом не найден.",
    "Failed to create album.": "Не удалось создать альбом.",
    "Couldn't modify the album. Please try again.":
      "Не удалось изменить альбом. Повторите попытку.",
    "Nothing was deleted.": "Ничего не удалено.",
    "Live Photo not found.": "Live Photo не найден.",
    "Could not find still image in Live Photo.":
      "Не удалось найти статичное изображение в Live Photo.",
    "Invalid image data.": "Недопустимые данные изображения.",
    "Timed out loading the photo (it may still be in iCloud). Please try again.":
      "Истекло время загрузки фото (возможно, оно еще в iCloud). Повторите попытку.",
    "The compressed copy is missing from your library.":
      "Сжатой копии нет в вашей медиатеке.",
    "The converted still is missing from your library.":
      "Преобразованного статичного фото нет в вашей медиатеке.",
    "Copies kept. Both versions are in your library; delete either one in Photos.":
      "Копии сохранены. Обе версии есть в вашей медиатеке; удалите любую из них в «Фото».",
    "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.":
      "Удалено %lld из %lld объектов. Не удалось удалить %lld. Повторите попытку.",
    "Your library changed. Scan again before searching.":
      "Медиатека изменилась. Повторите сканирование перед поиском.",
    "Removed changed or unavailable photos. Scan again to include new or edited photos.":
      "Измененные или недоступные фото убраны. Повторите сканирование, чтобы включить новые и отредактированные фото.",
    "Recently Deleted": "Недавно удаленные",
    "Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.":
      "Место вернется, когда оно будет очищено. В «Фото» откройте «Альбомы», затем «Недавно удаленные».",
    "Manage Apps & System Storage":
      "Управление программами и системным хранилищем",
    "Open Settings ▸ General ▸ iPhone Storage":
      "Откройте «Настройки» ▸ «Основные» ▸ «Хранилище iPhone»",
    "Library figures below cover only the photos you selected; device totals cover the whole device.":
      "Цифры по медиатеке ниже охватывают только выбранные вами фото; итоги по устройству относятся ко всему устройству.",
    "Find exact and near-duplicate photos":
      "Находит точные и почти одинаковые дубликаты фото",
    "Spot blurry, dark, and overexposed shots":
      "Находит размытые, темные и пересвеченные снимки",
    "Surface the biggest files taking up space":
      "Показывает самые большие файлы, занимающие место",
    "Delete only what you review and approve":
      "Удаляет только то, что вы просмотрели и одобрили",
    "items, all time": "объектов, за все время",
    "this month": "в этом месяце",
    "Size unknown": "Размер неизвестен",
    "Size unavailable": "Размер недоступен",
    "cleaned up since you started using TidyByte":
      "очищено с тех пор, как вы начали пользоваться TidyByte",
    "Nothing measurable yet. Items stored only in iCloud don't report a size.":
      "Пока нечего измерить. Объекты, хранящиеся только в iCloud, не сообщают размер.",
    "Enjoying TidyByte?": "Нравится TidyByte?",
    "Thanks for the support": "Спасибо за поддержку",
    "What should we fix?": "Что нам исправить?",
    "Tell us what got in the way.": "Расскажите, что вам помешало.",
    "Send Feedback": "Отправить отзыв",
    Yes: "Да",
    "Not really": "Не очень",
    "Not now": "Не сейчас",
    "Your rating helps other people find TidyByte.":
      "Ваша оценка помогает другим найти TidyByte.",
    "You just %@.": "Вы только что %@.",
    "The message couldn't be sent. Try again, or email us at %@.":
      "Не удалось отправить сообщение. Повторите попытку или напишите нам на %@.",
    "No mail account is set up on this device. Email us at %@.":
      "На этом устройстве не настроен аккаунт электронной почты. Напишите нам на %@.",
    "I just %@": "Я только что %@",
    "I'm cleaning up my photo library":
      "Я привожу в порядок свою медиатеку",
    "%@ with TidyByte — a private, on-device photo cleanup app. %@":
      "%@ с TidyByte — приватным приложением для очистки фото, которое работает только на вашем устройстве. %@",
    "Min size: %@": "Мин. размер: %@",
    "Swipe history cleared": "История свайпов очищена",
    "iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.":
      "iOS попросит вас подтвердить. Удаленные объекты попадают в «Недавно удаленные» в «Фото», где их можно восстановить в течение 30 дней.",
  },
};

// --------------------------------------------------------------- plural keys

// one/few/many/other for ru, one/other for the rest.
const PLURALS = {
  te: {
    "cleared %lld photo": [
      "%lld ఫోటో శుభ్రం చేయబడింది",
      "%lld ఫోటోలు శుభ్రం చేయబడ్డాయి",
    ],
    "cleared %lld blurry photo": [
      "%lld అస్పష్టమైన ఫోటో శుభ్రం చేయబడింది",
      "%lld అస్పష్టమైన ఫోటోలు శుభ్రం చేయబడ్డాయి",
    ],
    "cleared %lld screenshot": [
      "%lld స్క్రీన్షాట్ శుభ్రం చేయబడింది",
      "%lld స్క్రీన్షాట్లు శుభ్రం చేయబడ్డాయి",
    ],
    "cleared %lld large file": [
      "%lld పెద్ద ఫైల్ శుభ్రం చేయబడింది",
      "%lld పెద్ద ఫైళ్లు శుభ్రం చేయబడ్డాయి",
    ],
    "cleared %lld burst frame": [
      "%lld బరస్ట్ ఫ్రేమ్ శుభ్రం చేయబడింది",
      "%lld బరస్ట్ ఫ్రేమ్లు శుభ్రం చేయబడ్డాయి",
    ],
    "cleared %lld item (%@)": [
      "%lld అంశం శుభ్రం చేయబడింది (%@)",
      "%lld అంశాలు శుభ్రం చేయబడ్డాయి (%@)",
    ],
    "removed %lld duplicate": [
      "%lld నకిలీ తీసివేయబడింది",
      "%lld నకిలీలు తీసివేయబడ్డాయి",
    ],
    "removed %lld similar photo": [
      "%lld సమానమైన ఫోటో తీసివేయబడింది",
      "%lld సమానమైన ఫోటోలు తీసివేయబడ్డాయి",
    ],
    "compressed %lld photo": [
      "%lld ఫోటో కుదించబడింది",
      "%lld ఫోటోలు కుదించబడ్డాయి",
    ],
    "compressed %lld video": [
      "%lld వీడియో కుదించబడింది",
      "%lld వీడియోలు కుదించబడ్డాయి",
    ],
    "cleaned %lld burst photo": [
      "%lld బరస్ట్ ఫోటో శుభ్రం చేయబడింది",
      "%lld బరస్ట్ ఫోటోలు శుభ్రం చేయబడ్డాయి",
    ],
    "converted %lld Live Photo": [
      "%lld Live Photo స్థిర చిత్రంగా మార్చబడింది",
      "%lld Live Photos స్థిర చిత్రాలుగా మార్చబడ్డాయి",
    ],
    "reviewed %lld item": [
      "%lld అంశం సమీక్షించబడింది",
      "%lld అంశాలు సమీక్షించబడ్డాయి",
    ],
  },
  kn: {
    "cleared %lld photo": [
      "%lld ಫೋಟೋ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
      "%lld ಫೋಟೋಗಳನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
    ],
    "cleared %lld blurry photo": [
      "%lld ಅಸ್ಪಷ್ಟ ಫೋಟೋ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
      "%lld ಅಸ್ಪಷ್ಟ ಫೋಟೋಗಳನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
    ],
    "cleared %lld screenshot": [
      "%lld ಸ್ಕ್ರೀನ್ಶಾಟ್ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
      "%lld ಸ್ಕ್ರೀನ್ಶಾಟ್ಗಳನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
    ],
    "cleared %lld large file": [
      "%lld ದೊಡ್ಡ ಫೈಲ್ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
      "%lld ದೊಡ್ಡ ಫೈಲ್ಗಳನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
    ],
    "cleared %lld burst frame": [
      "%lld ಬರ್ಸ್ಟ್ ಫ್ರೇಮ್ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
      "%lld ಬರ್ಸ್ಟ್ ಫ್ರೇಮ್ಗಳನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
    ],
    "cleared %lld item (%@)": [
      "%lld ಐಟಂ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ (%@)",
      "%lld ಐಟಂಗಳನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ (%@)",
    ],
    "removed %lld duplicate": [
      "%lld ನಕಲಿ ತೆಗೆದುಹಾಕಲಾಗಿದೆ",
      "%lld ನಕಲಿಗಳನ್ನು ತೆಗೆದುಹಾಕಲಾಗಿದೆ",
    ],
    "removed %lld similar photo": [
      "%lld ಸಮಾನ ಫೋಟೋ ತೆಗೆದುಹಾಕಲಾಗಿದೆ",
      "%lld ಸಮಾನ ಫೋಟೋಗಳನ್ನು ತೆಗೆದುಹಾಕಲಾಗಿದೆ",
    ],
    "compressed %lld photo": [
      "%lld ಫೋಟೋ ಸಂಕುಚಿಸಲಾಗಿದೆ",
      "%lld ಫೋಟೋಗಳನ್ನು ಸಂಕುಚಿಸಲಾಗಿದೆ",
    ],
    "compressed %lld video": [
      "%lld ವೀಡಿಯೊ ಸಂಕುಚಿಸಲಾಗಿದೆ",
      "%lld ವೀಡಿಯೊಗಳನ್ನು ಸಂಕುಚಿಸಲಾಗಿದೆ",
    ],
    "cleaned %lld burst photo": [
      "%lld ಬರ್ಸ್ಟ್ ಫೋಟೋ ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
      "%lld ಬರ್ಸ್ಟ್ ಫೋಟೋಗಳನ್ನು ಸ್ವಚ್ಛಗೊಳಿಸಲಾಗಿದೆ",
    ],
    "converted %lld Live Photo": [
      "%lld Live Photo ಸ್ಟಿಲ್ ಆಗಿ ಪರಿವರ್ತಿಸಲಾಗಿದೆ",
      "%lld Live Photos ಸ್ಟಿಲ್ಗಳಾಗಿ ಪರಿವರ್ತಿಸಲಾಗಿದೆ",
    ],
    "reviewed %lld item": [
      "%lld ಐಟಂ ಪರಿಶೀಲಿಸಲಾಗಿದೆ",
      "%lld ಐಟಂಗಳನ್ನು ಪರಿಶೀಲಿಸಲಾಗಿದೆ",
    ],
  },
  ml: {
    "cleared %lld photo": [
      "%lld ഫോട്ടോ ക്ലീൻ ചെയ്തു",
      "%lld ഫോട്ടോകൾ ക്ലീൻ ചെയ്തു",
    ],
    "cleared %lld blurry photo": [
      "%lld മങ്ങിയ ഫോട്ടോ ക്ലീൻ ചെയ്തു",
      "%lld മങ്ങിയ ഫോട്ടോകൾ ക്ലീൻ ചെയ്തു",
    ],
    "cleared %lld screenshot": [
      "%lld സ്ക്രീൻഷോട്ട് ക്ലീൻ ചെയ്തു",
      "%lld സ്ക്രീൻഷോട്ടുകൾ ക്ലീൻ ചെയ്തു",
    ],
    "cleared %lld large file": [
      "%lld വലിയ ഫയൽ ക്ലീൻ ചെയ്തു",
      "%lld വലിയ ഫയലുകൾ ക്ലീൻ ചെയ്തു",
    ],
    "cleared %lld burst frame": [
      "%lld ബർസ്റ്റ് ഫ്രെയിം ക്ലീൻ ചെയ്തു",
      "%lld ബർസ്റ്റ് ഫ്രെയിമുകൾ ക്ലീൻ ചെയ്തു",
    ],
    "cleared %lld item (%@)": [
      "%lld ഇനം ക്ലീൻ ചെയ്തു (%@)",
      "%lld ഇനങ്ങൾ ക്ലീൻ ചെയ്തു (%@)",
    ],
    "removed %lld duplicate": [
      "%lld ഡ്യൂപ്ലിക്കേറ്റ് നീക്കി",
      "%lld ഡ്യൂപ്ലിക്കേറ്റുകൾ നീക്കി",
    ],
    "removed %lld similar photo": [
      "%lld സമാന ഫോട്ടോ നീക്കി",
      "%lld സമാന ഫോട്ടോകൾ നീക്കി",
    ],
    "compressed %lld photo": [
      "%lld ഫോട്ടോ കംപ്രസ് ചെയ്തു",
      "%lld ഫോട്ടോകൾ കംപ്രസ് ചെയ്തു",
    ],
    "compressed %lld video": [
      "%lld വീഡിയോ കംപ്രസ് ചെയ്തു",
      "%lld വീഡിയോകൾ കംപ്രസ് ചെയ്തു",
    ],
    "cleaned %lld burst photo": [
      "%lld ബർസ്റ്റ് ഫോട്ടോ ക്ലീൻ ചെയ്തു",
      "%lld ബർസ്റ്റ് ഫോട്ടോകൾ ക്ലീൻ ചെയ്തു",
    ],
    "converted %lld Live Photo": [
      "%lld Live Photo സ്റ്റിൽ ആക്കി മാറ്റി",
      "%lld Live Photos സ്റ്റിലുകളാക്കി മാറ്റി",
    ],
    "reviewed %lld item": [
      "%lld ഇനം പരിശോധിച്ചു",
      "%lld ഇനങ്ങൾ പരിശോധിച്ചു",
    ],
  },
  ru: {
    "cleared %lld photo": [
      "Очищен %lld снимок",
      "Очищено %lld снимка",
      "Очищено %lld снимков",
      "Очищено %lld снимка",
    ],
    "cleared %lld blurry photo": [
      "Очищен %lld размытый снимок",
      "Очищено %lld размытых снимка",
      "Очищено %lld размытых снимков",
      "Очищено %lld размытого снимка",
    ],
    "cleared %lld screenshot": [
      "Очищен %lld скриншот",
      "Очищено %lld скриншота",
      "Очищено %lld скриншотов",
      "Очищено %lld скриншота",
    ],
    "cleared %lld large file": [
      "Очищен %lld большой файл",
      "Очищено %lld больших файла",
      "Очищено %lld больших файлов",
      "Очищено %lld большого файла",
    ],
    "cleared %lld burst frame": [
      "Очищен %lld кадр серии",
      "Очищено %lld кадра серии",
      "Очищено %lld кадров серии",
      "Очищено %lld кадра серии",
    ],
    "cleared %lld item (%@)": [
      "Очищен %lld объект (%@)",
      "Очищено %lld объекта (%@)",
      "Очищено %lld объектов (%@)",
      "Очищено %lld объекта (%@)",
    ],
    "removed %lld duplicate": [
      "Удален %lld дубликат",
      "Удалено %lld дубликата",
      "Удалено %lld дубликатов",
      "Удалено %lld дубликата",
    ],
    "removed %lld similar photo": [
      "Удалено %lld похожее фото",
      "Удалено %lld похожих фото",
      "Удалено %lld похожих фото",
      "Удалено %lld похожего фото",
    ],
    "compressed %lld photo": [
      "Сжат %lld снимок",
      "Сжато %lld снимка",
      "Сжато %lld снимков",
      "Сжато %lld снимка",
    ],
    "compressed %lld video": [
      "Сжат %lld видеофайл",
      "Сжато %lld видеофайла",
      "Сжато %lld видеофайлов",
      "Сжато %lld видеофайла",
    ],
    "cleaned %lld burst photo": [
      "Очищено %lld серийное фото",
      "Очищено %lld серийных фото",
      "Очищено %lld серийных фото",
      "Очищено %lld серийного фото",
    ],
    "converted %lld Live Photo": [
      "Преобразован %lld снимок Live Photo",
      "Преобразовано %lld снимка Live Photo",
      "Преобразовано %lld снимков Live Photo",
      "Преобразовано %lld снимка Live Photo",
    ],
    "reviewed %lld item": [
      "Просмотрен %lld объект",
      "Просмотрено %lld объекта",
      "Просмотрено %lld объектов",
      "Просмотрено %lld объекта",
    ],
  },
};

// ------------------------------------------------------------------- insert

// The plural catalog fixes the order new plural keys are appended in.
const pluralOrder = Object.keys(
  JSON.parse(fs.readFileSync(path.join(here, "_plural-keys.json"), "utf8")),
).slice(51);

const CATEGORIES = {
  te: ["one", "other"],
  kn: ["one", "other"],
  ml: ["one", "other"],
  ru: ["one", "few", "many", "other"],
};

for (const lang of ["te", "kn", "ml", "ru"]) {
  const file = path.join(here, `${lang}.json`);
  const json = JSON.parse(fs.readFileSync(file, "utf8"));

  const plain = PLAIN[lang];
  const plural = PLURALS[lang];
  const cats = CATEGORIES[lang];

  for (const [key, value] of Object.entries(plain)) {
    if (key in json.strings) throw new Error(`${lang}: plain key already present: ${key}`);
    json.strings[key] = value;
  }

  for (const key of pluralOrder) {
    const forms = plural[key];
    if (!forms) throw new Error(`${lang}: no forms for plural key: ${key}`);
    if (forms.length !== cats.length) {
      throw new Error(`${lang}: ${key} has ${forms.length} forms, expected ${cats.length}`);
    }
    if (key in json.plurals) throw new Error(`${lang}: plural key already present: ${key}`);
    json.plurals[key] = Object.fromEntries(cats.map((c, i) => [c, forms[i]]));
  }

  // Plain keys keep the file's existing plain UTF-16 code-unit sort order.
  json.strings = Object.fromEntries(
    Object.keys(json.strings)
      .sort()
      .map((k) => [k, json.strings[k]]),
  );

  fs.writeFileSync(file, JSON.stringify(json, null, 2) + "\n");
  console.log(
    `${lang}.json written: strings=${Object.keys(json.strings).length} plurals=${Object.keys(json.plurals).length}`,
  );
}
