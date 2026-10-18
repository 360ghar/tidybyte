// Batch 7 insertion: the 57 keys that were previously built as plain Swift
// `String` values and so never reached the catalog. Adds de/ja/ko/zh-Hans.
//
// Textual insertion so the hand-formatted `plurals` block is never
// re-serialized. The `strings` block is re-emitted in full with the same
// 4-space indent and default code-unit sort the file already uses.
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))

/** The 57 English keys, in the order the catalog lists them. */
const KEYS = [
  "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.",
  "A lens smudge may have reduced image clarity.",
  "Allow Photo Access?",
  "Already compressed",
  "Cancelled.",
  "Choose albums or change your filters.",
  "Couldn't load the video (it may still be in iCloud). Please try again.",
  "Dark",
  "Export failed: %@",
  "Exported file was empty.",
  "Failed to create export session.",
  "Failed to load the photo.",
  "Failed to re-encode the photo.",
  "Failed to read file size.",
  "Light",
  "Local AI could not interpret this search.",
  "Local AI is unavailable.",
  "No matching photos",
  "No photos in this category.",
  "No screen recordings were found.",
  "Not Now",
  "Nothing to free on iPhone",
  "Open TidyByte to refresh",
  "Photo Access Is Off",
  "Photo Access Is On",
  "Photo Access Is Restricted",
  "Photo not found.",
  "Photo size unknown (iCloud-only) — skipped.",
  "Review whether you still need this screen recording.",
  "Review whether you still need this screenshot.",
  "Save failed: %@",
  "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.",
  "Searching labels across all scanned categories.",
  "Size unknown (iCloud-only) — skipped",
  "Some requested concepts were not found in this scan. Try a simpler content search.",
  "Submit a content search or try different words.",
  "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.",
  "This item can't be compressed as a photo.",
  "This item uses %@; review whether you need it.",
  "This language is not supported by local AI.",
  "This photo has very high brightness.",
  "This photo has very low brightness.",
  "This photo may be out of focus.",
  "This photo received a low visual-quality score.",
  "TidyByte Needs Your Photos",
  "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.",
  "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.",
  "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.",
  "Unknown error",
  "Up to %@ to free on iPhone",
  "Updated %lldd ago",
  "Use 300 characters or fewer.",
  "Using label search across scanned photos.",
  "Video not found.",
  "Video size unknown (iCloud-only) — skipped.",
  "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.",
  "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.",
]

