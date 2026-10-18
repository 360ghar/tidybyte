import fs from 'node:fs';
import path from 'node:path';

const dir = '/Users/sakshammittal/Documents/360ghar/github/archived/tidybyte/scripts/localization/translations';

const additions = {
  mr: {
    'Start a cleanup session with %@': '%@ सोबत क्लीनअप सत्र सुरू करा',
    'Clean up photos with %@': '%@ सोबत फोटो स्वच्छ करा',
    'Tidy my photos with %@': '%@ सोबत माझे फोटो नीटनेटके करा',
    'Show storage in %@': '%@ मध्ये स्टोरेज दाखवा',
    'Check my storage with %@': '%@ सोबत माझे स्टोरेज तपासा',
    'Clean screenshots with %@': '%@ सोबत स्क्रीनशॉट स्वच्छ करा',
    'How much can I free with %@': '%@ सोबत मी किती मोकळे करू शकतो?',
    'Check free space with %@': '%@ सोबत मोकळी जागा तपासा',
    'Show my savings in %@': '%@ मध्ये माझी बचत दाखवा',
  },
  gu: {
    'Start a cleanup session with %@': '%@ સાથે ક્લીનઅપ સત્ર શરૂ કરો',
    'Clean up photos with %@': '%@ સાથે ફોટા સાફ કરો',
    'Tidy my photos with %@': '%@ સાથે મારા ફોટા વ્યવસ્થિત કરો',
    'Show storage in %@': '%@ માં સ્ટોરેજ બતાવો',
    'Check my storage with %@': '%@ સાથે મારું સ્ટોરેજ તપાસો',
    'Clean screenshots with %@': '%@ સાથે સ્ક્રીનશોટ સાફ કરો',
    'How much can I free with %@': '%@ સાથે હું કેટલું ખાલી કરી શકું?',
    'Check free space with %@': '%@ સાથે ખાલી જગ્યા તપાસો',
    'Show my savings in %@': '%@ માં મારી બચત બતાવો',
  },
  pa: {
    'Start a cleanup session with %@': '%@ ਨਾਲ ਸਫ਼ਾਈ ਸੈਸ਼ਨ ਸ਼ੁਰੂ ਕਰੋ',
    'Clean up photos with %@': '%@ ਨਾਲ ਫ਼ੋਟੋਆਂ ਸਾਫ਼ ਕਰੋ',
    'Tidy my photos with %@': '%@ ਨਾਲ ਮੇਰੀਆਂ ਫ਼ੋਟੋਆਂ ਸਾਫ਼-ਸੁਥਰੀਆਂ ਕਰੋ',
    'Show storage in %@': '%@ ਵਿੱਚ ਸਟੋਰੇਜ ਦਿਖਾਓ',
    'Check my storage with %@': '%@ ਨਾਲ ਮੇਰਾ ਸਟੋਰੇਜ ਜਾਂਚੋ',
    'Clean screenshots with %@': '%@ ਨਾਲ ਸਕਰੀਨਸ਼ਾਟ ਸਾਫ਼ ਕਰੋ',
    'How much can I free with %@': '%@ ਨਾਲ ਮੈਂ ਕਿੰਨੀ ਥਾਂ ਖਾਲੀ ਕਰ ਸਕਦਾ ਹਾਂ?',
    'Check free space with %@': '%@ ਨਾਲ ਖਾਲੀ ਥਾਂ ਜਾਂਚੋ',
    'Show my savings in %@': '%@ ਵਿੱਚ ਮੇਰੀ ਬਚਤ ਦਿਖਾਓ',
  },
  ta: {
    'Start a cleanup session with %@': '%@ உடன் சுத்த அமர்வைத் தொடங்கு',
    'Clean up photos with %@': '%@ உடன் புகைப்படங்களைச் சுத்தம் செய்',
    'Tidy my photos with %@': '%@ உடன் என் புகைப்படங்களை ஒழுங்குபடுத்து',
    'Show storage in %@': '%@-இல் சேமிப்பகத்தைக் காட்டு',
    'Check my storage with %@': '%@ உடன் என் சேமிப்பகத்தைச் சரிபார்',
    'Clean screenshots with %@': '%@ உடன் ஸ்கிரீன்ஷாட்களைச் சுத்தம் செய்',
    'How much can I free with %@': '%@ உடன் நான் எவ்வளவு காலி செய்ய முடியும்?',
    'Check free space with %@': '%@ உடன் காலி இடத்தைச் சரிபார்',
    'Show my savings in %@': '%@-இல் என் சேமிப்பைக் காட்டு',
  },
};

for (const lang of Object.keys(additions)) {
  const file = path.join(dir, `${lang}.json`);
  const original = JSON.parse(fs.readFileSync(file, 'utf8'));
  const beforeKeys = Object.keys(original.strings);
  const beforePlurals = JSON.stringify(original.plurals);

  for (const [k, v] of Object.entries(additions[lang])) {
    if (k in original.strings) throw new Error(`${lang}: key already present: ${k}`);
    original.strings[k] = v;
  }

  // Preserve existing key order (default lexicographic sort).
  const sorted = {};
  for (const k of Object.keys(original.strings).sort()) sorted[k] = original.strings[k];
  original.strings = sorted;

  fs.writeFileSync(file, JSON.stringify(original, null, 2) + '\n', 'utf8');
  console.log(`${lang}: ${beforeKeys.length} -> ${Object.keys(original.strings).length}, plurals unchanged: ${beforePlurals === JSON.stringify(original.plurals)}`);
}
