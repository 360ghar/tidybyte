// Batch 10 — Spanish, French, Italian, Brazilian Portuguese.
//
// Writes two deliverables:
//   A. docs/appstore/listings.json       (the es / fr / it / pt-BR entries)
//   B. scripts/localization/site/site-translations/<lang>.json  (108 keys each)
//
//   node scripts/localization/translations/_batch10-insert-es-fr-it-ptbr.mjs
//
// listings.json is rewritten through JSON.parse/JSON.stringify so the other 20
// storefront entries keep their exact values and key order; the insert is
// asserted on the parsed objects before anything is written.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..', '..');

const LANGS = ['es', 'fr', 'it', 'pt-BR'];

// ---------------------------------------------------------------------------
// Deliverable A — App Store listings
// ---------------------------------------------------------------------------

const LISTINGS = {
  es: {
    name: 'TidyByte',
    subtitle: 'Limpia fotos, libera espacio',
    promotionalText:
      'Libera espacio en minutos. Desliza para borrar fotos sobrantes, encuentra duplicados y fotos borrosas y comprime vídeos: 100 % en tu dispositivo. Sin anuncios ni cuenta.',
    description: `TidyByte es la forma más rápida y más privada de limpiar la fototeca de tu iPhone, y es totalmente gratis.

¿Cansado del aviso «Almacenamiento casi lleno»? TidyByte convierte la limpieza de fotos en algo que vas a terminar de verdad. Desliza a la izquierda para borrar y a la derecha para conservar: revisa toda tu fototeca foto a foto, como en una app de citas, y recupera gigabytes en minutos.

Además del deslizamiento, TidyByte incluye un conjunto completo de herramientas inteligentes que sacan a la luz lo que está desperdiciando tu espacio: duplicados exactos y visuales, fotos casi idénticas, fotos borrosas o con poca luz, capturas de pantalla, grabaciones de pantalla, elementos de chat guardados por apps de mensajería, ráfagas y tus archivos más grandes. Convierte Live Photos en fotos fijas y comprime vídeos y fotos para ahorrar aún más, sin borrar tus recuerdos.

Tus fotos nunca salen de tu iPhone. TidyByte procesa el 100 % en el dispositivo con los frameworks Vision y Photos de Apple, incluida una búsqueda con IA local que encuentra fotos a partir de una descripción en lenguaje natural. No hay servidores, ni cuenta, ni inicio de sesión, ni anuncios, ni ningún tipo de seguimiento. Nunca se sube nada.

TidyByte es gratis, sin compras dentro de la app ni muros de pago. Todas las funciones están disponibles para todo el mundo.

Funciones:
• Deslizar estilo Tinder para revisar fotos y vídeos: desliza para borrar o conservar
• Buscador de duplicados: duplicados exactos (SHA-256) y visualmente similares
• Fotos similares: agrupa tomas casi idénticas hechas seguidas
• Detección de fotos borrosas: encuentra tomas desenfocadas o mal expuestas
• Limpiador de capturas de pantalla: reúne y borra las capturas
• Limpiador de grabaciones de pantalla: elimina los archivos grandes olvidados
• Limpiador de elementos de chat: revisa lo que guardaron WhatsApp, Telegram y otros mensajeros
• Limpiador de ráfagas: elige la mejor de cada ráfaga
• Categorías inteligentes: ordena las fotos por tipo de contenido, con búsqueda con IA en lenguaje natural
• Buscador de archivos grandes: saca a la luz los archivos más pesados de tu fototeca
• Conversor de Live Photos: convierte Live Photos en fotos fijas para ahorrar espacio
• Compresión de vídeo: reduce los vídeos sin que se vean mal
• Compresión de fotos: vuelve a codificar las fotos para recuperar espacio
• Panel de almacenamiento: mira de un vistazo qué ocupa tu espacio
• Actividad y ahorros: registra todo lo que has limpiado y el espacio total liberado
• Widget de pantalla de inicio y atajos de Siri para limpiar con un toque
• Recordatorios de limpieza opcionales mediante notificaciones locales

Libera espacio. Mantén tu privacidad. Limpia con un desliz.`,
    keywords: 'almacenamiento,duplicados,capturas,comprimir,borrosa,borrar,galería,ordenar,vídeos',
    whatsNew:
      'Busca tus fotos con palabras normales —«perros en la playa»— con IA en el dispositivo. Además, dos herramientas nuevas: Grabaciones de pantalla y Elementos de chat, para los archivos más grandes que se esconden en tu fototeca. Todo sigue funcionando en tu dispositivo: sin cuenta, sin anuncios, sin suscripción.',
  },
  fr: {
    name: 'TidyByte',
    subtitle: "Nettoyage photo, plus d'espace",
    promotionalText:
      "Libérez de l'espace en minutes. Swipez pour supprimer, repérez doublons et photos floues, compressez vos vidéos — 100 % sur l'appareil. Sans pub ni compte.",
    description: `TidyByte est la façon la plus rapide et la plus privée de nettoyer la photothèque de votre iPhone, et c'est entièrement gratuit.

Marre du message « Stockage presque plein » ? TidyByte transforme le nettoyage de photos en quelque chose que vous irez vraiment au bout. Balayez vers la gauche pour supprimer, vers la droite pour garder : passez toute votre photothèque en revue photo par photo, comme dans une appli de rencontre, et récupérez des gigaoctets en quelques minutes.

Au-delà du swipe, TidyByte embarque une boîte à outils complète qui met le doigt sur ce qui gaspille votre espace : doublons exacts et visuels, photos quasi identiques, photos floues ou mal exposées, captures d'écran, enregistrements d'écran, éléments de messagerie enregistrés par les applis de chat, rafales et vos plus gros fichiers. Convertissez les Live Photos en photos fixes et compressez vidéos et photos pour gagner encore de l'espace, sans supprimer vos souvenirs.

Vos photos ne quittent jamais votre iPhone. TidyByte traite 100 % des données sur l'appareil avec les frameworks Vision et Photos d'Apple, y compris une recherche IA locale qui retrouve une photo à partir d'une description en langage courant. Pas de serveur, pas de compte ni de connexion, pas de pub, aucun suivi. Rien n'est jamais envoyé.

TidyByte est gratuit, sans achat intégré ni paywall. Toutes les fonctions sont accessibles à tout le monde.

Fonctionnalités :
• Swipe façon Tinder pour passer en revue photos et vidéos — vers la gauche pour supprimer, vers la droite pour garder
• Détecteur de doublons — doublons exacts (SHA-256) et doublons visuels
• Photos similaires — regroupez les prises de vue quasi identiques
• Détection des photos floues — repérez les clichés flous ou mal exposés
• Nettoyage des captures d'écran — rassemblez et supprimez les captures
• Nettoyage des enregistrements d'écran — supprimez les plus gros fichiers oubliés
• Nettoyage des médias de messagerie — voyez ce que WhatsApp, Telegram et les autres ont enregistré
• Nettoyage des rafales — gardez la meilleure de la série
• Catégories intelligentes — triez les photos par type de contenu, avec recherche IA en langage courant
• Recherche de fichiers volumineux — faites ressortir les fichiers les plus lourds
• Convertisseur de Live Photos — transformez les Live Photos en photos fixes pour gagner de l'espace
• Compression vidéo — allégez vos vidéos sans les rendre illisibles
• Compression des photos — réencodez vos photos pour récupérer de l'espace
• Tableau de bord du stockage — voyez d'un coup d'œil ce qui occupe votre espace
• Activité et économies — suivez tout ce que vous avez nettoyé et l'espace total libéré
• Widget d'écran d'accueil et raccourcis Siri pour nettoyer en un tap
• Rappels de nettoyage facultatifs par notifications locales

Libérez de l'espace. Gardez votre vie privée. Nettoyez d'un swipe.`,
    keywords: 'stockage,doublons,captures,comprimer,floues,galerie,libérer,vidéos,iphone',
    whatsNew:
      "Cherchez vos photos en mots simples — « chiens sur la plage » — avec l'IA sur l'appareil. Plus deux nouveaux outils : Enregistrements d'écran et Éléments de messagerie, pour les plus gros fichiers cachés dans votre photothèque. Tout tourne toujours sur votre appareil : aucun compte, aucune pub, aucun abonnement.",
  },
  it: {
    name: 'TidyByte',
    subtitle: 'Pulisci foto, libera spazio',
    promotionalText:
      "Libera spazio in minuti. Scorri per eliminare l'inutile, trova duplicati e foto sfocate, comprimi i video: 100% sul tuo dispositivo. Niente pubblicità né account.",
    description: `TidyByte è il modo più rapido e più privato per fare pulizia nella libreria foto dell'iPhone, ed è del tutto gratis.

Stanco dell'avviso «Spazio quasi esaurito»? TidyByte trasforma la pulizia delle foto in qualcosa che porterai davvero a termine. Scorri a sinistra per eliminare, a destra per tenere: rivedi tutta la libreria una foto alla volta, come in un'app di incontri, e recupera gigabyte in pochi minuti.

Oltre allo scorrimento, TidyByte include un set completo di strumenti intelligenti che fanno emergere ciò che sta occupando il tuo spazio: duplicati esatti e visivi, foto quasi identiche, foto sfocate o poco illuminate, istantanee, registrazioni dello schermo, contenuti salvati dalle app di messaggistica, raffiche e i file più grandi. Converti le Live Photo in foto statiche e comprimi video e foto per risparmiare ancora di più, senza eliminare i tuoi ricordi.

Le tue foto non lasciano mai l'iPhone. TidyByte elabora tutto al 100% sul dispositivo con i framework Vision e Photos di Apple, inclusa una ricerca IA locale che trova le foto da una descrizione in parole semplici. Nessun server, nessun account, nessun accesso, nessuna pubblicità e nessun tracciamento di alcun tipo. Niente viene mai caricato.

TidyByte è gratis, senza acquisti in-app e senza paywall. Tutte le funzioni sono disponibili per tutti.

Funzioni:
• Scorrimento in stile Tinder per rivedere foto e video: scorri per eliminare o tenere
• Trova duplicati: duplicati esatti (SHA-256) e visivamente simili
• Foto simili: raggruppa gli scatti quasi identici
• Rilevamento foto sfocate: trova scatti mossi o poco esposti
• Pulizia istantanee: raduna e cancella le istantanee
• Pulizia registrazioni dello schermo: cancella i file più grandi dimenticati
• Pulizia contenuti di chat: rivedi ciò che WhatsApp, Telegram e gli altri hanno salvato
• Pulizia raffiche: scegli la migliore di ogni raffica
• Categorie intelligenti: ordina le foto per tipo di contenuto, con ricerca IA in parole semplici
• Trova file di grandi dimensioni: fai emergere i file più pesanti della libreria
• Convertitore Live Photo: trasforma le Live Photo in foto statiche per risparmiare spazio
• Compressione video: alleggerisci i video senza rovinarli
• Compressione foto: ricodifica le foto per recuperare spazio
• Pannello dello spazio: vedi a colpo d'occhio cosa occupa il tuo spazio
• Attività e risparmi: tieni traccia di tutto ciò che hai pulito e dello spazio totale liberato
• Widget della schermata Home e scorciatoie Siri per pulire con un tocco
• Promemoria di pulizia opzionali con notifiche locali

Libera spazio. Proteggi la tua privacy. Pulisci con uno scorrimento.`,
    keywords: 'duplicati,istantanee,comprimere,sfocate,galleria,memoria,video,iphone,archivio',
    whatsNew:
      "Cerca le tue foto a parole tue — «cani in spiaggia» — con l'IA sul dispositivo. In più due strumenti nuovi: Registrazioni schermo e Contenuti chat, per i file più grandi nascosti nella libreria. Tutto continua a girare sul tuo dispositivo: nessun account, nessuna pubblicità, nessun abbonamento.",
  },
  'pt-BR': {
    name: 'TidyByte',
    subtitle: 'Limpe fotos, libere espaço',
    promotionalText:
      'Libere espaço em minutos. Deslize para excluir fotos inúteis, ache duplicatas e fotos desfocadas e comprima vídeos: tudo 100% no seu dispositivo. Sem anúncios nem conta.',
    description: `TidyByte é o jeito mais rápido e mais privado de limpar a biblioteca de fotos do seu iPhone, e é totalmente grátis.

Cansado do aviso «Armazenamento quase cheio»? O TidyByte transforma a limpeza de fotos em algo que você vai terminar de verdade. Deslize para a esquerda para excluir, para a direita para manter: revise a biblioteca inteira foto por foto, como em um app de relacionamento, e libere gigabytes em minutos.

Além de deslizar, o TidyByte traz um conjunto completo de ferramentas inteligentes que mostram exatamente o que está ocupando seu espaço: duplicatas exatas e visuais, fotos quase idênticas, fotos desfocadas ou com pouca luz, capturas de tela, gravações de tela, mídia de chat salva por apps de mensagem, sequências de rajada e seus maiores arquivos. Converta Live Photos em fotos estáticas e comprima vídeos e fotos para economizar ainda mais, sem apagar suas memórias.

Suas fotos nunca saem do seu iPhone. O TidyByte processa 100% no dispositivo com os frameworks Vision e Photos da Apple, incluindo uma busca com IA local que encontra fotos a partir de uma descrição em linguagem comum. Não há servidor, conta, login, anúncios nem qualquer tipo de rastreamento. Nada é enviado. Nunca.

O TidyByte é grátis, sem compras dentro do app e sem paywall. Todos os recursos estão disponíveis para todo mundo.

Recursos:
• Deslizar no estilo Tinder para revisar fotos e vídeos — deslize para excluir ou manter
• Buscador de duplicatas — duplicatas exatas (SHA-256) e visualmente semelhantes
• Fotos semelhantes — agrupe fotos quase idênticas feitas em sequência
• Detecção de fotos desfocadas — encontre fotos tremidas ou mal expostas
• Limpador de capturas de tela — junte e apague as capturas
• Limpador de gravações de tela — apague os maiores arquivos esquecidos
• Limpador de mídia de chat — revise o que WhatsApp, Telegram e outros mensageiros salvaram
• Limpador de rajadas — escolha a melhor de cada sequência
• Categorias inteligentes — organize por tipo de conteúdo, com busca por IA em linguagem comum
• Buscador de arquivos grandes — mostre os arquivos mais pesados da biblioteca
• Conversor de Live Photos — transforme Live Photos em fotos estáticas para economizar espaço
• Compressão de vídeos — reduza vídeos sem deixá-los ruins
• Compressão de fotos — recodifique fotos para recuperar espaço
• Painel de armazenamento — veja de relance o que ocupa seu espaço
• Atividade e economia — acompanhe tudo o que você limpou e o espaço total liberado
• Widget da Tela de Início e atalhos da Siri para limpar com um toque
• Lembretes de limpeza opcionais por notificações locais

Libere espaço. Mantenha sua privacidade. Limpe com um deslize.`,
    keywords: 'armazenamento,duplicatas,capturas,comprimir,desfocadas,galeria,vídeos,iphone',
    whatsNew:
      'Busque suas fotos com palavras simples — «cachorros na praia» — com IA no dispositivo. E mais duas ferramentas novas: Gravações de tela e Mídia de chat, para os maiores arquivos escondidos na sua biblioteca. Tudo continua rodando no seu dispositivo: sem conta, sem anúncios, sem assinatura.',
  },
};

