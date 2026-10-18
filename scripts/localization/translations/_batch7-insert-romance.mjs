#!/usr/bin/env node
/**
 * Batch 7 — insert the 57 new English keys into es / fr / it / pt-BR.
 *
 * Reads each language file as raw text, regenerates only the `"strings"`
 * object (2-space indent, keys sorted the way the file already sorts them,
 * i.e. UTF-16 code-unit ascending) and re-attaches the `"plurals"` block
 * byte-for-byte so nothing outside `strings` is touched.
 *
 * Run: node scripts/localization/translations/_batch7-insert-romance.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const LANGS = ['es', 'fr', 'it', 'pt-BR']

/** The 57 keys, in the order the brief presents them. */
const KEYS = [
  // 1. Photo permission
  'TidyByte Needs Your Photos',
  "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.",
  'Photo Access Is On',
  'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.',
  'Photo Access Is Off',
  'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.',
  'Photo Access Is Restricted',
  'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.',
  'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.',
  'Allow Photo Access?',
  'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.',
  'Not Now',
  // 2. Compression errors
  'Photo not found.',
  "This item can't be compressed as a photo.",
  'Failed to load the photo.',
  'Photo size unknown (iCloud-only) — skipped.',
  'Video not found.',
  "Couldn't load the video (it may still be in iCloud). Please try again.",
  'Video size unknown (iCloud-only) — skipped.',
  'Failed to create export session.',
  'Exported file was empty.',
  'Failed to read file size.',
  'Cancelled.',
  'Unknown error',
  'Save failed: %@',
  'Export failed: %@',
  'Already compressed',
  'Size unknown (iCloud-only) — skipped',
  'Failed to re-encode the photo.',
  // 3. Local AI and search
  'Local AI is unavailable.',
  'This language is not supported by local AI.',
  'Local AI could not interpret this search.',
  'Use 300 characters or fewer.',
  'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.',
  'Some requested concepts were not found in this scan. Try a simpler content search.',
  'Searching labels across all scanned categories.',
  'Using label search across scanned photos.',
  'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.',
  // 4. Swipe review reasons
  'This photo may be out of focus.',
  'This photo has very low brightness.',
  'This photo has very high brightness.',
  'A lens smudge may have reduced image clarity.',
  'This photo received a low visual-quality score.',
  'Review whether you still need this screenshot.',
  'Review whether you still need this screen recording.',
  'This item uses %@; review whether you need it.',
  // 5. Appearance picker and widget
  'Light',
  'Dark',
  'Nothing to free on iPhone',
  'Up to %@ to free on iPhone',
  'Open TidyByte to refresh',
  'Updated %lldd ago',
  // 6. Empty-state fixes
  'No matching photos',
  'Submit a content search or try different words.',
  'No photos in this category.',
  'Choose albums or change your filters.',
  'No screen recordings were found.',
]

