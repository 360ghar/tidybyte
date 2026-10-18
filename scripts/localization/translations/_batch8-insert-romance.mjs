#!/usr/bin/env node
/**
 * Batch 8 — insert the 93 new English keys into es / fr / it / pt-BR.
 *
 * 80 plain keys go into `"strings"` (key = the exact English text).
 * 13 counted keys go into `"plurals"` (key = the English singular, value =
 * `{ one, other }`).
 *
 * Regenerates both blocks from the parsed JSON with the file's existing
 * formatting (2-space indent, 4-space inside a block, trailing newline) and the
 * existing orders: `strings` stays UTF-16 code-unit ascending, `plurals` keeps
 * its current order with the 13 new keys appended in `_plural-keys.json` order.
 *
 * Stat-line plurals: `cleared %lld photo` and friends are only ever rendered
 * inside `L10n.format("I just %@", …)` (share text) and
 * `L10n.format("You just %@.", …)` (rating prompt) — never standalone. So the
 * Spanish/French/pt-BR forms are infinitives that complete "Acabo de ___" /
 * "Je viens de ___" / "Acabei de ___", and the Italian forms are past
 * participles that complete "Ho appena ___" / "Hai appena ___". The two wrapper
 * keys in this batch are translated to match.
 *
 * Run: node scripts/localization/translations/_batch8-insert-romance.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const LANGS = ['es', 'fr', 'it', 'pt-BR']

const byCodeUnit = (a, b) => (a < b ? -1 : a > b ? 1 : 0)

/** key -> { es, fr, it, 'pt-BR' } — the 80 plain keys. */
const PLAIN = {
  // ---------------------------------------------------------------- swipe home
  'Worst Shots': {
    es: 'Peores fotos',
    fr: 'Pires photos',
    it: 'Scatti peggiori',
    'pt-BR': 'Piores fotos',
  },
  'Review low-scoring photos, lowest first': {
    es: 'Revisa las fotos con puntuación más baja, de menor a mayor',
    fr: 'Examinez les photos les moins bien notées, en partant des plus basses',
    it: 'Esamina le foto con il punteggio più basso, partendo dalle peggiori',
    'pt-BR': 'Revise as fotos com a pontuação mais baixa, das menores primeiro',
  },
  "Photos you haven't reviewed yet": {
    es: 'Fotos que aún no has revisado',
    fr: "Photos que vous n'avez pas encore examinées",
    it: 'Foto che non hai ancora esaminato',
    'pt-BR': 'Fotos que você ainda não revisou',
  },
  'Every photo and video in your library': {
    es: 'Todas las fotos y los vídeos de tu fototeca',
    fr: 'Toutes les photos et vidéos de votre photothèque',
    it: 'Tutte le foto e i video nella tua libreria',
    'pt-BR': 'Todas as fotos e os vídeos da sua biblioteca',
  },
  'Review photos and videos taken on or before a date': {
    es: 'Revisa las fotos y los vídeos tomados en una fecha o antes',
    fr: 'Examinez les photos et vidéos pris à une date ou avant',
    it: 'Esamina foto e video scattati a una data o prima',
    'pt-BR': 'Revise as fotos e os vídeos tirados em uma data ou antes',
  },
  'Photos not organized into your albums': {
    es: 'Fotos que no están organizadas en tus álbumes',
    fr: 'Photos non classées dans vos albums',
    it: 'Foto non organizzate nei tuoi album',
    'pt-BR': 'Fotos que não estão organizadas nos seus álbuns',
  },
  'Specific Album': {
    es: 'Álbum específico',
    fr: 'Album spécifique',
    it: 'Album specifico',
    'pt-BR': 'Álbum específico',
  },
  'Review photos from a specific album': {
    es: 'Revisa las fotos de un álbum específico',
    fr: "Examinez les photos d'un album spécifique",
    it: 'Esamina le foto di un album specifico',
    'pt-BR': 'Revise as fotos de um álbum específico',
  },

  // ------------------------------------------------------- swipe session copy
  'Marked for deletion. Nothing is deleted until you confirm at the end.': {
    es: 'Marcado para eliminación. No se elimina nada hasta que lo confirmes al final.',
    fr: "Marqué pour suppression. Rien n'est supprimé tant que vous ne confirmez pas à la fin.",
    it: "Contrassegnato per l'eliminazione. Nulla viene eliminato finché non confermi alla fine.",
    'pt-BR': 'Marcado para exclusão. Nada é apagado até você confirmar no final.',
  },
  'Delete is off until the photo loads.': {
    es: 'La eliminación está desactivada hasta que se cargue la foto.',
    fr: "La suppression est désactivée jusqu'au chargement de la photo.",
    it: "L'eliminazione è disattivata finché la foto non viene caricata.",
    'pt-BR': 'Apagar fica desativado até a foto carregar.',
  },
  'Pinch or double-tap a photo to inspect it': {
    es: 'Pellizca o toca dos veces una foto para inspeccionarla',
    fr: "Pincez ou touchez deux fois une photo pour l'inspecter",
    it: 'Pizzica o tocca due volte una foto per esaminarla',
    'pt-BR': 'Faça o gesto de pinça ou toque duas vezes em uma foto para inspecioná-la',
  },
  "That photo can't be undone anymore.": {
    es: 'Ya no puedes deshacer esa foto.',
    fr: 'Vous ne pouvez plus annuler cette photo.',
    it: 'Non puoi più annullare quella foto.',
    'pt-BR': 'Você não pode mais desfazer essa foto.',
  },
  'Undo your newer actions first to reach that photo.': {
    es: 'Deshaz primero las acciones más recientes para llegar a esa foto.',
    fr: "Annulez d'abord vos actions les plus récentes pour atteindre cette photo.",
    it: 'Annulla prima le azioni più recenti per raggiungere quella foto.',
    'pt-BR': 'Desfaça primeiro as ações mais recentes para chegar a essa foto.',
  },
  'Your library changed during analysis. Try Worst Shots again.': {
    es: 'Tu fototeca cambió durante el análisis. Prueba Peores fotos de nuevo.',
    fr: "Votre photothèque a changé pendant l'analyse. Réessayez Pires photos.",
    it: "La tua libreria è cambiata durante l'analisi. Riprova Scatti peggiori.",
    'pt-BR': 'Sua biblioteca mudou durante a análise. Tente Piores fotos de novo.',
  },
  'No photo is waiting to be filed. Dismiss and try again.': {
    es: 'No hay ninguna foto pendiente de archivar. Cierra y vuelve a intentarlo.',
    fr: "Aucune photo n'attend d'être classée. Fermez et réessayez.",
    it: "Nessuna foto è in attesa di archiviazione. Chiudi e riprova.",
    'pt-BR': 'Nenhuma foto está aguardando para ser arquivada. Feche e tente novamente.',
  },
  'Still adding — please wait a moment and try again.': {
    es: 'Aún añadiendo — espera un momento e inténtalo de nuevo.',
    fr: 'Ajout en cours — patientez un instant et réessayez.',
    it: 'Aggiunta in corso — attendi un momento e riprova.',
    'pt-BR': 'Ainda adicionando — aguarde um momento e tente novamente.',
  },
  "Couldn't save your changes. Please try again.": {
    es: 'No se pudieron guardar los cambios. Inténtalo de nuevo.',
    fr: "Impossible d'enregistrer vos modifications. Réessayez.",
    it: 'Impossibile salvare le modifiche. Riprova.',
    'pt-BR': 'Não foi possível salvar as alterações. Tente novamente.',
  },

  // --------------------------------------------------------- session result rows
  'Added to albums': {
    es: 'Añadidos a álbumes',
    fr: 'Ajoutés aux albums',
    it: 'Aggiunti ad album',
    'pt-BR': 'Adicionados a álbuns',
  },
  'Moved to Recently Deleted': {
    es: 'Movidos a Recientemente eliminados',
    fr: 'Déplacés vers Récemment supprimés',
    it: 'Spostati in Eliminati di recente',
    'pt-BR': 'Movidos para Excluídos recentemente',
  },
  'Kept': {
    es: 'Conservadas',
    fr: 'Gardées',
    it: 'Conservate',
    'pt-BR': 'Mantidas',
  },
  'Skipped': {
    es: 'Omitidas',
    fr: 'Ignorées',
    it: 'Saltate',
    'pt-BR': 'Puladas',
  },
  'Deleted': {
    es: 'Eliminados',
    fr: 'Supprimés',
    it: 'Eliminati',
    'pt-BR': 'Apagados',
  },

  // ------------------------------------------------------ burst keeper reasons
  'Kept: your choice': {
    es: 'Conservada: tu elección',
    fr: 'Gardée : votre choix',
    it: 'Conservata: la tua scelta',
    'pt-BR': 'Mantida: sua escolha',
  },
  'Kept: your pick in Photos': {
    es: 'Conservada: tu elección en Fotos',
    fr: 'Gardée : votre choix dans Photos',
    it: 'Conservata: la tua scelta in Foto',
    'pt-BR': 'Mantida: sua escolha no Fotos',
  },
  "Kept: iPhone's pick": {
    es: "Conservada: elección del iPhone",
    fr: "Gardée : choix de l'iPhone",
    it: "Conservata: scelta dell'iPhone",
    'pt-BR': 'Mantida: escolha do iPhone',
  },
  'Kept: favorite': {
    es: 'Conservada: favorita',
    fr: 'Gardée : favorite',
    it: 'Conservata: preferita',
    'pt-BR': 'Mantida: favorita',
  },
  'Kept: highest resolution': {
    es: 'Conservada: mayor resolución',
    fr: 'Gardée : résolution maximale',
    it: 'Conservata: risoluzione massima',
    'pt-BR': 'Mantida: maior resolução',
  },
  'Kept: last frame': {
    es: 'Conservada: último fotograma',
    fr: 'Gardée : dernière image',
    it: 'Conservata: ultimo fotogramma',
    'pt-BR': 'Mantida: último quadro',
  },
  'Kept: auto pick': {
    es: 'Conservada: elección automática',
    fr: 'Gardée : choix auto',
    it: 'Conservata: scelta automatica',
    'pt-BR': 'Mantida: escolha automática',
  },
  // The leading space is load-bearing: this sentence is appended to the one
  // before it, and the catalog joins them without adding a space.
  ' Favorites are kept.': {
    es: ' Los favoritos se conservan.',
    fr: ' Les favoris sont conservés.',
    it: ' I preferiti vengono conservati.',
    'pt-BR': ' Os favoritos são mantidos.',
  },
  'This keeps the starred frame of each burst and deletes the rest.': {
    es: 'Esto conserva el fotograma con estrella de cada ráfaga y elimina el resto.',
    fr: "Cela conserve l'image avec étoile de chaque rafale et supprime le reste.",
    it: 'Questa opzione mantiene il fotogramma con la stella di ogni raffica ed elimina il resto.',
    'pt-BR': 'Isso mantém o quadro com estrela de cada rajada e apaga o resto.',
  },

  // --------------------------------------------------------- burst cleaner result
  '1 burst cleaned down to a single photo.': {
    es: '1 ráfaga reducida a una sola foto.',
    fr: '1 rafale réduite à une seule photo.',
    it: '1 raffica ridotta a una sola foto.',
    'pt-BR': '1 rajada reduzida a uma única foto.',
  },
  '%lld bursts cleaned down to single photos.': {
    es: '%lld ráfagas reducidas a una sola foto.',
    fr: '%lld rafales réduites à une seule photo.',
    it: '%lld raffiche ridotte a una sola foto.',
    'pt-BR': '%lld rajadas reduzidas a uma única foto.',
  },

  // --------------------------------------------------------------------- errors
  'Album not found.': {
    es: 'No se encontró el álbum.',
    fr: 'Album introuvable.',
    it: 'Album non trovato.',
    'pt-BR': 'Álbum não encontrado.',
  },
  'Failed to create album.': {
    es: 'No se pudo crear el álbum.',
    fr: "Impossible de créer l'album.",
    it: "Impossibile creare l'album.",
    'pt-BR': 'Não foi possível criar o álbum.',
  },
  "Couldn't modify the album. Please try again.": {
    es: 'No se pudo modificar el álbum. Inténtalo de nuevo.',
    fr: "Impossible de modifier l'album. Réessayez.",
    it: "Impossibile modificare l'album. Riprova.",
    'pt-BR': 'Não foi possível modificar o álbum. Tente novamente.',
  },
  'Nothing was deleted.': {
    es: 'No se eliminó nada.',
    fr: "Rien n'a été supprimé.",
    it: 'Non è stato eliminato nulla.',
    'pt-BR': 'Nada foi apagado.',
  },
  'Live Photo not found.': {
    es: 'No se encontró la Live Photo.',
    fr: 'Live Photo introuvable.',
    it: 'Live Photo non trovata.',
    'pt-BR': 'Live Photo não encontrada.',
  },
  'Could not find still image in Live Photo.': {
    es: 'No se encontró la foto fija en la Live Photo.',
    fr: 'Impossible de trouver la photo fixe dans la Live Photo.',
    it: 'Impossibile trovare la foto statica nella Live Photo.',
    'pt-BR': 'Não foi possível encontrar a foto estática na Live Photo.',
  },
  'Invalid image data.': {
    es: 'Datos de imagen no válidos.',
    fr: "Données d'image non valides.",
    it: 'Dati immagine non validi.',
    'pt-BR': 'Dados de imagem inválidos.',
  },
  'Timed out loading the photo (it may still be in iCloud). Please try again.': {
    es: 'Se agotó el tiempo al cargar la foto (puede que siga en iCloud). Inténtalo de nuevo.',
    fr: "Délai dépassé lors du chargement de la photo (elle est peut-être encore dans iCloud). Réessayez.",
    it: 'Tempo scaduto durante il caricamento della foto (potrebbe essere ancora in iCloud). Riprova.',
    'pt-BR': 'O tempo esgotou ao carregar a foto (ela pode ainda estar no iCloud). Tente novamente.',
  },
  'The compressed copy is missing from your library.': {
    es: 'La copia comprimida no está en tu fototeca.',
    fr: 'La copie compressée est absente de votre photothèque.',
    it: 'La copia compressa non è nella tua libreria.',
    'pt-BR': 'A cópia comprimida não está na sua biblioteca.',
  },
  'The converted still is missing from your library.': {
    es: 'La foto fija convertida no está en tu fototeca.',
    fr: 'La photo fixe convertie est absente de votre photothèque.',
    it: 'La foto statica convertita non è nella tua libreria.',
    'pt-BR': 'A foto estática convertida não está na sua biblioteca.',
  },
  'Copies kept. Both versions are in your library; delete either one in Photos.': {
    es: 'Copias conservadas. Ambas versiones están en tu fototeca; elimina la que quieras en Fotos.',
    fr: 'Copies conservées. Les deux versions sont dans votre photothèque ; supprimez celle que vous voulez dans Photos.',
    it: 'Copie conservate. Entrambe le versioni sono nella tua libreria; elimina quella che preferisci in Foto.',
    'pt-BR': 'Cópias mantidas. As duas versões estão na sua biblioteca; apague qualquer uma no Fotos.',
  },
  "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.": {
    es: 'Se eliminaron %lld de %lld elementos. No se pudieron eliminar %lld. Inténtalo de nuevo.',
    fr: "%lld éléments sur %lld supprimés. %lld n'ont pas pu être supprimés. Réessayez.",
    it: 'Eliminati %lld elementi su %lld. Impossibile eliminare %lld. Riprova.',
    'pt-BR': 'Apagados %lld de %lld itens. Não foi possível apagar %lld. Tente novamente.',
  },
  'Your library changed. Scan again before searching.': {
    es: 'Tu fototeca cambió. Vuelve a analizar antes de buscar.',
    fr: "Votre photothèque a changé. Relancez l'analyse avant de rechercher.",
    it: "La tua libreria è cambiata. Ripeti l'analisi prima di cercare.",
    'pt-BR': 'Sua biblioteca mudou. Analise de novo antes de buscar.',
  },
  'Removed changed or unavailable photos. Scan again to include new or edited photos.': {
    es: 'Se quitaron las fotos modificadas o no disponibles. Vuelve a analizar para incluir fotos nuevas o editadas.',
    fr: "Les photos modifiées ou indisponibles ont été retirées. Relancez l'analyse pour inclure les photos nouvelles ou modifiées.",
    it: "Le foto modificate o non disponibili sono state rimosse. Ripeti l'analisi per includere foto nuove o modificate.",
    'pt-BR': 'As fotos alteradas ou indisponíveis foram removidas. Analise de novo para incluir fotos novas ou editadas.',
  },

  // ------------------------------------------- storage dashboard and permission
  'Recently Deleted': {
    es: 'Recientemente eliminados',
    fr: 'Récemment supprimés',
    it: 'Eliminati di recente',
    'pt-BR': 'Excluídos recentemente',
  },
  'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.': {
    es: 'El espacio se recupera cuando se vacíe. En Fotos, abre Álbumes y luego Recientemente eliminados.',
    fr: "L'espace est récupéré quand il est vidé. Dans Photos, ouvrez Albums, puis Récemment supprimés.",
    it: 'Lo spazio torna quando viene svuotato. In Foto, apri Album, poi Eliminati di recente.',
    'pt-BR': 'O espaço volta quando ele for esvaziado. No Fotos, abra Álbuns e depois Excluídos recentemente.',
  },
  'Manage Apps & System Storage': {
    es: 'Gestionar apps y almacenamiento del sistema',
    fr: 'Gérer les apps et le stockage système',
    it: 'Gestisci app e archiviazione di sistema',
    'pt-BR': 'Gerenciar apps e armazenamento do sistema',
  },
  'Open Settings ▸ General ▸ iPhone Storage': {
    es: 'Abre Ajustes ▸ General ▸ Almacenamiento del iPhone',
    fr: 'Ouvrez Réglages ▸ Général ▸ Stockage iPhone',
    it: 'Apri Impostazioni ▸ Generali ▸ Spazio iPhone',
    'pt-BR': 'Abra Ajustes ▸ Geral ▸ Armazenamento do iPhone',
  },
  'Library figures below cover only the photos you selected; device totals cover the whole device.': {
    es: 'Las cifras de la fototeca de abajo solo incluyen las fotos que seleccionaste; los totales del dispositivo abarcan todo el dispositivo.',
    fr: "Les chiffres de la photothèque ci-dessous ne couvrent que les photos que vous avez sélectionnées ; les totaux de l'appareil couvrent tout l'appareil.",
    it: "I dati della libreria qui sotto coprono solo le foto che hai selezionato; i totali del dispositivo coprono l'intero dispositivo.",
    'pt-BR': 'Os números da biblioteca abaixo cobrem apenas as fotos que você selecionou; os totais do dispositivo cobrem o dispositivo inteiro.',
  },
  'Find exact and near-duplicate photos': {
    es: 'Encuentra fotos duplicadas exactas y casi idénticas',
    fr: 'Trouvez les doublons exacts et quasi identiques',
    it: 'Trova foto duplicate esatte e quasi identiche',
    'pt-BR': 'Encontre fotos duplicadas exatas e quase idênticas',
  },
  'Spot blurry, dark, and overexposed shots': {
    es: 'Detecta fotos borrosas, oscuras y sobreexpuestas',
    fr: 'Repérez les photos floues, sombres et surexposées',
    it: 'Individua scatti sfocati, scuri e sovraesposti',
    'pt-BR': 'Identifique fotos desfocadas, escuras e superexpostas',
  },
  'Surface the biggest files taking up space': {
    es: 'Muestra los archivos más grandes que ocupan espacio',
    fr: 'Faites ressortir les fichiers les plus volumineux qui prennent de la place',
    it: 'Metti in evidenza i file più grandi che occupano spazio',
    'pt-BR': 'Mostre os maiores arquivos que ocupam espaço',
  },
  'Delete only what you review and approve': {
    es: 'Elimina solo lo que revises y apruebes',
    fr: 'Ne supprimez que ce que vous examinez et approuvez',
    it: 'Elimina solo ciò che esamini e approvi',
    'pt-BR': 'Apague só o que você revisar e aprovar',
  },

  // -------------------------------------------------------- activity and savings
  'items, all time': {
    es: 'elementos, en total',
    fr: 'éléments, au total',
    it: 'elementi, in totale',
    'pt-BR': 'itens, no total',
  },
  'this month': {
    es: 'este mes',
    fr: 'ce mois-ci',
    it: 'questo mese',
    'pt-BR': 'este mês',
  },
  'Size unknown': {
    es: 'Tamaño desconocido',
    fr: 'Taille inconnue',
    it: 'Dimensione sconosciuta',
    'pt-BR': 'Tamanho desconhecido',
  },
  'Size unavailable': {
    es: 'Tamaño no disponible',
    fr: 'Taille indisponible',
    it: 'Dimensione non disponibile',
    'pt-BR': 'Tamanho indisponível',
  },
  'cleaned up since you started using TidyByte': {
    es: 'liberados desde que empezaste a usar TidyByte',
    fr: 'libérés depuis que vous utilisez TidyByte',
    it: 'liberati da quando usi TidyByte',
    'pt-BR': 'liberados desde que você começou a usar o TidyByte',
  },
  "Nothing measurable yet. Items stored only in iCloud don't report a size.": {
    es: 'Aún no hay nada medible. Los elementos guardados solo en iCloud no indican su tamaño.',
    fr: "Rien de mesurable pour l'instant. Les éléments stockés uniquement dans iCloud n'indiquent pas de taille.",
    it: 'Ancora niente di misurabile. Gli elementi solo in iCloud non indicano una dimensione.',
    'pt-BR': 'Nada mensurável ainda. Itens armazenados apenas no iCloud não informam um tamanho.',
  },

  // ------------------------------------------------------- rate prompt and feedback
  'Enjoying TidyByte?': {
    es: '¿Te gusta TidyByte?',
    fr: 'Vous aimez TidyByte ?',
    it: 'Ti piace TidyByte?',
    'pt-BR': 'Está gostando do TidyByte?',
  },
  'Thanks for the support': {
    es: 'Gracias por el apoyo',
    fr: 'Merci pour votre soutien',
    it: 'Grazie per il supporto',
    'pt-BR': 'Obrigado pelo apoio',
  },
  'What should we fix?': {
    es: '¿Qué deberíamos mejorar?',
    fr: 'Que devrions-nous corriger ?',
    it: 'Cosa dovremmo sistemare?',
    'pt-BR': 'O que devemos corrigir?',
  },
  'Tell us what got in the way.': {
    es: 'Cuéntanos qué te lo impidió.',
    fr: 'Dites-nous ce qui vous a gêné.',
    it: 'Dicci cosa ti ha bloccato.',
    'pt-BR': 'Conte o que atrapalhou.',
  },
  'Send Feedback': {
    es: 'Enviar comentarios',
    fr: 'Envoyer des commentaires',
    it: 'Invia feedback',
    'pt-BR': 'Enviar feedback',
  },
  'Yes': {
    es: 'Sí',
    fr: 'Oui',
    it: 'Sì',
    'pt-BR': 'Sim',
  },
  'Not really': {
    es: 'No mucho',
    fr: 'Pas vraiment',
    it: 'Non proprio',
    'pt-BR': 'Nem tanto',
  },
  'Not now': {
    es: 'Ahora no',
    fr: 'Pas maintenant',
    it: 'Non ora',
    'pt-BR': 'Agora não',
  },
  'Your rating helps other people find TidyByte.': {
    es: 'Tu valoración ayuda a que otras personas encuentren TidyByte.',
    fr: "Votre note aide d'autres personnes à trouver TidyByte.",
    it: 'La tua valutazione aiuta altre persone a trovare TidyByte.',
    'pt-BR': 'Sua avaliação ajuda outras pessoas a encontrar o TidyByte.',
  },
  'You just %@.': {
    es: 'Acabas de %@.',
    fr: 'Vous venez de %@.',
    it: 'Hai appena %@.',
    'pt-BR': 'Você acabou de %@.',
  },
  "The message couldn't be sent. Try again, or email us at %@.": {
    es: 'No se pudo enviar el mensaje. Inténtalo de nuevo o escríbenos a %@.',
    fr: "Le message n'a pas pu être envoyé. Réessayez ou écrivez-nous à %@.",
    it: 'Impossibile inviare il messaggio. Riprova o scrivici a %@.',
    'pt-BR': 'Não foi possível enviar a mensagem. Tente novamente ou envie um e-mail para %@.',
  },
  'No mail account is set up on this device. Email us at %@.': {
    es: 'No hay ninguna cuenta de correo configurada en este dispositivo. Escríbenos a %@.',
    fr: "Aucun compte de messagerie n'est configuré sur cet appareil. Écrivez-nous à %@.",
    it: 'Nessun account di posta è configurato su questo dispositivo. Scrivici a %@.',
    'pt-BR': 'Nenhuma conta de e-mail está configurada neste dispositivo. Envie um e-mail para %@.',
  },

  // ----------------------------------------------------------------- share text
  'I just %@': {
    es: 'Acabo de %@',
    fr: 'Je viens de %@',
    it: 'Ho appena %@',
    'pt-BR': 'Acabei de %@',
  },
  "I'm cleaning up my photo library": {
    es: 'Estoy limpiando mi fototeca',
    fr: 'Je nettoie ma photothèque',
    it: 'Sto pulendo la mia libreria foto',
    'pt-BR': 'Estou limpando minha biblioteca de fotos',
  },
  '%@ with TidyByte — a private, on-device photo cleanup app. %@': {
    es: '%@ con TidyByte — una app privada de limpieza de fotos en el dispositivo. %@',
    fr: "%@ avec TidyByte — une app privée de nettoyage de photos sur l'appareil. %@",
    it: "%@ con TidyByte — un'app privata per pulire le foto sul dispositivo. %@",
    'pt-BR': '%@ com o TidyByte — um app privado de limpeza de fotos no dispositivo. %@',
  },

  // ------------------------------------------------------------------------ misc
  'Min size: %@': {
    es: 'Tamaño mínimo: %@',
    fr: 'Taille minimale : %@',
    it: 'Dimensione minima: %@',
    'pt-BR': 'Tamanho mínimo: %@',
  },
  'Swipe history cleared': {
    es: 'Historial de deslizamientos borrado',
    fr: 'Historique des balayages effacé',
    it: 'Cronologia delle scorrite cancellata',
    'pt-BR': 'Histórico de deslizes apagado',
  },
  'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.': {
    es: 'iOS te pedirá que lo confirmes. Los elementos eliminados van a Recientemente eliminados en Fotos, donde puedes recuperarlos durante 30 días.',
    fr: 'iOS vous demandera de confirmer. Les éléments supprimés vont dans Récemment supprimés dans Photos, où vous pouvez les restaurer pendant 30 jours.',
    it: 'iOS ti chiederà di confermare. Gli elementi eliminati vanno in Eliminati di recente in Foto, dove puoi recuperarli per 30 giorni.',
    'pt-BR': 'O iOS vai pedir para você confirmar. Os itens apagados vão para Excluídos recentemente no Fotos, onde você pode restaurá-los por 30 dias.',
  },
}