// ---------------------------------------------------------------------------
// Deliverable B — website landing page
// ---------------------------------------------------------------------------

// [english, es, fr, it, pt-BR] — the English column is the key copied from
// site-strings.json, so it is never typed twice.
const SITE = [
  ['01 &mdash; How it works', '01 &mdash; Cómo funciona', '01 &mdash; Comment ça marche', '01 &mdash; Come funziona', '01 &mdash; Como funciona'],
  ['02 &mdash; Cleanup toolkit', '02 &mdash; Herramientas de limpieza', '02 &mdash; Boîte à outils', '02 &mdash; Strumenti di pulizia', '02 &mdash; Kit de limpeza'],
  ['03 &mdash; Storage dashboard', '03 &mdash; Panel de almacenamiento', '03 &mdash; Tableau de bord du stockage', '03 &mdash; Pannello dello spazio', '03 &mdash; Painel de armazenamento'],
  ['04 &mdash; Privacy', '04 &mdash; Privacidad', '04 &mdash; Confidentialité', '04 &mdash; Privacy', '04 &mdash; Privacidade'],
  ['05 &mdash; Open source', '05 &mdash; Código abierto', '05 &mdash; Open source', '05 &mdash; Open source', '05 &mdash; Código aberto'],
  ['06 &mdash; FAQ', '06 &mdash; Preguntas frecuentes', '06 &mdash; FAQ', '06 &mdash; Domande frequenti', '06 &mdash; Perguntas frequentes'],
  ['07 &mdash; Get the app', '07 &mdash; Consigue la app', '07 &mdash; Télécharger l&rsquo;app', '07 &mdash; Scarica l&rsquo;app', '07 &mdash; Baixe o app'],
  ['64 GB', '64 GB', '64 GB', '64 GB', '64 GB'],
  [
    'A donut chart of your library by type, plus the largest files.',
    'Un gráfico de anillo de tu fototeca por tipo, más los archivos más grandes.',
    'Un graphique en anneau de votre photothèque par type, avec les fichiers les plus lourds.',
    'Un grafico a ciambella della libreria per tipo, con i file più grandi.',
    'Um gráfico de rosca da sua biblioteca por tipo, mais os maiores arquivos.',
  ],
  [
    'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.',
    'Un gráfico de anillo en vivo de en qué se va tu almacenamiento &mdash; fotos, vídeos, capturas de pantalla, Live Photos, otros. Toca un sector para ver los elementos exactos que puedes liberar.',
    'Un graphique en anneau en direct de votre stockage &mdash; photos, vidéos, captures d&rsquo;écran, Live Photos, autres. Touchez une part pour voir les éléments exacts à libérer.',
    'Un grafico a ciambella in tempo reale di dove va il tuo spazio &mdash; foto, video, istantanee, Live Photo, altro. Tocca uno spicchio per vedere gli elementi esatti che puoi liberare.',
    'Um gráfico de rosca ao vivo de onde vai seu armazenamento &mdash; fotos, vídeos, capturas de tela, Live Photos, outros. Toque em uma fatia para ver os itens exatos que você pode liberar.',
  ],
  [
    'A swipe session in progress &mdash; one photo, one decision.',
    'Una sesión de deslizamiento en curso &mdash; una foto, una decisión.',
    'Une session de swipe en cours &mdash; une photo, une décision.',
    'Una sessione di scorrimento in corso &mdash; una foto, una decisione.',
    'Uma sessão de deslizar em andamento &mdash; uma foto, uma decisão.',
  ],
  ['AI photo search', 'Búsqueda de fotos con IA', 'Recherche photo IA', 'Ricerca foto con IA', 'Busca de fotos com IA'],
  ['Activity &amp; savings', 'Actividad y ahorros', 'Activité et économies', 'Attività e risparmi', 'Atividade e economia'],
  [
    'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.',
    'Todo el procesamiento ocurre en el dispositivo con los frameworks Vision y Photos de Apple.',
    'Tout le traitement se fait sur l&rsquo;appareil avec les frameworks Vision et Photos d&rsquo;Apple.',
    'Tutta l&rsquo;elaborazione avviene sul dispositivo con i framework Vision e Photos di Apple.',
    'Todo o processamento acontece no dispositivo, usando os frameworks Vision e Photos da Apple.',
  ],
  [
    'Are deleted photos gone immediately?',
    '¿Las fotos borradas desaparecen al instante?',
    'Les photos supprimées disparaissent-elles tout de suite ?',
    'Le foto eliminate spariscono subito?',
    'As fotos excluídas somem na hora?',
  ],
  ['Blurry photos', 'Fotos borrosas', 'Photos floues', 'Foto sfocate', 'Fotos desfocadas'],
  ['Burst photos', 'Fotos en ráfaga', 'Photos en rafale', 'Foto in raffica', 'Fotos em rajada'],
  ['Chat media', 'Elementos de chat', 'Éléments de messagerie', 'Contenuti chat', 'Mídia de chat'],
  [
    'Clay illustration of a teal vault keeping smiling photo cards safe.',
    'Ilustración de plastilina de una caja fuerte turquesa que protege tarjetas de fotos sonrientes.',
    'Illustration en pâte à modeler d&rsquo;un coffre turquoise qui protège des cartes photo souriantes.',
    'Illustrazione in stile plastilina di una cassaforte turchese che protegge foto sorridenti.',
    'Ilustração de massinha de um cofre turquesa protegendo cartões de foto sorridentes.',
  ],
  [
    'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.',
    'Ilustración estilo plastilina de un teléfono que lanza tarjetas de fotos a una bandeja de clasificación sobre colinas verdes.',
    'Illustration style pâte à modeler d&rsquo;un téléphone qui lance des cartes photo dans un bac de tri sur des collines vertes.',
    'Illustrazione in stile plastilina di un telefono che lancia foto in un vassoio di smistamento su colline verdi.',
    'Ilustração estilo massinha de um telefone jogando cartões de foto em uma bandeja de separação sobre colinas verdes.',
  ],
  [
    'Clean your library in minutes.',
    'Limpia tu biblioteca en minutos.',
    'Nettoyez votre photothèque en quelques minutes.',
    'Fai pulizia nella libreria in pochi minuti.',
    'Limpe sua biblioteca em minutos.',
  ],
  ['Cleanup history', 'Historial de limpiezas', 'Historique des nettoyages', 'Cronologia pulizie', 'Histórico de limpezas'],
  ['Clear them in one pass', 'Bórralas de una vez', 'Supprimez-les en une passe', 'Cancellale in un colpo solo', 'Apague tudo de uma vez'],
  [
    'Clear what WhatsApp and Telegram saved.',
    'Borra lo que guardaron WhatsApp y Telegram.',
    'Supprimez ce que WhatsApp et Telegram ont enregistré.',
    'Cancella ciò che WhatsApp e Telegram hanno salvato.',
    'Apague o que o WhatsApp e o Telegram salvaram.',
  ],
  [
    'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.',
    'Confirma una vez y el espacio vuelve. Las fotos borradas esperan 30 días en Recientemente eliminados.',
    'Confirmez une fois et l&rsquo;espace revient. Les photos supprimées restent 30 jours dans Récemment supprimés.',
    'Conferma una volta e lo spazio torna. Gli scatti eliminati restano 30 giorni in Eliminati di recente.',
    'Confirme uma vez e o espaço volta. As fotos excluídas ficam 30 dias em Excluídos recentemente.',
  ],
  [
    'Convert to stills to save space.',
    'Conviértelas en fotos fijas para ahorrar espacio.',
    'Convertissez-les en photos fixes pour gagner de l&rsquo;espace.',
    'Convertile in foto statiche per risparmiare spazio.',
    'Converta em fotos estáticas para economizar espaço.',
  ],
  [
    'Describe a photo in plain words, find it on-device.',
    'Describe una foto con palabras normales y encuéntrala en el dispositivo.',
    'Décrivez une photo en mots simples, retrouvez-la sur l&rsquo;appareil.',
    'Descrivi una foto a parole tue e trovala sul dispositivo.',
    'Descreva uma foto com palavras simples e encontre no dispositivo.',
  ],
  [
    'Does TidyByte support iPad?',
    '¿TidyByte funciona en iPad?',
    'TidyByte est-il compatible iPad ?',
    'TidyByte è compatibile con iPad?',
    'O TidyByte funciona no iPad?',
  ],
  [
    'Does TidyByte upload my photos?',
    '¿TidyByte sube mis fotos?',
    'TidyByte envoie-t-il mes photos ?',
    'TidyByte carica le mie foto?',
    'O TidyByte envia minhas fotos?',
  ],
  [
    'Download TidyByte Free',
    'Descarga TidyByte gratis',
    'Télécharger TidyByte gratuitement',
    'Scarica TidyByte gratis',
    'Baixe o TidyByte grátis',
  ],
  ['Duplicates', 'Duplicados', 'Doublons', 'Duplicati', 'Duplicatas'],
  [
    'Every delete and compression decision, recorded on-device and reviewable.',
    'Cada borrado y cada compresión, registrados en el dispositivo y revisables.',
    'Chaque suppression et compression, enregistrée sur l&rsquo;appareil et consultable.',
    'Ogni eliminazione e compressione, registrata sul dispositivo e consultabile.',
    'Cada exclusão e compressão, registrada no dispositivo e revisável.',
  ],
  [
    'Every kind of clutter, handled.',
    'Todo tipo de desorden, resuelto.',
    'Tous les encombrements, réglés.',
    'Ogni tipo di disordine, risolto.',
    'Todo tipo de bagunça, resolvido.',
  ],
  [
    'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.',
    'Los duplicados exactos se detectan por el hash SHA-256 de los datos del archivo. Los casi duplicados usan las huellas de Vision de Apple para encontrar tomas visualmente similares.',
    'Les doublons exacts sont détectés par hash SHA-256 des données du fichier. Les quasi-doublons utilisent les empreintes Vision d&rsquo;Apple pour repérer les prises de vue visuellement proches.',
    'I duplicati esatti si riconoscono dall&rsquo;hash SHA-256 dei dati del file. I quasi-duplicati usano le impronte Vision di Apple per trovare scatti visivamente simili.',
    'As duplicatas exatas são detectadas pelo hash SHA-256 dos dados do arquivo. As quase duplicatas usam as impressões do Vision da Apple para achar fotos visualmente semelhantes.',
  ],
  [
    'Find exact copies, byte-for-byte.',
    'Encuentra copias exactas, byte a byte.',
    'Trouvez les copies exactes, octet par octet.',
    'Trova copie identiche, byte per byte.',
    'Encontre cópias exatas, byte a byte.',
  ],
  [
    'Free &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Gratis &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Gratuit &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Gratis &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Grátis &middot; iPhone &amp; iPad &middot; iOS 17+',
  ],
  [
    'Frequently asked questions.',
    'Preguntas frecuentes.',
    'Questions fréquentes.',
    'Domande frequenti.',
    'Perguntas frequentes.',
  ],
  [
    'Group near-identical shots.',
    'Agrupa tomas casi idénticas.',
    'Regroupez les prises de vue quasi identiques.',
    'Raggruppa scatti quasi identici.',
    'Agrupe fotos quase idênticas.',
  ],
  [
    'How are duplicates detected?',
    '¿Cómo se detectan los duplicados?',
    'Comment les doublons sont-ils détectés ?',
    'Come vengono rilevati i duplicati?',
    'Como as duplicatas são detectadas?',
  ],
  [
    'How do I report a bug or request a feature?',
    '¿Cómo informo de un error o propongo una función?',
    'Comment signaler un bug ou proposer une fonctionnalité ?',
    'Come segnalo un bug o propongo una funzione?',
    'Como relato um bug ou peço um recurso?',
  ],
  ['How it works', 'Cómo funciona', 'Comment ça marche', 'Come funziona', 'Como funciona'],
  [
    'Is there a free trial or subscription?',
    '¿Hay prueba gratuita o suscripción?',
    'Y a-t-il un essai gratuit ou un abonnement ?',
    'C&rsquo;è una prova gratuita o un abbonamento?',
    'Existe teste grátis ou assinatura?',
  ],
  ['Large files', 'Archivos grandes', 'Fichiers volumineux', 'File di grandi dimensioni', 'Arquivos grandes'],
  [
    'Left deletes, right keeps. Every choice lands in a review list before anything is touched.',
    'Izquierda borra, derecha conserva. Cada elección va a una lista de revisión antes de tocar nada.',
    'À gauche on supprime, à droite on garde. Chaque choix arrive dans une liste à relire avant toute modification.',
    'A sinistra elimini, a destra tieni. Ogni scelta finisce in una lista da rivedere prima di toccare qualsiasi cosa.',
    'Esquerda exclui, direita mantém. Cada escolha vai para uma lista de revisão antes de qualquer alteração.',
  ],
  ['Live Photos', 'Live Photos', 'Live Photos', 'Live Photo', 'Live Photos'],
  [
    'New in 1.0.5 &mdash; on-device AI photo search',
    'Novedad en 1.0.5 &mdash; búsqueda de fotos con IA en el dispositivo',
    'Nouveau en 1.0.5 &mdash; recherche photo IA sur l&rsquo;appareil',
    'Novità nella 1.0.5 &mdash; ricerca foto con IA sul dispositivo',
    'Novidade na 1.0.5 &mdash; busca de fotos com IA no dispositivo',
  ],
  ['No account', 'Sin cuenta', 'Sans compte', 'Nessun account', 'Sem conta'],
  [
    'No account to create. No subscription to manage. Just one swipe at a time.',
    'Nada de crear cuentas. Nada de gestionar suscripciones. Solo un desliz a la vez.',
    'Aucun compte à créer. Aucun abonnement à gérer. Juste un swipe à la fois.',
    'Nessun account da creare. Nessun abbonamento da gestire. Solo uno scorrimento alla volta.',
    'Nenhuma conta para criar. Nenhuma assinatura para gerenciar. Só um deslize por vez.',
  ],
  ['No ads', 'Sin anuncios', 'Sans pub', 'Niente pubblicità', 'Sem anúncios'],
  [
    'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.',
    'Sin SDK de analítica, sin servidores, sin scripts de terceros, sin seguimiento &mdash; en ningún sitio.',
    'Aucun SDK d&rsquo;analyse, aucun serveur, aucun script tiers, aucun suivi &mdash; nulle part.',
    'Nessun SDK di analisi, nessun server, nessuno script di terze parti, nessun tracciamento &mdash; da nessuna parte.',
    'Sem SDK de análise, sem servidor, sem scripts de terceiros, sem rastreamento &mdash; em lugar nenhum.',
  ],
  [
    'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.',
    'Ninguna herramienta de limpieza toca los originales. La única operación que vuelve a codificar es la compresión de vídeo o de fotos, y el ajuste lo eliges tú.',
    'Aucun outil de nettoyage ne touche aux originaux. La seule opération qui réencode est l&rsquo;outil de compression vidéo ou photo, et c&rsquo;est vous qui choisissez le préréglage.',
    'Nessuno strumento di pulizia tocca gli originali. L&rsquo;unica operazione che ricodifica è la compressione video o foto, e il preset lo scegli tu.',
    'Nenhuma ferramenta de limpeza mexe nos originais. A única operação que recodifica é a compressão de vídeo ou de fotos, e você escolhe o ajuste.',
  ],
  [
    'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.',
    'No. Todo el procesamiento ocurre en tu iPhone con los frameworks Photos y Vision de Apple &mdash; sin SDK de analítica, sin servidores, sin seguimiento.',
    'Non. Tout se passe localement sur votre iPhone avec les frameworks Photos et Vision d&rsquo;Apple &mdash; aucun SDK d&rsquo;analyse, aucun serveur, aucun suivi.',
    'No. Tutto avviene in locale sul tuo iPhone con i framework Photos e Vision di Apple &mdash; nessun SDK di analisi, nessun server, nessun tracciamento.',
    'Não. Todo o processamento acontece localmente no seu iPhone com os frameworks Photos e Vision da Apple &mdash; sem SDK de análise, sem servidor, sem rastreamento.',
  ],
  [
    'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.',
    'Una tarjeta. Una decisión. Limpiarás años de fotos antes de que se enfríe tu café.',
    'Une carte. Une décision. Vous nettoierez des années de photos avant que votre café ne refroidisse.',
    'Una scheda. Una decisione. Farai pulizia di anni di foto prima che il caffè si raffreddi.',
    'Um cartão. Uma decisão. Você vai limpar anos de fotos antes do café esfriar.',
  ],
  [
    'Open an issue on',
    'Abre una incidencia en',
    'Signalez un problème sur',
    'Apri una segnalazione su',
    'Relate um problema no',
  ],
  ['Other', 'Otros', 'Autres', 'Altro', 'Outros'],
  ['Photo compression', 'Compresión de fotos', 'Compression des photos', 'Compressione foto', 'Compressão de fotos'],
  [
    'Photos never leave your phone',
    'Tus fotos nunca salen de tu teléfono',
    'Vos photos ne quittent jamais votre téléphone',
    'Le foto non lasciano mai il tuo telefono',
    'Suas fotos nunca saem do seu celular',
  ],
  [
    'Pick the best from a sequence.',
    'Elige la mejor de cada secuencia.',
    'Gardez la meilleure de la série.',
    'Scegli la migliore della sequenza.',
    'Escolha a melhor da sequência.',
  ],
  ['Pick where to start', 'Elige por dónde empezar', 'Choisissez par où commencer', 'Scegli da dove iniziare', 'Escolha por onde começar'],
  [
    'Re-encode photos to reclaim space.',
    'Vuelve a codificar las fotos para recuperar espacio.',
    'Réencodez vos photos pour récupérer de l&rsquo;espace.',
    'Ricodifica le foto per recuperare spazio.',
    'Recodifique fotos para recuperar espaço.',
  ],
  [
    'Read every line that touches your photos.',
    'Lee cada línea que toca tus fotos.',
    'Lisez chaque ligne qui touche à vos photos.',
    'Leggi ogni riga che tocca le tue foto.',
    'Leia cada linha que mexe nas suas fotos.',
  ],
  [
    'Read the privacy policy',
    'Lee la política de privacidad',
    'Lire la politique de confidentialité',
    'Leggi l&rsquo;informativa sulla privacy',
    'Leia a política de privacidade',
  ],
  [
    'Round up and clear them in one pass.',
    'Reúnelas y bórralas de una vez.',
    'Rassemblez-les et supprimez-les en une passe.',
    'Radunale e cancellale in un colpo solo.',
    'Junte tudo e apague de uma vez.',
  ],
  ['Screen recordings', 'Grabaciones de pantalla', 'Enregistrements d&rsquo;écran', 'Registrazioni schermo', 'Gravações de tela'],
  ['Screenshots', 'Capturas de pantalla', 'Captures d&rsquo;écran', 'Istantanee', 'Capturas de tela'],
  [
    'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.',
    'Capturas, duplicados, fotos borrosas o toda tu biblioteca. Cada herramienta abre una baraja de tarjetas de fotos.',
    'Captures, doublons, flou ou toute votre photothèque. Chaque outil ouvre un jeu de cartes photo.',
    'Istantanee, duplicati, sfocate o l&rsquo;intera libreria. Ogni strumento apre un mazzo di schede foto.',
    'Capturas, duplicatas, fotos desfocadas ou a biblioteca inteira. Cada ferramenta abre um baralho de cartões de foto.',
  ],
  [
    'See exactly what&rsquo;s using your space.',
    'Mira exactamente qué está ocupando tu espacio.',
    'Voyez exactement ce qui occupe votre espace.',
    'Vedi esattamente cosa occupa il tuo spazio.',
    'Veja exatamente o que ocupa seu espaço.',
  ],
  ['See how it works', 'Mira cómo funciona', 'Voir comment ça marche', 'Scopri come funziona', 'Veja como funciona'],
  ['See what changed &rarr;', 'Ver las novedades &rarr;', 'Voir les nouveautés &rarr;', 'Vedi le novità &rarr;', 'Veja o que mudou &rarr;'],
  [
    'Shrink videos, keep them watchable.',
    'Reduce los vídeos sin que se vean mal.',
    'Allégez vos vidéos sans les rendre illisibles.',
    'Alleggerisci i video senza rovinarli.',
    'Reduza os vídeos sem deixá-los ruins.',
  ],
  ['Similar photos', 'Fotos similares', 'Photos similaires', 'Foto simili', 'Fotos semelhantes'],
  ['Smart categories', 'Categorías inteligentes', 'Catégories intelligentes', 'Categorie intelligenti', 'Categorias inteligentes'],
  [
    'Sort by content type, browse faster.',
    'Ordena por tipo de contenido y navega más rápido.',
    'Triez par type de contenu, parcourez plus vite.',
    'Ordina per tipo di contenuto e sfoglia più in fretta.',
    'Ordene por tipo de conteúdo e navegue mais rápido.',
  ],
  [
    'Spot out-of-focus and shaky shots.',
    'Detecta tomas desenfocadas y movidas.',
    'Repérez les photos floues ou bougées.',
    'Individua scatti sfocati e mossi.',
    'Encontre fotos desfocadas e tremidas.',
  ],
  ['Storage breakdown', 'Desglose del almacenamiento', 'Répartition du stockage', 'Dettaglio dello spazio', 'Detalhes do armazenamento'],
  ['Support', 'Soporte', 'Assistance', 'Assistenza', 'Suporte'],
  [
    'Surface the biggest space hogs.',
    'Saca a la luz lo que más espacio ocupa.',
    'Faites ressortir les plus gros consommateurs d&rsquo;espace.',
    'Fai emergere ciò che occupa più spazio.',
    'Mostre o que mais ocupa espaço.',
  ],
  [
    'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.',
    'Desliza a la izquierda para borrar y a la derecha para conservar &mdash; y recupera gigabytes en minutos. Duplicados, capturas de pantalla, elementos de chat, fotos borrosas y vídeos enormes resueltos, imágenes comprimidas, 100% en el dispositivo. Sin anuncios, sin suscripción, sin cuenta.',
    'Balayez vers la gauche pour supprimer, vers la droite pour garder &mdash; et récupérez des gigaoctets en quelques minutes. Doublons, captures d&rsquo;écran, médias de messagerie, photos floues et vidéos trop lourdes traités, images compressées, 100 % sur l&rsquo;appareil. Sans pub, sans abonnement, sans compte.',
    'Scorri a sinistra per eliminare, a destra per tenere &mdash; e recupera gigabyte in pochi minuti. Duplicati, istantanee, contenuti chat, foto sfocate e video enormi gestiti, immagini compresse, 100% sul dispositivo. Nessuna pubblicità, nessun abbonamento, nessun account.',
    'Deslize para a esquerda para excluir, para a direita para manter &mdash; e libere gigabytes em minutos. Duplicatas, capturas de tela, mídia de chat, fotos desfocadas e vídeos enormes resolvidos, imagens comprimidas, 100% no dispositivo. Sem anúncios, sem assinatura, sem conta.',
  ],
  ['Swipe to decide', 'Desliza para decidir', 'Swipez pour décider', 'Scorri per decidere', 'Deslize para decidir'],
  [
    'The best free iPhone storage cleaner and photo cleaner.',
    'El mejor limpiador de almacenamiento y de fotos para iPhone, gratis.',
    'Le meilleur nettoyeur de stockage et de photos pour iPhone, gratuit.',
    'Il miglior pulitore di spazio e di foto per iPhone, gratis.',
    'O melhor limpador de armazenamento e de fotos para iPhone, grátis.',
  ],
  [
    'The largest files nobody remembers making.',
    'Los archivos más grandes que nadie recuerda haber creado.',
    'Les fichiers les plus lourds que personne ne se rappelle avoir créés.',
    'I file più grandi che nessuno ricorda di aver creato.',
    'Os maiores arquivos que ninguém lembra de ter criado.',
  ],
  ['The swipe, explained.', 'El deslizamiento, explicado.', 'Le swipe, expliqué.', 'Lo scorrimento, spiegato.', 'O deslize, explicado.'],
  [
    'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.',
    'Van al álbum Recientemente eliminados de iOS, donde esperan 30 días antes de borrarse para siempre &mdash; exactamente igual que si las borras desde la app Fotos.',
    'Elles vont dans l&rsquo;album Récemment supprimés d&rsquo;iOS, où elles restent 30 jours avant d&rsquo;être définitivement effacées &mdash; exactement comme une suppression depuis l&rsquo;app Photos.',
    'Finiscono nell&rsquo;album Eliminati di recente di iOS, dove restano 30 giorni prima di essere eliminate per sempre &mdash; esattamente come eliminarle dall&rsquo;app Foto.',
    'Elas vão para o álbum Excluídos recentemente do iOS, onde ficam 30 dias antes de serem removidas de vez &mdash; exatamente como excluir pelo app Fotos.',
  ],
  ['TidyByte in numbers', 'TidyByte en cifras', 'TidyByte en chiffres', 'TidyByte in numeri', 'TidyByte em números'],
  [
    'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.',
    'TidyByte tiene licencia MIT. Lee el código, comprueba lo que decimos y abre una incidencia.',
    'TidyByte est sous licence MIT. Lisez le code, vérifiez nos affirmations, ouvrez un ticket.',
    'TidyByte ha licenza MIT. Leggi il codice, verifica le promesse, apri una segnalazione.',
    'O TidyByte tem licença MIT. Leia o código, confira o que dizemos e abra uma issue.',
  ],
  [
    'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See',
    'TidyByte es gratis, sin compras dentro de la app ni muros de pago. Todas las funciones están disponibles para todo el mundo. Consulta',
    'TidyByte est gratuit, sans achat intégré ni paywall. Toutes les fonctions sont accessibles à tout le monde. Voir',
    'TidyByte è gratis, senza acquisti in-app e senza paywall. Tutte le funzioni sono disponibili per tutti. Scopri',
    'O TidyByte é grátis, sem compras dentro do app e sem paywall. Todos os recursos estão disponíveis para todos. Veja',
  ],
  [
    'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.',
    'Panel de almacenamiento de TidyByte con un gráfico de anillo de fotos, vídeos, capturas de pantalla, Live Photos y otros.',
    'Tableau de bord du stockage de TidyByte avec un graphique en anneau des photos, vidéos, captures d&rsquo;écran, Live Photos et autres.',
    'Pannello dello spazio di TidyByte con un grafico a ciambella di foto, video, istantanee, Live Photo e altro.',
    'Painel de armazenamento do TidyByte com um gráfico de rosca de fotos, vídeos, capturas de tela, Live Photos e outros.',
  ],
  [
    'TidyByte swipe session with one photo card on screen and delete and keep buttons below.',
    'Sesión de deslizamiento de TidyByte con una tarjeta de foto en pantalla y los botones de borrar y conservar debajo.',
    'Session de swipe TidyByte avec une carte photo à l&rsquo;écran et les boutons supprimer et garder en dessous.',
    'Sessione di scorrimento di TidyByte con una scheda foto sullo schermo e i pulsanti elimina e tieni in basso.',
    'Sessão de deslizar do TidyByte com um cartão de foto na tela e os botões excluir e manter abaixo.',
  ],
  [
    'TidyByte swipe-review screen mid-session.',
    'Pantalla de revisión con deslizamiento de TidyByte en mitad de una sesión.',
    'Écran de révision par swipe de TidyByte en pleine session.',
    'Schermata di revisione con scorrimento di TidyByte a metà sessione.',
    'Tela de revisão por deslize do TidyByte no meio de uma sessão.',
  ],
  [
    'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.',
    'TidyByte funciona con toda tu biblioteca, incluidos los elementos que solo están en iCloud. El sistema los descarga cuando hacen falta; también puedes deslizar sin esperar.',
    'TidyByte fonctionne avec toute votre photothèque, y compris les éléments stockés uniquement dans iCloud. Le système les télécharge au besoin ; vous pouvez aussi passer sans attendre.',
    'TidyByte funziona con l&rsquo;intera libreria, compresi gli elementi salvati solo su iCloud. Il sistema li scarica quando serve; puoi anche scorrere senza aspettare.',
    'O TidyByte funciona com a biblioteca inteira, inclusive itens guardados só no iCloud. O sistema baixa quando precisa; você também pode deslizar sem esperar.',
  ],
  [
    'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.',
    'Doce herramientas de limpieza más información de almacenamiento, historial de limpiezas y búsqueda con IA en el dispositivo &mdash; todo funcionando en tu teléfono. Toca cualquiera para ver cómo funciona.',
    'Douze outils de nettoyage, plus l&rsquo;analyse du stockage, l&rsquo;historique des nettoyages et la recherche IA sur l&rsquo;appareil &mdash; le tout sur votre téléphone. Touchez-en un pour voir comment il marche.',
    'Dodici strumenti di pulizia più analisi dello spazio, cronologia pulizie e ricerca IA sul dispositivo &mdash; tutto in esecuzione sul tuo telefono. Tocca uno strumento per vedere come funziona.',
    'Doze ferramentas de limpeza mais análise do armazenamento, histórico de limpezas e busca com IA no dispositivo &mdash; tudo rodando no seu celular. Toque em qualquer uma para ver como funciona.',
  ],
  ['Video compression', 'Compresión de vídeo', 'Compression vidéo', 'Compressione video', 'Compressão de vídeos'],
  ['Videos', 'Vídeos', 'Vidéos', 'Video', 'Vídeos'],
  ['View on GitHub &rarr;', 'Ver en GitHub &rarr;', 'Voir sur GitHub &rarr;', 'Vedi su GitHub &rarr;', 'Ver no GitHub &rarr;'],
  [
    'We can&rsquo;t see your photos. We don&rsquo;t want to.',
    'No podemos ver tus fotos. No queremos.',
    'Nous ne voyons pas vos photos. Et nous n&rsquo;en avons pas envie.',
    'Non possiamo vedere le tue foto. E non vogliamo.',
    'Nós não vemos suas fotos. E não queremos.',
  ],
  [
    'What about iCloud-only photos?',
    '¿Y las fotos que solo están en iCloud?',
    'Et les photos uniquement dans iCloud ?',
    'E le foto solo su iCloud?',
    'E as fotos que estão só no iCloud?',
  ],
  [
    'Will it lower the quality of my photos?',
    '¿Va a bajar la calidad de mis fotos?',
    'Est-ce que la qualité de mes photos va baisser ?',
    'La qualità delle mie foto peggiora?',
    'Isso vai piorar a qualidade das minhas fotos?',
  ],
  [
    'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.',
    'Sí. TidyByte es una app universal que funciona de forma nativa en iPhone y iPad. Todas las herramientas de limpieza funcionan en ambos, la interfaz de deslizamiento se adapta a la pantalla más grande del iPad y el iPad admite todas las orientaciones.',
    'Oui. TidyByte est une app universelle qui tourne nativement sur iPhone et iPad. Tous les outils de nettoyage fonctionnent sur les deux, l&rsquo;interface de swipe s&rsquo;adapte au grand écran de l&rsquo;iPad et l&rsquo;iPad gère toutes les orientations.',
    'Sì. TidyByte è un&rsquo;app universale che funziona nativamente su iPhone e iPad. Tutti gli strumenti di pulizia funzionano su entrambi, l&rsquo;interfaccia a scorrimento si adatta allo schermo più grande dell&rsquo;iPad e l&rsquo;iPad supporta tutti gli orientamenti.',
    'Sim. O TidyByte é um app universal que roda nativamente no iPhone e no iPad. Todas as ferramentas de limpeza funcionam nos dois, a interface de deslizar se adapta à tela maior do iPad e o iPad aceita todas as orientações.',
  ],
  [
    'Your photos never leave your phone.',
    'Tus fotos nunca salen de tu teléfono.',
    'Vos photos ne quittent jamais votre téléphone.',
    'Le tue foto non lasciano mai il tuo telefono.',
    'Suas fotos nunca saem do seu celular.',
  ],
  [
    'bytes uploaded, ever',
    'bytes subidos, nunca',
    'octets envoyés, jamais',
    'byte caricati, mai',
    'bytes enviados, nunca',
  ],
  ['cleanup tools', 'herramientas de limpieza', 'outils de nettoyage', 'strumenti di pulizia', 'ferramentas de limpeza'],
  [
    'how it compares to subscription photo cleaners',
    'cómo se compara con los limpiadores de fotos por suscripción',
    'comment il se compare aux nettoyeurs photo par abonnement',
    'come si confronta con i pulitori di foto in abbonamento',
    'como ele se compara aos limpadores de fotos por assinatura',
  ],
  [
    'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.',
    'lleva la cuenta: todo lo que has limpiado, un gráfico de 30 días y el espacio total que has liberado. El widget de pantalla de inicio y los atajos de Siri te llevan directo a una limpieza.',
    'tient le score : tout ce que vous avez nettoyé, un graphique sur 30 jours et l&rsquo;espace total libéré. Le widget d&rsquo;écran d&rsquo;accueil et les raccourcis Siri vous emmènent droit dans un nettoyage.',
    'tiene il conto: tutto ciò che hai pulito, un grafico di 30 giorni e lo spazio totale liberato. Il widget della schermata Home e le scorciatoie Siri ti portano dritto a una pulizia.',
    'mantém a conta: tudo o que você limpou, um gráfico de 30 dias e o total de espaço liberado. O widget da Tela de Início e os atalhos da Siri levam direto para uma limpeza.',
  ],
  ['open source, MIT', 'código abierto, MIT', 'open source, MIT', 'open source, MIT', 'código aberto, MIT'],
  [
    'or use the contact form on the',
    'o usa el formulario de contacto de la sección',
    'ou utilisez le formulaire de contact de la section',
    'o usa il modulo di contatto nella sezione',
    'ou use o formulário de contato da seção',
  ],
  ['page.', 'del sitio.', 'du site.', 'del sito.', 'do site.'],
  ['photo library', 'fototeca', 'photothèque', 'libreria foto', 'biblioteca de fotos'],
  ['to own it outright', 'y es tuyo para siempre', 'et il est à vous pour de bon', 'ed è tuo per sempre', 'e é seu para sempre'],
];