const translations = {
  de: {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Eine Einschränkung durch Screen Time oder Geräteverwaltung blockiert den Fotozugriff. Der Schalter „Fotos“ in den Einstellungen kann das nicht ändern — zuerst muss diese Einschränkung aufgehoben werden.",
    "A lens smudge may have reduced image clarity.": "Eine verschmutzte Linse kann die Bildschärfe beeinträchtigt haben.",
    "Allow Photo Access?": "Fotozugriff erlauben?",
    "Already compressed": "Bereits komprimiert",
    "Cancelled.": "Abgebrochen.",
    "Choose albums or change your filters.": "Wähle Alben aus oder ändere deine Filter.",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "Das Video konnte nicht geladen werden (es ist möglicherweise noch in iCloud). Versuche es erneut.",
    "Dark": "Dunkel",
    "Export failed: %@": "Export fehlgeschlagen: %@",
    "Exported file was empty.": "Die exportierte Datei war leer.",
    "Failed to create export session.": "Exportsitzung konnte nicht erstellt werden.",
    "Failed to load the photo.": "Das Foto konnte nicht geladen werden.",
    "Failed to re-encode the photo.": "Das Foto konnte nicht neu kodiert werden.",
    "Failed to read file size.": "Dateigröße konnte nicht gelesen werden.",
    "Light": "Hell",
    "Local AI could not interpret this search.": "Die lokale KI konnte diese Suche nicht interpretieren.",
    "Local AI is unavailable.": "Lokale KI ist nicht verfügbar.",
    "No matching photos": "Keine passenden Fotos",
    "No photos in this category.": "In dieser Kategorie sind keine Fotos.",
    "No screen recordings were found.": "Es wurden keine Bildschirmaufnahmen gefunden.",
    "Not Now": "Nicht jetzt",
    "Nothing to free on iPhone": "Auf dem iPhone nichts freizugeben",
    "Open TidyByte to refresh": "TidyByte öffnen zum Aktualisieren",
    "Photo Access Is Off": "Fotozugriff ist deaktiviert",
    "Photo Access Is On": "Fotozugriff ist aktiviert",
    "Photo Access Is Restricted": "Fotozugriff ist eingeschränkt",
    "Photo not found.": "Foto nicht gefunden.",
    "Photo size unknown (iCloud-only) — skipped.": "Fotogröße unbekannt (nur in iCloud) — übersprungen.",
    "Review whether you still need this screen recording.": "Prüfe, ob du diese Bildschirmaufnahme noch brauchst.",
    "Review whether you still need this screenshot.": "Prüfe, ob du diesen Screenshot noch brauchst.",
    "Save failed: %@": "Speichern fehlgeschlagen: %@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "Die Suche unterstützt nur sichtbare Inhalte, etwa Hunde am Strand. Datumsangaben, Orte, Namen und Text werden nicht erfasst.",
    "Searching labels across all scanned categories.": "Labels werden in allen gescannten Kategorien durchsucht.",
    "Size unknown (iCloud-only) — skipped": "Größe unbekannt (nur in iCloud) — übersprungen",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "Einige gesuchte Begriffe wurden in diesem Scan nicht gefunden. Versuche eine einfachere Inhaltssuche.",
    "Submit a content search or try different words.": "Starte eine Inhaltssuche oder versuche andere Wörter.",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "Diese Wörter ergeben keine unterstützte Labelsuche. Versuche sichtbare Inhalte wie Hund oder Strand. Die Labelsuche unterstützt keine Datumsangaben, Namen oder Ausschlüsse.",
    "This item can't be compressed as a photo.": "Dieses Objekt kann nicht als Foto komprimiert werden.",
    "This item uses %@; review whether you need it.": "Dieses Objekt belegt %@; prüfe, ob du es brauchst.",
    "This language is not supported by local AI.": "Diese Sprache wird von der lokalen KI nicht unterstützt.",
    "This photo has very high brightness.": "Dieses Foto ist sehr hell.",
    "This photo has very low brightness.": "Dieses Foto ist sehr dunkel.",
    "This photo may be out of focus.": "Dieses Foto ist möglicherweise unscharf.",
    "This photo received a low visual-quality score.": "Die Bildqualität dieses Fotos wurde niedrig bewertet.",
    "TidyByte Needs Your Photos": "TidyByte benötigt deine Fotos",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "TidyByte sieht nur die Fotos, die du ausgewählt hast. Füge jederzeit weitere hinzu, wenn der Rest deiner Mediathek geprüft werden soll.",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByte kann deine Mediathek auf diesem Gerät prüfen. Nichts wird hochgeladen, und nichts ändert sich ohne deine Zustimmung.",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByte prüft deine Mediathek auf diesem Gerät, um zu finden, was sich aufräumen lässt. Nichts wird hochgeladen, und nichts ändert sich ohne deine Zustimmung. iOS fragt als Nächstes nach der Berechtigung.",
    "Unknown error": "Unbekannter Fehler",
    "Up to %@ to free on iPhone": "Auf dem iPhone bis zu %@ freigeben",
    "Updated %lldd ago": "Vor %lld Tg. aktualisiert",
    "Use 300 characters or fewer.": "Verwende höchstens 300 Zeichen.",
    "Using label search across scanned photos.": "Labelsuche über die gescannten Fotos wird verwendet.",
    "Video not found.": "Video nicht gefunden.",
    "Video size unknown (iCloud-only) — skipped.": "Videogröße unbekannt (nur in iCloud) — übersprungen.",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOS fragt nur einmal nach dem Fotozugriff, und das ist diese Abfrage. Danach prüft TidyByte deine Mediathek auf diesem Gerät. Nichts wird hochgeladen, und nichts ändert sich ohne deine Prüfung.",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOS blockiert für TidyByte den Zugriff auf deine Mediathek und wird nicht erneut fragen. Der einzige Weg zurück führt über die Einstellungen — aktiviere dort den Fotozugriff, und hier funktioniert wieder alles.",
  },

  ja: {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Screen Timeまたはデバイス管理の制限が写真へのアクセスをブロックしています。「設定」の「写真」スイッチでは変更できません — 先にその制限を解除する必要があります。",
    "A lens smudge may have reduced image clarity.": "レンズの汚れにより、画像の鮮明さが低下している可能性があります。",
    "Allow Photo Access?": "写真へのアクセスを許可しますか?",
    "Already compressed": "圧縮済み",
    "Cancelled.": "キャンセルしました。",
    "Choose albums or change your filters.": "アルバムを選択するか、フィルタを変更してください。",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "ビデオを読み込めませんでした（まだiCloudにある可能性があります）。もう一度お試しください。",
    "Dark": "ダーク",
    "Export failed: %@": "書き出しに失敗しました: %@",
    "Exported file was empty.": "書き出したファイルが空でした。",
    "Failed to create export session.": "書き出しセッションを作成できませんでした。",
    "Failed to load the photo.": "写真を読み込めませんでした。",
    "Failed to re-encode the photo.": "写真を再エンコードできませんでした。",
    "Failed to read file size.": "ファイルサイズを読み取れませんでした。",
    "Light": "ライト",
    "Local AI could not interpret this search.": "ローカルAIはこの検索を解釈できませんでした。",
    "Local AI is unavailable.": "ローカルAIは利用できません。",
    "No matching photos": "一致する写真はありません",
    "No photos in this category.": "このカテゴリには写真がありません。",
    "No screen recordings were found.": "画面収録が見つかりませんでした。",
    "Not Now": "今はしない",
    "Nothing to free on iPhone": "iPhoneで空けられるものはありません",
    "Open TidyByte to refresh": "TidyByteを開いて更新",
    "Photo Access Is Off": "写真へのアクセスはオフです",
    "Photo Access Is On": "写真へのアクセスはオンです",
    "Photo Access Is Restricted": "写真へのアクセスが制限されています",
    "Photo not found.": "写真が見つかりません。",
    "Photo size unknown (iCloud-only) — skipped.": "写真のサイズが不明（iCloudのみ）— スキップしました。",
    "Review whether you still need this screen recording.": "この画面収録がまだ必要か確認してください。",
    "Review whether you still need this screenshot.": "このスクリーンショットがまだ必要か確認してください。",
    "Save failed: %@": "保存に失敗しました: %@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "検索できるのは、ビーチにいる犬のように、写真に写っている内容だけです。日付、場所、名前、文字は索引に含まれません。",
    "Searching labels across all scanned categories.": "スキャン済みのすべてのカテゴリでラベルを検索しています。",
    "Size unknown (iCloud-only) — skipped": "サイズが不明（iCloudのみ）— スキップ",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "このスキャンでは一部の指定された内容が見つかりませんでした。より簡単な内容検索をお試しください。",
    "Submit a content search or try different words.": "内容検索を実行するか、別の言葉をお試しください。",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "これらの語句は対応しているラベル検索になりません。犬やビーチなど、写真に写っている内容をお試しください。ラベル検索は日付、名前、除外には対応していません。",
    "This item can't be compressed as a photo.": "この項目は写真として圧縮できません。",
    "This item uses %@; review whether you need it.": "この項目は%@を使用しています；必要かどうかを確認してください。",
    "This language is not supported by local AI.": "この言語はローカルAIではサポートされていません。",
    "This photo has very high brightness.": "この写真は明るさが非常に高いです。",
    "This photo has very low brightness.": "この写真は明るさが非常に低いです。",
    "This photo may be out of focus.": "この写真はピントが合っていない可能性があります。",
    "This photo received a low visual-quality score.": "この写真の画質評価が低くなっています。",
    "TidyByte Needs Your Photos": "TidyByteに写真へのアクセスが必要です",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "TidyByteは選択した写真だけを見ることができます。ライブラリの残りを確認したいときは、いつでも写真を追加してください。",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByteはこのデバイス上でライブラリを確認できます。何もアップロードされず、あなたの同意なしに何かが変更されることもありません。",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByteはこのデバイス上でライブラリを確認し、整理する価値のある項目を探します。何もアップロードされず、あなたの同意なしに何かが変更されることもありません。次にiOSがアクセスを求めます。",
    "Unknown error": "不明なエラー",
    "Up to %@ to free on iPhone": "iPhoneで最大%@を空けられます",
    "Updated %lldd ago": "%lld日前に更新",
    "Use 300 characters or fewer.": "300文字以内で入力してください。",
    "Using label search across scanned photos.": "スキャン済みの写真でラベル検索を使用しています。",
    "Video not found.": "ビデオが見つかりません。",
    "Video size unknown (iCloud-only) — skipped.": "ビデオのサイズが不明（iCloudのみ）— スキップしました。",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOSが写真へのアクセスを求めるのは一度だけで、これがその確認です。その後、TidyByteはこのデバイス上でライブラリを確認します。何もアップロードされず、あなたが確認しない限り何も変更されません。",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOSがTidyByteのライブラリへのアクセスをブロックしており、再度確認されることはありません。元に戻す方法は「設定」だけです — そこで写真へのアクセスをオンにすると、ここでの機能が再び動作します。",
  },

  ko: {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Screen Time 또는 기기 관리 제한이 사진 접근을 차단하고 있습니다. 설정의 사진 스위치로는 변경할 수 없습니다 — 먼저 해당 제한을 해제해야 합니다.",
    "A lens smudge may have reduced image clarity.": "렌즈 얼룩으로 이미지 선명도가 낮아졌을 수 있습니다.",
    "Allow Photo Access?": "사진 접근을 허용할까요?",
    "Already compressed": "이미 압축됨",
    "Cancelled.": "취소됨.",
    "Choose albums or change your filters.": "앨범을 선택하거나 필터를 변경하세요.",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "동영상을 불러오지 못했습니다(iCloud에 아직 있을 수 있습니다). 다시 시도하세요.",
    "Dark": "다크",
    "Export failed: %@": "내보내기 실패: %@",
    "Exported file was empty.": "내보낸 파일이 비어 있습니다.",
    "Failed to create export session.": "내보내기 세션을 생성하지 못했습니다.",
    "Failed to load the photo.": "사진을 불러오지 못했습니다.",
    "Failed to re-encode the photo.": "사진을 다시 인코딩하지 못했습니다.",
    "Failed to read file size.": "파일 크기를 읽지 못했습니다.",
    "Light": "라이트",
    "Local AI could not interpret this search.": "로컬 AI가 이 검색을 해석하지 못했습니다.",
    "Local AI is unavailable.": "로컬 AI를 사용할 수 없습니다.",
    "No matching photos": "일치하는 사진 없음",
    "No photos in this category.": "이 카테고리에는 사진이 없습니다.",
    "No screen recordings were found.": "화면 기록을 찾을 수 없습니다.",
    "Not Now": "나중에",
    "Nothing to free on iPhone": "iPhone에서 확보할 항목 없음",
    "Open TidyByte to refresh": "TidyByte를 열어 새로 고침",
    "Photo Access Is Off": "사진 접근 권한이 꺼져 있음",
    "Photo Access Is On": "사진 접근 권한이 켜져 있음",
    "Photo Access Is Restricted": "사진 접근 권한이 제한됨",
    "Photo not found.": "사진을 찾을 수 없습니다.",
    "Photo size unknown (iCloud-only) — skipped.": "사진 크기를 알 수 없음(iCloud에만) — 건너뜀.",
    "Review whether you still need this screen recording.": "이 화면 기록이 아직 필요한지 검토하세요.",
    "Review whether you still need this screenshot.": "이 스크린샷이 아직 필요한지 검토하세요.",
    "Save failed: %@": "저장 실패: %@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "검색은 해변의 강아지처럼 사진에 보이는 내용만 지원합니다. 날짜, 장소, 이름, 텍스트는 색인되지 않습니다.",
    "Searching labels across all scanned categories.": "스캔한 모든 카테고리에서 라벨을 검색하는 중입니다.",
    "Size unknown (iCloud-only) — skipped": "크기를 알 수 없음(iCloud에만) — 건너뜀",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "이번 스캔에서 일부 요청한 내용을 찾지 못했습니다. 더 간단한 콘텐츠 검색을 시도하세요.",
    "Submit a content search or try different words.": "콘텐츠 검색을 제출하거나 다른 단어를 시도하세요.",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "이 단어들은 지원되는 라벨 검색을 구성하지 않습니다. 강아지나 해변처럼 사진에 보이는 내용을 시도하세요. 라벨 검색은 날짜, 이름, 제외를 지원하지 않습니다.",
    "This item can't be compressed as a photo.": "이 항목은 사진으로 압축할 수 없습니다.",
    "This item uses %@; review whether you need it.": "이 항목은 %@을(를) 사용합니다; 필요한지 검토하세요.",
    "This language is not supported by local AI.": "이 언어는 로컬 AI에서 지원되지 않습니다.",
    "This photo has very high brightness.": "이 사진은 밝기가 매우 높습니다.",
    "This photo has very low brightness.": "이 사진은 밝기가 매우 낮습니다.",
    "This photo may be out of focus.": "이 사진은 초점이 맞지 않았을 수 있습니다.",
    "This photo received a low visual-quality score.": "이 사진은 시각적 품질 점수가 낮습니다.",
    "TidyByte Needs Your Photos": "TidyByte에 사진 접근 권한이 필요합니다",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "TidyByte는 선택한 사진만 볼 수 있습니다. 나머지 보관함도 검토하려면 언제든지 사진을 추가하세요.",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByte는 이 기기에서 보관함을 검토할 수 있습니다. 아무것도 업로드되지 않으며, 허용하지 않으면 아무것도 변경되지 않습니다.",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByte는 이 기기에서 보관함을 검토하여 정리할 항목을 찾습니다. 아무것도 업로드되지 않으며, 허용하지 않으면 아무것도 변경되지 않습니다. 다음 단계에서 iOS가 접근 권한을 요청합니다.",
    "Unknown error": "알 수 없는 오류",
    "Up to %@ to free on iPhone": "iPhone에서 최대 %@ 확보 가능",
    "Updated %lldd ago": "%lld일 전 업데이트됨",
    "Use 300 characters or fewer.": "300자 이하로 입력하세요.",
    "Using label search across scanned photos.": "스캔한 사진에서 라벨 검색을 사용합니다.",
    "Video not found.": "동영상을 찾을 수 없습니다.",
    "Video size unknown (iCloud-only) — skipped.": "동영상 크기를 알 수 없음(iCloud에만) — 건너뜀.",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOS가 사진 접근 권한을 요청하는 것은 한 번뿐이며, 지금이 그 요청입니다. 이후 TidyByte는 이 기기에서 보관함을 검토합니다. 아무것도 업로드되지 않으며, 검토하지 않으면 아무것도 변경되지 않습니다.",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOS가 TidyByte의 보관함 접근을 차단했으며 다시 묻지 않습니다. 되돌리는 방법은 설정뿐입니다 — 설정에서 사진 접근 권한을 켜면 여기의 모든 기능이 다시 작동합니다.",
  },

  'zh-Hans': {
    "A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.": "Screen Time 或设备管理限制阻止了照片访问。“设置”中的“照片”开关无法更改 — 必须先解除该限制。",
    "A lens smudge may have reduced image clarity.": "镜头污渍可能降低了图像的清晰度。",
    "Allow Photo Access?": "允许访问照片？",
    "Already compressed": "已压缩",
    "Cancelled.": "已取消。",
    "Choose albums or change your filters.": "选择相簿或更改筛选条件。",
    "Couldn't load the video (it may still be in iCloud). Please try again.": "无法载入视频（可能仍保存在 iCloud 中）。请重试。",
    "Dark": "深色",
    "Export failed: %@": "导出失败：%@",
    "Exported file was empty.": "导出的文件为空。",
    "Failed to create export session.": "无法创建导出会话。",
    "Failed to load the photo.": "无法载入照片。",
    "Failed to re-encode the photo.": "无法重新编码照片。",
    "Failed to read file size.": "无法读取文件大小。",
    "Light": "浅色",
    "Local AI could not interpret this search.": "本地 AI 无法解读此搜索。",
    "Local AI is unavailable.": "本地 AI 不可用。",
    "No matching photos": "没有匹配的照片",
    "No photos in this category.": "此类别中没有照片。",
    "No screen recordings were found.": "未找到屏幕录制。",
    "Not Now": "以后",
    "Nothing to free on iPhone": "iPhone 上没有可释放的空间",
    "Open TidyByte to refresh": "打开 TidyByte 以刷新",
    "Photo Access Is Off": "照片访问权限已关闭",
    "Photo Access Is On": "照片访问权限已开启",
    "Photo Access Is Restricted": "照片访问权限受限制",
    "Photo not found.": "找不到照片。",
    "Photo size unknown (iCloud-only) — skipped.": "照片大小未知（仅限 iCloud）— 已跳过。",
    "Review whether you still need this screen recording.": "查看你是否还需要这段屏幕录制。",
    "Review whether you still need this screenshot.": "查看你是否还需要这张截屏。",
    "Save failed: %@": "保存失败：%@",
    "Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.": "搜索仅支持可见内容，例如海滩上的狗。日期、地点、姓名和文字不会被索引。",
    "Searching labels across all scanned categories.": "正在所有已扫描的类别中搜索标签。",
    "Size unknown (iCloud-only) — skipped": "大小未知（仅限 iCloud）— 已跳过",
    "Some requested concepts were not found in this scan. Try a simpler content search.": "本次扫描中未找到部分所请求的概念。请尝试更简单的内容搜索。",
    "Submit a content search or try different words.": "提交内容搜索，或尝试其他词语。",
    "These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.": "这些词无法构成受支持的标签搜索。请尝试狗或海滩等可见内容。标签搜索不支持日期、姓名或排除条件。",
    "This item can't be compressed as a photo.": "此项目无法作为照片压缩。",
    "This item uses %@; review whether you need it.": "此项目占用 %@；查看你是否需要它。",
    "This language is not supported by local AI.": "本地 AI 不支持此语言。",
    "This photo has very high brightness.": "这张照片的亮度非常高。",
    "This photo has very low brightness.": "这张照片的亮度非常低。",
    "This photo may be out of focus.": "这张照片可能未对焦。",
    "This photo received a low visual-quality score.": "这张照片的视觉质量评分较低。",
    "TidyByte Needs Your Photos": "TidyByte 需要访问你的照片",
    "TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.": "TidyByte 只能看到你选择的照片。想让 TidyByte 查看图库中的其余内容时，随时可以添加更多照片。",
    "TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.": "TidyByte 可以在此设备上查看你的图库。不会上传任何内容，未经你同意也不会更改任何内容。",
    "TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.": "TidyByte 会在此设备上查看你的图库，找出值得清理的内容。不会上传任何内容，未经你同意也不会更改任何内容。接下来 iOS 会请求访问权限。",
    "Unknown error": "未知错误",
    "Up to %@ to free on iPhone": "iPhone 上最多可释放 %@",
    "Updated %lldd ago": "%lld 天前更新",
    "Use 300 characters or fewer.": "请使用 300 个字符以内。",
    "Using label search across scanned photos.": "正在对已扫描的照片使用标签搜索。",
    "Video not found.": "找不到视频。",
    "Video size unknown (iCloud-only) — skipped.": "视频大小未知（仅限 iCloud）— 已跳过。",
    "iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.": "iOS 只会询问一次照片访问权限，这次就是。随后 TidyByte 会在此设备上查看你的图库。不会上传任何内容，未经你查看也不会更改任何内容。",
    "iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.": "iOS 已阻止 TidyByte 访问你的图库，并且不会再询问。只能通过“设置”恢复 — 在那里开启照片访问权限，这里的一切就会重新正常工作。",
  },
}

