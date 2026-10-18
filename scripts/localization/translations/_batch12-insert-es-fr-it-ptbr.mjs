// Batch 12 — Spanish, French, German, Brazilian Portuguese, Italian.
//
// Adds the 43 keys listed in `_batch12-keys.json` to the five translation
// files. Writes nothing until the key set is asserted against that file, so a
// key added or renamed in the list cannot silently ship untranslated.
//
//   node scripts/localization/translations/_batch12-insert-es-fr-it-ptbr.mjs
//
// The baseline copy of each file is written to /tmp/batch12-baseline/ before
// the file is touched, so `_batch12-verify-es-fr-it-ptbr.mjs` can prove that no
// pre-existing key changed and that `plurals` is untouched.
//
// Key order: the files are in plain code-point sort order (verified: the
// existing key list equals `[...keys].sort()` and does not equal a
// `localeCompare` sort), so the union is re-sorted the same way.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = '/tmp/batch12-baseline';

const LANGS = ['es', 'fr', 'de', 'pt-BR', 'it'];
const EXPECTED_BASELINE_STRINGS = 641;
const EXPECTED_FINAL_STRINGS = EXPECTED_BASELINE_STRINGS + 43;

/// Keys whose correct translation is the English text, because the only words
/// in them are keep-literal product names (glossary `keepLiteral`). Everything
/// else that came back unchanged is a mistake, not a translation.
const ALLOWED_IDENTICAL = new Set(['Live Photo.', 'In iCloud.']);

const TEMPLATE_KEY =
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.";

// ---------------------------------------------------------------------------
// The translations. One object per language, exactly the 43 keys.
//
// The six sentence fragments are written to read correctly after the verb of
// the template, and are kept parallel across the photo / video / Live Photo
// variants. They are not capitalized and carry no full stop.
// ---------------------------------------------------------------------------