// ---------------------------------------------------------------------------
// Write + verify
// ---------------------------------------------------------------------------

let failures = 0;
const fail = (m) => {
  failures += 1;
  console.error(`FAIL: ${m}`);
};

// --- A. listings.json
const listingPath = join(ROOT, 'docs/appstore/listings.json');
const rawListings = readFileSync(listingPath, 'utf8');
const listings = JSON.parse(rawListings);
const englishListing = listings.en;

const before = JSON.stringify(listings);

if (SITE.length !== 108 || SITE.some((r) => r.length !== 5)) {
  fail(`SITE has ${SITE.length} rows and row widths ${[...new Set(SITE.map((r) => r.length))].join(',')}`);
}
for (const lang of LANGS) {
  const entry = LISTINGS[lang];
  if (!entry) fail(`${lang} listing missing`);
  for (const field of ['name', 'subtitle', 'promotionalText', 'description', 'keywords', 'whatsNew']) {
    const value = entry[field];
    if (typeof value !== 'string' || value.trim() === '') fail(`${lang}.${field} is empty`);
    const limit = listings._limits[field];
    if (value.length > limit) fail(`${lang}.${field} is ${value.length} chars, over the ${limit} limit`);
  }
  if (entry.name !== englishListing.name) fail(`${lang}.name is not the brand`);
  if (/,\s/.test(entry.keywords)) fail(`${lang}.keywords has a space after a comma`);
  const terms = entry.keywords.split(',');
  if (new Set(terms).size !== terms.length) fail(`${lang}.keywords repeats a term`);
  const subtitleWords = new Set(
    entry.subtitle.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 2),
  );
  for (const term of terms) {
    if (term.includes(' ')) continue;
    if (subtitleWords.has(term.toLowerCase())) fail(`${lang}.keywords repeats subtitle word ${term}`);
  }
  if (Object.keys(entry).join(',') !== 'name,subtitle,promotionalText,description,keywords,whatsNew') {
    fail(`${lang} field order does not match en`);
  }
  listings[lang] = entry;
}