/**
 * key -> { es: {one, other}, fr: …, it: …, 'pt-BR': … } — the 13 counted keys.
 * The forms are the verb phrases that complete the wrapper keys above:
 * es "Acabo de ___", fr "Je viens de ___", it "Ho appena ___", pt-BR "Acabei de ___".
 */
const PLURALS = {
  'cleared %lld photo': {
    es: { one: 'limpiar %lld foto', other: 'limpiar %lld fotos' },
    fr: { one: 'nettoyer %lld photo', other: 'nettoyer %lld photos' },
    it: { one: 'pulito %lld foto', other: 'pulito %lld foto' },
    'pt-BR': { one: 'limpar %lld foto', other: 'limpar %lld fotos' },
  },
  'cleared %lld blurry photo': {
    es: { one: 'limpiar %lld foto borrosa', other: 'limpiar %lld fotos borrosas' },
    fr: { one: 'nettoyer %lld photo floue', other: 'nettoyer %lld photos floues' },
    it: { one: 'pulito %lld foto sfocata', other: 'pulito %lld foto sfocate' },
    'pt-BR': { one: 'limpar %lld foto desfocada', other: 'limpar %lld fotos desfocadas' },
  },
  'cleared %lld screenshot': {
    es: { one: 'limpiar %lld captura de pantalla', other: 'limpiar %lld capturas de pantalla' },
    fr: { one: "nettoyer %lld capture d'écran", other: "nettoyer %lld captures d'écran" },
    it: { one: 'pulito %lld istantanea', other: 'pulito %lld istantanee' },
    'pt-BR': { one: 'limpar %lld captura de tela', other: 'limpar %lld capturas de tela' },
  },
  'cleared %lld large file': {
    es: { one: 'limpiar %lld archivo grande', other: 'limpiar %lld archivos grandes' },
    fr: { one: 'nettoyer %lld fichier volumineux', other: 'nettoyer %lld fichiers volumineux' },
    it: { one: 'pulito %lld file di grandi dimensioni', other: 'pulito %lld file di grandi dimensioni' },
    'pt-BR': { one: 'limpar %lld arquivo grande', other: 'limpar %lld arquivos grandes' },
  },
  'cleared %lld burst frame': {
    es: { one: 'limpiar %lld fotograma de ráfaga', other: 'limpiar %lld fotogramas de ráfaga' },
    fr: { one: 'nettoyer %lld image de rafale', other: 'nettoyer %lld images de rafale' },
    it: { one: 'pulito %lld fotogramma raffica', other: 'pulito %lld fotogrammi raffica' },
    'pt-BR': { one: 'limpar %lld quadro da rajada', other: 'limpar %lld quadros da rajada' },
  },
  'cleared %lld item (%@)': {
    es: { one: 'limpiar %lld elemento (%@)', other: 'limpiar %lld elementos (%@)' },
    fr: { one: 'nettoyer %lld élément (%@)', other: 'nettoyer %lld éléments (%@)' },
    it: { one: 'pulito %lld elemento (%@)', other: 'pulito %lld elementi (%@)' },
    'pt-BR': { one: 'limpar %lld item (%@)', other: 'limpar %lld itens (%@)' },
  },
  'removed %lld duplicate': {
    es: { one: 'eliminar %lld duplicado', other: 'eliminar %lld duplicados' },
    fr: { one: 'supprimer %lld doublon', other: 'supprimer %lld doublons' },
    it: { one: 'eliminato %lld duplicato', other: 'eliminato %lld duplicati' },
    'pt-BR': { one: 'remover %lld duplicata', other: 'remover %lld duplicatas' },
  },
  'removed %lld similar photo': {
    es: { one: 'eliminar %lld foto similar', other: 'eliminar %lld fotos similares' },
    fr: { one: 'supprimer %lld photo similaire', other: 'supprimer %lld photos similaires' },
    it: { one: 'eliminato %lld foto simile', other: 'eliminato %lld foto simili' },
    'pt-BR': { one: 'remover %lld foto semelhante', other: 'remover %lld fotos semelhantes' },
  },
  'compressed %lld photo': {
    es: { one: 'comprimir %lld foto', other: 'comprimir %lld fotos' },
    fr: { one: 'compresser %lld photo', other: 'compresser %lld photos' },
    it: { one: 'compresso %lld foto', other: 'compresso %lld foto' },
    'pt-BR': { one: 'comprimir %lld foto', other: 'comprimir %lld fotos' },
  },
  'compressed %lld video': {
    es: { one: 'comprimir %lld vídeo', other: 'comprimir %lld vídeos' },
    fr: { one: 'compresser %lld vidéo', other: 'compresser %lld vidéos' },
    it: { one: 'compresso %lld video', other: 'compresso %lld video' },
    'pt-BR': { one: 'comprimir %lld vídeo', other: 'comprimir %lld vídeos' },
  },
  'cleaned %lld burst photo': {
    es: { one: 'limpiar %lld foto en ráfaga', other: 'limpiar %lld fotos en ráfaga' },
    fr: { one: 'nettoyer %lld photo en rafale', other: 'nettoyer %lld photos en rafale' },
    it: { one: 'pulito %lld scatto in raffica', other: 'pulito %lld scatti in raffica' },
    'pt-BR': { one: 'limpar %lld foto em rajada', other: 'limpar %lld fotos em rajada' },
  },
  'converted %lld Live Photo': {
    es: { one: 'convertir %lld Live Photo', other: 'convertir %lld Live Photos' },
    fr: { one: 'convertir %lld Live Photo', other: 'convertir %lld Live Photos' },
    it: { one: 'convertito %lld Live Photo', other: 'convertito %lld Live Photos' },
    'pt-BR': { one: 'converter %lld Live Photo', other: 'converter %lld Live Photos' },
  },
  'reviewed %lld item': {
    es: { one: 'revisar %lld elemento', other: 'revisar %lld elementos' },
    fr: { one: 'examiner %lld élément', other: 'examiner %lld éléments' },
    it: { one: 'esaminato %lld elemento', other: 'esaminato %lld elementi' },
    'pt-BR': { one: 'revisar %lld item', other: 'revisar %lld itens' },
  },
}