/** key -> { es, fr, it, 'pt-BR' } */
const T = {
  'TidyByte Needs Your Photos': {
    es: 'TidyByte necesita tus fotos',
    fr: 'TidyByte a besoin de vos photos',
    it: 'TidyByte ha bisogno delle tue foto',
    'pt-BR': 'O TidyByte precisa das suas fotos',
  },
  "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.":
    {
      es: 'TidyByte revisa tu fototeca en este dispositivo para encontrar lo que merece una limpieza. No se sube nada y nada cambia sin tu aprobación. iOS pedirá acceso a continuación.',
      fr: "TidyByte examine votre photothèque sur cet appareil pour trouver ce qui mérite d'être nettoyé. Rien n'est envoyé, et rien ne change sans votre accord. iOS demandera l'accès ensuite.",
      it: "TidyByte esamina la tua libreria su questo dispositivo per trovare ciò che vale la pena pulire. Nulla viene caricato e nulla cambia senza il tuo consenso. iOS chiederà l'accesso tra poco.",
      'pt-BR':
        'O TidyByte revisa sua biblioteca neste dispositivo para encontrar o que vale a pena limpar. Nada é enviado, e nada muda sem a sua autorização. O iOS pedirá acesso em seguida.',
    },
  'Photo Access Is On': {
    es: 'El acceso a las fotos está activado',
    fr: "L'accès aux photos est activé",
    it: "L'accesso a Foto è attivo",
    'pt-BR': 'O acesso às fotos está ativado',
  },
  'TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.':
    {
      es: 'TidyByte puede revisar tu fototeca en este dispositivo. No se sube nada y nada cambia sin tu aprobación.',
      fr: "TidyByte peut examiner votre photothèque sur cet appareil. Rien n'est envoyé, et rien ne change sans votre accord.",
      it: 'TidyByte può esaminare la tua libreria su questo dispositivo. Nulla viene caricato e nulla cambia senza il tuo consenso.',
      'pt-BR':
        'O TidyByte pode revisar sua biblioteca neste dispositivo. Nada é enviado, e nada muda sem a sua autorização.',
    },
  'Photo Access Is Off': {
    es: 'El acceso a las fotos está desactivado',
    fr: "L'accès aux photos est désactivé",
    it: "L'accesso a Foto è disattivato",
    'pt-BR': 'O acesso às fotos está desativado',
  },
  'iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.':
    {
      es: 'iOS está bloqueando el acceso de TidyByte a tu fototeca y no volverá a preguntar. Ajustes es la única forma de volver — activa allí el acceso a las fotos y todo volverá a funcionar aquí.',
      fr: "iOS bloque l'accès de TidyByte à votre photothèque et ne le demandera plus. Réglages est le seul moyen de revenir en arrière — activez-y l'accès aux photos et tout refonctionnera ici.",
      it: "iOS sta bloccando l'accesso di TidyByte alla tua libreria e non lo chiederà più. Impostazioni è l'unico modo per tornare indietro — attiva lì l'accesso a Foto e tutto qui ricomincerà a funzionare.",
      'pt-BR':
        'O iOS está bloqueando o acesso do TidyByte à sua biblioteca e não vai perguntar de novo. Ajustes é o único caminho de volta — ative o acesso às fotos lá e tudo aqui volta a funcionar.',
    },
  'Photo Access Is Restricted': {
    es: 'El acceso a las fotos está restringido',
    fr: "L'accès aux photos est restreint",
    it: "L'accesso a Foto è limitato",
    'pt-BR': 'O acesso às fotos está restrito',
  },
  'A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.':
    {
      es: 'Una restricción de Screen Time o de gestión del dispositivo está bloqueando el acceso a las fotos. El interruptor de Fotos en Ajustes no puede cambiarlo — primero hay que eliminar esa restricción.',
      fr: "Une restriction Screen Time ou de gestion de l'appareil bloque l'accès aux photos. Le réglage Photos dans Réglages ne peut pas le modifier — cette restriction doit d'abord être levée.",
      it: "Una restrizione di Screen Time o di gestione del dispositivo blocca l'accesso a Foto. L'interruttore Foto in Impostazioni non può cambiarlo — prima va rimossa quella restrizione.",
      'pt-BR':
        'Uma restrição de Screen Time ou de gerenciamento do dispositivo está bloqueando o acesso às fotos. O ajuste de Fotos em Ajustes não pode mudar isso — essa restrição precisa ser removida primeiro.',
    },
  'TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.':
    {
      es: 'TidyByte solo puede ver las fotos que seleccionaste. Añade más cuando quieras que revise el resto de tu fototeca.',
      fr: "TidyByte ne voit que les photos que vous avez sélectionnées. Ajoutez-en d'autres quand vous voulez qu'il examine le reste de votre photothèque.",
      it: 'TidyByte vede solo le foto che hai selezionato. Aggiungine altre quando vuoi che esamini il resto della libreria.',
      'pt-BR':
        'O TidyByte só vê as fotos que você selecionou. Adicione mais quando quiser que ele revise o resto da sua biblioteca.',
    },
  'Allow Photo Access?': {
    es: '¿Permitir acceso a las fotos?',
    fr: "Autoriser l'accès aux photos ?",
    it: "Consentire l'accesso a Foto?",
    'pt-BR': 'Permitir acesso às fotos?',
  },
  'iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.':
    {
      es: 'iOS pide acceso a las fotos solo una vez, y esta es esa petición. Después, TidyByte revisa tu fototeca en este dispositivo. No se sube nada y nada cambia sin tu revisión.',
      fr: "iOS ne demande l'accès aux photos qu'une seule fois, et c'est cette demande. TidyByte examine ensuite votre photothèque sur cet appareil. Rien n'est envoyé, et rien ne change sans votre examen.",
      it: "iOS chiede l'accesso a Foto una sola volta, e questa è quella richiesta. TidyByte esamina poi la tua libreria su questo dispositivo. Nulla viene caricato e nulla cambia senza la tua revisione.",
      'pt-BR':
        'O iOS pede acesso às fotos só uma vez, e este é esse pedido. Depois, o TidyByte revisa sua biblioteca neste dispositivo. Nada é enviado, e nada muda sem a sua revisão.',
    },
  'Not Now': {
    es: 'Ahora no',
    fr: 'Pas maintenant',
    it: 'Non ora',
    'pt-BR': 'Agora não',
  },

  'Photo not found.': {
    es: 'No se encontró la foto.',
    fr: 'Photo introuvable.',
    it: 'Foto non trovata.',
    'pt-BR': 'Foto não encontrada.',
  },
  "This item can't be compressed as a photo.": {
    es: 'Este elemento no se puede comprimir como foto.',
    fr: 'Cet élément ne peut pas être compressé comme photo.',
    it: 'Questo elemento non può essere compresso come foto.',
    'pt-BR': 'Este item não pode ser comprimido como foto.',
  },
  'Failed to load the photo.': {
    es: 'No se pudo cargar la foto.',
    fr: 'Impossible de charger la photo.',
    it: 'Impossibile caricare la foto.',
    'pt-BR': 'Falha ao carregar a foto.',
  },
  'Photo size unknown (iCloud-only) — skipped.': {
    es: 'Tamaño de la foto desconocido (solo en iCloud) — omitida.',
    fr: 'Taille de la photo inconnue (iCloud uniquement) — ignorée.',
    it: 'Dimensione della foto sconosciuta (solo iCloud) — saltata.',
    'pt-BR': 'Tamanho da foto desconhecido (apenas no iCloud) — ignorada.',
  },
  'Video not found.': {
    es: 'No se encontró el vídeo.',
    fr: 'Vidéo introuvable.',
    it: 'Video non trovato.',
    'pt-BR': 'Vídeo não encontrado.',
  },
  "Couldn't load the video (it may still be in iCloud). Please try again.": {
    es: 'No se pudo cargar el vídeo (puede que siga en iCloud). Inténtalo de nuevo.',
    fr: "Impossible de charger la vidéo (elle est peut-être encore dans iCloud). Réessayez.",
    it: 'Impossibile caricare il video (potrebbe essere ancora in iCloud). Riprova.',
    'pt-BR':
      'Não foi possível carregar o vídeo (ele pode ainda estar no iCloud). Tente novamente.',
  },
  'Video size unknown (iCloud-only) — skipped.': {
    es: 'Tamaño del vídeo desconocido (solo en iCloud) — omitido.',
    fr: 'Taille de la vidéo inconnue (iCloud uniquement) — ignorée.',
    it: 'Dimensione del video sconosciuta (solo iCloud) — saltato.',
    'pt-BR': 'Tamanho do vídeo desconhecido (apenas no iCloud) — ignorado.',
  },
  'Failed to create export session.': {
    es: 'No se pudo crear la sesión de exportación.',
    fr: "Impossible de créer la session d'exportation.",
    it: 'Impossibile creare la sessione di esportazione.',
    'pt-BR': 'Falha ao criar a sessão de exportação.',
  },
  'Exported file was empty.': {
    es: 'El archivo exportado estaba vacío.',
    fr: 'Le fichier exporté était vide.',
    it: 'Il file esportato era vuoto.',
    'pt-BR': 'O arquivo exportado estava vazio.',
  },
  'Failed to read file size.': {
    es: 'No se pudo leer el tamaño del archivo.',
    fr: 'Impossible de lire la taille du fichier.',
    it: 'Impossibile leggere la dimensione del file.',
    'pt-BR': 'Falha ao ler o tamanho do arquivo.',
  },
  'Cancelled.': {
    es: 'Cancelado.',
    fr: 'Annulé.',
    it: 'Annullato.',
    'pt-BR': 'Cancelado.',
  },
  'Unknown error': {
    es: 'Error desconocido',
    fr: 'Erreur inconnue',
    it: 'Errore sconosciuto',
    'pt-BR': 'Erro desconhecido',
  },
  'Save failed: %@': {
    es: 'Error al guardar: %@',
    fr: "Échec de l'enregistrement : %@",
    it: 'Salvataggio non riuscito: %@',
    'pt-BR': 'Falha ao salvar: %@',
  },
  'Export failed: %@': {
    es: 'Error al exportar: %@',
    fr: "Échec de l'exportation : %@",
    it: 'Esportazione non riuscita: %@',
    'pt-BR': 'Falha ao exportar: %@',
  },
  'Already compressed': {
    es: 'Ya comprimido',
    fr: 'Déjà compressé',
    it: 'Già compresso',
    'pt-BR': 'Já comprimido',
  },
  'Size unknown (iCloud-only) — skipped': {
    es: 'Tamaño desconocido (solo en iCloud) — omitido',
    fr: 'Taille inconnue (iCloud uniquement) — ignorée',
    it: 'Dimensione sconosciuta (solo iCloud) — saltato',
    'pt-BR': 'Tamanho desconhecido (apenas no iCloud) — ignorado',
  },
  'Failed to re-encode the photo.': {
    es: 'No se pudo volver a codificar la foto.',
    fr: 'Impossible de réencoder la photo.',
    it: 'Impossibile ricodificare la foto.',
    'pt-BR': 'Falha ao recodificar a foto.',
  },

  'Local AI is unavailable.': {
    es: 'La IA local no está disponible.',
    fr: "L'IA locale n'est pas disponible.",
    it: "L'IA locale non è disponibile.",
    'pt-BR': 'A IA local não está disponível.',
  },
  'This language is not supported by local AI.': {
    es: 'La IA local no admite este idioma.',
    fr: "Cette langue n'est pas prise en charge par l'IA locale.",
    it: "Questa lingua non è supportata dall'IA locale.",
    'pt-BR': 'Este idioma não é compatível com a IA local.',
  },
  'Local AI could not interpret this search.': {
    es: 'La IA local no pudo interpretar esta búsqueda.',
    fr: "L'IA locale n'a pas pu interpréter cette recherche.",
    it: "L'IA locale non ha potuto interpretare questa ricerca.",
    'pt-BR': 'A IA local não conseguiu interpretar esta busca.',
  },
  'Use 300 characters or fewer.': {
    es: 'Usa 300 caracteres o menos.',
    fr: 'Utilisez 300 caractères ou moins.',
    it: 'Usa 300 caratteri o meno.',
    'pt-BR': 'Use 300 caracteres ou menos.',
  },
  'Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.':
    {
      es: 'La búsqueda solo admite contenido visible, como perros en una playa. Las fechas, los lugares, los nombres y el texto no se indexan.',
      fr: 'La recherche ne prend en charge que le contenu visible, comme des chiens sur une plage. Les dates, les lieux, les noms et le texte ne sont pas indexés.',
      it: 'La ricerca supporta solo contenuti visibili, come cani su una spiaggia. Date, luoghi, nomi e testo non sono indicizzati.',
      'pt-BR':
        'A busca abrange apenas conteúdo visível, como cachorros em uma praia. Datas, lugares, nomes e texto não são indexados.',
    },
  'Some requested concepts were not found in this scan. Try a simpler content search.': {
    es: 'Algunos conceptos solicitados no se encontraron en este análisis. Prueba una búsqueda de contenido más sencilla.',
    fr: "Certains concepts demandés n'ont pas été trouvés lors de cette analyse. Essayez une recherche de contenu plus simple.",
    it: 'Alcuni concetti richiesti non sono stati trovati in questa analisi. Prova una ricerca di contenuti più semplice.',
    'pt-BR':
      'Alguns conceitos solicitados não foram encontrados nesta análise. Tente uma busca de conteúdo mais simples.',
  },
  'Searching labels across all scanned categories.': {
    es: 'Buscando etiquetas en todas las categorías analizadas.',
    fr: "Recherche d'étiquettes dans toutes les catégories analysées.",
    it: 'Ricerca di etichette in tutte le categorie analizzate.',
    'pt-BR': 'Buscando rótulos em todas as categorias analisadas.',
  },
  'Using label search across scanned photos.': {
    es: 'Usando la búsqueda por etiquetas en las fotos analizadas.',
    fr: 'Utilisation de la recherche par étiquettes sur les photos analysées.',
    it: 'Uso della ricerca per etichette nelle foto analizzate.',
    'pt-BR': 'Usando a busca por rótulos nas fotos analisadas.',
  },
  'These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.':
    {
      es: 'Estas palabras no forman una búsqueda por etiquetas compatible. Prueba con contenido visible como perro o playa. La búsqueda por etiquetas no admite fechas, nombres ni exclusiones.',
      fr: 'Ces mots ne forment pas une recherche par étiquettes prise en charge. Essayez un contenu visible comme chien ou plage. La recherche par étiquettes ne prend pas en charge les dates, les noms ni les exclusions.',
      it: 'Queste parole non formano una ricerca per etichette supportata. Prova contenuti visibili come cane o spiaggia. La ricerca per etichette non supporta date, nomi o esclusioni.',
      'pt-BR':
        'Estas palavras não formam uma busca por rótulos compatível. Tente conteúdo visível como cachorro ou praia. A busca por rótulos não é compatível com datas, nomes ou exclusões.',
    },

  'This photo may be out of focus.': {
    es: 'Es posible que esta foto esté desenfocada.',
    fr: 'Cette photo est peut-être floue.',
    it: 'Questa foto potrebbe essere fuori fuoco.',
    'pt-BR': 'Esta foto pode estar fora de foco.',
  },
  'This photo has very low brightness.': {
    es: 'Esta foto tiene una luminosidad muy baja.',
    fr: 'Cette photo a une luminosité très faible.',
    it: 'Questa foto ha una luminosità molto bassa.',
    'pt-BR': 'Esta foto tem brilho muito baixo.',
  },
  'This photo has very high brightness.': {
    es: 'Esta foto tiene una luminosidad muy alta.',
    fr: 'Cette photo a une luminosité très élevée.',
    it: 'Questa foto ha una luminosità molto alta.',
    'pt-BR': 'Esta foto tem brilho muito alto.',
  },
  'A lens smudge may have reduced image clarity.': {
    es: 'Puede que una mancha en la lente haya reducido la nitidez de la imagen.',
    fr: "Une trace sur l'objectif a peut-être réduit la netteté de l'image.",
    it: "Un'impronta sull'obiettivo potrebbe aver ridotto la nitidezza dell'immagine.",
    'pt-BR': 'Uma mancha na lente pode ter reduzido a nitidez da imagem.',
  },
  'This photo received a low visual-quality score.': {
    es: 'Esta foto recibió una puntuación baja de calidad visual.',
    fr: 'Cette photo a reçu un faible score de qualité visuelle.',
    it: 'Questa foto ha ricevuto un punteggio basso di qualità visiva.',
    'pt-BR': 'Esta foto recebeu uma pontuação baixa de qualidade visual.',
  },
  'Review whether you still need this screenshot.': {
    es: 'Revisa si todavía necesitas esta captura de pantalla.',
    fr: "Vérifiez si vous avez encore besoin de cette capture d'écran.",
    it: 'Verifica se ti serve ancora questa istantanea.',
    'pt-BR': 'Veja se você ainda precisa desta captura de tela.',
  },
  'Review whether you still need this screen recording.': {
    es: 'Revisa si todavía necesitas esta grabación de pantalla.',
    fr: "Vérifiez si vous avez encore besoin de cet enregistrement d'écran.",
    it: 'Verifica se ti serve ancora questa registrazione schermo.',
    'pt-BR': 'Veja se você ainda precisa desta gravação de tela.',
  },
  'This item uses %@; review whether you need it.': {
    es: 'Este elemento ocupa %@; revisa si lo necesitas.',
    fr: 'Cet élément occupe %@ ; vérifiez si vous en avez besoin.',
    it: 'Questo elemento occupa %@; verifica se ti serve.',
    'pt-BR': 'Este item ocupa %@; veja se você precisa dele.',
  },

  Light: {
    es: 'Claro',
    fr: 'Clair',
    it: 'Chiaro',
    'pt-BR': 'Claro',
  },
  Dark: {
    es: 'Oscuro',
    fr: 'Sombre',
    it: 'Scuro',
    'pt-BR': 'Escuro',
  },
  'Nothing to free on iPhone': {
    es: 'Nada que liberar en el iPhone',
    fr: "Rien à libérer sur l'iPhone",
    it: 'Niente da liberare su iPhone',
    'pt-BR': 'Nada para liberar no iPhone',
  },
  'Up to %@ to free on iPhone': {
    es: 'Hasta %@ que puedes liberar en el iPhone',
    fr: "Jusqu'à %@ à libérer sur l'iPhone",
    it: 'Fino a %@ da liberare su iPhone',
    'pt-BR': 'Até %@ para liberar no iPhone',
  },
  'Open TidyByte to refresh': {
    es: 'Abre TidyByte para actualizar',
    fr: 'Ouvrez TidyByte pour actualiser',
    it: 'Apri TidyByte per aggiornare',
    'pt-BR': 'Abra o TidyByte para atualizar',
  },
  'Updated %lldd ago': {
    es: 'Actualizado hace %lld d',
    fr: 'Mis à jour il y a %lld j',
    it: 'Aggiornato %lld g fa',
    'pt-BR': 'Atualizado há %lld d',
  },

  'No matching photos': {
    es: 'No hay fotos coincidentes',
    fr: 'Aucune photo correspondante',
    it: 'Nessuna foto corrispondente',
    'pt-BR': 'Nenhuma foto correspondente',
  },
  'Submit a content search or try different words.': {
    es: 'Haz una búsqueda de contenido o prueba otras palabras.',
    fr: "Lancez une recherche de contenu ou essayez d'autres mots.",
    it: 'Avvia una ricerca di contenuti o prova altre parole.',
    'pt-BR': 'Faça uma busca de conteúdo ou tente outras palavras.',
  },
  'No photos in this category.': {
    es: 'No hay fotos en esta categoría.',
    fr: 'Aucune photo dans cette catégorie.',
    it: 'Nessuna foto in questa categoria.',
    'pt-BR': 'Nenhuma foto nesta categoria.',
  },
  'Choose albums or change your filters.': {
    es: 'Elige álbumes o cambia tus filtros.',
    fr: 'Choisissez des albums ou modifiez vos filtres.',
    it: 'Scegli gli album o cambia i filtri.',
    'pt-BR': 'Escolha álbuns ou mude seus filtros.',
  },
  'No screen recordings were found.': {
    es: 'No se encontraron grabaciones de pantalla.',
    fr: "Aucun enregistrement d'écran n'a été trouvé.",
    it: 'Nessuna registrazione schermo trovata.',
    'pt-BR': 'Nenhuma gravação de tela foi encontrada.',
  },
}

