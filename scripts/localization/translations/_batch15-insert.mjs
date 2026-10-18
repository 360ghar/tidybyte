#!/usr/bin/env node
/**
 * Batch 15 — inserts the 20 keys the defect sweep found.
 *
 * Covers de/es/fr/it/pt-BR, gu/kn/ml/pa/ar, ja/ko/zh-Hans/ru/he.
 * The five Indic and Devanagari languages (hi/bn/ta/te/mr) are handled by a
 * separate worker, so this script deliberately skips them.
 *
 * Run from the repo root: node scripts/localization/translations/_batch15-insert.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const LANGS = [
  'de', 'es', 'fr', 'it', 'pt-BR',
  'gu', 'kn', 'ml', 'pa', 'ar',
  'ja', 'ko', 'zh-Hans', 'ru', 'he',
];

/** The 18 plain keys, per language. */
const PLAIN = {
  de: {
    '%@ and %@': '%@ und %@',
    '%@ total': '%@ gesamt',
    '%@. %@ available.': '%@. %@ verfügbar.',
    'Apps, system & other': 'Apps, System & Sonstiges',
    Camera: 'Kamera',
    'Compress to save ~%@': 'Komprimieren und ~%@ sparen',
    'Failed to add to album: %@': 'Zum Album hinzufügen fehlgeschlagen: %@',
    'Free up %@': '%@ freigeben',
    Good: 'Gut',
    'Library grew by %@ %@': 'Mediathek um %@ %@ gewachsen',
    'Library shrank by %@ %@': 'Mediathek um %@ %@ geschrumpft',
    'No change %@': 'Keine Änderung %@',
    Overexposed: 'Überbelichtet',
    Photo: 'Foto',
    'Photos & Videos': 'Fotos & Videos',
    'Save ~%@ by converting': '~%@ durch Konvertieren sparen',
    Video: 'Video',
    estimated: 'geschätzt',
  },
  es: {
    '%@ and %@': '%@ y %@',
    '%@ total': '%@ en total',
    '%@. %@ available.': '%@. %@ disponible.',
    'Apps, system & other': 'Apps, sistema y otros',
    Camera: 'Cámara',
    'Compress to save ~%@': 'Comprime para ahorrar ~%@',
    'Failed to add to album: %@': 'No se pudo añadir al álbum: %@',
    'Free up %@': 'Libera %@',
    Good: 'Buena',
    'Library grew by %@ %@': 'La fototeca creció %@ %@',
    'Library shrank by %@ %@': 'La fototeca se redujo %@ %@',
    'No change %@': 'Sin cambios %@',
    Overexposed: 'Sobreexpuesta',
    Photo: 'Foto',
    'Photos & Videos': 'Fotos y vídeos',
    'Save ~%@ by converting': 'Ahorra ~%@ al convertir',
    Video: 'Vídeo',
    estimated: 'estimado',
  },
  fr: {
    '%@ and %@': '%@ et %@',
    '%@ total': '%@ au total',
    '%@. %@ available.': '%@. %@ disponible.',
    'Apps, system & other': 'Apps, système et autres',
    Camera: 'Appareil photo',
    'Compress to save ~%@': 'Compresser pour économiser ~%@',
    'Failed to add to album: %@': "Échec de l'ajout à l'album : %@",
    'Free up %@': 'Libérer %@',
    Good: 'Bonne',
    'Library grew by %@ %@': 'La photothèque a augmenté de %@ %@',
    'Library shrank by %@ %@': 'La photothèque a diminué de %@ %@',
    'No change %@': 'Aucun changement %@',
    Overexposed: 'Surexposée',
    Photo: 'Photo',
    'Photos & Videos': 'Photos et vidéos',
    'Save ~%@ by converting': 'Économisez ~%@ en convertissant',
    Video: 'Vidéo',
    estimated: 'estimé',
  },
  it: {
    '%@ and %@': '%@ e %@',
    '%@ total': '%@ in totale',
    '%@. %@ available.': '%@. %@ disponibile.',
    'Apps, system & other': 'App, sistema e altro',
    Camera: 'Fotocamera',
    'Compress to save ~%@': 'Comprimi per risparmiare ~%@',
    'Failed to add to album: %@': "Impossibile aggiungere all'album: %@",
    'Free up %@': 'Libera %@',
    Good: 'Buona',
    'Library grew by %@ %@': 'La libreria è cresciuta di %@ %@',
    'Library shrank by %@ %@': 'La libreria si è ridotta di %@ %@',
    'No change %@': 'Nessuna modifica %@',
    Overexposed: 'Sovraesposta',
    Photo: 'Foto',
    'Photos & Videos': 'Foto e video',
    'Save ~%@ by converting': 'Risparmia ~%@ convertendo',
    Video: 'Video',
    estimated: 'stimato',
  },
  'pt-BR': {
    '%@ and %@': '%@ e %@',
    '%@ total': '%@ no total',
    '%@. %@ available.': '%@. %@ disponível.',
    'Apps, system & other': 'Apps, sistema e outros',
    Camera: 'Câmera',
    'Compress to save ~%@': 'Compacte para economizar ~%@',
    'Failed to add to album: %@': 'Não foi possível adicionar ao álbum: %@',
    'Free up %@': 'Libere %@',
    Good: 'Boa',
    'Library grew by %@ %@': 'A biblioteca cresceu %@ %@',
    'Library shrank by %@ %@': 'A biblioteca diminuiu %@ %@',
    'No change %@': 'Sem alterações %@',
    Overexposed: 'Superexposta',
    Photo: 'Foto',
    'Photos & Videos': 'Fotos e vídeos',
    'Save ~%@ by converting': 'Economize ~%@ convertendo',
    Video: 'Vídeo',
    estimated: 'estimado',
  },
  gu: {
    '%@ and %@': '%@ અને %@',
    '%@ total': 'કુલ %@',
    '%@. %@ available.': '%@. %@ ઉપલબ્ધ.',
    'Apps, system & other': 'એપ્સ, સિસ્ટમ અને અન્ય',
    Camera: 'કૅમેરા',
    'Compress to save ~%@': '~%@ બચાવવા માટે કમ્પ્રેસ કરો',
    'Failed to add to album: %@': 'આલ્બમમાં ઉમેરવામાં નિષ્ફળ: %@',
    'Free up %@': '%@ ખાલી કરો',
    Good: 'સારું',
    'Library grew by %@ %@': 'લાઇબ્રેરી %@ %@ વધી',
    'Library shrank by %@ %@': 'લાઇબ્રેરી %@ %@ ઘટી',
    'No change %@': 'કોઈ ફેરફાર નથી %@',
    Overexposed: 'વધુ પ્રકાશિત',
    Photo: 'ફોટો',
    'Photos & Videos': 'ફોટા અને વિડિયો',
    'Save ~%@ by converting': 'કન્વર્ટ કરીને ~%@ બચાવો',
    Video: 'વિડિયો',
    estimated: 'અંદાજિત',
  },
  kn: {
    '%@ and %@': '%@ ಮತ್ತು %@',
    '%@ total': 'ಒಟ್ಟು %@',
    '%@. %@ available.': '%@. %@ ಲಭ್ಯವಿದೆ.',
    'Apps, system & other': 'ಆ್ಯಪ್ಗಳು, ಸಿಸ್ಟಂ ಮತ್ತು ಇತರೆ',
    Camera: 'ಕ್ಯಾಮೆರಾ',
    'Compress to save ~%@': '~%@ ಉಳಿಸಲು ಕಂಪ್ರೆಸ್ ಮಾಡಿ',
    'Failed to add to album: %@': 'ಆಲ್ಬಮ್ಗೆ ಸೇರಿಸಲು ವಿಫಲವಾಗಿದೆ: %@',
    'Free up %@': '%@ ಖಾಲಿ ಮಾಡಿ',
    Good: 'ಉತ್ತಮ',
    'Library grew by %@ %@': 'ಲೈಬ್ರರಿ %@ %@ ಹೆಚ್ಚಾಗಿದೆ',
    'Library shrank by %@ %@': 'ಲೈಬ್ರರಿ %@ %@ ಕಡಿಮೆಯಾಗಿದೆ',
    'No change %@': 'ಯಾವುದೇ ಬದಲಾವಣೆ ಇಲ್ಲ %@',
    Overexposed: 'ಹೆಚ್ಚು ಬೆಳಕು',
    Photo: 'ಫೋಟೋ',
    'Photos & Videos': 'ಫೋಟೋಗಳು ಮತ್ತು ವೀಡಿಯೊಗಳು',
    'Save ~%@ by converting': 'ಪರಿವರ್ತಿಸಿ ~%@ ಉಳಿಸಿ',
    Video: 'ವೀಡಿಯೊ',
    estimated: 'ಅಂದಾಜು',
  },
  ml: {
    '%@ and %@': '%@ കൂടാതെ %@',
    '%@ total': 'ആകെ %@',
    '%@. %@ available.': '%@. %@ ലഭ്യമാണ്.',
    'Apps, system & other': 'ആപ്പുകൾ, സിസ്റ്റം, മറ്റുള്ളവ',
    Camera: 'ക്യാമറ',
    'Compress to save ~%@': '~%@ ലാഭിക്കാൻ കംപ്രസ് ചെയ്യുക',
    'Failed to add to album: %@': 'ആൽബത്തിലേക്ക് ചേർക്കാനായില്ല: %@',
    'Free up %@': '%@ ഒഴിവാക്കുക',
    Good: 'നല്ലത്',
    'Library grew by %@ %@': 'ലൈബ്രറി %@ %@ വർധിച്ചു',
    'Library shrank by %@ %@': 'ലൈബ്രറി %@ %@ കുറഞ്ഞു',
    'No change %@': 'മാറ്റമില്ല %@',
    Overexposed: 'അധിക പ്രകാശം',
    Photo: 'ഫോട്ടോ',
    'Photos & Videos': 'ഫോട്ടോകളും വീഡിയോകളും',
    'Save ~%@ by converting': 'പരിവർത്തിച്ച് ~%@ ലാഭിക്കുക',
    Video: 'വീഡിയോ',
    estimated: 'ഏകദേശം',
  },
  pa: {
    '%@ and %@': '%@ ਅਤੇ %@',
    '%@ total': 'ਕੁੱਲ %@',
    '%@. %@ available.': '%@. %@ ਉਪਲਬਧ।',
    'Apps, system & other': 'ਐਪਾਂ, ਸਿਸਟਮ ਅਤੇ ਹੋਰ',
    Camera: 'ਕੈਮਰਾ',
    'Compress to save ~%@': '~%@ ਬਚਾਉਣ ਲਈ ਕੰਪ੍ਰੈਸ ਕਰੋ',
    'Failed to add to album: %@': 'ਐਲਬਮ ਵਿੱਚ ਜੋੜਨਾ ਅਸਫਲ: %@',
    'Free up %@': '%@ ਖਾਲੀ ਕਰੋ',
    Good: 'ਵਧੀਆ',
    'Library grew by %@ %@': 'ਲਾਇਬ੍ਰੇਰੀ %@ %@ ਵਧੀ',
    'Library shrank by %@ %@': 'ਲਾਇਬ੍ਰੇਰੀ %@ %@ ਘਟੀ',
    'No change %@': 'ਕੋਈ ਤਬਦੀਲੀ ਨਹੀਂ %@',
    Overexposed: 'ਬਹੁਤ ਜ਼ਿਆਦਾ ਰੌਸ਼ਨੀ',
    Photo: 'ਫ਼ੋਟੋ',
    'Photos & Videos': 'ਫ਼ੋਟੋਆਂ ਅਤੇ ਵੀਡੀਓ',
    'Save ~%@ by converting': 'ਬਦਲ ਕੇ ~%@ ਬਚਾਓ',
    Video: 'ਵੀਡੀਓ',
    estimated: 'ਅੰਦਾਜ਼ਨ',
  },
  ar: {
    '%@ and %@': '%@ و%@',
    '%@ total': '%@ إجمالًا',
    '%@. %@ available.': '%@. %@ متاح.',
    'Apps, system & other': 'التطبيقات والنظام وأخرى',
    Camera: 'الكاميرا',
    'Compress to save ~%@': 'اضغط لتوفير ~%@',
    'Failed to add to album: %@': 'فشل الإضافة إلى الألبوم: %@',
    'Free up %@': 'حرّر %@',
    Good: 'جيدة',
    'Library grew by %@ %@': 'زادت المكتبة بمقدار %@ %@',
    'Library shrank by %@ %@': 'انخفضت المكتبة بمقدار %@ %@',
    'No change %@': 'لا تغيير %@',
    Overexposed: 'مفرطة الإضاءة',
    Photo: 'صورة',
    'Photos & Videos': 'الصور والفيديوهات',
    'Save ~%@ by converting': 'وفّر ~%@ بالتحويل',
    Video: 'فيديو',
    estimated: 'تقديري',
  },
  ja: {
    '%@ and %@': '%@と%@',
    '%@ total': '合計 %@',
    '%@. %@ available.': '%@。%@ が利用できます。',
    'Apps, system & other': 'アプリ、システム、その他',
    Camera: 'カメラ',
    'Compress to save ~%@': '圧縮して約%@節約',
    'Failed to add to album: %@': 'アルバムに追加できませんでした: %@',
    'Free up %@': '%@を空ける',
    Good: '適正',
    'Library grew by %@ %@': 'ライブラリが %@ %@ 増えました',
    'Library shrank by %@ %@': 'ライブラリが %@ %@ 減りました',
    'No change %@': '変化なし %@',
    Overexposed: '明るすぎ',
    Photo: '写真',
    'Photos & Videos': '写真とビデオ',
    'Save ~%@ by converting': '変換して約%@節約',
    Video: 'ビデオ',
    estimated: '推定',
  },
  ko: {
    '%@ and %@': '%@ 및 %@',
    '%@ total': '총 %@',
    '%@. %@ available.': '%@. %@ 사용 가능.',
    'Apps, system & other': '앱, 시스템 및 기타',
    Camera: '카메라',
    'Compress to save ~%@': '압축하여 약 %@ 절약',
    'Failed to add to album: %@': '앨범에 추가하지 못했습니다: %@',
    'Free up %@': '%@ 확보',
    Good: '적정',
    'Library grew by %@ %@': '보관함이 %@ %@ 늘었습니다',
    'Library shrank by %@ %@': '보관함이 %@ %@ 줄었습니다',
    'No change %@': '변화 없음 %@',
    Overexposed: '너무 밝음',
    Photo: '사진',
    'Photos & Videos': '사진 및 동영상',
    'Save ~%@ by converting': '변환하여 약 %@ 절약',
    Video: '동영상',
    estimated: '예상',
  },
  'zh-Hans': {
    '%@ and %@': '%@ 和 %@',
    '%@ total': '共 %@',
    '%@. %@ available.': '%@。可使用%@。',
    'Apps, system & other': 'App、系统及其他',
    Camera: '相机',
    'Compress to save ~%@': '压缩可节省约 %@',
    'Failed to add to album: %@': '无法添加到相簿：%@',
    'Free up %@': '释放 %@',
    Good: '良好',
    'Library grew by %@ %@': '图库增加了 %@ %@',
    'Library shrank by %@ %@': '图库减少了 %@ %@',
    'No change %@': '无变化 %@',
    Overexposed: '过亮',
    Photo: '照片',
    'Photos & Videos': '照片和视频',
    'Save ~%@ by converting': '转换可节省约 %@',
    Video: '视频',
    estimated: '估计',
  },
  ru: {
    '%@ and %@': '%@ и %@',
    '%@ total': 'Всего %@',
    '%@. %@ available.': '%@. Доступно: %@.',
    'Apps, system & other': 'Приложения, система и другое',
    Camera: 'Камера',
    'Compress to save ~%@': 'Сжать и сэкономить ~%@',
    'Failed to add to album: %@': 'Не удалось добавить в альбом: %@',
    'Free up %@': 'Освободить %@',
    Good: 'Хорошо',
    'Library grew by %@ %@': 'Медиатека выросла на %@ %@',
    'Library shrank by %@ %@': 'Медиатека уменьшилась на %@ %@',
    'No change %@': 'Без изменений %@',
    Overexposed: 'Пересвечено',
    Photo: 'Фото',
    'Photos & Videos': 'Фото и видео',
    'Save ~%@ by converting': 'Сэкономить ~%@ при конвертации',
    Video: 'Видео',
    estimated: 'примерно',
  },
  he: {
    '%@ and %@': '%@ ו%@',
    '%@ total': '%@ בסך הכול',
    '%@. %@ available.': '%@. %@ זמין.',
    'Apps, system & other': 'אפליקציות, מערכת ואחר',
    Camera: 'מצלמה',
    'Compress to save ~%@': 'כווץ כדי לחסוך ~%@',
    'Failed to add to album: %@': 'הוספה לאלבום נכשלה: %@',
    'Free up %@': 'פנה %@',
    Good: 'טובה',
    'Library grew by %@ %@': 'הספרייה גדלה ב-%@ %@',
    'Library shrank by %@ %@': 'הספרייה קטנה ב-%@ %@',
    'No change %@': 'ללא שינוי %@',
    Overexposed: 'חשיפה יתרה',
    Photo: 'תמונה',
    'Photos & Videos': 'תמונות וסרטונים',
    'Save ~%@ by converting': 'חסוך ~%@ בהמרה',
    Video: 'סרטון',
    estimated: 'משוער',
  },
};

