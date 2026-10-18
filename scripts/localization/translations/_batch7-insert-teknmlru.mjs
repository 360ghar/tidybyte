// Batch 7 insertion for te, kn, ml, ru.
//
// Adds 57 new English keys to each language file's "strings" block. The block is
// edited as text (not re-serialized) so every pre-existing line stays byte-identical
// and the "plurals" block is untouched.
//
// Run: node _batch7-insert-teknmlru.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const BASELINE = "/tmp/batch7-baseline";

// ---------------------------------------------------------------------------
// The 57 keys (English source text, verbatim from _batch7-brief.md).
// ---------------------------------------------------------------------------

// Group 1 - photo permission (12)
const K = {
  needsPhotos: "TidyByte Needs Your Photos",
  needsPhotosBody:
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.",
  accessOn: "Photo Access Is On",
  accessOnBody:
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.",
  accessOff: "Photo Access Is Off",
  accessOffBody:
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.",
  accessRestricted: "Photo Access Is Restricted",
  accessRestrictedBody:
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.",
  limitedBody:
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.",
  allowAccess: "Allow Photo Access?",
  allowAccessBody:
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.",
  notNow: "Not Now",

  // Group 2 - compression errors (17)
  photoNotFound: "Photo not found.",
  notAnImage: "This item can't be compressed as a photo.",
  photoLoadFailed: "Failed to load the photo.",
  photoEncodeFailed: "Failed to re-encode the photo.",
  photoSizeUnknown: "Photo size unknown (iCloud-only) — skipped.",
  videoNotFound: "Video not found.",
  videoLoadFailed:
    "Couldn't load the video (it may still be in iCloud). Please try again.",
  videoSizeUnknown: "Video size unknown (iCloud-only) — skipped.",
  exportSessionFailed: "Failed to create export session.",
  exportedEmpty: "Exported file was empty.",
  fileSizeReadFailed: "Failed to read file size.",
  cancelled: "Cancelled.",
  unknownError: "Unknown error",
  saveFailed: "Save failed: %@",
  exportFailed: "Export failed: %@",
  alreadyCompressed: "Already compressed",
  sizeUnknown: "Size unknown (iCloud-only) — skipped",

  // Group 3 - local AI and search (9)
  aiUnavailable: "Local AI is unavailable.",
  aiLanguageUnsupported: "This language is not supported by local AI.",
  aiNoInterpret: "Local AI could not interpret this search.",
  tooManyCharacters: "Use 300 characters or fewer.",
  visibleContentOnly:
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.",
  conceptsNotFound:
    "Some requested concepts were not found in this scan. Try a simpler content search.",
  searchingLabels: "Searching labels across all scanned categories.",
  usingLabelSearch: "Using label search across scanned photos.",
  labelSearchUnsupported:
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.",

  // Group 4 - swipe review reasons (8)
  outOfFocus: "This photo may be out of focus.",
  lowBrightness: "This photo has very low brightness.",
  highBrightness: "This photo has very high brightness.",
  lensSmudge: "A lens smudge may have reduced image clarity.",
  lowQualityScore: "This photo received a low visual-quality score.",
  reviewScreenshot: "Review whether you still need this screenshot.",
  reviewScreenRecording: "Review whether you still need this screen recording.",
  usesSize: "This item uses %@; review whether you need it.",

  // Group 5 - appearance picker and widget (6)
  light: "Light",
  dark: "Dark",
  nothingToFree: "Nothing to free on iPhone",
  upToFree: "Up to %@ to free on iPhone",
  openToRefresh: "Open TidyByte to refresh",
  updatedAgo: "Updated %lldd ago",

  // Group 6 - empty states (5)
  noMatchingPhotos: "No matching photos",
  submitSearch: "Submit a content search or try different words.",
  noPhotosInCategory: "No photos in this category.",
  chooseAlbums: "Choose albums or change your filters.",
  noScreenRecordings: "No screen recordings were found.",
};

// ---------------------------------------------------------------------------
// Translations
// ---------------------------------------------------------------------------