/** The whole file, in the format the batch-7 files were written in. */
function serialize(strings, plurals) {
  const stringLines = Object.keys(strings)
    .sort(byCodeUnit)
    .map((key) => `    ${JSON.stringify(key)}: ${JSON.stringify(strings[key])}`)
  const pluralLines = Object.keys(plurals).map((key) => {
    const forms = plurals[key]
    const inner = Object.keys(forms)
      .map((category) => `      ${JSON.stringify(category)}: ${JSON.stringify(forms[category])}`)
      .join(',\n')
    return `    ${JSON.stringify(key)}: {\n${inner}\n    }`
  })
  return (
    '{\n' +
    `  "strings": {\n${stringLines.join(',\n')}\n  },\n` +
    `  "plurals": {\n${pluralLines.join(',\n')}\n  }\n` +
    '}\n'
  )
}

function main() {
  const plainKeys = Object.keys(PLAIN)
  const pluralKeys = Object.keys(PLURALS)
  if (plainKeys.length !== 80) throw new Error(`expected 80 plain keys, got ${plainKeys.length}`)
  if (pluralKeys.length !== 13) throw new Error(`expected 13 plural keys, got ${pluralKeys.length}`)

  // The 13 keys must be exactly the ones `_plural-keys.json` added beyond the
  // 51 the language files already carry, so a typo in a key name cannot slip in.
  const pluralCatalog = JSON.parse(readFileSync(join(here, '_plural-keys.json'), 'utf8'))
  const declaredNew = Object.keys(pluralCatalog).slice(51)
  if (JSON.stringify(declaredNew.slice().sort()) !== JSON.stringify(pluralKeys.slice().sort())) {
    throw new Error(
      `plural key list mismatch:\n  catalog: ${JSON.stringify(declaredNew)}\n  table:   ${JSON.stringify(pluralKeys)}`,
    )
  }

  for (const lang of LANGS) {
    const path = join(here, `${lang}.json`)
    const parsed = JSON.parse(readFileSync(path, 'utf8'))

    const strings = { ...parsed.strings }
    for (const key of plainKeys) {
      const value = PLAIN[key][lang]
      if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${lang}: missing translation for ${JSON.stringify(key)}`)
      }
      if (key in strings || key in parsed.plurals) {
        throw new Error(`${lang}: key already present: ${JSON.stringify(key)}`)
      }
      strings[key] = value
    }

    // Existing plural order is preserved; the 13 new keys follow in catalog order.
    const plurals = { ...parsed.plurals }
    for (const key of pluralKeys) {
      const forms = PLURALS[key][lang]
      if (!forms?.one || !forms?.other) {
        throw new Error(`${lang}: missing plural forms for ${JSON.stringify(key)}`)
      }
      plurals[key] = { one: forms.one, other: forms.other }
    }

    const out = serialize(strings, plurals)
    const reparsed = JSON.parse(out) // fail before writing anything unparseable
    if (Object.keys(reparsed.strings).length !== Object.keys(strings).length) {
      throw new Error(`${lang}: strings lost in serialization`)
    }
    if (Object.keys(reparsed.plurals).length !== Object.keys(plurals).length) {
      throw new Error(`${lang}: plurals lost in serialization`)
    }
    writeFileSync(path, out)
    console.log(
      `${lang}: ${Object.keys(parsed.strings).length} -> ${Object.keys(strings).length} strings, ` +
        `${Object.keys(parsed.plurals).length} -> ${Object.keys(plurals).length} plurals`,
    )
  }
}

main()