if (JSON.stringify(listings) === before) {
  console.log('(re-run: the four entries on disk already match this file; rewriting anyway)');
}

writeFileSync(listingPath, JSON.stringify(listings, null, 2) + '\n', 'utf8');
console.log(`wrote ${listingPath}`);

// --- B. site translations
const stringsPath = join(ROOT, 'scripts/localization/site/site-strings.json');
const source = JSON.parse(readFileSync(stringsPath, 'utf8')).strings;
const sourceSet = new Set(source);
if (source.length !== sourceSet.size) fail('site-strings.json has duplicate strings');
for (const row of SITE) {
  if (!sourceSet.has(row[0])) fail(`site row key not in site-strings.json: ${JSON.stringify(row[0])}`);
}
const missing = source.filter((s) => !SITE.some((r) => r[0] === s));
if (missing.length) fail(`${missing.length} source string(s) have no translation row`);

const outDir = join(ROOT, 'scripts/localization/site/site-translations');
mkdirSync(outDir, { recursive: true });

LANGS.forEach((lang, index) => {
  const out = {};
  for (const row of SITE) {
    if (row[index + 1] === undefined) fail(`${lang} missing a translation for ${JSON.stringify(row[0])}`);
    out[row[0]] = row[index + 1];
  }
  const file = join(outDir, `${lang}.json`);
  writeFileSync(file, JSON.stringify(out, null, 2) + '\n', 'utf8');
  console.log(`wrote ${file}`);
});

if (failures > 0) {
  console.error(`\n${failures} problem(s) found; files were still written so they can be inspected.`);
  process.exit(1);
}
console.log('\nBatch 10 insert complete.');