const translations = {
  te: {
    [K.needsPhotos]: "TidyByteకు మీ ఫోటోలు కావాలి",
    [K.needsPhotosBody]:
      "TidyByte శుభ్రం చేయదగినవి కనుగొనడానికి ఈ పరికరంలోనే మీ లైబ్రరీని సమీక్షిస్తుంది. ఏదీ అప్లోడ్ చేయబడదు, మీ అనుమతి లేకుండా ఏదీ మారదు. తర్వాత iOS యాక్సెస్ అడుగుతుంది.",
    [K.accessOn]: "ఫోటో యాక్సెస్ ఆన్లో ఉంది",
    [K.accessOnBody]:
      "TidyByte ఈ పరికరంలోనే మీ లైబ్రరీని సమీక్షించగలదు. ఏదీ అప్లోడ్ చేయబడదు, మీ అనుమతి లేకుండా ఏదీ మారదు.",
    [K.accessOff]: "ఫోటో యాక్సెస్ ఆఫ్లో ఉంది",
    [K.accessOffBody]:
      "iOS మీ లైబ్రరీ నుండి TidyByteను నిరోధిస్తోంది, ఇక అడగదు. సెట్టింగ్లే తిరిగి వెళ్లే ఏకైక మార్గం — అక్కడ ఫోటో యాక్సెస్ను ఆన్ చేయండి, ఇక్కడ అంతా మళ్లీ పని చేయడం ప్రారంభిస్తుంది.",
    [K.accessRestricted]: "ఫోటో యాక్సెస్ పరిమితం చేయబడింది",
    [K.accessRestrictedBody]:
      "Screen Time లేదా పరికర నిర్వహణ పరిమితి ఫోటో యాక్సెస్ను నిరోధిస్తోంది. సెట్టింగ్లలోని ఫోటోలు స్విచ్ దీన్ని మార్చలేదు — ముందు ఆ పరిమితిని తీసివేయాలి.",
    [K.limitedBody]:
      "మీరు ఎంచుకున్న ఫోటోలను మాత్రమే TidyByte చూడగలదు. మీ లైబ్రరీలో మిగిలినవి సమీక్షించాలనుకున్నప్పుడు ఎప్పుడైనా మరిన్ని జోడించండి.",
    [K.allowAccess]: "ఫోటో యాక్సెస్ అనుమతించాలా?",
    [K.allowAccessBody]:
      "iOS ఫోటో యాక్సెస్ను ఒక్కసారే అడుగుతుంది, అదే ఇది. తర్వాత TidyByte ఈ పరికరంలోనే మీ లైబ్రరీని సమీక్షిస్తుంది. ఏదీ అప్లోడ్ చేయబడదు, మీ సమీక్ష లేకుండా ఏదీ మారదు.",
    [K.notNow]: "ఇప్పుడు కాదు",

    [K.photoNotFound]: "ఫోటో కనుగొనబడలేదు.",
    [K.notAnImage]: "ఈ అంశాన్ని ఫోటోగా కుదించలేము.",
    [K.photoLoadFailed]: "ఫోటోను లోడ్ చేయలేకపోయాం.",
    [K.photoEncodeFailed]: "ఫోటోను మళ్లీ ఎన్కోడ్ చేయలేకపోయాం.",
    [K.photoSizeUnknown]:
      "ఫోటో పరిమాణం తెలియదు (iCloud-మాత్రమే) — దాటవేయబడింది.",
    [K.videoNotFound]: "వీడియో కనుగొనబడలేదు.",
    [K.videoLoadFailed]:
      "వీడియోను లోడ్ చేయలేకపోయాం (అది ఇంకా iCloudలో ఉండవచ్చు). మళ్లీ ప్రయత్నించండి.",
    [K.videoSizeUnknown]:
      "వీడియో పరిమాణం తెలియదు (iCloud-మాత్రమే) — దాటవేయబడింది.",
    [K.exportSessionFailed]: "ఎగుమతి సెషన్ను సృష్టించలేకపోయాం.",
    [K.exportedEmpty]: "ఎగుమతి చేసిన ఫైల్ ఖాళీగా ఉంది.",
    [K.fileSizeReadFailed]: "ఫైల్ పరిమాణాన్ని చదవలేకపోయాం.",
    [K.cancelled]: "రద్దు చేయబడింది.",
    [K.unknownError]: "తెలియని లోపం",
    [K.saveFailed]: "సేవ్ విఫలమైంది: %@",
    [K.exportFailed]: "ఎగుమతి విఫలమైంది: %@",
    [K.alreadyCompressed]: "ఇప్పటికే కుదించబడింది",
    [K.sizeUnknown]: "పరిమాణం తెలియదు (iCloud-మాత్రమే) — దాటవేయబడింది",

    [K.aiUnavailable]: "లోకల్ AI అందుబాటులో లేదు.",
    [K.aiLanguageUnsupported]: "ఈ భాషకు లోకల్ AI మద్దతు లేదు.",
    [K.aiNoInterpret]: "లోకల్ AI ఈ శోధనను అర్థం చేసుకోలేకపోయింది.",
    [K.tooManyCharacters]: "300 అక్షరాలు లేదా అంతకంటే తక్కువ వాడండి.",
    [K.visibleContentOnly]:
      "శోధన కనిపించే కంటెంట్కు మాత్రమే మద్దతు ఇస్తుంది, ఉదాహరణకు బీచ్లో కుక్కలు. తేదీలు, ప్రదేశాలు, పేర్లు, వచనం ఇండెక్స్ చేయబడవు.",
    [K.conceptsNotFound]:
      "కొన్ని అభ్యర్థించిన భావనలు ఈ స్కాన్లో కనుగొనబడలేదు. సరళమైన కంటెంట్ శోధన ప్రయత్నించండి.",
    [K.searchingLabels]: "స్కాన్ చేసిన అన్ని వర్గాల్లో లేబుళ్లను వెతుకుతోంది.",
    [K.usingLabelSearch]: "స్కాన్ చేసిన ఫోటోలలో లేబుల్ శోధన వాడుతోంది.",
    [K.labelSearchUnsupported]:
      "ఈ పదాలు మద్దతు ఉన్న లేబుల్ శోధనగా ఏర్పడవు. కుక్క లేదా బీచ్ వంటి కనిపించే కంటెంట్ ప్రయత్నించండి. లేబుల్ శోధన తేదీలు, పేర్లు, మినహాయింపులకు మద్దతు ఇవ్వదు.",

    [K.outOfFocus]: "ఈ ఫోటో ఫోకస్ లేకుండా ఉండవచ్చు.",
    [K.lowBrightness]: "ఈ ఫోటో చాలా తక్కువ వెలుతురు కలిగి ఉంది.",
    [K.highBrightness]: "ఈ ఫోటో చాలా ఎక్కువ వెలుతురు కలిగి ఉంది.",
    [K.lensSmudge]: "లెన్స్ మరక చిత్ర స్పష్టతను తగ్గించి ఉండవచ్చు.",
    [K.lowQualityScore]: "ఈ ఫోటోకు తక్కువ దృశ్య నాణ్యత స్కోరు లభించింది.",
    [K.reviewScreenshot]: "ఈ స్క్రీన్షాట్ ఇంకా అవసరమో లేదో సమీక్షించండి.",
    [K.reviewScreenRecording]:
      "ఈ స్క్రీన్ రికార్డింగ్ ఇంకా అవసరమో లేదో సమీక్షించండి.",
    [K.usesSize]: "ఈ అంశం %@ వాడుతుంది; ఇది మీకు అవసరమో లేదో సమీక్షించండి.",

    [K.light]: "లైట్",
    [K.dark]: "డార్క్",
    [K.nothingToFree]: "iPhoneలో ఖాళీ చేయడానికి ఏమీ లేదు",
    [K.upToFree]: "iPhoneలో ఖాళీ చేయడానికి %@ వరకు",
    [K.openToRefresh]: "రిఫ్రెష్ చేయడానికి TidyByte తెరవండి",
    [K.updatedAgo]: "%lld రోజుల క్రితం నవీకరించబడింది",

    [K.noMatchingPhotos]: "సరిపోలే ఫోటోలు లేవు",
    [K.submitSearch]:
      "కంటెంట్ శోధన సమర్పించండి లేదా వేరే పదాలు ప్రయత్నించండి.",
    [K.noPhotosInCategory]: "ఈ వర్గంలో ఫోటోలు లేవు.",
    [K.chooseAlbums]: "ఆల్బమ్లను ఎంచుకోండి లేదా మీ ఫిల్టర్లను మార్చండి.",
    [K.noScreenRecordings]: "స్క్రీన్ రికార్డింగ్లు ఏవీ కనుగొనబడలేదు.",
  },

  kn: {
    [K.needsPhotos]: "TidyByte ಗೆ ನಿಮ್ಮ ಫೋಟೋಗಳು ಬೇಕು",
    [K.needsPhotosBody]:
      "TidyByte ಸ್ವಚ್ಛಗೊಳಿಸಲು ಯೋಗ್ಯವಾದದ್ದನ್ನು ಕಂಡುಹಿಡಿಯಲು ಈ ಸಾಧನದಲ್ಲೇ ನಿಮ್ಮ ಲೈಬ್ರರಿಯನ್ನು ಪರಿಶೀಲಿಸುತ್ತದೆ. ಯಾವುದನ್ನೂ ಅಪ್ಲೋಡ್ ಮಾಡಲಾಗುವುದಿಲ್ಲ, ನಿಮ್ಮ ಅನುಮತಿ ಇಲ್ಲದೆ ಯಾವುದೂ ಬದಲಾಗುವುದಿಲ್ಲ. ಮುಂದೆ iOS ಪ್ರವೇಶ ಕೇಳುತ್ತದೆ.",
    [K.accessOn]: "ಫೋಟೋ ಪ್ರವೇಶ ಆನ್ ಆಗಿದೆ",
    [K.accessOnBody]:
      "TidyByte ಈ ಸಾಧನದಲ್ಲೇ ನಿಮ್ಮ ಲೈಬ್ರರಿಯನ್ನು ಪರಿಶೀಲಿಸಬಲ್ಲದು. ಯಾವುದನ್ನೂ ಅಪ್ಲೋಡ್ ಮಾಡಲಾಗುವುದಿಲ್ಲ, ನಿಮ್ಮ ಅನುಮತಿ ಇಲ್ಲದೆ ಯಾವುದೂ ಬದಲಾಗುವುದಿಲ್ಲ.",
    [K.accessOff]: "ಫೋಟೋ ಪ್ರವೇಶ ಆಫ್ ಆಗಿದೆ",
    [K.accessOffBody]:
      "iOS ನಿಮ್ಮ ಲೈಬ್ರರಿಯಿಂದ TidyByte ಗೆ ಪ್ರವೇಶ ನಿರ್ಬಂಧಿಸಿದೆ, ಇನ್ನು ಕೇಳುವುದಿಲ್ಲ. ಸೆಟ್ಟಿಂಗ್ಗಳೇ ಹಿಂತಿರುಗುವ ಏಕೈಕ ದಾರಿ — ಅಲ್ಲಿ ಫೋಟೋ ಪ್ರವೇಶವನ್ನು ಆನ್ ಮಾಡಿ, ಇಲ್ಲಿನ ಎಲ್ಲವೂ ಮತ್ತೆ ಕೆಲಸ ಮಾಡಲು ಪ್ರಾರಂಭಿಸುತ್ತದೆ.",
    [K.accessRestricted]: "ಫೋಟೋ ಪ್ರವೇಶ ನಿರ್ಬಂಧಿಸಲಾಗಿದೆ",
    [K.accessRestrictedBody]:
      "Screen Time ಅಥವಾ ಸಾಧನ ನಿರ್ವಹಣಾ ನಿರ್ಬಂಧವು ಫೋಟೋ ಪ್ರವೇಶವನ್ನು ತಡೆಯುತ್ತಿದೆ. ಸೆಟ್ಟಿಂಗ್ಗಳಲ್ಲಿನ ಫೋಟೋಗಳು ಸ್ವಿಚ್ ಅದನ್ನು ಬದಲಾಯಿಸಲಾಗದು — ಮೊದಲು ಆ ನಿರ್ಬಂಧವನ್ನು ತೆಗೆಯಬೇಕು.",
    [K.limitedBody]:
      "ನೀವು ಆಯ್ಕೆ ಮಾಡಿದ ಫೋಟೋಗಳನ್ನು ಮಾತ್ರ TidyByte ನೋಡಬಲ್ಲದು. ನಿಮ್ಮ ಲೈಬ್ರರಿಯ ಉಳಿದ ಭಾಗವನ್ನು ಪರಿಶೀಲಿಸಬೇಕೆಂದಾಗ ಯಾವಾಗ ಬೇಕಾದರೂ ಇನ್ನಷ್ಟು ಸೇರಿಸಿ.",
    [K.allowAccess]: "ಫೋಟೋ ಪ್ರವೇಶಕ್ಕೆ ಅನುಮತಿ ನೀಡುವುದೇ?",
    [K.allowAccessBody]:
      "iOS ಫೋಟೋ ಪ್ರವೇಶವನ್ನು ಒಮ್ಮೆ ಮಾತ್ರ ಕೇಳುತ್ತದೆ, ಅದೇ ಇದು. ನಂತರ TidyByte ಈ ಸಾಧನದಲ್ಲೇ ನಿಮ್ಮ ಲೈಬ್ರರಿಯನ್ನು ಪರಿಶೀಲಿಸುತ್ತದೆ. ಯಾವುದನ್ನೂ ಅಪ್ಲೋಡ್ ಮಾಡಲಾಗುವುದಿಲ್ಲ, ನಿಮ್ಮ ಪರಿಶೀಲನೆ ಇಲ್ಲದೆ ಯಾವುದೂ ಬದಲಾಗುವುದಿಲ್ಲ.",
    [K.notNow]: "ಈಗ ಬೇಡ",

    [K.photoNotFound]: "ಫೋಟೋ ಕಂಡುಬಂದಿಲ್ಲ.",
    [K.notAnImage]: "ಈ ಐಟಂ ಅನ್ನು ಫೋಟೋವಾಗಿ ಸಂಕುಚಿಸಲಾಗದು.",
    [K.photoLoadFailed]: "ಫೋಟೋ ಲೋಡ್ ಮಾಡಲಾಗಲಿಲ್ಲ.",
    [K.photoEncodeFailed]: "ಫೋಟೋವನ್ನು ಮತ್ತೆ ಎನ್ಕೋಡ್ ಮಾಡಲಾಗಲಿಲ್ಲ.",
    [K.photoSizeUnknown]: "ಫೋಟೋ ಗಾತ್ರ ತಿಳಿದಿಲ್ಲ (iCloud-ಮಾತ್ರ) — ಬಿಟ್ಟುಬಿಡಲಾಗಿದೆ.",
    [K.videoNotFound]: "ವೀಡಿಯೊ ಕಂಡುಬಂದಿಲ್ಲ.",
    [K.videoLoadFailed]:
      "ವೀಡಿಯೊ ಲೋಡ್ ಮಾಡಲಾಗಲಿಲ್ಲ (ಅದು ಇನ್ನೂ iCloud ನಲ್ಲಿರಬಹುದು). ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.",
    [K.videoSizeUnknown]: "ವೀಡಿಯೊ ಗಾತ್ರ ತಿಳಿದಿಲ್ಲ (iCloud-ಮಾತ್ರ) — ಬಿಟ್ಟುಬಿಡಲಾಗಿದೆ.",
    [K.exportSessionFailed]: "ಎಕ್ಸ್ಪೋರ್ಟ್ ಸೆಷನ್ ರಚಿಸಲಾಗಲಿಲ್ಲ.",
    [K.exportedEmpty]: "ಎಕ್ಸ್ಪೋರ್ಟ್ ಮಾಡಿದ ಫೈಲ್ ಖಾಲಿಯಾಗಿತ್ತು.",
    [K.fileSizeReadFailed]: "ಫೈಲ್ ಗಾತ್ರ ಓದಲಾಗಲಿಲ್ಲ.",
    [K.cancelled]: "ರದ್ದುಮಾಡಲಾಗಿದೆ.",
    [K.unknownError]: "ಅಜ್ಞಾತ ದೋಷ",
    [K.saveFailed]: "ಉಳಿಸಲಾಗಲಿಲ್ಲ: %@",
    [K.exportFailed]: "ಎಕ್ಸ್ಪೋರ್ಟ್ ವಿಫಲವಾಗಿದೆ: %@",
    [K.alreadyCompressed]: "ಈಗಾಗಲೇ ಸಂಕುಚಿಸಲಾಗಿದೆ",
    [K.sizeUnknown]: "ಗಾತ್ರ ತಿಳಿದಿಲ್ಲ (iCloud-ಮಾತ್ರ) — ಬಿಟ್ಟುಬಿಡಲಾಗಿದೆ",

    [K.aiUnavailable]: "ಸ್ಥಳೀಯ AI ಲಭ್ಯವಿಲ್ಲ.",
    [K.aiLanguageUnsupported]: "ಈ ಭಾಷೆಗೆ ಸ್ಥಳೀಯ AI ಬೆಂಬಲವಿಲ್ಲ.",
    [K.aiNoInterpret]: "ಸ್ಥಳೀಯ AI ಈ ಹುಡುಕಾಟವನ್ನು ಅರ್ಥೈಸಿಕೊಳ್ಳಲಾಗಲಿಲ್ಲ.",
    [K.tooManyCharacters]: "300 ಅಕ್ಷರಗಳು ಅಥವಾ ಕಡಿಮೆ ಬಳಸಿ.",
    [K.visibleContentOnly]:
      "ಹುಡುಕಾಟವು ಕಾಣುವ ವಿಷಯಕ್ಕೆ ಮಾತ್ರ ಬೆಂಬಲ ನೀಡುತ್ತದೆ, ಉದಾಹರಣೆಗೆ ಕಡಲತೀರದಲ್ಲಿ ನಾಯಿಗಳು. ದಿನಾಂಕಗಳು, ಸ್ಥಳಗಳು, ಹೆಸರುಗಳು ಮತ್ತು ಪಠ್ಯ ಸೂಚ್ಯಂಕಗೊಳ್ಳುವುದಿಲ್ಲ.",
    [K.conceptsNotFound]:
      "ಕೆಲವು ವಿನಂತಿಸಿದ ಪರಿಕಲ್ಪನೆಗಳು ಈ ಸ್ಕ್ಯಾನ್ನಲ್ಲಿ ಕಂಡುಬಂದಿಲ್ಲ. ಸರಳವಾದ ವಿಷಯ ಹುಡುಕಾಟ ಪ್ರಯತ್ನಿಸಿ.",
    [K.searchingLabels]: "ಸ್ಕ್ಯಾನ್ ಮಾಡಿದ ಎಲ್ಲಾ ವರ್ಗಗಳಲ್ಲಿ ಲೇಬಲ್ಗಳನ್ನು ಹುಡುಕಲಾಗುತ್ತಿದೆ.",
    [K.usingLabelSearch]: "ಸ್ಕ್ಯಾನ್ ಮಾಡಿದ ಫೋಟೋಗಳಲ್ಲಿ ಲೇಬಲ್ ಹುಡುಕಾಟ ಬಳಸಲಾಗುತ್ತಿದೆ.",
    [K.labelSearchUnsupported]:
      "ಈ ಪದಗಳು ಬೆಂಬಲಿತ ಲೇಬಲ್ ಹುಡುಕಾಟವನ್ನು ರೂಪಿಸುವುದಿಲ್ಲ. ನಾಯಿ ಅಥವಾ ಕಡಲತೀರದಂತಹ ಕಾಣುವ ವಿಷಯವನ್ನು ಪ್ರಯತ್ನಿಸಿ. ಲೇಬಲ್ ಹುಡುಕಾಟವು ದಿನಾಂಕಗಳು, ಹೆಸರುಗಳು ಅಥವಾ ಹೊರಗಿಡುವಿಕೆಗಳಿಗೆ ಬೆಂಬಲ ನೀಡುವುದಿಲ್ಲ.",

    [K.outOfFocus]: "ಈ ಫೋಟೋ ಫೋಕಸ್ನಲ್ಲಿಲ್ಲದಿರಬಹುದು.",
    [K.lowBrightness]: "ಈ ಫೋಟೋ ಬಹಳ ಕಡಿಮೆ ಪ್ರಕಾಶಮಾನತೆ ಹೊಂದಿದೆ.",
    [K.highBrightness]: "ಈ ಫೋಟೋ ಬಹಳ ಹೆಚ್ಚು ಪ್ರಕಾಶಮಾನತೆ ಹೊಂದಿದೆ.",
    [K.lensSmudge]: "ಲೆನ್ಸ್ ಕಲೆ ಚಿತ್ರದ ಸ್ಪಷ್ಟತೆಯನ್ನು ಕಡಿಮೆ ಮಾಡಿರಬಹುದು.",
    [K.lowQualityScore]: "ಈ ಫೋಟೋಗೆ ಕಡಿಮೆ ದೃಶ್ಯ-ಗುಣಮಟ್ಟದ ಸ್ಕೋರ್ ಸಿಕ್ಕಿದೆ.",
    [K.reviewScreenshot]: "ಈ ಸ್ಕ್ರೀನ್ಶಾಟ್ ಇನ್ನೂ ಬೇಕೇ ಎಂದು ಪರಿಶೀಲಿಸಿ.",
    [K.reviewScreenRecording]: "ಈ ಸ್ಕ್ರೀನ್ ರೆಕಾರ್ಡಿಂಗ್ ಇನ್ನೂ ಬೇಕೇ ಎಂದು ಪರಿಶೀಲಿಸಿ.",
    [K.usesSize]: "ಈ ಐಟಂ %@ ಬಳಸುತ್ತದೆ; ಅದು ನಿಮಗೆ ಬೇಕೇ ಎಂದು ಪರಿಶೀಲಿಸಿ.",

    [K.light]: "ಲೈಟ್",
    [K.dark]: "ಡಾರ್ಕ್",
    [K.nothingToFree]: "iPhone ನಲ್ಲಿ ಖಾಲಿ ಮಾಡಲು ಏನೂ ಇಲ್ಲ",
    [K.upToFree]: "iPhone ನಲ್ಲಿ ಖಾಲಿ ಮಾಡಲು %@ ವರೆಗೆ",
    [K.openToRefresh]: "ರಿಫ್ರೆಶ್ ಮಾಡಲು TidyByte ತೆರೆಯಿರಿ",
    [K.updatedAgo]: "%lld ದಿನಗಳ ಹಿಂದೆ ನವೀಕರಿಸಲಾಗಿದೆ",

    [K.noMatchingPhotos]: "ಹೊಂದಿಕೆಯಾಗುವ ಫೋಟೋಗಳಿಲ್ಲ",
    [K.submitSearch]: "ವಿಷಯ ಹುಡುಕಾಟ ಸಲ್ಲಿಸಿ ಅಥವಾ ಬೇರೆ ಪದಗಳನ್ನು ಪ್ರಯತ್ನಿಸಿ.",
    [K.noPhotosInCategory]: "ಈ ವರ್ಗದಲ್ಲಿ ಫೋಟೋಗಳಿಲ್ಲ.",
    [K.chooseAlbums]: "ಆಲ್ಬಮ್ಗಳನ್ನು ಆಯ್ಕೆಮಾಡಿ ಅಥವಾ ನಿಮ್ಮ ಫಿಲ್ಟರ್ಗಳನ್ನು ಬದಲಾಯಿಸಿ.",
    [K.noScreenRecordings]: "ಸ್ಕ್ರೀನ್ ರೆಕಾರ್ಡಿಂಗ್ಗಳು ಯಾವುವೂ ಕಂಡುಬಂದಿಲ್ಲ.",
  },

  ml: {
    [K.needsPhotos]: "TidyByte-ന് നിങ്ങളുടെ ഫോട്ടോകൾ ആവശ്യമാണ്",
    [K.needsPhotosBody]:
      "ശുചീകരിക്കാൻ യോഗ്യമായത് കണ്ടെത്താൻ TidyByte ഈ ഉപകരണത്തിൽ തന്നെ നിങ്ങളുടെ ലൈബ്രറി പരിശോധിക്കുന്നു. ഒന്നും അപ്ലോഡ് ചെയ്യുന്നില്ല, നിങ്ങളുടെ അനുമതിയില്ലാതെ ഒന്നും മാറുന്നുമില്ല. അടുത്തതായി iOS ആക്സസ് ചോദിക്കും.",
    [K.accessOn]: "ഫോട്ടോ ആക്സസ് ഓണാണ്",
    [K.accessOnBody]:
      "TidyByte-ക്ക് ഈ ഉപകരണത്തിൽ തന്നെ നിങ്ങളുടെ ലൈബ്രറി പരിശോധിക്കാം. ഒന്നും അപ്ലോഡ് ചെയ്യുന്നില്ല, നിങ്ങളുടെ അനുമതിയില്ലാതെ ഒന്നും മാറുന്നുമില്ല.",
    [K.accessOff]: "ഫോട്ടോ ആക്സസ് ഓഫാണ്",
    [K.accessOffBody]:
      "നിങ്ങളുടെ ലൈബ്രറിയിൽ നിന്ന് iOS TidyByte-നെ തടയുന്നു, ഇനി ചോദിക്കില്ല. സെറ്റിംഗ്സ് മാത്രമാണ് തിരികെയുള്ള വഴി — അവിടെ ഫോട്ടോ ആക്സസ് ഓണാക്കുക, ഇവിടെയുള്ളതെല്ലാം വീണ്ടും പ്രവർത്തിക്കാൻ തുടങ്ങും.",
    [K.accessRestricted]: "ഫോട്ടോ ആക്സസ് നിയന്ത്രിതമാണ്",
    [K.accessRestrictedBody]:
      "Screen Time അല്ലെങ്കിൽ ഉപകരണ നിർവഹണ നിയന്ത്രണം ഫോട്ടോ ആക്സസ് തടയുന്നു. സെറ്റിംഗ്സിലെ ഫോട്ടോകൾ സ്വിച്ചിന് അത് മാറ്റാനാകില്ല — ആ നിയന്ത്രണം ആദ്യം നീക്കണം.",
    [K.limitedBody]:
      "നിങ്ങൾ തിരഞ്ഞെടുത്ത ഫോട്ടോകൾ മാത്രമേ TidyByte-ക്ക് കാണാനാകൂ. ലൈബ്രറിയിലെ ബാക്കി പരിശോധിക്കണമെന്ന് തോന്നുമ്പോൾ എപ്പോൾ വേണമെങ്കിലും കൂടുതൽ ചേർക്കുക.",
    [K.allowAccess]: "ഫോട്ടോ ആക്സസ് അനുവദിക്കണോ?",
    [K.allowAccessBody]:
      "iOS ഫോട്ടോ ആക്സസ് ഒരിക്കൽ മാത്രം ചോദിക്കും, അതാണ് ഇത്. തുടർന്ന് TidyByte ഈ ഉപകരണത്തിൽ തന്നെ നിങ്ങളുടെ ലൈബ്രറി പരിശോധിക്കുന്നു. ഒന്നും അപ്ലോഡ് ചെയ്യുന്നില്ല, നിങ്ങളുടെ പരിശോധനയില്ലാതെ ഒന്നും മാറുന്നുമില്ല.",
    [K.notNow]: "ഇപ്പോൾ വേണ്ട",

    [K.photoNotFound]: "ഫോട്ടോ കണ്ടെത്തിയില്ല.",
    [K.notAnImage]: "ഈ ഇനം ഫോട്ടോ ആയി കംപ്രസ് ചെയ്യാനാകില്ല.",
    [K.photoLoadFailed]: "ഫോട്ടോ ലോഡ് ചെയ്യാനായില്ല.",
    [K.photoEncodeFailed]: "ഫോട്ടോ വീണ്ടും എൻകോഡ് ചെയ്യാനായില്ല.",
    [K.photoSizeUnknown]: "ഫോട്ടോ വലിപ്പം അറിയില്ല (iCloud-ഒൺലി) — ഒഴിവാക്കി.",
    [K.videoNotFound]: "വീഡിയോ കണ്ടെത്തിയില്ല.",
    [K.videoLoadFailed]:
      "വീഡിയോ ലോഡ് ചെയ്യാനായില്ല (അത് ഇപ്പോഴും iCloud-ൽ ആകാം). വീണ്ടും ശ്രമിക്കുക.",
    [K.videoSizeUnknown]: "വീഡിയോ വലിപ്പം അറിയില്ല (iCloud-ഒൺലി) — ഒഴിവാക്കി.",
    [K.exportSessionFailed]: "എക്സ്പോർട്ട് സെഷൻ സൃഷ്ടിക്കാനായില്ല.",
    [K.exportedEmpty]: "എക്സ്പോർട്ട് ചെയ്ത ഫയൽ ശൂന്യമായിരുന്നു.",
    [K.fileSizeReadFailed]: "ഫയൽ വലിപ്പം വായിക്കാനായില്ല.",
    [K.cancelled]: "റദ്ദാക്കി.",
    [K.unknownError]: "അജ്ഞാതമായ പിശക്",
    [K.saveFailed]: "സേവ് ചെയ്യാനായില്ല: %@",
    [K.exportFailed]: "എക്സ്പോർട്ട് പരാജയപ്പെട്ടു: %@",
    [K.alreadyCompressed]: "ഇതിനകം കംപ്രസ് ചെയ്തിട്ടുണ്ട്",
    [K.sizeUnknown]: "വലിപ്പം അറിയില്ല (iCloud-ഒൺലി) — ഒഴിവാക്കി",

    [K.aiUnavailable]: "ലോക്കൽ AI ലഭ്യമല്ല.",
    [K.aiLanguageUnsupported]: "ഈ ഭാഷയ്ക്ക് ലോക്കൽ AI പിന്തുണയില്ല.",
    [K.aiNoInterpret]: "ഈ തിരയൽ ലോക്കൽ AI-ക്ക് മനസ്സിലാക്കാനായില്ല.",
    [K.tooManyCharacters]: "300 പ്രതീകങ്ങളോ അതിൽ കുറവോ ഉപയോഗിക്കുക.",
    [K.visibleContentOnly]:
      "കാണുന്ന ഉള്ളടക്കത്തിന് മാത്രമേ തിരയൽ പിന്തുണയ്ക്കൂ, ഉദാഹരണത്തിന് കടൽത്തീരത്ത് നായ്ക്കൾ. തീയതികൾ, സ്ഥലങ്ങൾ, പേരുകൾ, പാഠം എന്നിവ സൂചികയിലാക്കുന്നില്ല.",
    [K.conceptsNotFound]:
      "ചില അഭ്യർത്ഥിത ആശയങ്ങൾ ഈ സ്കാനിൽ കണ്ടെത്തിയില്ല. ലളിതമായ ഒരു ഉള്ളടക്ക തിരയൽ ശ്രമിക്കുക.",
    [K.searchingLabels]: "സ്കാൻ ചെയ്ത എല്ലാ വിഭാഗങ്ങളിലും ലേബലുകൾ തിരയുന്നു.",
    [K.usingLabelSearch]: "സ്കാൻ ചെയ്ത ഫോട്ടോകളിൽ ലേബൽ തിരയൽ ഉപയോഗിക്കുന്നു.",
    [K.labelSearchUnsupported]:
      "ഈ വാക്കുകൾ പിന്തുണയുള്ള ഒരു ലേബൽ തിരയൽ രൂപപ്പെടുത്തുന്നില്ല. നായ അല്ലെങ്കിൽ കടൽത്തീരം പോലുള്ള കാണുന്ന ഉള്ളടക്കം ശ്രമിക്കുക. തീയതികൾ, പേരുകൾ, ഒഴിവാക്കലുകൾ എന്നിവയ്ക്ക് ലേബൽ തിരയൽ പിന്തുണ നൽകുന്നില്ല.",

    [K.outOfFocus]: "ഈ ഫോട്ടോ ഫോക്കസിലല്ലായിരിക്കാം.",
    [K.lowBrightness]: "ഈ ഫോട്ടോയിൽ വളരെ കുറഞ്ഞ പ്രകാശമാണ്.",
    [K.highBrightness]: "ഈ ഫോട്ടോയിൽ വളരെ കൂടിയ പ്രകാശമാണ്.",
    [K.lensSmudge]: "ലെൻസിലെ പാട് ചിത്രത്തിന്റെ വ്യക്തത കുറച്ചിരിക്കാം.",
    [K.lowQualityScore]: "ഈ ഫോട്ടോയ്ക്ക് കുറഞ്ഞ ദൃശ്യ-ഗുണനിലവാര സ്കോർ ലഭിച്ചു.",
    [K.reviewScreenshot]: "ഈ സ്ക്രീൻഷോട്ട് ഇപ്പോഴും വേണോ എന്ന് പരിശോധിക്കുക.",
    [K.reviewScreenRecording]:
      "ഈ സ്ക്രീൻ റെക്കോർഡിംഗ് ഇപ്പോഴും വേണോ എന്ന് പരിശോധിക്കുക.",
    [K.usesSize]: "ഈ ഇനം %@ ഉപയോഗിക്കുന്നു; അത് നിങ്ങൾക്ക് വേണോ എന്ന് പരിശോധിക്കുക.",

    [K.light]: "ലൈറ്റ്",
    [K.dark]: "ഡാർക്ക്",
    [K.nothingToFree]: "iPhone-ൽ ഒഴിവാക്കാൻ ഒന്നുമില്ല",
    [K.upToFree]: "iPhone-ൽ ഒഴിവാക്കാൻ %@ വരെ",
    [K.openToRefresh]: "പുതുക്കാൻ TidyByte തുറക്കുക",
    [K.updatedAgo]: "%lld ദിവസം മുമ്പ് പുതുക്കി",

    [K.noMatchingPhotos]: "പൊരുത്തപ്പെടുന്ന ഫോട്ടോകളില്ല",
    [K.submitSearch]:
      "ഒരു ഉള്ളടക്ക തിരയൽ സമർപ്പിക്കുക അല്ലെങ്കിൽ വേറെ വാക്കുകൾ ശ്രമിക്കുക.",
    [K.noPhotosInCategory]: "ഈ വിഭാഗത്തിൽ ഫോട്ടോകളില്ല.",
    [K.chooseAlbums]: "ആൽബങ്ങൾ തിരഞ്ഞെടുക്കുക അല്ലെങ്കിൽ ഫിൽട്ടറുകൾ മാറ്റുക.",
    [K.noScreenRecordings]: "സ്ക്രീൻ റെക്കോർഡിംഗുകൾ ഒന്നും കണ്ടെത്തിയില്ല.",
  },

  ru: {
    [K.needsPhotos]: "TidyByte нужен доступ к вашим фото",
    [K.needsPhotosBody]:
      "TidyByte просматривает медиатеку на этом устройстве и находит то, что стоит очистить. Ничего не загружается в сеть, и ничего не меняется без вашего согласия. Далее iOS запросит доступ.",
    [K.accessOn]: "Доступ к фото включен",
    [K.accessOnBody]:
      "TidyByte может просматривать вашу медиатеку на этом устройстве. Ничего не загружается в сеть, и ничего не меняется без вашего согласия.",
    [K.accessOff]: "Доступ к фото выключен",
    [K.accessOffBody]:
      "iOS блокирует доступ TidyByte к вашей медиатеке и больше не спросит. Вернуться можно только через «Настройки» — включите там доступ к фото, и все здесь снова заработает.",
    [K.accessRestricted]: "Доступ к фото ограничен",
    [K.accessRestrictedBody]:
      "Доступ к фото блокирует ограничение Screen Time или управления устройством. Переключатель «Фото» в «Настройках» этого не изменит — сначала нужно снять само ограничение.",
    [K.limitedBody]:
      "TidyByte видит только выбранные вами фото. Добавьте еще, когда захотите просмотреть остальную часть медиатеки.",
    [K.allowAccess]: "Разрешить доступ к фото?",
    [K.allowAccessBody]:
      "iOS запрашивает доступ к фото только один раз, и это тот самый запрос. Затем TidyByte просматривает медиатеку на этом устройстве. Ничего не загружается в сеть, и ничего не меняется без вашего просмотра.",
    [K.notNow]: "Не сейчас",

    [K.photoNotFound]: "Фото не найдено.",
    [K.notAnImage]: "Этот объект нельзя сжать как фото.",
    [K.photoLoadFailed]: "Не удалось загрузить фото.",
    [K.photoEncodeFailed]: "Не удалось повторно закодировать фото.",
    [K.photoSizeUnknown]: "Размер фото неизвестен (только в iCloud) — пропущено.",
    [K.videoNotFound]: "Видео не найдено.",
    [K.videoLoadFailed]:
      "Не удалось загрузить видео (возможно, оно еще в iCloud). Повторите попытку.",
    [K.videoSizeUnknown]: "Размер видео неизвестен (только в iCloud) — пропущено.",
    [K.exportSessionFailed]: "Не удалось создать сеанс экспорта.",
    [K.exportedEmpty]: "Экспортированный файл пуст.",
    [K.fileSizeReadFailed]: "Не удалось прочитать размер файла.",
    [K.cancelled]: "Отменено.",
    [K.unknownError]: "Неизвестная ошибка",
    [K.saveFailed]: "Не удалось сохранить: %@",
    [K.exportFailed]: "Не удалось экспортировать: %@",
    [K.alreadyCompressed]: "Уже сжато",
    [K.sizeUnknown]: "Размер неизвестен (только в iCloud) — пропущено",

    [K.aiUnavailable]: "Локальный ИИ недоступен.",
    [K.aiLanguageUnsupported]: "Этот язык не поддерживается локальным ИИ.",
    [K.aiNoInterpret]: "Локальный ИИ не смог обработать этот запрос.",
    [K.tooManyCharacters]: "Используйте не более 300 символов.",
    [K.visibleContentOnly]:
      "Поиск поддерживает только видимое содержимое, например собаки на пляже. Даты, места, имена и текст не индексируются.",
    [K.conceptsNotFound]:
      "Некоторые запрошенные понятия не найдены при этом сканировании. Попробуйте более простой поиск по содержимому.",
    [K.searchingLabels]: "Поиск меток по всем просканированным категориям.",
    [K.usingLabelSearch]: "Используется поиск по меткам среди просканированных фото.",
    [K.labelSearchUnsupported]:
      "Эти слова не образуют поддерживаемый поиск по меткам. Попробуйте видимое содержимое, например «собака» или «пляж». Поиск по меткам не поддерживает даты, имена и исключения.",

    [K.outOfFocus]: "Это фото может быть не в фокусе.",
    [K.lowBrightness]: "У этого фото очень низкая яркость.",
    [K.highBrightness]: "У этого фото очень высокая яркость.",
    [K.lensSmudge]: "Загрязнение объектива могло снизить четкость изображения.",
    [K.lowQualityScore]: "Это фото получило низкую оценку визуального качества.",
    [K.reviewScreenshot]: "Проверьте, нужен ли вам еще этот скриншот.",
    [K.reviewScreenRecording]: "Проверьте, нужна ли вам еще эта запись экрана.",
    [K.usesSize]: "Этот объект занимает %@; проверьте, нужен ли он вам.",

    [K.light]: "Светлое",
    [K.dark]: "Темное",
    [K.nothingToFree]: "На iPhone нечего освободить",
    [K.upToFree]: "До %@ можно освободить на iPhone",
    [K.openToRefresh]: "Откройте TidyByte для обновления",
    [K.updatedAgo]: "Обновлено %lld дн. назад",

    [K.noMatchingPhotos]: "Нет подходящих фото",
    [K.submitSearch]:
      "Отправьте поиск по содержимому или попробуйте другие слова.",
    [K.noPhotosInCategory]: "В этой категории нет фото.",
    [K.chooseAlbums]: "Выберите альбомы или измените фильтры.",
    [K.noScreenRecordings]: "Записи экрана не найдены.",
  },
};