/** The 2 plural keys, per language, using exactly that language's CLDR set. */
const PLURALS = {
  de: {
    '%lld saved from apps': { one: '%lld aus einer App gesichert', other: '%lld aus Apps gesichert' },
    '%lld videos over %lld MB': { one: '%lld Video über %lld MB', other: '%lld Videos über %lld MB' },
  },
  es: {
    '%lld saved from apps': {
      one: '%lld guardada desde una app',
      many: '%lld guardadas desde apps',
      other: '%lld guardadas desde apps',
    },
    '%lld videos over %lld MB': {
      one: '%lld vídeo de más de %lld MB',
      many: '%lld vídeos de más de %lld MB',
      other: '%lld vídeos de más de %lld MB',
    },
  },
  fr: {
    '%lld saved from apps': {
      one: '%lld enregistrée depuis une app',
      many: '%lld enregistrées depuis des apps',
      other: '%lld enregistrées depuis des apps',
    },
    '%lld videos over %lld MB': {
      one: '%lld vidéo de plus de %lld MB',
      many: '%lld vidéos de plus de %lld MB',
      other: '%lld vidéos de plus de %lld MB',
    },
  },
  it: {
    '%lld saved from apps': {
      one: "%lld salvata da un'app",
      many: "%lld salvate da app",
      other: "%lld salvate da app",
    },
    '%lld videos over %lld MB': {
      one: '%lld video oltre %lld MB',
      many: '%lld video oltre %lld MB',
      other: '%lld video oltre %lld MB',
    },
  },
  'pt-BR': {
    '%lld saved from apps': {
      one: '%lld salva de apps',
      many: '%lld salvas de apps',
      other: '%lld salvas de apps',
    },
    '%lld videos over %lld MB': {
      one: '%lld vídeo acima de %lld MB',
      many: '%lld vídeos acima de %lld MB',
      other: '%lld vídeos acima de %lld MB',
    },
  },
  gu: {
    '%lld saved from apps': { one: '%lld એપમાંથી સાચવેલી', other: '%lld એપ્સમાંથી સાચવેલી' },
    '%lld videos over %lld MB': {
      one: '%lld વિડિયો %lld MB થી વધુ',
      other: '%lld વિડિયો %lld MB થી વધુ',
    },
  },
  kn: {
    '%lld saved from apps': { one: '%lld ಆ್ಯಪ್ನಿಂದ ಉಳಿಸಲಾಗಿದೆ', other: '%lld ಆ್ಯಪ್ಗಳಿಂದ ಉಳಿಸಲಾಗಿದೆ' },
    '%lld videos over %lld MB': {
      one: '%lld ವೀಡಿಯೊ %lld MB ಗಿಂತ ಹೆಚ್ಚು',
      other: '%lld ವೀಡಿಯೊಗಳು %lld MB ಗಿಂತ ಹೆಚ್ಚು',
    },
  },
  ml: {
    '%lld saved from apps': {
      one: '%lld ആപ്പിൽ നിന്ന് സേവ് ചെയ്തത്',
      other: '%lld ആപ്പുകളിൽ നിന്ന് സേവ് ചെയ്തത്',
    },
    '%lld videos over %lld MB': {
      one: '%lld വീഡിയോ %lld MB-ൽ കൂടുതൽ',
      other: '%lld വീഡിയോകൾ %lld MB-ൽ കൂടുതൽ',
    },
  },
  pa: {
    '%lld saved from apps': { one: '%lld ਐਪ ਤੋਂ ਸੇਵ ਕੀਤੀ', other: '%lld ਐਪਾਂ ਤੋਂ ਸੇਵ ਕੀਤੀਆਂ' },
    '%lld videos over %lld MB': {
      one: '%lld ਵੀਡੀਓ %lld MB ਤੋਂ ਵੱਧ',
      other: '%lld ਵੀਡੀਓ %lld MB ਤੋਂ ਵੱਧ',
    },
  },
  ar: {
    '%lld saved from apps': {
      zero: '%lld محفوظة من التطبيقات',
      one: '%lld محفوظة من تطبيق',
      two: '%lld محفوظتان من تطبيقين',
      few: '%lld محفوظة من تطبيقات',
      many: '%lld محفوظة من تطبيق',
      other: '%lld محفوظة من تطبيق',
    },
    '%lld videos over %lld MB': {
      zero: '%lld فيديو أكبر من %lld MB',
      one: '%lld فيديو أكبر من %lld MB',
      two: '%lld فيديوهان أكبر من %lld MB',
      few: '%lld فيديوهات أكبر من %lld MB',
      many: '%lld فيديو أكبر من %lld MB',
      other: '%lld فيديو أكبر من %lld MB',
    },
  },
  ja: {
    '%lld saved from apps': { other: '%lld件をアプリから保存' },
    '%lld videos over %lld MB': { other: '%lld MB を超えるビデオ %lld本' },
  },
  ko: {
    '%lld saved from apps': { other: '앱에서 저장한 %lld개' },
    '%lld videos over %lld MB': { other: '%lld MB 초과 동영상 %lld개' },
  },
  'zh-Hans': {
    '%lld saved from apps': { other: '%lld 个从 App 保存的' },
    '%lld videos over %lld MB': { other: '%lld 个超过 %lld MB 的视频' },
  },
  ru: {
    '%lld saved from apps': {
      one: '%lld сохранён из приложения',
      few: '%lld сохранены из приложений',
      many: '%lld сохранено из приложений',
      other: '%lld сохранено из приложений',
    },
    '%lld videos over %lld MB': {
      one: '%lld видео больше %lld MB',
      few: '%lld видео больше %lld MB',
      many: '%lld видео больше %lld MB',
      other: '%lld видео больше %lld MB',
    },
  },
  he: {
    '%lld saved from apps': {
      one: '%lld נשמר מאפליקציה',
      two: '%lld נשמרו מאפליקציות',
      other: '%lld נשמרו מאפליקציות',
    },
    '%lld videos over %lld MB': {
      one: '%lld סרטון מעל %lld MB',
      two: '%lld סרטונים מעל %lld MB',
      other: '%lld סרטונים מעל %lld MB',
    },
  },
};