/** Keys the file already sorts by: UTF-16 code-unit ascending. */
const byCodeUnit = (a, b) => (a < b ? -1 : a > b ? 1 : 0)

/** Everything up to and including the line that opens `"plurals"`. */
const PLURALS_MARKER = '\n  "plurals": {'

/**
 * Preflight: the hand-typed key list must equal the set derived from the brief
 * plus the extractor output, so a typo in a key aborts before anything is
 * written. See `_batch7-verify-romance.mjs` for the same derivation.
 *
 * The 57th key is named explicitly. The brief lists 56 (51 in its tables plus 5
 * empty states); the extractor output the brief was written from had exactly
 * one further new non-plural key, the compression error below, which is what
 * makes 57. The 46 remaining new keys are all in `_plural-keys.json` and belong
 * to the plural batch, so they are excluded here.
 */
const FIFTY_SEVENTH = 'Failed to re-encode the photo.'

function expectedKeys (existingStrings) {
  const root = join(here, '..', '..', '..')
  const brief = readFileSync(join(here, '_batch7-brief.md'), 'utf8')
  const found = JSON.parse(
    readFileSync(join(root, 'scripts/localization/strings.found.json'), 'utf8')
  )
  const pluralKeyList = Object.keys(
    JSON.parse(readFileSync(join(here, '_plural-keys.json'), 'utf8'))
  )
  const emptyStateKeys = [
    'No matching photos',
    'Submit a content search or try different words.',
    'No photos in this category.',
    'Choose albums or change your filters.',
    'No screen recordings were found.',
  ]
  const newKeys = [...new Set(found.keys.map((entry) => entry.key))].filter(
    (key) => !(key in existingStrings) && !pluralKeyList.includes(key)
  )
  return [
    ...newKeys.filter((key) => brief.includes(`\`${key}\``)),
    ...emptyStateKeys,
    FIFTY_SEVENTH,
  ]
}