const LANGS = ["te", "kn", "ml", "ru"];
const NEW_SET = new Set(Object.keys(translations.te));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const ENTRY_RE = /^ {4}("(?:[^"\\]|\\.)*"): (.*?)(,?)$/;

function parseStringsBlock(raw) {
  const pluralsIdx = raw.indexOf('\n  "plurals": {');
  if (pluralsIdx === -1) throw new Error('no top-level "plurals" block');
  const head = raw.slice(0, pluralsIdx); // ends with '\n  },'
  const tail = raw.slice(pluralsIdx); // starts with '\n  "plurals": {'
  const stringsIdx = head.indexOf('  "strings": {');
  if (stringsIdx === -1) throw new Error('no top-level "strings" block');
  const before = head.slice(0, stringsIdx);
  const block = head.slice(stringsIdx);
  const open = '  "strings": {\n';
  if (!block.startsWith(open)) throw new Error('unexpected "strings" opening');
  if (!block.endsWith("\n  },")) throw new Error('unexpected "strings" closing');
  const body = block.slice(open.length, block.length - "\n  },".length);
  return { before, open, body, after: "\n  }," + tail };
}

function bodyToEntries(body) {
  const entries = [];
  for (const line of body.split("\n")) {
    const m = ENTRY_RE.exec(line);
    if (!m) throw new Error(`unparsable line: ${JSON.stringify(line)}`);
    const key = JSON.parse(m[1]);
    const value = JSON.parse(m[2]);
    entries.push({ key, value, raw: line });
  }
  return entries;
}