let changed = 0;
for (const language of LANGS) {
  const path = join(DIR, `${language}.json`);
  const data = JSON.parse(readFileSync(path, 'utf8'));
  const beforeStrings = Object.keys(data.strings ?? {}).length;
  const beforePlurals = Object.keys(data.plurals ?? {}).length;

  data.strings ??= {};
  data.plurals ??= {};

  for (const [key, value] of Object.entries(PLAIN[language])) {
    data.strings[key] = value;
  }
  for (const [key, forms] of Object.entries(PLURALS[language])) {
    data.plurals[key] = forms;
  }

  // The two objects have different conventions, and getting them wrong turns a
  // small insertion into a huge diff:
  //
  //   - `.strings` is kept in code-unit key order. Plain `.sort()`, NOT
  //     `localeCompare`: the two disagree on keys beginning with punctuation
  //     (`-%@` sorts after `%@` by code unit, before it under `localeCompare`),
  //     and every file in the repo uses code-unit order.
  //   - `.plurals` is NOT sorted. Each batch appends its keys, so the object
  //     reads as a history of when keys were added. Sorting it reorders 66
  //     existing entries and buries the two real additions.
  data.strings = Object.fromEntries(Object.entries(data.strings).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);

  const dStrings = Object.keys(data.strings).length - beforeStrings;
  const dPlurals = Object.keys(data.plurals).length - beforePlurals;
  console.log(
    `${language.padEnd(9)} strings ${beforeStrings} -> ${Object.keys(data.strings).length} (+${dStrings})`
    + `  plurals ${beforePlurals} -> ${Object.keys(data.plurals).length} (+${dPlurals})`,
  );
  changed += 1;
}
console.log(`\n${changed} file(s) written.`);