const TRANSLATIONS = {
  es: {
    ' known · %lld sizes unavailable': ' conocidos · %lld tamaños no disponibles',
    [TEMPLATE_KEY]:
      '1. TidyByte guarda %@.\n2. Cuando todas las copias estén guardadas, iOS te pide que elimines %@.\n\nSi tocas "No permitir", conservas ambas versiones. Los originales eliminados permanecen en Recientemente eliminados durante 30 días.',
    Best: 'Mejor',
    'Best exposed': 'Mejor exposición',
    'Best overall': 'Mejor en conjunto',
    'Best quality': 'Mejor calidad',
    Blur: 'Desenfoque',
    Brightness: 'Brillo',
    "Couldn't prepare the selected items to share.":
      'No se pudieron preparar los elementos seleccionados para compartir.',
    Darkness: 'Oscuridad',
    'Detected by file name heuristics — may include some camera photos':
      'Detectadas por heurística del nombre de archivo — pueden incluir algunas fotos de cámara',
    "Don't Delete": 'No eliminar',
    'Failed to save compressed photo to library.':
      'No se pudo guardar la foto comprimida en la fototeca.',
    'Failed to save compressed video to library.':
      'No se pudo guardar el vídeo comprimido en la fototeca.',
    'Highest res': 'Mayor resolución',
    'In iCloud.': 'En iCloud.',
    'Keep as Best': 'Conservar como mejor',
    'Keeping this · %@': 'Conservando esta · %@',
    'Lens smudge confidence': 'Confianza de mancha en la lente',
    'Live Photo.': 'Live Photo.',
    'Most recent': 'Más reciente',
    'No Large Files': 'Sin archivos grandes',
    'No Large Videos': 'Sin vídeos grandes',
    'No files larger than %lld MB. Lower the threshold to see more.':
      'No hay archivos de más de %lld MB. Baja el umbral para ver más.',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      'No hay fotos de más de %lld MB. Baja el umbral o cambia a Todo/Vídeos.',
    'No savings — kept original': 'Sin ahorro — se conservó el original',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      'No hay vídeos de más de %lld MB. Baja el umbral o cambia a Todo/Fotos.',
    'Not loaded yet. Delete is off until it shows.':
      'Aún no se ha cargado. Eliminar está desactivado hasta que aparezca.',
    'Original kept — both versions in your library':
      'Original conservado — ambas versiones están en tu fototeca',
    'Recommended: %@': 'Recomendación: %@',
    Sharpest: 'Más nítida',
    'Sizes unavailable': 'Tamaños no disponibles',
    'Step 1 of 2 · Saving copy %lld of %lld': 'Paso 1 de 2 · Guardando copia %lld de %lld',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      'Paso 2 de 2 · Confirma en el aviso de iOS para eliminar los originales',
    'Working…': 'Procesando…',
    'Your choice': 'Tu elección',
    'Your library changed during analysis. Scan again for current results.':
      'Tu fototeca cambió durante el análisis. Vuelve a analizar para ver los resultados actuales.',
    'a new, smaller copy of each photo': 'una copia nueva y más pequeña de cada foto',
    'a new, smaller copy of each video': 'una copia nueva y más pequeña de cada vídeo',
    'the Live Photos': 'las Live Photos',
    'the original photos': 'las fotos originales',
    'the original videos': 'los vídeos originales',
    'the still image of each Live Photo as a new photo':
      'la foto fija de cada Live Photo como una foto nueva',
  },

  fr: {
    ' known · %lld sizes unavailable': ' connu · %lld tailles indisponibles',
    [TEMPLATE_KEY]:
      '1. TidyByte enregistre %@.\n2. Une fois toutes les copies enregistrées, iOS vous demande de supprimer %@.\n\nSi vous touchez "Ne pas autoriser", vous gardez les deux versions. Les originaux supprimés restent dans Récemment supprimés pendant 30 jours.',
    Best: 'Meilleure',
    'Best exposed': 'Mieux exposée',
    'Best overall': 'Meilleure au global',
    'Best quality': 'Meilleure qualité',
    Blur: 'Flou',
    Brightness: 'Luminosité',
    "Couldn't prepare the selected items to share.":
      'Impossible de préparer les éléments sélectionnés pour le partage.',
    Darkness: 'Obscurité',
    'Detected by file name heuristics — may include some camera photos':
      "Détectées par heuristique sur le nom du fichier — peut inclure des photos prises avec l'appareil photo",
    "Don't Delete": 'Ne pas supprimer',
    'Failed to save compressed photo to library.':
      "Impossible d'enregistrer la photo compressée dans la photothèque.",
    'Failed to save compressed video to library.':
      "Impossible d'enregistrer la vidéo compressée dans la photothèque.",
    'Highest res': 'Plus haute résolution',
    'In iCloud.': 'Dans iCloud.',
    'Keep as Best': 'Garder comme meilleure',
    'Keeping this · %@': 'Vous gardez celle-ci · %@',
    'Lens smudge confidence': "Confiance traces sur l'objectif",
    'Live Photo.': 'Live Photo.',
    'Most recent': 'Plus récente',
    'No Large Files': 'Aucun fichier volumineux',
    'No Large Videos': 'Aucune vidéo volumineuse',
    'No files larger than %lld MB. Lower the threshold to see more.':
      'Aucun fichier de plus de %lld MB. Abaissez le seuil pour en voir plus.',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      'Aucune photo de plus de %lld MB. Abaissez le seuil ou passez à Tout/Vidéos.',
    'No savings — kept original': 'Aucune économie — original conservé',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      'Aucune vidéo de plus de %lld MB. Abaissez le seuil ou passez à Tout/Photos.',
    'Not loaded yet. Delete is off until it shows.':
      "Pas encore chargée. Supprimer est désactivé tant qu'elle ne s'affiche pas.",
    'Original kept — both versions in your library':
      'Original conservé — les deux versions sont dans votre photothèque',
    'Recommended: %@': 'Recommandation : %@',
    Sharpest: 'Plus nette',
    'Sizes unavailable': 'Tailles indisponibles',
    'Step 1 of 2 · Saving copy %lld of %lld':
      'Étape 1 sur 2 · Enregistrement de la copie %lld sur %lld',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      "Étape 2 sur 2 · Confirmez dans l'alerte iOS pour supprimer les originaux",
    'Working…': 'Traitement…',
    'Your choice': 'Votre choix',
    'Your library changed during analysis. Scan again for current results.':
      "Votre photothèque a changé pendant l'analyse. Relancez l'analyse pour obtenir des résultats à jour.",
    'a new, smaller copy of each photo': 'une nouvelle copie plus légère de chaque photo',
    'a new, smaller copy of each video': 'une nouvelle copie plus légère de chaque vidéo',
    'the Live Photos': 'les Live Photos',
    'the original photos': "les photos d'origine",
    'the original videos': "les vidéos d'origine",
    'the still image of each Live Photo as a new photo':
      'la photo fixe de chaque Live Photo comme une nouvelle photo',
  },

  de: {
    ' known · %lld sizes unavailable': ' bekannt · %lld Größen nicht verfügbar',
    [TEMPLATE_KEY]:
      '1. TidyByte sichert %@.\n2. Wenn alle Kopien gesichert sind, fragt iOS, ob du %@ löschen möchtest.\n\nWenn du auf „Nicht erlauben“ tippst, behältst du beide Versionen. Gelöschte Originale bleiben 30 Tage in „Zuletzt gelöscht“.',
    Best: 'Bestes',
    'Best exposed': 'Beste Belichtung',
    'Best overall': 'Insgesamt am besten',
    'Best quality': 'Beste Qualität',
    Blur: 'Unschärfe',
    Brightness: 'Helligkeit',
    "Couldn't prepare the selected items to share.":
      'Die ausgewählten Objekte konnten nicht zum Teilen vorbereitet werden.',
    Darkness: 'Dunkelheit',
    'Detected by file name heuristics — may include some camera photos':
      'Anhand von Dateinamen-Heuristiken erkannt — kann einige Kamerafotos enthalten',
    "Don't Delete": 'Nicht löschen',
    'Failed to save compressed photo to library.':
      'Das komprimierte Foto konnte nicht in der Mediathek gesichert werden.',
    'Failed to save compressed video to library.':
      'Das komprimierte Video konnte nicht in der Mediathek gesichert werden.',
    'Highest res': 'Höchste Auflösung',
    'In iCloud.': 'In iCloud.',
    'Keep as Best': 'Als bestes behalten',
    'Keeping this · %@': 'Diese wird behalten · %@',
    'Lens smudge confidence': 'Sicherheit: verschmutzte Linse',
    'Live Photo.': 'Live Photo.',
    'Most recent': 'Neueste',
    'No Large Files': 'Keine großen Dateien',
    'No Large Videos': 'Keine großen Videos',
    'No files larger than %lld MB. Lower the threshold to see more.':
      'Keine Dateien über %lld MB. Verringere den Schwellenwert, um mehr zu sehen.',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      'Keine Fotos über %lld MB. Verringere den Schwellenwert oder wechsle zu Alle/Videos.',
    'No savings — kept original': 'Keine Einsparung — Original behalten',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      'Keine Videos über %lld MB. Verringere den Schwellenwert oder wechsle zu Alle/Fotos.',
    'Not loaded yet. Delete is off until it shows.':
      'Noch nicht geladen. Löschen ist deaktiviert, bis es angezeigt wird.',
    'Original kept — both versions in your library':
      'Original behalten — beide Versionen sind in deiner Mediathek',
    'Recommended: %@': 'Empfohlen: %@',
    Sharpest: 'Schärfste',
    'Sizes unavailable': 'Größen nicht verfügbar',
    'Step 1 of 2 · Saving copy %lld of %lld':
      'Schritt 1 von 2 · Kopie %lld von %lld wird gesichert',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      'Schritt 2 von 2 · Bestätige im iOS-Dialog, um die Originale zu löschen',
    'Working…': 'Wird verarbeitet…',
    'Your choice': 'Deine Wahl',
    'Your library changed during analysis. Scan again for current results.':
      'Deine Mediathek hat sich während der Analyse geändert. Scanne erneut für aktuelle Ergebnisse.',
    'a new, smaller copy of each photo': 'eine neue, kleinere Kopie von jedem Foto',
    'a new, smaller copy of each video': 'eine neue, kleinere Kopie von jedem Video',
    'the Live Photos': 'die Live Photos',
    'the original photos': 'die Originalfotos',
    'the original videos': 'die Originalvideos',
    'the still image of each Live Photo as a new photo':
      'das Standbild jeder Live Photo als neues Foto',
  },

  'pt-BR': {
    ' known · %lld sizes unavailable': ' conhecidos · %lld tamanhos indisponíveis',
    [TEMPLATE_KEY]:
      '1. O TidyByte salva %@.\n2. Quando todas as cópias forem salvas, o iOS pede que você apague %@.\n\nSe você tocar em "Não Permitir", mantém as duas versões. Os originais apagados ficam em Excluídos recentemente por 30 dias.',
    Best: 'Melhor',
    'Best exposed': 'Melhor exposição',
    'Best overall': 'Melhor no geral',
    'Best quality': 'Melhor qualidade',
    Blur: 'Desfoque',
    Brightness: 'Brilho',
    "Couldn't prepare the selected items to share.":
      'Não foi possível preparar os itens selecionados para compartilhar.',
    Darkness: 'Escuridão',
    'Detected by file name heuristics — may include some camera photos':
      'Detectadas por heurística de nome de arquivo — pode incluir algumas fotos da câmera',
    "Don't Delete": 'Não apagar',
    'Failed to save compressed photo to library.':
      'Falha ao salvar a foto comprimida na biblioteca.',
    'Failed to save compressed video to library.':
      'Falha ao salvar o vídeo comprimido na biblioteca.',
    'Highest res': 'Maior resolução',
    'In iCloud.': 'No iCloud.',
    'Keep as Best': 'Manter como melhor',
    'Keeping this · %@': 'Mantendo esta · %@',
    'Lens smudge confidence': 'Confiança de mancha na lente',
    'Live Photo.': 'Live Photo.',
    'Most recent': 'Mais recente',
    'No Large Files': 'Nenhum arquivo grande',
    'No Large Videos': 'Nenhum vídeo grande',
    'No files larger than %lld MB. Lower the threshold to see more.':
      'Nenhum arquivo acima de %lld MB. Reduza o limite para ver mais.',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      'Nenhuma foto acima de %lld MB. Reduza o limite ou mude para Tudo/Vídeos.',
    'No savings — kept original': 'Sem economia — original mantido',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      'Nenhum vídeo acima de %lld MB. Reduza o limite ou mude para Tudo/Fotos.',
    'Not loaded yet. Delete is off until it shows.':
      'Ainda não carregou. Apagar fica desativado até aparecer.',
    'Original kept — both versions in your library':
      'Original mantido — as duas versões estão na sua biblioteca',
    'Recommended: %@': 'Recomendação: %@',
    Sharpest: 'Mais nítida',
    'Sizes unavailable': 'Tamanhos indisponíveis',
    'Step 1 of 2 · Saving copy %lld of %lld': 'Etapa 1 de 2 · Salvando cópia %lld de %lld',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      'Etapa 2 de 2 · Confirme no alerta do iOS para apagar os originais',
    'Working…': 'Processando…',
    'Your choice': 'Sua escolha',
    'Your library changed during analysis. Scan again for current results.':
      'Sua biblioteca mudou durante a análise. Analise de novo para ver os resultados atuais.',
    'a new, smaller copy of each photo': 'uma nova cópia menor de cada foto',
    'a new, smaller copy of each video': 'uma nova cópia menor de cada vídeo',
    'the Live Photos': 'as Live Photos',
    'the original photos': 'as fotos originais',
    'the original videos': 'os vídeos originais',
    'the still image of each Live Photo as a new photo':
      'a foto estática de cada Live Photo como uma nova foto',
  },

  it: {
    ' known · %lld sizes unavailable': ' noti · %lld dimensioni non disponibili',
    [TEMPLATE_KEY]:
      '1. TidyByte salva %@.\n2. Quando tutte le copie sono salvate, iOS ti chiede di eliminare %@.\n\nSe tocchi "Non consentire", mantieni entrambe le versioni. Gli originali eliminati restano in Eliminati di recente per 30 giorni.',
    Best: 'Migliore',
    'Best exposed': 'Esposizione migliore',
    'Best overall': 'Migliore nel complesso',
    'Best quality': 'Qualità migliore',
    Blur: 'Sfocatura',
    Brightness: 'Luminosità',
    "Couldn't prepare the selected items to share.":
      'Impossibile preparare gli elementi selezionati da condividere.',
    Darkness: 'Oscurità',
    'Detected by file name heuristics — may include some camera photos':
      'Rilevate tramite euristica sul nome del file — possono includere foto della fotocamera',
    "Don't Delete": 'Non eliminare',
    'Failed to save compressed photo to library.':
      'Impossibile salvare la foto compressa nella libreria.',
    'Failed to save compressed video to library.':
      'Impossibile salvare il video compresso nella libreria.',
    'Highest res': 'Risoluzione più alta',
    'In iCloud.': 'In iCloud.',
    'Keep as Best': 'Tieni come migliore',
    'Keeping this · %@': 'Tieni questa · %@',
    'Lens smudge confidence': "Confidenza impronte sull'obiettivo",
    'Live Photo.': 'Live Photo.',
    'Most recent': 'Più recente',
    'No Large Files': 'Nessun file di grandi dimensioni',
    'No Large Videos': 'Nessun video di grandi dimensioni',
    'No files larger than %lld MB. Lower the threshold to see more.':
      'Nessun file oltre %lld MB. Riduci la soglia per vederne di più.',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      'Nessuna foto oltre %lld MB. Riduci la soglia o passa a Tutti/Video.',
    'No savings — kept original': 'Nessun risparmio — originale conservato',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      'Nessun video oltre %lld MB. Riduci la soglia o passa a Tutti/Foto.',
    'Not loaded yet. Delete is off until it shows.':
      'Non ancora caricata. Elimina è disattivato finché non compare.',
    'Original kept — both versions in your library':
      'Originale conservato — entrambe le versioni sono nella tua libreria',
    'Recommended: %@': 'Consigliato: %@',
    Sharpest: 'Più nitida',
    'Sizes unavailable': 'Dimensioni non disponibili',
    'Step 1 of 2 · Saving copy %lld of %lld':
      'Passaggio 1 di 2 · Salvataggio copia %lld di %lld',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      "Passaggio 2 di 2 · Conferma nell'avviso di iOS per eliminare gli originali",
    'Working…': 'Elaborazione…',
    'Your choice': 'La tua scelta',
    'Your library changed during analysis. Scan again for current results.':
      "La tua libreria è cambiata durante l'analisi. Ripeti l'analisi per ottenere risultati aggiornati.",
    'a new, smaller copy of each photo': 'una nuova copia più piccola di ogni foto',
    'a new, smaller copy of each video': 'una nuova copia più piccola di ogni video',
    'the Live Photos': 'le Live Photo',
    'the original photos': 'le foto originali',
    'the original videos': 'i video originali',
    'the still image of each Live Photo as a new photo':
      'la foto statica di ogni Live Photo come una nuova foto',
  },
};

