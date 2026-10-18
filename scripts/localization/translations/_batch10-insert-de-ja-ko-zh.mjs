#!/usr/bin/env node
// Batch 10 — inserts de / ja / ko / zh-Hans.
//
// Two deliverables:
//   A. docs/appstore/listings.json      — one localized listing per language
//   B. scripts/localization/site/site-translations/<lang>.json — 108 landing-page
//      strings per language, keyed byte-for-byte by the English source string.
//
// Both files are written from this script rather than by hand so that the 19
// other listing entries stay untouched and the 108 keys cannot drift.
//
// Run: node scripts/localization/translations/_batch10-insert-de-ja-ko-zh.mjs

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..', '..');

const LISTINGS = join(root, 'docs', 'appstore', 'listings.json');
const SITE_STRINGS = join(root, 'scripts', 'localization', 'site', 'site-strings.json');
const OUT_DIR = join(root, 'scripts', 'localization', 'site', 'site-translations');

// ---------------------------------------------------------------------------
// Deliverable A — App Store listings
// ---------------------------------------------------------------------------

const LISTINGS_BY_LANG = {
  de: {
    name: 'TidyByte',
    subtitle: 'Fotos entrümpeln, Platz frei',
    promotionalText:
      'Speicher in Minuten freigeben. Wische schlechte Fotos weg, finde Duplikate und unscharfe Aufnahmen, komprimiere Videos — 100 % auf dem Gerät. Keine Werbung, kein Konto.',
    description:
      'TidyByte ist der schnellste und privateste Weg, deine iPhone-Fotomediathek aufzuräumen — und komplett kostenlos.\n\n' +
      'Keine Lust mehr auf „Speicher fast voll“? TidyByte macht aus dem Foto-Aufräumen etwas, das du wirklich zu Ende bringst. Nach links wischen zum Löschen, nach rechts wischen zum Behalten — schau dir deine ganze Mediathek Foto für Foto an, wie in einer Dating-App, und hol dir in Minuten Gigabyte zurück.\n\n' +
      'Neben dem Wischen steckt in TidyByte ein komplettes Set cleverer Aufräum-Tools, die genau zeigen, was deinen Speicher belegt: exakte und visuelle Duplikate, fast identische ähnliche Aufnahmen, unscharfe oder schlecht belichtete Fotos, Screenshots, Bildschirmaufnahmen, von Messengern gespeicherte Chat-Medien, Serienbilder und deine größten Dateien. Verwandle Live Photos in Standbilder und komprimiere Videos und Fotos, um noch mehr zu sparen — ohne deine Erinnerungen zu löschen.\n\n' +
      'Deine Fotos verlassen nie dein Telefon. TidyByte erledigt 100 % der Verarbeitung auf dem Gerät mit Apples Vision- und Photos-Frameworks, inklusive einer lokalen KI-Suche, die Fotos anhand einer einfachen Beschreibung findet. Es gibt kein Backend, kein Konto und keinen Login, keine Werbung und keinerlei Tracking. Nichts wird hochgeladen, niemals.\n\n' +
      'TidyByte ist kostenlos, ohne In-App-Käufe und ohne Paywalls. Jede Funktion steht allen zur Verfügung.\n\n' +
      'Funktionen:\n' +
      '• Wischen im Tinder-Stil, um Fotos und Videos zu prüfen — wischen zum Löschen oder Behalten\n' +
      '• Duplikat-Finder — exakte (SHA-256) und visuell ähnliche Duplikate\n' +
      '• Ähnliche Fotos — gruppiert fast identische Aufnahmen aus kurzer Zeit\n' +
      '• Unscharfe Fotos erkennen — findet unscharfe und schlecht belichtete Aufnahmen\n' +
      '• Screenshot-Cleaner — sammelt Screenshots ein und räumt sie weg\n' +
      '• Bildschirmaufnahmen-Cleaner — räumt die größten vergessenen Dateien weg\n' +
      '• Chat-Medien-Cleaner — prüfe, was WhatsApp, Telegram und andere Messenger gespeichert haben\n' +
      '• Serienbild-Cleaner — such das beste aus einer Serie\n' +
      '• Smarte Kategorien — sortiere Fotos nach Inhaltstyp, mit KI-Suche in einfachen Worten direkt auf dem Gerät\n' +
      '• Große Dateien finden — zeigt die größten Dateien in deiner Mediathek\n' +
      '• Live-Photo-Konverter — mach aus Live Photos Standbilder, um Speicher zu sparen\n' +
      '• Videokompression — verkleinere Videos und behalte sie anschaubar\n' +
      '• Fotokompression — kodiere Fotos neu, um Speicher zurückzuholen\n' +
      '• Speicher-Dashboard — sieh auf einen Blick, was deinen Speicher belegt\n' +
      '• Aktivität & Ersparnis — verfolge alles, was du aufgeräumt hast, und den insgesamt freigegebenen Speicher\n' +
      '• Widget auf dem Home-Bildschirm und Siri-Kurzbefehle für Aufräumen mit einem Tipp\n' +
      '• Optionale Erinnerungen ans Aufräumen per lokalen Mitteilungen\n\n' +
      'Speicher freigeben. Privatsphäre behalten. Aufräumen mit einem Wisch.',
    keywords:
      'speicher freigeben,duplikate finden,fotos löschen,screenshots löschen,bilder komprimieren',
    whatsNew:
      'Suche deine Fotos mit einfachen Worten — „Hunde am Strand“ — dank KI auf dem Gerät. Dazu zwei neue Tools: Bildschirmaufnahmen und Chat-Medien, für die größten versteckten Dateien in deiner Mediathek. Alles läuft weiterhin auf deinem Gerät: kein Konto, keine Werbung, kein Abo.',
  },

  ja: {
    name: 'TidyByte',
    subtitle: '無料で写真整理、空き容量を増やす',
    promotionalText:
      '数分で空き容量を解放。いらない写真はスワイプで削除、重複やぶれた写真を見つけ、動画は圧縮 — すべて100%端末内で完結。広告なし、アカウント登録なし。',
    description:
      'TidyByte は、iPhone の写真ライブラリをいちばん速く、いちばんプライベートに整理する方法です。しかも完全無料。\n\n' +
      '「ストレージがほぼいっぱいです」にうんざりしていませんか？TidyByte なら写真整理が本当に最後まで終わります。左にスワイプで削除、右にスワイプでキープ — マッチングアプリのように1枚ずつライブラリ全体を見直し、数分でギガバイトを取り戻せます。\n\n' +
      'スワイプだけでなく、TidyByte には容量を圧迫している本当の原因をあぶり出す整理ツールがそろっています。完全な重複と見た目の重複、ほぼ同じ似た写真、ぶれた写真や露出の悪い写真、スクリーンショット、画面収録、メッセージアプリが保存したチャットメディア、連写、そして容量の大きいファイル。Live Photos を静止画に変換し、動画や写真を圧縮すれば、思い出を消さずにさらに節約できます。\n\n' +
      '写真が端末の外に出ることはありません。TidyByte は Apple の Vision と Photos フレームワークを使い、処理の100%を端末内で行います。ふつうの言葉で書いた説明から写真を探すローカル AI 検索も含まれます。バックエンドも、アカウントやログインも、広告も、いかなるトラッキングもありません。アップロードは一切行われません。\n\n' +
      'TidyByte は無料で、アプリ内課金もペイウォールもありません。すべての機能を誰でも使えます。\n\n' +
      '機能:\n' +
      '• Tinder 風スワイプで写真と動画を確認 — 削除かキープかをスワイプで選択\n' +
      '• 重複ファインダー — 完全な重複（SHA-256）と見た目が似た重複\n' +
      '• 似た写真 — 近い時間に撮ったほぼ同じ写真をまとめる\n' +
      '• ぶれ写真の検出 — ピントが合っていない写真や露出の悪い写真を検出\n' +
      '• スクリーンショット整理 — スクリーンショットをまとめて一掃\n' +
      '• 画面収録の整理 — 忘れられていた大きなファイルを一掃\n' +
      '• チャットメディア整理 — WhatsApp、Telegram などが保存したデータを確認\n' +
      '• 連写の整理 — 連写からベストな1枚を選ぶ\n' +
      '• スマートカテゴリ — 内容の種類で並べ替え、端末内 AI がふつうの言葉で検索\n' +
      '• 大きいファイル検索 — ライブラリ内のいちばん大きいファイルを表示\n' +
      '• Live Photo 変換 — Live Photos を静止画にして容量を節約\n' +
      '• 動画圧縮 — 見られる画質を保ちながら動画を小さく\n' +
      '• 写真圧縮 — 写真を再エンコードして容量を確保\n' +
      '• ストレージダッシュボード — 何が容量を使っているかをひと目で確認\n' +
      '• アクティビティと削減量 — 整理した内容と解放した合計容量を記録\n' +
      '• ホーム画面ウィジェットと Siri ショートカットでワンタップ整理\n' +
      '• ローカル通知による任意の整理リマインダー\n\n' +
      '容量を空ける。プライバシーを守る。スワイプで整理。',
    keywords:
      '写真削除,ストレージ整理,重複写真,スクリーンショット削除,画像圧縮,動画圧縮,空き容量不足,似た写真',
    whatsNew:
      '「ビーチの犬」のようなふつうの言葉で、端末内 AI が写真を検索できます。新しいツールも2つ追加：画面収録とチャットメディア。ライブラリに眠る大きなファイルを整理できます。処理はすべて端末内のまま：アカウント不要、広告なし、サブスクなし。',
  },

  ko: {
    name: 'TidyByte',
    subtitle: '무료 사진 정리, 저장 공간 확보',
    promotionalText:
      '몇 분 만에 공간을 비우세요. 필요 없는 사진은 스와이프로 삭제하고, 중복과 흔들린 사진을 찾고, 동영상을 압축하세요 — 100% 기기 안에서. 광고 없음, 계정 없음.',
    description:
      'TidyByte는 iPhone 사진 보관함을 가장 빠르고 가장 사적인 방법으로 정리합니다. 게다가 완전 무료입니다.\n\n' +
      '「저장 공간이 거의 가득 찼습니다」라는 알림에 지치셨나요? TidyByte는 사진 정리를 실제로 끝까지 해내게 해 줍니다. 왼쪽으로 밀어 삭제, 오른쪽으로 밀어 유지 — 데이팅 앱처럼 사진을 한 장씩 보며 보관함 전체를 살펴보고, 몇 분 만에 기가바이트를 되찾으세요.\n\n' +
      '밀기만이 아니라, TidyByte에는 공간을 잡아먹는 원인을 정확히 짚어 주는 정리 도구가 가득합니다. 완전 중복과 시각적 중복, 거의 같은 유사 사진, 흔들리거나 노출이 나쁜 사진, 스크린샷, 화면 기록, 메신저가 저장한 채팅 미디어, 연사, 그리고 가장 큰 파일까지. Live Photos를 정지 사진으로 바꾸고 동영상과 사진을 압축하면 추억은 그대로 두고 공간을 더 아낄 수 있습니다.\n\n' +
      '사진은 절대 휴대폰을 떠나지 않습니다. TidyByte는 Apple의 Vision 및 Photos 프레임워크를 사용해 처리를 100% 기기에서 수행하며, 일상적인 설명으로 사진을 찾는 로컬 AI 검색도 포함합니다. 서버도, 계정이나 로그인도, 광고도, 어떤 종류의 추적도 없습니다. 무엇도 업로드되지 않습니다.\n\n' +
      'TidyByte는 무료이며 인앱 결제도 페이월도 없습니다. 모든 기능을 누구나 사용할 수 있습니다.\n\n' +
      '기능:\n' +
      '• Tinder 스타일 스와이프로 사진과 동영상 검토 — 밀어서 삭제하거나 유지\n' +
      '• 중복 사진 찾기 — 완전 중복(SHA-256)과 시각적으로 유사한 중복\n' +
      '• 비슷한 사진 — 비슷한 시각에 찍은 거의 같은 사진을 묶어 줌\n' +
      '• 흔들린 사진 감지 — 초점이 맞지 않거나 노출이 나쁜 사진 찾기\n' +
      '• 스크린샷 정리 — 스크린샷을 모아 한 번에 비우기\n' +
      '• 화면 기록 정리 — 잊고 있던 가장 큰 파일 비우기\n' +
      '• 채팅 미디어 정리 — WhatsApp, Telegram 등 메신저가 저장한 파일 확인\n' +
      '• 연사 정리 — 연사에서 가장 좋은 한 장 고르기\n' +
      '• 스마트 카테고리 — 내용 유형별로 정리하고, 온디바이스 AI가 일상적인 말로 검색\n' +
      '• 큰 파일 찾기 — 보관함에서 가장 큰 파일 보여 주기\n' +
      '• Live Photo 변환 — Live Photos를 정지 사진으로 바꿔 공간 절약\n' +
      '• 동영상 압축 — 볼 수 있는 화질은 유지하며 동영상 줄이기\n' +
      '• 사진 압축 — 사진을 다시 인코딩해 공간 되찾기\n' +
      '• 저장 공간 대시보드 — 무엇이 공간을 쓰는지 한눈에 보기\n' +
      '• 활동 및 절약 — 정리한 내용과 되찾은 총 공간 기록\n' +
      '• 홈 화면 위젯과 Siri 단축어로 한 번에 정리\n' +
      '• 로컬 알림으로 받는 선택적 정리 알림\n\n' +
      '공간을 비우세요. 개인정보는 지키세요. 한 번의 스와이프로 정리하세요.',
    keywords:
      '사진삭제,저장공간정리,중복사진,스크린샷삭제,사진압축,동영상압축,용량부족,사진정리앱',
    whatsNew:
      '「해변의 강아지」처럼 일상적인 말로 사진을 검색하세요 — 온디바이스 AI가 처리합니다. 새 도구 두 가지도 추가: 화면 기록과 채팅 미디어로 보관함에 숨은 큰 파일을 정리하세요. 모든 처리는 여전히 기기 안에서: 계정 없음, 광고 없음, 구독 없음.',
  },

  'zh-Hans': {
    name: 'TidyByte',
    subtitle: '免费照片清理，释放空间',
    promotionalText:
      '几分钟释放空间。滑动删掉没用的照片，找出重复和模糊照片，压缩视频——100% 在设备上完成。没有广告，无需账号。',
    description:
      'TidyByte 是清理 iPhone 照片图库最快、最私密的方式——而且完全免费。\n\n' +
      '受够「存储空间几乎已满」了吗？TidyByte 让照片清理真正做完。左滑删除，右滑保留——像约会应用一样一张张看完整个图库，几分钟找回几个 GB。\n\n' +
      '除了滑动，TidyByte 还带了一整套聪明的清理工具，精确找出占空间的元凶：完全重复和视觉重复、几乎一样的相似照片、模糊或曝光不佳的照片、截图、屏幕录制、聊天应用保存的媒体、连拍，以及最大的文件。把 Live Photos 转成静态照片，压缩视频和照片，在不删掉回忆的前提下省下更多空间。\n\n' +
      '你的照片永远不会离开手机。TidyByte 使用 Apple 的 Vision 和 Photos 框架，100% 在设备上处理，还包括用大白话描述就能找到照片的本地 AI 搜索。没有后端、没有账号和登录、没有广告、没有任何跟踪。什么都不会上传。\n\n' +
      'TidyByte 完全免费，没有内购，也没有付费墙。所有功能人人可用。\n\n' +
      '功能:\n' +
      '• Tinder 式滑动浏览照片和视频——滑动决定删除或保留\n' +
      '• 重复照片查找——完全重复（SHA-256）和视觉上相似\n' +
      '• 相似照片——把相近时间拍的几乎一样的照片归组\n' +
      '• 模糊照片检测——找出跑焦和曝光不佳的照片\n' +
      '• 截图清理——把截图一次清掉\n' +
      '• 屏幕录制清理——清掉被遗忘的大文件\n' +
      '• 聊天媒体清理——看看 WhatsApp、Telegram 等应用存了什么\n' +
      '• 连拍清理——从连拍里挑出最好的一张\n' +
      '• 智能分类——按内容类型整理，端侧 AI 支持大白话搜索\n' +
      '• 大文件查找——列出图库中最大的文件\n' +
      '• Live Photo 转换——把 Live Photos 变成静态照片省空间\n' +
      '• 视频压缩——把视频变小，依然能看\n' +
      '• 照片压缩——重新编码照片，找回空间\n' +
      '• 存储面板——一眼看清什么在占空间\n' +
      '• 活动和节省——记录你清理的一切和释放的总空间\n' +
      '• 主屏幕小组件和 Siri 快捷指令，一键开始清理\n' +
      '• 可选的本地通知清理提醒\n\n' +
      '释放空间。守住隐私。滑动清理。',
    keywords:
      '手机内存清理,重复照片,截图清理,照片压缩,视频压缩,相册清理,存储空间不足,照片管理',
    whatsNew:
      '用大白话搜索照片——比如「沙滩上的狗」——由端侧 AI 完成。新增两个工具：屏幕录制和聊天媒体，帮你清掉图库里藏得最深的大文件。所有处理依然在你的设备上：无需账号、没有广告、没有订阅。',
  },
};