const langs = ['de', 'ja', 'ko', 'zh-Hans']
const problems = []

for (const lang of langs) {
  const path = join(dir, `${lang}.json`)
  const before = readFileSync(path, 'utf8')
  const parsedBefore = JSON.parse(before)
  const priorStrings = { ...parsedBefore.strings }
  const additions = translations[lang]

  if (Object.keys(additions).length !== KEYS.length) {
    problems.push(`${lang}: expected ${KEYS.length} additions, got ${Object.keys(additions).length}`)
    continue
  }
  for (const k of KEYS) {
    if (!(k in additions)) problems.push(`${lang}: missing translation for: ${k}`)
  }
  for (const k of Object.keys(additions)) {
    if (!KEYS.includes(k)) problems.push(`${lang}: translation for unknown key: ${k}`)
    if (k in priorStrings) problems.push(`${lang}: key already existed: ${k}`)
    if (!additions[k] || !additions[k].trim()) problems.push(`${lang}: empty translation for: ${k}`)
  }
  if (problems.length) continue

  const merged = { ...priorStrings, ...additions }
  const entries = Object.keys(merged)
    .sort()
    .map((k) => `    ${JSON.stringify(k)}: ${JSON.stringify(merged[k])}`)
    .join(',\n')
  const block = `  "strings": {\n${entries}\n  }`

  const start = before.indexOf('  "strings": {')
  if (start === -1) { problems.push(`${lang}: strings block not found`); continue }
  const end = before.indexOf('\n  },', start)
  if (end === -1) { problems.push(`${lang}: strings block end not found`); continue }
  if (!before.slice(end + 5, end + 5 + 15).startsWith('\n  "plurals"')) {
    problems.push(`${lang}: unexpected text after strings block: ${JSON.stringify(before.slice(end + 5, end + 40))}`)
    continue
  }

  const after = before.slice(0, start) + block + before.slice(end + 4)
  const reparsed = JSON.parse(after)

  // Invariants.
  const priorKeys = Object.keys(priorStrings)
  if (Object.keys(reparsed.strings).length !== priorKeys.length + KEYS.length) {
    problems.push(`${lang}: key count ${Object.keys(reparsed.strings).length} != ${priorKeys.length + KEYS.length}`)
  }
  for (const k of priorKeys) {
    if (reparsed.strings[k] !== priorStrings[k]) problems.push(`${lang}: pre-existing key changed: ${k}`)
  }
  if (JSON.stringify(reparsed.plurals) !== JSON.stringify(parsedBefore.plurals)) {
    problems.push(`${lang}: plurals section changed`)
  }
  if (!after.endsWith('\n')) problems.push(`${lang}: lost trailing newline`)

  if (problems.length) continue

  writeFileSync(path, after)
  console.log(`${lang}: ${priorKeys.length} -> ${Object.keys(reparsed.strings).length} keys (plurals untouched)`)
}

if (problems.length) {
  console.error('\nPROBLEMS:')
  for (const p of problems) console.error(' -', p)
  process.exit(1)
}
console.log('\nall four files written, invariants hold')