function renderBody(entries) {
  return entries
    .map((e) => `    ${JSON.stringify(e.key)}: ${JSON.stringify(e.value)}`)
    .join(",\n");
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

fs.mkdirSync(BASELINE, { recursive: true });

// Pre-flight: the key set must be exactly the brief's table keys plus the one
// key the brief's prose omits ("Failed to re-encode the photo.", which sits in
// the same PhotoCompressionError enum as "Failed to load the photo.").
const briefRaw = fs.readFileSync(path.join(here, "_batch7-brief.md"), "utf8");
const briefKeys = [];
for (const line of briefRaw.split("\n")) {
  const trimmed = line.trim();
  if (!trimmed.startsWith("|") || /^\|\s*-+/.test(trimmed)) continue;
  if (/^\|\s*(Title|English)\s*\|/.test(trimmed)) continue;
  for (const cell of trimmed.split("|").slice(1, -1).map((c) => c.trim())) {
    const m = /^`([^`]+)`$/.exec(cell);
    if (m) briefKeys.push(m[1]);
  }
}
const inferredKey = K.photoEncodeFailed;
{
  const expected = new Set([...briefKeys, inferredKey]);
  const actual = new Set(Object.keys(translations.te));
  const missing = [...expected].filter((k) => !actual.has(k));
  const extra = [...actual].filter((k) => !expected.has(k));
  if (missing.length || extra.length) {
    throw new Error(
      `key set mismatch vs brief: missing=${JSON.stringify(missing)} extra=${JSON.stringify(extra)}`,
    );
  }
  if (briefKeys.includes(inferredKey)) {
    throw new Error("brief already lists the inferred key; update the check");
  }
  console.log(
    `pre-flight: ${briefKeys.length} brief keys + 1 inferred (${JSON.stringify(inferredKey)}) = ${actual.size}`,
  );
}

// Pre-flight: every key must appear verbatim in the Swift sources, so a typo in
// punctuation or an apostrophe cannot silently create a key nothing looks up.
{
  const repoRoot = path.resolve(here, "..", "..", "..");
  const swiftFiles = [];
  for (const root of ["Tidybyte", "TidybyteWidget"]) {
    const abs = path.join(repoRoot, root);
    if (!fs.existsSync(abs)) continue;
    (function walk(dir) {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.name.endsWith(".swift")) swiftFiles.push(p);
      }
    })(abs);
  }
  const source = swiftFiles.map((f) => fs.readFileSync(f, "utf8")).join("\n");
  const notFound = Object.keys(translations.te).filter(
    (k) => !source.includes(JSON.stringify(k)),
  );
  if (notFound.length) {
    throw new Error(
      `keys not present in Swift sources: ${JSON.stringify(notFound)}`,
    );
  }
  console.log(
    `pre-flight: all ${Object.keys(translations.te).length} keys found verbatim in ${swiftFiles.length} Swift files`,
  );
}

for (const lang of LANGS) {
  const file = path.join(here, `${lang}.json`);
  const raw = fs.readFileSync(file, "utf8");
  const original = JSON.parse(raw);
  const table = translations[lang];

  // Snapshot the pre-edit state for the verifier. Only the pristine (pre-batch)
  // file is snapshotted, so re-runs keep the original baseline.
  const pristine = Object.keys(original.strings).length === 495;
  if (pristine) {
    fs.writeFileSync(
      path.join(BASELINE, `${lang}.json`),
      JSON.stringify(original, null, 2) + "\n",
    );
  }

  const newKeys = Object.keys(table);
  if (newKeys.length !== 57) {
    throw new Error(`${lang}: expected 57 translations, got ${newKeys.length}`);
  }

  const parts = parseStringsBlock(raw);
  const entries = bodyToEntries(parts.body);

  const existing = new Map(entries.map((e) => [e.key, e]));
  if (existing.size !== entries.length) throw new Error(`${lang}: duplicate key`);

  // Every pre-existing line must round-trip byte-identically.
  const regeneratedOld = renderBody(entries);
  if (regeneratedOld !== parts.body) {
    throw new Error(`${lang}: pre-existing lines do not round-trip`);
  }

  // Idempotent: an existing new key is reconciled to the table value rather
  // than treated as an error, so this script can be re-run after a fixup.
  let inserted = 0;
  let reconciled = 0;
  const additions = [];
  for (const k of newKeys) {
    if (!table[k]) throw new Error(`${lang}: empty translation for: ${k}`);
    const prior = existing.get(k);
    if (prior) {
      if (prior.value !== table[k]) {
        prior.value = table[k];
        reconciled += 1;
      }
    } else {
      additions.push({ key: k, value: table[k] });
      inserted += 1;
    }
  }

  // Sort order used by the file: plain UTF-16 code-unit sort.
  const merged = [...entries, ...additions].sort((a, b) =>
    a.key < b.key ? -1 : a.key > b.key ? 1 : 0,
  );

  const next = parts.before + parts.open + renderBody(merged) + parts.after;

  // Guard: the written text must parse and keep every old value.
  const reparsed = JSON.parse(next);
  for (const k of Object.keys(original.strings)) {
    if (NEW_SET.has(k)) continue; // batch-7 keys may be reconciled
    if (reparsed.strings[k] !== original.strings[k]) {
      throw new Error(`${lang}: changed existing value for: ${k}`);
    }
  }
  if (JSON.stringify(reparsed.plurals) !== JSON.stringify(original.plurals)) {
    throw new Error(`${lang}: plurals changed`);
  }
  if (Object.keys(reparsed.strings).length !== 552) {
    throw new Error(
      `${lang}: expected 552 strings, got ${Object.keys(reparsed.strings).length}`,
    );
  }

  fs.writeFileSync(file, next);
  console.log(
    `${lang}.json: ${entries.length} -> ${Object.keys(reparsed.strings).length} keys ` +
      `(+${inserted} inserted, ${reconciled} reconciled)`,
  );
}

console.log("baseline snapshots written to " + BASELINE);