const listings = JSON.parse(readFileSync(LISTINGS, 'utf8'));
for (const [lang, entry] of Object.entries(LISTINGS_BY_LANG)) {
  if (!listings[lang]) throw new Error(`listings.json has no ${lang} entry to fill`);
  listings[lang] = { ...listings[lang], ...entry };
}
writeFileSync(LISTINGS, `${JSON.stringify(listings, null, 2)}\n`);
console.log(`listings.json: wrote ${Object.keys(LISTINGS_BY_LANG).join(', ')}`);

// ---------------------------------------------------------------------------
// Deliverable B — landing page
// ---------------------------------------------------------------------------

const SITE_BY_LANG = {
  de: {
    '01 &mdash; How it works': '01 &mdash; So funktioniert es',
    '02 &mdash; Cleanup toolkit': '02 &mdash; Aufräum-Tools',
    '03 &mdash; Storage dashboard': '03 &mdash; Speicher-Dashboard',
    '04 &mdash; Privacy': '04 &mdash; Datenschutz',
    '05 &mdash; Open source': '05 &mdash; Open Source',
    '06 &mdash; FAQ': '06 &mdash; FAQ',
    '07 &mdash; Get the app': '07 &mdash; App holen',
    '64 GB': '64 GB',
    'A donut chart of your library by type, plus the largest files.':
      'Ein Donut-Diagramm deiner Mediathek nach Typ, plus die größten Dateien.',
    'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
      'Ein Live-Donut-Diagramm, das zeigt, wohin dein Speicher geht &mdash; Fotos, Videos, Screenshots, Live Photos, Sonstiges. Antippbare Segmente führen zu genau den Dateien, die du freigeben kannst.',
    'A swipe session in progress &mdash; one photo, one decision.':
      'Eine laufende Swipe-Session &mdash; ein Foto, eine Entscheidung.',
    'AI photo search': 'KI-Fotosuche',
    'Activity &amp; savings': 'Aktivität &amp; Ersparnis',
    'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
      'Die komplette Verarbeitung läuft auf dem Gerät, mit Apples Vision- und Photos-Frameworks.',
    'Are deleted photos gone immediately?': 'Sind gelöschte Fotos sofort weg?',
    'Blurry photos': 'Unscharfe Fotos',
    'Burst photos': 'Serienbilder',
    'Chat media': 'Chat-Medien',
    'Clay illustration of a teal vault keeping smiling photo cards safe.':
      'Clay-Illustration eines türkisfarbenen Tresors, der lächelnde Fotokarten sicher verwahrt.',
    'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
      'Clay-Illustration eines Telefons, das auf grünen Hügeln Fotokarten in ein Sortierfach wirft.',
    'Clean your library in minutes.': 'Räum deine Mediathek in Minuten auf.',
    'Cleanup history': 'Aufräum-Verlauf',
    'Clear them in one pass': 'In einem Durchgang wegräumen',
    'Clear what WhatsApp and Telegram saved.':
      'Räum weg, was WhatsApp und Telegram gespeichert haben.',
    'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
      'Einmal bestätigen und der Speicher ist zurück. Gelöschte Aufnahmen warten 30 Tage in „Zuletzt gelöscht“.',
    'Convert to stills to save space.':
      'In Standbilder umwandeln und Speicher sparen.',
    'Describe a photo in plain words, find it on-device.':
      'Beschreib ein Foto mit einfachen Worten und finde es auf dem Gerät.',
    'Does TidyByte support iPad?': 'Unterstützt TidyByte iPad?',
    'Does TidyByte upload my photos?': 'Lädt TidyByte meine Fotos hoch?',
    'Download TidyByte Free': 'TidyByte kostenlos laden',
    Duplicates: 'Duplikate',
    'Every delete and compression decision, recorded on-device and reviewable.':
      'Jede Lösch- und Kompressionsentscheidung, auf dem Gerät protokolliert und nachprüfbar.',
    'Every kind of clutter, handled.': 'Jede Art von Ballast, im Griff.',
    'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
      'Exakte Duplikate werden über den SHA-256-Hash der Dateidaten erkannt. Fast-Duplikate nutzen Apple Vision Feature Prints, um visuell ähnliche Aufnahmen zu finden.',
    'Find exact copies, byte-for-byte.': 'Finde exakte Kopien, Byte für Byte.',
    'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
      'Kostenlos &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Frequently asked questions.': 'Häufige Fragen.',
    'Group near-identical shots.': 'Gruppiere fast identische Aufnahmen.',
    'How are duplicates detected?': 'Wie werden Duplikate erkannt?',
    'How do I report a bug or request a feature?':
      'Wie melde ich einen Fehler oder wünsche mir eine Funktion?',
    'How it works': 'So funktioniert es',
    'Is there a free trial or subscription?': 'Gibt es eine Testphase oder ein Abo?',
    'Large files': 'Große Dateien',
    'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
      'Links löscht, rechts behält. Jede Entscheidung landet in einer Prüfliste, bevor etwas angefasst wird.',
    'Live Photos': 'Live Photos',
    'New in 1.0.5 &mdash; on-device AI photo search':
      'Neu in 1.0.5 &mdash; KI-Fotosuche auf dem Gerät',
    'No account': 'Kein Konto',
    'No account to create. No subscription to manage. Just one swipe at a time.':
      'Kein Konto anzulegen. Kein Abo zu verwalten. Nur ein Wisch nach dem anderen.',
    'No ads': 'Keine Werbung',
    'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
      'Kein Analyse-SDK, kein Backend, keine Skripte Dritter, kein Tracking &mdash; nirgends.',
    'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
      'Kein Aufräum-Tool rührt die Originale an. Die einzige Operation, die neu kodiert, ist das ausdrückliche Video- oder Foto-Komprimieren, und die Voreinstellung wählst du.',
    'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
      'Nein. Die komplette Verarbeitung läuft lokal auf deinem iPhone mit Apples Photos- und Vision-Frameworks &mdash; kein Analyse-SDK, kein Backend, kein Tracking.',
    'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
      'Eine Karte. Eine Entscheidung. Du räumst Jahre an Fotos weg, bevor dein Kaffee kalt ist.',
    'Open an issue on': 'Ein Problem meldest du auf',
    Other: 'Sonstiges',
    'Photo compression': 'Foto-Kompression',
    'Photos never leave your phone': 'Fotos verlassen dein Telefon nie',
    'Pick the best from a sequence.': 'Wähl das beste aus einer Serie.',
    'Pick where to start': 'Wähl den Einstieg',
    'Re-encode photos to reclaim space.':
      'Fotos neu kodieren, um Speicher zurückzuholen.',
    'Read every line that touches your photos.':
      'Lies jede Zeile, die deine Fotos anfasst.',
    'Read the privacy policy': 'Datenschutzerklärung lesen',
    'Round up and clear them in one pass.':
      'In einem Durchgang einsammeln und wegräumen.',
    'Screen recordings': 'Bildschirmaufnahmen',
    Screenshots: 'Screenshots',
    'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
      'Screenshots, Duplikate, Unschärfe oder deine ganze Mediathek. Jedes Tool öffnet ein Deck aus Fotokarten.',
    'See exactly what&rsquo;s using your space.':
      'Sieh genau, was deinen Speicher belegt.',
    'See how it works': 'So funktioniert es',
    'See what changed &rarr;': 'Sieh, was sich geändert hat &rarr;',
    'Shrink videos, keep them watchable.':
      'Verkleinere Videos und behalte sie anschaubar.',
    'Similar photos': 'Ähnliche Fotos',
    'Smart categories': 'Smarte Kategorien',
    'Sort by content type, browse faster.':
      'Sortiere nach Inhaltstyp, blätter schneller.',
    'Spot out-of-focus and shaky shots.':
      'Erkenne unscharfe und verwackelte Aufnahmen.',
    'Storage breakdown': 'Speicher-Aufschlüsselung',
    Support: 'Support',
    'Surface the biggest space hogs.': 'Zeig die größten Speicherfresser.',
    'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
      'Nach links wischen zum Löschen, nach rechts zum Behalten &mdash; und in Minuten Gigabyte zurückholen. Duplikate, Screenshots, Chat-Medien, unscharfe Aufnahmen und zu große Videos im Griff, Bilder komprimiert, 100 % auf dem Gerät. Keine Werbung, kein Abo, kein Konto.',
    'Swipe to decide': 'Wischen und entscheiden',
    'The best free iPhone storage cleaner and photo cleaner.':
      'Der beste kostenlose Speicher- und Foto-Cleaner für iPhone.',
    'The largest files nobody remembers making.':
      'Die größten Dateien, an die sich niemand erinnert.',
    'The swipe, explained.': 'Der Wisch, erklärt.',
    'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
      'Sie landen im iOS-Album „Zuletzt gelöscht“, wo sie 30 Tage liegen, bevor sie endgültig entfernt werden &mdash; genau wie beim Löschen in der Photos-App.',
    'TidyByte in numbers': 'TidyByte in Zahlen',
    'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
      'TidyByte steht unter MIT-Lizenz. Lies den Quellcode, prüfe die Aussagen, eröffne ein Issue.',
    'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
      'TidyByte ist kostenlos, ohne In-App-Käufe und ohne Paywalls. Jede Funktion steht jedem zur Verfügung. Siehe,',
    'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
      'TidyByte Speicher-Dashboard mit einem Donut-Diagramm aus Fotos, Videos, Screenshots, Live Photos und Sonstigem.',
    'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
      'TidyByte Swipe-Session mit einer Fotokarte auf dem Bildschirm und Löschen- und Behalten-Schaltflächen darunter.',
    'TidyByte swipe-review screen mid-session.':
      'TidyByte Swipe-Ansicht mitten in einer Session.',
    'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
      'TidyByte arbeitet mit deiner kompletten Mediathek, auch mit Dateien, die nur in iCloud liegen. Das System lädt sie bei Bedarf; du kannst auch weiterswischen, ohne zu warten.',
    'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
      'Zwölf Aufräum-Tools plus Speicher-Einblick, Aufräum-Verlauf und KI-Suche auf dem Gerät &mdash; alles läuft auf deinem Gerät. Tippe eins an und sieh, wie es funktioniert.',
    'Video compression': 'Video-Kompression',
    Videos: 'Videos',
    'View on GitHub &rarr;': 'Auf GitHub ansehen &rarr;',
    'We can&rsquo;t see your photos. We don&rsquo;t want to.':
      'Wir können deine Fotos nicht sehen. Wir wollen es auch nicht.',
    'What about iCloud-only photos?':
      'Was ist mit Fotos, die nur in iCloud liegen?',
    'Will it lower the quality of my photos?':
      'Verschlechtert es die Qualität meiner Fotos?',
    'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
      'Ja. TidyByte ist eine Universal-App, die nativ auf iPhone und iPad läuft. Jedes Aufräum-Tool funktioniert auf beiden, die Swipe-Oberfläche passt sich dem größeren Bildschirm des iPad an, und iPad unterstützt alle Ausrichtungen.',
    'Your photos never leave your phone.':
      'Deine Fotos verlassen dein Telefon nie.',
    'bytes uploaded, ever': 'hochgeladene Bytes, jemals',
    'cleanup tools': 'Aufräum-Tools',
    'how it compares to subscription photo cleaners':
      'wie es im Vergleich zu Abo-Foto-Cleanern abschneidet',
    'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
      'zählt mit: alles, was du aufgeräumt hast, ein 30-Tage-Diagramm und der insgesamt freigegebene Speicher. Das Widget auf dem Home-Bildschirm und Siri-Kurzbefehle springen direkt ins Aufräumen.',
    'open source, MIT': 'Open Source, MIT',
    'or use the contact form on the':
      'oder du nutzt das Kontaktformular auf der',
    'page.': 'Seite.',
    'photo library': 'Fotomediathek',
    'to own it outright': 'um es endgültig zu besitzen',
  },

  ja: {
    '01 &mdash; How it works': '01 &mdash; 使い方',
    '02 &mdash; Cleanup toolkit': '02 &mdash; 整理ツール',
    '03 &mdash; Storage dashboard': '03 &mdash; ストレージダッシュボード',
    '04 &mdash; Privacy': '04 &mdash; プライバシー',
    '05 &mdash; Open source': '05 &mdash; オープンソース',
    '06 &mdash; FAQ': '06 &mdash; よくある質問',
    '07 &mdash; Get the app': '07 &mdash; アプリを入手',
    '64 GB': '64 GB',
    'A donut chart of your library by type, plus the largest files.':
      'ライブラリを種類別に示したドーナツグラフと、大きいファイルの一覧。',
    'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
      '容量の内訳をリアルタイムで示すドーナツグラフ &mdash; 写真、動画、スクリーンショット、Live Photos、その他。スライスをタップすると、解放できる項目まで掘り下げられます。',
    'A swipe session in progress &mdash; one photo, one decision.':
      '進行中のスワイプ &mdash; 1枚の写真、1つの判断。',
    'AI photo search': 'AI 写真検索',
    'Activity &amp; savings': 'アクティビティ &amp; 削減量',
    'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
      '処理はすべて Apple の Vision と Photos フレームワークを使い、端末内で行われます。',
    'Are deleted photos gone immediately?': '削除した写真はすぐに消えますか？',
    'Blurry photos': 'ぶれた写真',
    'Burst photos': '連写写真',
    'Chat media': 'チャットメディア',
    'Clay illustration of a teal vault keeping smiling photo cards safe.':
      '笑顔のフォトカードを守る、ティール色の金庫のクレイ風イラスト。',
    'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
      '緑の丘で、スマートフォンがフォトカードを仕分けトレーに投げ入れるクレイ風イラスト。',
    'Clean your library in minutes.': '数分でライブラリを整理。',
    'Cleanup history': '整理履歴',
    'Clear them in one pass': 'まとめて一掃',
    'Clear what WhatsApp and Telegram saved.':
      'WhatsApp と Telegram が保存したデータを一掃。',
    'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
      '一度確認すれば容量が戻ります。削除した写真は「最近削除した項目」に30日間残ります。',
    'Convert to stills to save space.': '静止画に変換して容量を節約。',
    'Describe a photo in plain words, find it on-device.':
      'ふつうの言葉で写真を説明すれば、端末内で見つかります。',
    'Does TidyByte support iPad?': 'TidyByte は iPad に対応していますか？',
    'Does TidyByte upload my photos?': 'TidyByte は写真をアップロードしますか？',
    'Download TidyByte Free': 'TidyByte を無料でダウンロード',
    Duplicates: '重複写真',
    'Every delete and compression decision, recorded on-device and reviewable.':
      'すべての削除と圧縮の判断を端末内に記録し、あとから確認できます。',
    'Every kind of clutter, handled.': 'あらゆるムダを、ひとつずつ。',
    'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
      '完全な重複はファイルデータの SHA-256 ハッシュで照合します。似た写真は Apple Vision の特徴量プリントで、見た目の近い写真を探します。',
    'Find exact copies, byte-for-byte.': '完全なコピーを1バイト単位で検出。',
    'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
      '無料 &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Frequently asked questions.': 'よくある質問。',
    'Group near-identical shots.': 'ほぼ同じ写真をまとめる。',
    'How are duplicates detected?': '重複はどうやって検出しますか？',
    'How do I report a bug or request a feature?':
      '不具合の報告や機能の要望はどうすればいいですか？',
    'How it works': '使い方',
    'Is there a free trial or subscription?':
      '無料トライアルやサブスクはありますか？',
    'Large files': '大きいファイル',
    'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
      '左で削除、右でキープ。選んだ内容はすべて確認リストに入り、実際に削除する前に見直せます。',
    'Live Photos': 'Live Photos',
    'New in 1.0.5 &mdash; on-device AI photo search':
      '1.0.5 の新機能 &mdash; 端末内 AI 写真検索',
    'No account': 'アカウント不要',
    'No account to create. No subscription to manage. Just one swipe at a time.':
      '作るアカウントも、管理するサブスクもありません。スワイプを1回ずつ進めるだけ。',
    'No ads': '広告なし',
    'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
      '解析 SDK もバックエンドも第三者スクリプトもトラッキングもありません &mdash; どこにも。',
    'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
      '写真の元データに手を触れる整理ツールはありません。再エンコードするのは、自分で選んだ動画圧縮と写真圧縮だけです。プリセットも自分で決められます。',
    'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
      'いいえ。処理はすべてお使いの iPhone 上で、Apple の Photos と Vision フレームワークを使ってローカルに行われます &mdash; 解析 SDK もバックエンドもトラッキングもありません。',
    'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
      '1枚のカード。1つの判断。コーヒーが冷める前に、何年分もの写真を整理できます。',
    'Open an issue on': '不具合や要望は',
    Other: 'その他',
    'Photo compression': '写真圧縮',
    'Photos never leave your phone': '写真は端末から出ていきません',
    'Pick the best from a sequence.': '連写からベストな1枚を選ぶ。',
    'Pick where to start': 'はじめるところを選ぶ',
    'Re-encode photos to reclaim space.':
      '写真を再エンコードして容量を取り戻す。',
    'Read every line that touches your photos.':
      '写真に触れるコードを、すべて読めます。',
    'Read the privacy policy': 'プライバシーポリシーを読む',
    'Round up and clear them in one pass.': 'まとめて集めて、一気に一掃。',
    'Screen recordings': '画面収録',
    Screenshots: 'スクリーンショット',
    'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
      'スクリーンショット、重複、ぶれ、ライブラリ全体。どのツールもフォトカードのデッキを開きます。',
    'See exactly what&rsquo;s using your space.':
      '何が容量を使っているかを、正確に。',
    'See how it works': '使い方を見る',
    'See what changed &rarr;': '変更点を見る &rarr;',
    'Shrink videos, keep them watchable.':
      '動画を小さく、見られる画質のまま。',
    'Similar photos': '似た写真',
    'Smart categories': 'スマートカテゴリ',
    'Sort by content type, browse faster.':
      '内容の種類で並べ替えて、すばやく見る。',
    'Spot out-of-focus and shaky shots.':
      'ピントの甘い写真や手ぶれ写真を見つける。',
    'Storage breakdown': '容量の内訳',
    Support: 'サポート',
    'Surface the biggest space hogs.': '容量を最も食うファイルを表示。',
    'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
      '左にスワイプで削除、右にスワイプでキープ &mdash; 数分でギガバイトを取り戻せます。重複、スクリーンショット、チャットメディア、ぶれた写真、大きすぎる動画まで対応し、画像は圧縮。100% 端末内で完結します。広告なし、サブスクなし、アカウントなし。',
    'Swipe to decide': 'スワイプで決める',
    'The best free iPhone storage cleaner and photo cleaner.':
      'iPhone 向け、いちばん使いやすい無料のストレージ整理・写真整理アプリ。',
    'The largest files nobody remembers making.':
      '誰も撮ったことを覚えていない、いちばん大きいファイル。',
    'The swipe, explained.': 'スワイプを、説明します。',
    'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
      'iOS の「最近削除した項目」に入り、30日間そのまま残ってから完全に削除されます &mdash; Photos アプリから削除したときとまったく同じです。',
    'TidyByte in numbers': '数字で見る TidyByte',
    'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
      'TidyByte は MIT ライセンスです。ソースを読み、説明を検証し、issue を立ててください。',
    'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
      'TidyByte は無料で、アプリ内課金もペイウォールもありません。すべての機能を誰でも使えます。詳しくは',
    'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
      '写真、動画、スクリーンショット、Live Photos、その他のドーナツグラフを表示した TidyByte のストレージダッシュボード。',
    'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
      'フォトカードが1枚表示され、下に削除とキープのボタンがある TidyByte のスワイプ画面。',
    'TidyByte swipe-review screen mid-session.':
      'TidyByte のスワイプ確認画面（セッション途中）。',
    'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
      'TidyByte は iCloud にしかない項目も含めて、ライブラリ全体を扱えます。必要に応じてシステムがダウンロードしますし、待たずに次へスワイプしてもかまいません。',
    'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
      '12 の整理ツールに、容量の内訳、整理履歴、端末内 AI 検索 &mdash; すべて端末上で動きます。どれか1つをタップすると使い方がわかります。',
    'Video compression': '動画圧縮',
    Videos: '動画',
    'View on GitHub &rarr;': 'GitHub で見る &rarr;',
    'We can&rsquo;t see your photos. We don&rsquo;t want to.':
      '私たちはあなたの写真を見られません。見たいとも思いません。',
    'What about iCloud-only photos?':
      'iCloud にしかない写真はどうなりますか？',
    'Will it lower the quality of my photos?': '写真の画質は落ちますか？',
    'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
      'はい。TidyByte は iPhone と iPad でネイティブに動くユニバーサルアプリです。どの整理ツールも両方で使え、スワイプ画面は iPad の広い画面に合わせて表示され、iPad はすべての向きに対応します。',
    'Your photos never leave your phone.': '写真は端末から出ていきません。',
    'bytes uploaded, ever': 'これまでにアップロードされたバイト数',
    'cleanup tools': '整理ツール',
    'how it compares to subscription photo cleaners':
      'サブスク型の写真整理アプリとの比較をご覧ください',
    'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
      'すべてを記録します：整理した内容、30日間のグラフ、解放した合計容量。ホーム画面ウィジェットと Siri ショートカットから、そのまま整理を始められます。',
    'open source, MIT': 'オープンソース、MIT',
    'or use the contact form on the': 'で Issue を作成するか、',
    'page.': 'ページのお問い合わせフォームをご利用ください。',
    'photo library': '写真ライブラリ',
    'to own it outright': 'ずっと自分のものにできる',
  },

  ko: {
    '01 &mdash; How it works': '01 &mdash; 사용 방법',
    '02 &mdash; Cleanup toolkit': '02 &mdash; 정리 도구',
    '03 &mdash; Storage dashboard': '03 &mdash; 저장 공간 대시보드',
    '04 &mdash; Privacy': '04 &mdash; 개인정보 보호',
    '05 &mdash; Open source': '05 &mdash; 오픈 소스',
    '06 &mdash; FAQ': '06 &mdash; 자주 묻는 질문',
    '07 &mdash; Get the app': '07 &mdash; 앱 받기',
    '64 GB': '64 GB',
    'A donut chart of your library by type, plus the largest files.':
      '보관함을 종류별로 보여 주는 도넛 차트와 가장 큰 파일 목록.',
    'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
      '저장 공간이 어디로 가는지 실시간으로 보여 주는 도넛 차트 &mdash; 사진, 동영상, 스크린샷, Live Photos, 기타. 조각을 탭하면 비울 수 있는 항목까지 확인할 수 있습니다.',
    'A swipe session in progress &mdash; one photo, one decision.':
      '진행 중인 스와이프 &mdash; 사진 한 장, 결정 하나.',
    'AI photo search': 'AI 사진 검색',
    'Activity &amp; savings': '활동 &amp; 절약',
    'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
      '모든 처리는 Apple의 Vision 및 Photos 프레임워크를 사용해 기기 안에서 이루어집니다.',
    'Are deleted photos gone immediately?': '삭제한 사진은 바로 사라지나요?',
    'Blurry photos': '흔들린 사진',
    'Burst photos': '연사 사진',
    'Chat media': '채팅 미디어',
    'Clay illustration of a teal vault keeping smiling photo cards safe.':
      '웃는 포토 카드를 안전하게 지키는 청록색 금고의 클레이 일러스트.',
    'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
      '푸른 언덕에서 휴대폰이 포토 카드를 분류 트레이에 던져 넣는 클레이풍 일러스트.',
    'Clean your library in minutes.': '몇 분 만에 보관함을 정리하세요.',
    'Cleanup history': '정리 기록',
    'Clear them in one pass': '한 번에 비우기',
    'Clear what WhatsApp and Telegram saved.':
      'WhatsApp과 Telegram이 저장한 파일을 비우세요.',
    'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
      '한 번만 확인하면 공간이 돌아옵니다. 삭제한 사진은 최근 삭제된 항목에 30일 동안 남습니다.',
    'Convert to stills to save space.': '정지 사진으로 변환해 공간을 아끼세요.',
    'Describe a photo in plain words, find it on-device.':
      '사진을 일상적인 말로 설명하면 기기 안에서 찾아 줍니다.',
    'Does TidyByte support iPad?': 'TidyByte는 iPad를 지원하나요?',
    'Does TidyByte upload my photos?': 'TidyByte가 제 사진을 업로드하나요?',
    'Download TidyByte Free': 'TidyByte 무료 다운로드',
    Duplicates: '중복 사진',
    'Every delete and compression decision, recorded on-device and reviewable.':
      '모든 삭제와 압축 결정을 기기에 기록하고 다시 확인할 수 있습니다.',
    'Every kind of clutter, handled.': '온갖 잡동사니, 전부 처리.',
    'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
      '완전한 중복은 파일 데이터의 SHA-256 해시로 찾습니다. 거의 같은 사진은 Apple Vision 특징 프린트로 시각적으로 비슷한 사진을 찾습니다.',
    'Find exact copies, byte-for-byte.': '완전히 같은 사본을 바이트 단위로 찾습니다.',
    'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
      '무료 &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Frequently asked questions.': '자주 묻는 질문.',
    'Group near-identical shots.': '거의 같은 사진을 묶어 줍니다.',
    'How are duplicates detected?': '중복은 어떻게 찾나요?',
    'How do I report a bug or request a feature?':
      '버그를 알리거나 기능을 요청하려면 어떻게 하나요?',
    'How it works': '사용 방법',
    'Is there a free trial or subscription?': '무료 체험이나 구독이 있나요?',
    'Large files': '큰 파일',
    'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
      '왼쪽은 삭제, 오른쪽은 유지. 모든 선택은 검토 목록에 담겨, 무엇이든 건드리기 전에 확인할 수 있습니다.',
    'Live Photos': 'Live Photos',
    'New in 1.0.5 &mdash; on-device AI photo search':
      '1.0.5의 새로운 기능 &mdash; 온디바이스 AI 사진 검색',
    'No account': '계정 없음',
    'No account to create. No subscription to manage. Just one swipe at a time.':
      '만들 계정도, 관리할 구독도 없습니다. 한 번에 한 장씩 넘기면 됩니다.',
    'No ads': '광고 없음',
    'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
      '분석 SDK도, 서버도, 서드파티 스크립트도, 추적도 없습니다 &mdash; 어디에도.',
    'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
      '어떤 정리 도구도 원본을 건드리지 않습니다. 다시 인코딩하는 작업은 직접 실행하는 동영상 압축과 사진 압축뿐이고, 프리셋도 직접 고릅니다.',
    'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
      '아니요. 모든 처리는 Apple의 Photos 및 Vision 프레임워크를 사용해 iPhone에서 로컬로 이루어집니다 &mdash; 분석 SDK도, 서버도, 추적도 없습니다.',
    'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
      '카드 한 장. 결정 하나. 커피가 식기 전에 몇 년치 사진을 정리합니다.',
    'Open an issue on': '버그나 기능 요청은',
    Other: '기타',
    'Photo compression': '사진 압축',
    'Photos never leave your phone': '사진은 휴대폰을 떠나지 않습니다',
    'Pick the best from a sequence.': '연사에서 가장 좋은 한 장을 고르세요.',
    'Pick where to start': '시작할 곳 고르기',
    'Re-encode photos to reclaim space.':
      '사진을 다시 인코딩해 공간을 되찾으세요.',
    'Read every line that touches your photos.':
      '사진을 건드리는 모든 코드를 읽어 보세요.',
    'Read the privacy policy': '개인정보 처리방침 보기',
    'Round up and clear them in one pass.': '한 번에 모아서 비우세요.',
    'Screen recordings': '화면 기록',
    Screenshots: '스크린샷',
    'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
      '스크린샷, 중복, 흔들림, 또는 보관함 전체. 어떤 도구든 포토 카드 덱이 열립니다.',
    'See exactly what&rsquo;s using your space.':
      '무엇이 공간을 쓰는지 정확히 확인하세요.',
    'See how it works': '사용 방법 보기',
    'See what changed &rarr;': '무엇이 바뀌었는지 보기 &rarr;',
    'Shrink videos, keep them watchable.':
      '동영상을 줄이고, 볼 수 있는 화질은 그대로.',
    'Similar photos': '비슷한 사진',
    'Smart categories': '스마트 카테고리',
    'Sort by content type, browse faster.':
      '내용 유형별로 정리해 더 빠르게 찾아보세요.',
    'Spot out-of-focus and shaky shots.':
      '초점이 흐리거나 손떨림이 있는 사진을 찾아냅니다.',
    'Storage breakdown': '저장 공간 분석',
    Support: '지원',
    'Surface the biggest space hogs.':
      '공간을 가장 많이 차지하는 파일을 보여 줍니다.',
    'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
      '왼쪽으로 밀어 삭제하고 오른쪽으로 밀어 남기세요 &mdash; 몇 분 만에 기가바이트를 되찾습니다. 중복, 스크린샷, 채팅 미디어, 흔들린 사진, 너무 큰 동영상까지 처리하고 사진은 압축합니다. 100% 기기 안에서. 광고 없음, 구독 없음, 계정 없음.',
    'Swipe to decide': '스와이프로 결정',
    'The best free iPhone storage cleaner and photo cleaner.':
      'iPhone을 위한 최고의 무료 저장 공간·사진 정리 앱.',
    'The largest files nobody remembers making.':
      '아무도 만든 기억이 없는 가장 큰 파일들.',
    'The swipe, explained.': '스와이프, 이렇게 작동합니다.',
    'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
      'iOS의 「최근 삭제된 항목」 앨범으로 가서 30일 동안 있다가 완전히 삭제됩니다 &mdash; Photos 앱에서 삭제할 때와 똑같습니다.',
    'TidyByte in numbers': '숫자로 보는 TidyByte',
    'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
      'TidyByte는 MIT 라이선스입니다. 소스를 읽고, 주장을 검증하고, 이슈를 남겨 주세요.',
    'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
      'TidyByte는 무료이며 인앱 결제도 페이월도 없습니다. 모든 기능을 누구나 쓸 수 있습니다. 확인해 보세요:',
    'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
      '사진, 동영상, 스크린샷, Live Photos, 기타를 도넛 차트로 보여 주는 TidyByte 저장 공간 대시보드.',
    'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
      '사진 카드 한 장과 그 아래 삭제·유지 버튼이 있는 TidyByte 스와이프 화면.',
    'TidyByte swipe-review screen mid-session.':
      'TidyByte 스와이프 검토 화면(세션 진행 중).',
    'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
      'TidyByte는 iCloud에만 있는 항목을 포함해 보관함 전체에서 작동합니다. 필요할 때 시스템이 내려받으며, 기다리지 않고 다음으로 넘겨도 됩니다.',
    'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
      '정리 도구 12가지에 저장 공간 분석, 정리 기록, 온디바이스 AI 검색까지 &mdash; 모두 기기에서 실행됩니다. 하나를 탭하면 사용법을 볼 수 있습니다.',
    'Video compression': '동영상 압축',
    Videos: '동영상',
    'View on GitHub &rarr;': 'GitHub에서 보기 &rarr;',
    'We can&rsquo;t see your photos. We don&rsquo;t want to.':
      '저희는 당신의 사진을 볼 수 없습니다. 볼 생각도 없습니다.',
    'What about iCloud-only photos?':
      'iCloud에만 있는 사진은 어떻게 되나요?',
    'Will it lower the quality of my photos?': '사진 화질이 떨어지나요?',
    'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
      '네. TidyByte는 iPhone과 iPad에서 네이티브로 실행되는 유니버설 앱입니다. 모든 정리 도구가 두 기기에서 작동하고, 스와이프 화면은 iPad의 넓은 화면에 맞춰 표시되며, iPad는 모든 방향을 지원합니다.',
    'Your photos never leave your phone.': '사진은 휴대폰을 떠나지 않습니다.',
    'bytes uploaded, ever': '지금까지 업로드된 바이트',
    'cleanup tools': '정리 도구',
    'how it compares to subscription photo cleaners':
      '구독형 사진 정리 앱과의 비교',
    'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
      '모두 기록합니다: 정리한 내용, 30일 차트, 되찾은 총 공간까지. 홈 화면 위젯과 Siri 단축어로 바로 정리를 시작할 수 있습니다.',
    'open source, MIT': '오픈 소스, MIT',
    'or use the contact form on the': '이슈로 남기거나',
    'page.': '페이지의 문의 양식을 이용하세요.',
    'photo library': '사진 보관함',
    'to own it outright': '완전히 내 것으로',
  },

  'zh-Hans': {
    '01 &mdash; How it works': '01 &mdash; 使用方式',
    '02 &mdash; Cleanup toolkit': '02 &mdash; 清理工具箱',
    '03 &mdash; Storage dashboard': '03 &mdash; 存储面板',
    '04 &mdash; Privacy': '04 &mdash; 隐私',
    '05 &mdash; Open source': '05 &mdash; 开源',
    '06 &mdash; FAQ': '06 &mdash; 常见问题',
    '07 &mdash; Get the app': '07 &mdash; 获取应用',
    '64 GB': '64 GB',
    'A donut chart of your library by type, plus the largest files.':
      '按类型展示图库的环形图，以及最大的文件。',
    'A live donut chart of where your storage goes &mdash; photos, videos, screenshots, Live Photos, other. Tappable slices drill into the exact items you can free up.':
      '实时环形图，显示空间都去了哪里 &mdash; 照片、视频、截图、Live Photos、其他。点击扇区即可查看可以释放的具体项目。',
    'A swipe session in progress &mdash; one photo, one decision.':
      '正在进行的一次滑动 &mdash; 一张照片，一个决定。',
    'AI photo search': 'AI 照片搜索',
    'Activity &amp; savings': '活动 &amp; 节省',
    'All processing happens on-device using Apple&rsquo;s Vision and Photos frameworks.':
      '所有处理都在设备上完成，使用 Apple 的 Vision 和 Photos 框架。',
    'Are deleted photos gone immediately?': '删除的照片会立刻消失吗？',
    'Blurry photos': '模糊照片',
    'Burst photos': '连拍照片',
    'Chat media': '聊天媒体',
    'Clay illustration of a teal vault keeping smiling photo cards safe.':
      '黏土插画：一个青色保险箱守护着笑脸照片卡。',
    'Clay-style illustration of a phone tossing photo cards into a sorting tray on green hills.':
      '黏土风格插画：手机在绿色山丘上把照片卡投进分类托盘。',
    'Clean your library in minutes.': '几分钟清理完你的图库。',
    'Cleanup history': '清理记录',
    'Clear them in one pass': '一次清空',
    'Clear what WhatsApp and Telegram saved.':
      '清掉 WhatsApp 和 Telegram 保存的内容。',
    'Confirm once and the space comes back. Deleted shots wait 30 days in Recently Deleted.':
      '确认一次，空间就回来了。删除的照片会在「最近删除」里等 30 天。',
    'Convert to stills to save space.': '转成静态照片，省出空间。',
    'Describe a photo in plain words, find it on-device.':
      '用大白话描述一张照片，在设备上找到它。',
    'Does TidyByte support iPad?': 'TidyByte 支持 iPad 吗？',
    'Does TidyByte upload my photos?': 'TidyByte 会上传我的照片吗？',
    'Download TidyByte Free': '免费下载 TidyByte',
    Duplicates: '重复照片',
    'Every delete and compression decision, recorded on-device and reviewable.':
      '每一次删除和压缩决定都记录在设备上，随时可查。',
    'Every kind of clutter, handled.': '各种杂物，逐一处理。',
    'Exact duplicates are matched by SHA-256 hash of the file data. Near-duplicates use Apple Vision feature prints to find visually similar shots.':
      '完全重复的文件通过文件数据的 SHA-256 哈希匹配。近似重复使用 Apple Vision 特征打印找出视觉上相似的照片。',
    'Find exact copies, byte-for-byte.': '逐字节找出完全相同的副本。',
    'Free &middot; iPhone &amp; iPad &middot; iOS 17+':
      '免费 &middot; iPhone &amp; iPad &middot; iOS 17+',
    'Frequently asked questions.': '常见问题。',
    'Group near-identical shots.': '把几乎一样的照片归到一起。',
    'How are duplicates detected?': '重复照片是怎么检测的？',
    'How do I report a bug or request a feature?':
      '怎么反馈问题或提需求？',
    'How it works': '使用方式',
    'Is there a free trial or subscription?': '有免费试用或订阅吗？',
    'Large files': '大文件',
    'Left deletes, right keeps. Every choice lands in a review list before anything is touched.':
      '左滑删除，右滑保留。每个选择都会先进入待确认列表，之后才会真正动手。',
    'Live Photos': 'Live Photos',
    'New in 1.0.5 &mdash; on-device AI photo search':
      '1.0.5 新功能 &mdash; 端侧 AI 照片搜索',
    'No account': '无需账号',
    'No account to create. No subscription to manage. Just one swipe at a time.':
      '不用注册账号，不用管理订阅。一次滑一张就够了。',
    'No ads': '没有广告',
    'No analytics SDK, no backend, no third-party scripts, no tracking &mdash; anywhere.':
      '没有分析 SDK、没有后端、没有第三方脚本、没有跟踪 &mdash; 任何地方都没有。',
    'No cleanup tool touches the originals. The only operation that re-encodes is the explicit Video Compression or Photo Compression tool, and you choose the preset.':
      '没有任何清理工具会改动原图。唯一会重新编码的是你主动使用的视频压缩和照片压缩，而且预设由你选择。',
    'No. All processing happens locally on your iPhone using Apple&rsquo;s Photos and Vision frameworks &mdash; no analytics SDK, no backend, no tracking.':
      '不会。所有处理都在你的 iPhone 本地完成，使用 Apple 的 Photos 和 Vision 框架 &mdash; 没有分析 SDK、没有后端、没有跟踪。',
    'One card. One decision. You&rsquo;ll clear years of photos before your coffee gets cold.':
      '一张卡，一个决定。咖啡还没凉，你就能清掉几年的照片。',
    'Open an issue on': '问题或需求请在',
    Other: '其他',
    'Photo compression': '照片压缩',
    'Photos never leave your phone': '照片从不离开你的手机',
    'Pick the best from a sequence.': '从连拍里挑出最好的一张。',
    'Pick where to start': '选择从哪里开始',
    'Re-encode photos to reclaim space.': '重新编码照片，找回空间。',
    'Read every line that touches your photos.':
      '读懂每一行接触照片的代码。',
    'Read the privacy policy': '阅读隐私政策',
    'Round up and clear them in one pass.': '一次收集，一次清空。',
    'Screen recordings': '屏幕录制',
    Screenshots: '截图',
    'Screenshots, duplicates, blur, or your whole library. Each tool opens a deck of photo cards.':
      '截图、重复、模糊，或者整个图库。每个工具都会打开一叠照片卡。',
    'See exactly what&rsquo;s using your space.':
      '看清楚是什么占用了你的空间。',
    'See how it works': '看看怎么用',
    'See what changed &rarr;': '看看更新了什么 &rarr;',
    'Shrink videos, keep them watchable.':
      '压缩视频，依然好看。',
    'Similar photos': '相似照片',
    'Smart categories': '智能分类',
    'Sort by content type, browse faster.':
      '按内容类型排序，浏览更快。',
    'Spot out-of-focus and shaky shots.': '找出跑焦和手抖的照片。',
    'Storage breakdown': '存储构成',
    Support: '支持',
    'Surface the biggest space hogs.': '找出最占空间的文件。',
    'Swipe left to delete, swipe right to keep &mdash; and reclaim gigabytes in minutes. Duplicates, screenshots, chat media, blurry shots and oversized videos handled, images compressed, 100% on-device. No ads, no subscription, no account.':
      '左滑删除，右滑保留 &mdash; 几分钟就能找回几个 GB。重复照片、截图、聊天媒体、模糊照片和超大视频一并处理，图片压缩，100% 在设备上完成。没有广告，没有订阅，没有账号。',
    'Swipe to decide': '滑动决定',
    'The best free iPhone storage cleaner and photo cleaner.':
      '最好用的免费 iPhone 存储清理与照片清理应用。',
    'The largest files nobody remembers making.':
      '没人记得拍过的那些最大的文件。',
    'The swipe, explained.': '滑动是怎么回事。',
    'They go to the iOS Recently Deleted album, where they sit for 30 days before being permanently removed &mdash; exactly like deleting from the Photos app.':
      '它们会进入 iOS 的「最近删除」相簿，在那里停留 30 天后被永久删除 &mdash; 和在 Photos 应用里删除完全一样。',
    'TidyByte in numbers': '用数字看 TidyByte',
    'TidyByte is MIT-licensed. Read the source, verify the claims, file an issue.':
      'TidyByte 采用 MIT 许可。读源码，验证说法，提交 issue。',
    'TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to every user. See':
      'TidyByte 完全免费，没有内购，没有付费墙。所有功能对所有人开放。查看',
    'TidyByte storage dashboard with a donut chart of photos, videos, screenshots, Live Photos, and other.':
      'TidyByte 存储面板，用环形图展示照片、视频、截图、Live Photos 和其他。',
    'TidyByte swipe session with one photo card on screen and delete and keep buttons below.':
      'TidyByte 滑动界面，屏幕上是一张照片卡，下方是删除和保留按钮。',
    'TidyByte swipe-review screen mid-session.':
      'TidyByte 滑动浏览界面（会话进行中）。',
    'TidyByte works with your full library, including assets stored only in iCloud. The system downloads them as needed; you can also swipe past without waiting.':
      'TidyByte 支持整个图库，包括只存在 iCloud 里的项目。系统会按需下载；你也可以不等下载直接滑过去。',
    'Twelve cleanup tools plus storage insight, cleanup history and on-device AI search &mdash; all running on your device. Tap any one to see how it works.':
      '十二个清理工具，加上存储构成、清理记录和端侧 AI 搜索 &mdash; 全部在你的设备上运行。点开任意一个就能看到它怎么工作。',
    'Video compression': '视频压缩',
    Videos: '视频',
    'View on GitHub &rarr;': '在 GitHub 上查看 &rarr;',
    'We can&rsquo;t see your photos. We don&rsquo;t want to.':
      '我们看不到你的照片。我们也不想看。',
    'What about iCloud-only photos?': '只存在 iCloud 的照片呢？',
    'Will it lower the quality of my photos?': '会降低我的照片画质吗？',
    'Yes. TidyByte is a universal app that runs natively on iPhone and iPad. Every cleanup tool works on both, the swipe interface adapts to the iPad&rsquo;s larger screen, and iPad supports all orientations.':
      '会。TidyByte 是一款通用应用，在 iPhone 和 iPad 上都原生运行。所有清理工具在两者上都能用，滑动界面会适配 iPad 更大的屏幕，iPad 支持所有方向。',
    'Your photos never leave your phone.': '你的照片从不离开你的手机。',
    'bytes uploaded, ever': '至今上传的字节数',
    'cleanup tools': '清理工具',
    'how it compares to subscription photo cleaners':
      '它和订阅制照片清理应用的对比',
    'keeps score: everything you&rsquo;ve cleaned, a 30-day chart, and the total space you&rsquo;ve freed. The Home Screen widget and Siri shortcuts jump straight into a cleanup.':
      '全都记着：你清理过的一切、30 天图表，以及释放的总空间。主屏幕小组件和 Siri 快捷指令可以直接开始清理。',
    'open source, MIT': '开源，MIT',
    'or use the contact form on the': '上提交 issue，或使用',
    'page.': '页面的联系表单。',
    'photo library': '照片图库',
    'to own it outright': '一次买断',
  },
};

const source = JSON.parse(readFileSync(SITE_STRINGS, 'utf8'));
mkdirSync(OUT_DIR, { recursive: true });

for (const [lang, map] of Object.entries(SITE_BY_LANG)) {
  const ordered = {};
  const missing = [];
  for (const key of source.strings) {
    const value = map[key];
    if (typeof value !== 'string') missing.push(key);
    else ordered[key] = value;
  }
  const extra = Object.keys(map).filter((k) => !source.strings.includes(k));
  if (missing.length > 0) {
    throw new Error(`${lang}: ${missing.length} missing key(s):\n  ${missing.join('\n  ')}`);
  }
  if (extra.length > 0) {
    throw new Error(`${lang}: ${extra.length} key(s) not in site-strings.json:\n  ${extra.join('\n  ')}`);
  }
  const path = join(OUT_DIR, `${lang}.json`);
  writeFileSync(path, `${JSON.stringify(ordered, null, 2)}\n`);
  console.log(`site-translations/${lang}.json: ${Object.keys(ordered).length} keys`);
}