function serializeStrings (strings) {
  const lines = Object.keys(strings)
    .sort(byCodeUnit)
    .map((k) => `    ${JSON.stringify(k)}: ${JSON.stringify(strings[k])}`)
  return `{\n  "strings": {\n${lines.join(',\n')}\n  },\n`
}

function main () {
  if (KEYS.length !== 57) throw new Error(`expected 57 keys, got ${KEYS.length}`)
  const dupes = KEYS.filter((k, i) => KEYS.indexOf(k) !== i)
  if (dupes.length) throw new Error(`duplicate keys in table: ${JSON.stringify(dupes)}`)

  // Preflight against the first language file's current contents.
  const firstRaw = readFileSync(join(here, `${LANGS[0]}.json`), 'utf8')
  const want = expectedKeys(JSON.parse(firstRaw).strings)
  const missingFromTable = want.filter((key) => !KEYS.includes(key))
  const extraInTable = KEYS.filter((key) => !want.includes(key))
  if (missingFromTable.length || extraInTable.length || want.length !== 57) {
    throw new Error(
      `key list does not match the brief/extractor:\n` +
        `  expected ${want.length}, table has ${KEYS.length}\n` +
        `  missing from table: ${JSON.stringify(missingFromTable)}\n` +
        `  extra in table: ${JSON.stringify(extraInTable)}`
    )
  }

  for (const lang of LANGS) {
    const path = join(here, `${lang}.json`)
    const raw = readFileSync(path, 'utf8')

    const cut = raw.indexOf(PLURALS_MARKER)
    if (cut < 0) throw new Error(`${lang}: no "plurals" marker found`)
    const tail = raw.slice(cut + 1) // starts at `  "plurals": {`
    const parsed = JSON.parse(raw)
    const before = parsed.strings // for the counts and the guard below

    const strings = { ...parsed.strings }
    let added = 0
    for (const key of KEYS) {
      const value = T[key]?.[lang]
      if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${lang}: missing translation for ${JSON.stringify(key)}`)
      }
      if (key in strings) throw new Error(`${lang}: key already present: ${JSON.stringify(key)}`)
      strings[key] = value
      added += 1
    }
    if (added !== 57) throw new Error(`${lang}: added ${added}, expected 57`)

    const head = serializeStrings(strings)
    const out = head + tail
    JSON.parse(out) // fail before writing anything unparseable
    writeFileSync(path, out)
    console.log(
      `${lang}: ${Object.keys(before).length} -> ${Object.keys(strings).length} strings, ` +
        `plurals untouched (${Object.keys(parsed.plurals).length})`
    )
  }
}

main()