// ---------------------------------------------------------------------------
// Guard rails
// ---------------------------------------------------------------------------

const wantedKeys = JSON.parse(readFileSync(join(HERE, '_batch12-keys.json'), 'utf8'));
const wantedSet = new Set(wantedKeys);

function die(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

if (wantedKeys.length !== 43) die(`_batch12-keys.json holds ${wantedKeys.length} keys, expected 43`);
if (wantedSet.size !== 43) die('_batch12-keys.json has duplicate keys');

mkdirSync(BACKUP_DIR, { recursive: true });

for (const lang of LANGS) {
  const table = TRANSLATIONS[lang];
  if (!table) die(`${lang}: no translation table`);

  const missing = wantedKeys.filter((key) => !(key in table));
  const extra = Object.keys(table).filter((key) => !wantedSet.has(key));
  if (missing.length) die(`${lang}: ${missing.length} untranslated key(s): ${JSON.stringify(missing)}`);
  if (extra.length) die(`${lang}: ${extra.length} key(s) not in the list: ${JSON.stringify(extra)}`);

  for (const key of wantedKeys) {
    const value = table[key];
    if (typeof value !== 'string' || value.trim() === '') die(`${lang}: "${key}" is empty`);
    if (value === key && !ALLOWED_IDENTICAL.has(key)) die(`${lang}: "${key}" was left in English`);
  }

  const path = join(HERE, `${lang}.json`);
  const file = JSON.parse(readFileSync(path, 'utf8'));

  const before = Object.keys(file.strings).length;
  if (before !== EXPECTED_BASELINE_STRINGS) {
    die(`${lang}: expected ${EXPECTED_BASELINE_STRINGS} existing strings, found ${before}`);
  }
  for (const key of wantedKeys) {
    if (key in file.strings) die(`${lang}: "${key}" already exists`);
  }
  if (!file.plurals || Object.keys(file.plurals).length === 0) die(`${lang}: plurals missing`);

  copyFileSync(path, join(BACKUP_DIR, `${lang}.json`));

  for (const key of wantedKeys) file.strings[key] = table[key];

  const strings = {};
  for (const key of Object.keys(file.strings).sort()) strings[key] = file.strings[key];
  file.strings = strings;

  const after = Object.keys(file.strings).length;
  if (after !== EXPECTED_FINAL_STRINGS) {
    die(`${lang}: expected ${EXPECTED_FINAL_STRINGS} strings after insert, found ${after}`);
  }

  writeFileSync(path, `${JSON.stringify(file, null, 2)}\n`);
  console.log(`${lang.padEnd(6)} ${before} -> ${after} strings  (plurals untouched: ${Object.keys(file.plurals).length})`);
}

console.log('\nbaseline copies in', BACKUP_DIR);
