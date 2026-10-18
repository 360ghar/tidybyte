#!/usr/bin/env node
/**
 * Batch 8 — insert the 93 new English keys into de / ja / ko / zh-Hans.
 *
 * 80 plain keys go into `"strings"` (key = exact English text). The block is
 * regenerated from the parsed object with 2-space indent and keys sorted the
 * way the file already sorts them (UTF-16 code-unit ascending); the round trip
 * is byte-identical for the existing keys, so nothing but the additions move.
 *
 * 13 counted keys go into `"plurals"` (key = English singular). The existing
 * plural block is left byte-for-byte alone; the new entries are appended in
 * `_plural-keys.json` order, which is the order the file already uses.
 *
 * Run: node scripts/localization/translations/_batch8-insert.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const LANGS = ['de', 'ja', 'ko', 'zh-Hans']
const byCodeUnit = (a, b) => (a < b ? -1 : a > b ? 1 : 0)
const PLURALS_MARKER = '\n  "plurals": {'

/** The 80 plain keys, in the order the brief presents them. */
export const KEYS = [
  // Swipe home — filter cards
  'Worst Shots',
  'Review low-scoring photos, lowest first',
  "Photos you haven't reviewed yet",
  'Every photo and video in your library',
  'Review photos and videos taken on or before a date',
  'Photos not organized into your albums',
  'Specific Album',
  'Review photos from a specific album',
  // Swipe session — messages and undo
  'Marked for deletion. Nothing is deleted until you confirm at the end.',
  'Delete is off until the photo loads.',
  'Pinch or double-tap a photo to inspect it',
  "That photo can't be undone anymore.",
  'Undo your newer actions first to reach that photo.',
  'Your library changed during analysis. Try Worst Shots again.',
  'No photo is waiting to be filed. Dismiss and try again.',
  'Still adding — please wait a moment and try again.',
  "Couldn't save your changes. Please try again.",
  // Session completion — result rows
  'Added to albums',
  'Moved to Recently Deleted',
  'Kept',
  'Skipped',
  'Deleted',
  // Burst cleaner — keeper reasons
  'Kept: your choice',
  'Kept: your pick in Photos',
  "Kept: iPhone's pick",
  'Kept: favorite',
  'Kept: highest resolution',
  'Kept: last frame',
  'Kept: auto pick',
  ' Favorites are kept.',
  'This keeps the starred frame of each burst and deletes the rest.',
  // Burst cleaner — result
  '1 burst cleaned down to a single photo.',
  '%lld bursts cleaned down to single photos.',
  // Errors
  'Album not found.',
  'Failed to create album.',
  "Couldn't modify the album. Please try again.",
  'Nothing was deleted.',
  'Live Photo not found.',
  'Could not find still image in Live Photo.',
  'Invalid image data.',
  'Timed out loading the photo (it may still be in iCloud). Please try again.',
  'The compressed copy is missing from your library.',
  'The converted still is missing from your library.',
  'Copies kept. Both versions are in your library; delete either one in Photos.',
  "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.",
  'Your library changed. Scan again before searching.',
  'Removed changed or unavailable photos. Scan again to include new or edited photos.',
  // Storage dashboard and permission screen
  'Recently Deleted',
  'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.',
  'Manage Apps & System Storage',
  'Open Settings ▸ General ▸ iPhone Storage',
  'Library figures below cover only the photos you selected; device totals cover the whole device.',
  'Find exact and near-duplicate photos',
  'Spot blurry, dark, and overexposed shots',
  'Surface the biggest files taking up space',
  'Delete only what you review and approve',
  // Activity and savings
  'items, all time',
  'this month',
  'Size unknown',
  'Size unavailable',
  'cleaned up since you started using TidyByte',
  "Nothing measurable yet. Items stored only in iCloud don't report a size.",
  // Rate prompt and feedback
  'Enjoying TidyByte?',
  'Thanks for the support',
  'What should we fix?',
  'Tell us what got in the way.',
  'Send Feedback',
  'Yes',
  'Not really',
  'Not now',
  'Your rating helps other people find TidyByte.',
  'You just %@.',
  "The message couldn't be sent. Try again, or email us at %@.",
  'No mail account is set up on this device. Email us at %@.',
  // Share text
  'I just %@',
  "I'm cleaning up my photo library",
  '%@ with TidyByte — a private, on-device photo cleanup app. %@',
  // Misc
  'Min size: %@',
  'Swipe history cleared',
  'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.',
]

/** The 13 counted keys, in `_plural-keys.json` order. */
export const PLURAL_KEYS = [
  'cleared %lld photo',
  'cleared %lld blurry photo',
  'cleared %lld screenshot',
  'cleared %lld large file',
  'cleared %lld burst frame',
  'cleared %lld item (%@)',
  'removed %lld duplicate',
  'removed %lld similar photo',
  'compressed %lld photo',
  'compressed %lld video',
  'cleaned %lld burst photo',
  'converted %lld Live Photo',
  'reviewed %lld item',
]

const T = {
  'Worst Shots': {
    de: 'Schlechteste Aufnahmen',
    ja: 'ワーストショット',
    ko: '최악의 사진',
    'zh-Hans': '最差照片',
  },
  'Review low-scoring photos, lowest first': {
    de: 'Prüfe Fotos mit niedriger Bewertung, die schlechtesten zuerst',
    ja: '評価の低い写真を、低い順に確認します',
    ko: '점수가 낮은 사진부터 순서대로 검토합니다',
    'zh-Hans': '查看评分最低的照片，从最低的开始',
  },
  "Photos you haven't reviewed yet": {
    de: 'Fotos, die du noch nicht geprüft hast',
    ja: 'まだ確認していない写真',
    ko: '아직 검토하지 않은 사진',
    'zh-Hans': '你尚未查看的照片',
  },
  'Every photo and video in your library': {
    de: 'Alle Fotos und Videos in deiner Mediathek',
    ja: 'ライブラリ内のすべての写真とビデオ',
    ko: '사진 보관함의 모든 사진과 동영상',
    'zh-Hans': '你图库中的每一张照片和视频',
  },
  'Review photos and videos taken on or before a date': {
    de: 'Prüfe Fotos und Videos, die an oder vor einem Datum aufgenommen wurden',
    ja: '指定した日付以前に撮影した写真とビデオを確認します',
    ko: '지정한 날짜 이전에 촬영한 사진과 동영상을 검토합니다',
    'zh-Hans': '查看在某日期当天或之前拍摄的照片和视频',
  },
  'Photos not organized into your albums': {
    de: 'Fotos, die keinem deiner Alben zugeordnet sind',
    ja: 'アルバムに整理されていない写真',
    ko: '앨범에 정리되지 않은 사진',
    'zh-Hans': '未整理到相簿中的照片',
  },
  'Specific Album': {
    de: 'Bestimmtes Album',
    ja: '特定のアルバム',
    ko: '특정 앨범',
    'zh-Hans': '特定相簿',
  },
  'Review photos from a specific album': {
    de: 'Prüfe Fotos aus einem bestimmten Album',
    ja: '特定のアルバムの写真を確認します',
    ko: '특정 앨범의 사진을 검토합니다',
    'zh-Hans': '查看特定相簿中的照片',
  },
  'Marked for deletion. Nothing is deleted until you confirm at the end.': {
    de: 'Zum Löschen markiert. Nichts wird gelöscht, bis du es am Ende bestätigst.',
    ja: '削除対象としてマークしました。最後に確認するまで何も削除されません。',
    ko: '삭제 대상으로 표시했습니다. 마지막에 확인하기 전까지는 아무것도 삭제되지 않습니다.',
    'zh-Hans': '已标记为删除。在你最后确认之前，不会删除任何内容。',
  },
  'Delete is off until the photo loads.': {
    de: 'Löschen ist deaktiviert, bis das Foto geladen ist.',
    ja: '写真が読み込まれるまで削除はオフです。',
    ko: '사진이 로드될 때까지 삭제는 꺼져 있습니다.',
    'zh-Hans': '照片载入前无法删除。',
  },
  'Pinch or double-tap a photo to inspect it': {
    de: 'Ziehe zwei Finger auseinander oder tippe doppelt auf ein Foto, um es genauer anzusehen',
    ja: '写真をピンチまたはダブルタップすると、拡大して確認できます',
    ko: '사진을 핀치하거나 두 번 탭하면 자세히 볼 수 있습니다',
    'zh-Hans': '捏合或轻点两下照片可放大查看',
  },
  "That photo can't be undone anymore.": {
    de: 'Dieses Foto kann nicht mehr rückgängig gemacht werden.',
    ja: 'その写真はもう取り消せません。',
    ko: '그 사진은 더 이상 되돌릴 수 없습니다.',
    'zh-Hans': '该照片已无法撤销。',
  },
  'Undo your newer actions first to reach that photo.': {
    de: 'Mache zuerst deine neueren Aktionen rückgängig, um zu diesem Foto zu gelangen.',
    ja: 'その写真にたどり着くには、まず新しい操作から取り消してください。',
    ko: '해당 사진으로 돌아가려면 최근 작업부터 먼저 되돌려야 합니다.',
    'zh-Hans': '要先撤销较新的操作，才能回到该照片。',
  },
  'Your library changed during analysis. Try Worst Shots again.': {
    de: 'Deine Mediathek hat sich während der Analyse geändert. Versuche es erneut mit „Schlechteste Aufnahmen“.',
    ja: '解析中にライブラリが変更されました。「ワーストショット」をもう一度お試しください。',
    ko: '분석 중에 사진 보관함이 변경되었습니다. "최악의 사진"을 다시 시도하세요.',
    'zh-Hans': '分析期间你的图库发生了变化。请再次尝试“最差照片”。',
  },
  'No photo is waiting to be filed. Dismiss and try again.': {
    de: 'Es wartet kein Foto zum Einsortieren. Schließe den Dialog und versuche es erneut.',
    ja: 'アルバムに追加する写真がありません。閉じて、もう一度お試しください。',
    ko: '앨범에 넣을 사진이 없습니다. 닫고 다시 시도하세요.',
    'zh-Hans': '没有等待归档的照片。请关闭后重试。',
  },
  'Still adding — please wait a moment and try again.': {
    de: 'Wird noch hinzugefügt — warte einen Moment und versuche es erneut.',
    ja: '追加中です — 少し待ってからもう一度お試しください。',
    ko: '아직 추가하는 중입니다 — 잠시 기다렸다가 다시 시도하세요.',
    'zh-Hans': '仍在添加中 — 请稍等片刻后重试。',
  },
  "Couldn't save your changes. Please try again.": {
    de: 'Deine Änderungen konnten nicht gespeichert werden. Versuche es erneut.',
    ja: '変更を保存できませんでした。もう一度お試しください。',
    ko: '변경 사항을 저장하지 못했습니다. 다시 시도하세요.',
    'zh-Hans': '无法保存你的更改。请重试。',
  },
  'Added to albums': {
    de: 'Zu Alben hinzugefügt',
    ja: 'アルバムに追加',
    ko: '앨범에 추가됨',
    'zh-Hans': '已添加到相簿',
  },
  'Moved to Recently Deleted': {
    de: 'Nach „Zuletzt gelöscht“ verschoben',
    ja: '「最近削除した項目」に移動',
    ko: '최근 삭제된 항목으로 이동됨',
    'zh-Hans': '已移到“最近删除”',
  },
  Kept: {
    de: 'Behalten',
    ja: '残した',
    ko: '남김',
    'zh-Hans': '已保留',
  },
  Skipped: {
    de: 'Übersprungen',
    ja: 'スキップした',
    ko: '건너뜀',
    'zh-Hans': '已跳过',
  },
  Deleted: {
    de: 'Gelöscht',
    ja: '削除した',
    ko: '삭제됨',
    'zh-Hans': '已删除',
  },
  'Kept: your choice': {
    de: 'Behalten: deine Wahl',
    ja: '残す: あなたの選択',
    ko: '남기기: 직접 선택',
    'zh-Hans': '保留：你的选择',
  },
  'Kept: your pick in Photos': {
    de: 'Behalten: deine Wahl in Fotos',
    ja: '残す: 「写真」での選択',
    ko: '남기기: 사진 앱에서 선택',
    'zh-Hans': '保留：你在“照片”中的选择',
  },
  "Kept: iPhone's pick": {
    de: 'Behalten: iPhone-Auswahl',
    ja: '残す: iPhoneの選択',
    ko: '남기기: iPhone 선택',
    'zh-Hans': '保留：iPhone 的选择',
  },
  'Kept: favorite': {
    de: 'Behalten: Favorit',
    ja: '残す: お気に入り',
    ko: '남기기: 즐겨찾기',
    'zh-Hans': '保留：收藏',
  },
  'Kept: highest resolution': {
    de: 'Behalten: höchste Auflösung',
    ja: '残す: 最高解像度',
    ko: '남기기: 최고 해상도',
    'zh-Hans': '保留：最高分辨率',
  },
  'Kept: last frame': {
    de: 'Behalten: letztes Bild',
    ja: '残す: 最後のコマ',
    ko: '남기기: 마지막 프레임',
    'zh-Hans': '保留：最后一帧',
  },
  'Kept: auto pick': {
    de: 'Behalten: automatische Auswahl',
    ja: '残す: 自動選択',
    ko: '남기기: 자동 선택',
    'zh-Hans': '保留：自动选择',
  },
  ' Favorites are kept.': {
    de: ' Favoriten werden behalten.',
    ja: ' お気に入りは残されます。',
    ko: ' 즐겨찾기는 남습니다.',
    'zh-Hans': ' 收藏的照片会保留。',
  },
  'This keeps the starred frame of each burst and deletes the rest.': {
    de: 'Dies behält das mit einem Stern markierte Bild jeder Serie und löscht den Rest.',
    ja: '各バーストでスターを付けたコマを残し、それ以外を削除します。',
    ko: '각 버스트에서 별표한 프레임을 남기고 나머지를 삭제합니다.',
    'zh-Hans': '这会保留每组连拍中标星的那一帧，删除其余的。',
  },
  '1 burst cleaned down to a single photo.': {
    de: '1 Serie auf ein einzelnes Foto reduziert.',
    ja: '1件のバーストを1枚の写真に整理しました。',
    ko: '버스트 1개를 사진 1장으로 정리했습니다.',
    'zh-Hans': '已将 1 组连拍精简为一张照片。',
  },
  '%lld bursts cleaned down to single photos.': {
    de: '%lld Serien auf einzelne Fotos reduziert.',
    ja: '%lld件のバーストを1枚ずつの写真に整理しました。',
    ko: '버스트 %lld개를 각각 사진 1장으로 정리했습니다.',
    'zh-Hans': '已将 %lld 组连拍精简为单张照片。',
  },
  'Album not found.': {
    de: 'Album nicht gefunden.',
    ja: 'アルバムが見つかりません。',
    ko: '앨범을 찾을 수 없습니다.',
    'zh-Hans': '找不到相簿。',
  },
  'Failed to create album.': {
    de: 'Album konnte nicht erstellt werden.',
    ja: 'アルバムを作成できませんでした。',
    ko: '앨범을 생성하지 못했습니다.',
    'zh-Hans': '无法创建相簿。',
  },
  "Couldn't modify the album. Please try again.": {
    de: 'Das Album konnte nicht geändert werden. Versuche es erneut.',
    ja: 'アルバムを変更できませんでした。もう一度お試しください。',
    ko: '앨범을 수정하지 못했습니다. 다시 시도하세요.',
    'zh-Hans': '无法修改相簿。请重试。',
  },
  'Nothing was deleted.': {
    de: 'Es wurde nichts gelöscht.',
    ja: '何も削除されませんでした。',
    ko: '삭제된 항목이 없습니다.',
    'zh-Hans': '没有删除任何内容。',
  },
  'Live Photo not found.': {
    de: 'Live Photo nicht gefunden.',
    ja: 'Live Photoが見つかりません。',
    ko: 'Live Photo를 찾을 수 없습니다.',
    'zh-Hans': '找不到 Live Photo。',
  },
  'Could not find still image in Live Photo.': {
    de: 'Im Live Photo wurde kein Standbild gefunden.',
    ja: 'Live Photo内に静止画が見つかりませんでした。',
    ko: 'Live Photo에서 정지 이미지를 찾지 못했습니다.',
    'zh-Hans': '无法在 Live Photo 中找到静帧图像。',
  },
  'Invalid image data.': {
    de: 'Ungültige Bilddaten.',
    ja: '画像データが無効です。',
    ko: '잘못된 이미지 데이터입니다.',
    'zh-Hans': '图像数据无效。',
  },
  'Timed out loading the photo (it may still be in iCloud). Please try again.': {
    de: 'Zeitüberschreitung beim Laden des Fotos (es ist möglicherweise noch in iCloud). Versuche es erneut.',
    ja: '写真の読み込みがタイムアウトしました（まだiCloudにある可能性があります）。もう一度お試しください。',
    ko: '사진을 불러오는 시간이 초과되었습니다(iCloud에 있을 수 있음). 다시 시도하세요.',
    'zh-Hans': '载入照片超时（照片可能仍在 iCloud 中）。请重试。',
  },
  'The compressed copy is missing from your library.': {
    de: 'Die komprimierte Kopie fehlt in deiner Mediathek.',
    ja: '圧縮したコピーがライブラリに見つかりません。',
    ko: '압축된 복사본이 사진 보관함에 없습니다.',
    'zh-Hans': '你的图库中找不到压缩后的副本。',
  },
  'The converted still is missing from your library.': {
    de: 'Das konvertierte Standbild fehlt in deiner Mediathek.',
    ja: '変換した静止画がライブラリに見つかりません。',
    ko: '변환된 정지 이미지가 사진 보관함에 없습니다.',
    'zh-Hans': '你的图库中找不到转换后的静帧图像。',
  },
  'Copies kept. Both versions are in your library; delete either one in Photos.': {
    de: 'Kopien behalten. Beide Versionen sind in deiner Mediathek; lösche eine davon in Fotos.',
    ja: 'コピーは残しました。両方のバージョンがライブラリにあります。どちらか一方を「写真」で削除してください。',
    ko: '복사본은 남겨 두었습니다. 두 버전 모두 사진 보관함에 있으니, 사진 앱에서 하나를 삭제하세요.',
    'zh-Hans': '副本已保留。两个版本都在你的图库中，可在“照片”中删除其中一个。',
  },
  "Deleted %lld of %lld items. %lld couldn't be deleted. Try again.": {
    de: '%lld von %lld Objekten gelöscht. %lld konnten nicht gelöscht werden. Versuche es erneut.',
    ja: '%lld個中%lld個の項目を削除しました。%lld個は削除できませんでした。もう一度お試しください。',
    ko: '%lld개 중 %lld개 항목을 삭제했습니다. %lld개는 삭제하지 못했습니다. 다시 시도하세요.',
    'zh-Hans': '已删除 %lld 个项目（共 %lld 个）。%lld 个无法删除。请重试。',
  },
  'Your library changed. Scan again before searching.': {
    de: 'Deine Mediathek hat sich geändert. Scanne erneut, bevor du suchst.',
    ja: 'ライブラリが変更されました。検索する前に再スキャンしてください。',
    ko: '사진 보관함이 변경되었습니다. 검색하기 전에 다시 스캔하세요.',
    'zh-Hans': '你的图库已更改。请先重新扫描再搜索。',
  },
  'Removed changed or unavailable photos. Scan again to include new or edited photos.': {
    de: 'Geänderte oder nicht verfügbare Fotos entfernt. Scanne erneut, um neue oder bearbeitete Fotos einzubeziehen.',
    ja: '変更または利用できない写真を除外しました。再スキャンすると、新規または編集済みの写真も含まれます。',
    ko: '변경되었거나 사용할 수 없는 사진을 제외했습니다. 다시 스캔하면 새로 추가되거나 편집된 사진도 포함됩니다.',
    'zh-Hans': '已移除更改过或无法使用的照片。重新扫描可包含新增或编辑过的照片。',
  },
  'Recently Deleted': {
    de: 'Zuletzt gelöscht',
    ja: '最近削除した項目',
    ko: '최근 삭제된 항목',
    'zh-Hans': '最近删除',
  },
  'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.': {
    de: 'Der Speicher wird frei, sobald der Ordner geleert wird. Öffne in Fotos „Alben“, dann „Zuletzt gelöscht“.',
    ja: '空にすると空き容量が戻ります。「写真」で「アルバム」を開き、「最近削除した項目」を選んでください。',
    ko: '비우면 저장 공간이 돌아옵니다. 사진 앱에서 앨범을 연 다음 최근 삭제된 항목을 여세요.',
    'zh-Hans': '清空后空间才会释放。在“照片”中打开“相簿”，再打开“最近删除”。',
  },
  'Manage Apps & System Storage': {
    de: 'Apps- & System-Speicher verwalten',
    ja: 'アプリとシステムのストレージを管理',
    ko: '앱 및 시스템 저장 공간 관리',
    'zh-Hans': '管理 App 与系统储存空间',
  },
  'Open Settings ▸ General ▸ iPhone Storage': {
    de: 'Öffne Einstellungen ▸ Allgemein ▸ iPhone-Speicher',
    ja: '「設定」▸「一般」▸「iPhoneストレージ」を開く',
    ko: '설정 ▸ 일반 ▸ iPhone 저장 공간 열기',
    'zh-Hans': '打开“设置”▸“通用”▸“iPhone 储存空间”',
  },
  'Library figures below cover only the photos you selected; device totals cover the whole device.': {
    de: 'Die Werte unten beziehen sich nur auf die Fotos, die du ausgewählt hast; die Gerätewerte gelten für das gesamte Gerät.',
    ja: '以下のライブラリの数値は選択した写真のみが対象です。デバイスの合計はデバイス全体が対象です。',
    ko: '아래 사진 보관함 수치는 선택한 사진만 반영하며, 기기 합계는 기기 전체를 반영합니다.',
    'zh-Hans': '下方图库数据仅涵盖你选择的照片；设备总计则涵盖整台设备。',
  },
  'Find exact and near-duplicate photos': {
    de: 'Finde exakte und fast identische Fotos',
    ja: '完全な重複写真と類似写真を見つけます',
    ko: '완전히 같거나 거의 같은 사진을 찾습니다',
    'zh-Hans': '找出完全重复和近似重复的照片',
  },
  'Spot blurry, dark, and overexposed shots': {
    de: 'Erkenne unscharfe, dunkle und überbelichtete Aufnahmen',
    ja: 'ぼやけた写真、暗い写真、露出オーバーの写真を見つけます',
    ko: '흐릿하거나 어둡거나 과다 노출된 사진을 찾아냅니다',
    'zh-Hans': '找出模糊、过暗和曝光过度的照片',
  },
  'Surface the biggest files taking up space': {
    de: 'Zeige die größten Dateien, die Speicher belegen',
    ja: '容量を占めている大きなファイルを洗い出します',
    ko: '공간을 차지하는 가장 큰 파일을 보여 줍니다',
    'zh-Hans': '列出占用空间最大的文件',
  },
  'Delete only what you review and approve': {
    de: 'Lösche nur, was du geprüft und bestätigt hast',
    ja: '自分で確認して承認したものだけを削除します',
    ko: '직접 확인하고 승인한 항목만 삭제합니다',
    'zh-Hans': '只删除你查看并确认的内容',
  },
  'items, all time': {
    de: 'Objekte, insgesamt',
    ja: '項目、全期間',
    ko: '항목, 전체 기간',
    'zh-Hans': '项目，累计',
  },
  'this month': {
    de: 'diesen Monat',
    ja: '今月',
    ko: '이번 달',
    'zh-Hans': '本月',
  },
  'Size unknown': {
    de: 'Größe unbekannt',
    ja: 'サイズ不明',
    ko: '크기 알 수 없음',
    'zh-Hans': '大小未知',
  },
  'Size unavailable': {
    de: 'Größe nicht verfügbar',
    ja: 'サイズを取得できません',
    ko: '크기를 확인할 수 없음',
    'zh-Hans': '无法获取大小',
  },
  'cleaned up since you started using TidyByte': {
    de: 'seit deinem Start mit TidyByte bereinigt',
    ja: 'TidyByteを使い始めてからクリーンアップした合計',
    ko: 'TidyByte를 사용하기 시작한 이후 정리한 용량',
    'zh-Hans': '自开始使用 TidyByte 以来清理的空间',
  },
  "Nothing measurable yet. Items stored only in iCloud don't report a size.": {
    de: 'Noch nichts messbar. Objekte, die nur in iCloud liegen, melden keine Größe.',
    ja: 'まだ測定できるデータがありません。iCloudにのみ保存されている項目はサイズを報告しません。',
    ko: '아직 측정된 내용이 없습니다. iCloud에만 저장된 항목은 크기를 보고하지 않습니다.',
    'zh-Hans': '暂时没有可统计的数据。仅存储在 iCloud 中的项目不会报告大小。',
  },
  'Enjoying TidyByte?': {
    de: 'Gefällt dir TidyByte?',
    ja: 'TidyByteを気に入っていただけましたか？',
    ko: 'TidyByte가 마음에 드시나요?',
    'zh-Hans': '喜欢 TidyByte 吗？',
  },
  'Thanks for the support': {
    de: 'Danke für deine Unterstützung',
    ja: 'ご支援ありがとうございます',
    ko: '응원해 주셔서 감사합니다',
    'zh-Hans': '感谢你的支持',
  },
  'What should we fix?': {
    de: 'Was sollen wir verbessern?',
    ja: 'どこを直せばいいですか？',
    ko: '무엇을 고치면 좋을까요?',
    'zh-Hans': '我们该改进什么？',
  },
  'Tell us what got in the way.': {
    de: 'Sag uns, was dich gestört hat.',
    ja: '何が邪魔になったか教えてください。',
    ko: '어떤 점이 불편했는지 알려 주세요.',
    'zh-Hans': '告诉我们是什么阻碍了你。',
  },
  'Send Feedback': {
    de: 'Feedback senden',
    ja: 'フィードバックを送信',
    ko: '피드백 보내기',
    'zh-Hans': '发送反馈',
  },
  Yes: {
    de: 'Ja',
    ja: 'はい',
    ko: '예',
    'zh-Hans': '是',
  },
  'Not really': {
    de: 'Eher nicht',
    ja: 'いいえ、それほどでも',
    ko: '그저 그래요',
    'zh-Hans': '还好吧',
  },
  'Not now': {
    de: 'Nicht jetzt',
    ja: '今はしない',
    ko: '나중에',
    'zh-Hans': '以后',
  },
  'Your rating helps other people find TidyByte.': {
    de: 'Deine Bewertung hilft anderen, TidyByte zu finden.',
    ja: '評価していただくと、他の人がTidyByteを見つけやすくなります。',
    ko: '평가를 남겨 주시면 다른 사람들이 TidyByte를 찾는 데 도움이 됩니다.',
    'zh-Hans': '你的评分能帮助更多人发现 TidyByte。',
  },
  'You just %@.': {
    de: 'Du hast gerade %@.',
    ja: 'たった今%@。',
    ko: '방금 %@.',
    'zh-Hans': '你刚刚%@。',
  },
  "The message couldn't be sent. Try again, or email us at %@.": {
    de: 'Die Nachricht konnte nicht gesendet werden. Versuche es erneut oder schreibe uns an %@.',
    ja: 'メッセージを送信できませんでした。もう一度お試しいただくか、%@ までメールでご連絡ください。',
    ko: '메시지를 보내지 못했습니다. 다시 시도하거나 %@으로 이메일을 보내 주세요.',
    'zh-Hans': '消息无法发送。请重试，或发送邮件至 %@。',
  },
  'No mail account is set up on this device. Email us at %@.': {
    de: 'Auf diesem Gerät ist kein Mail-Konto eingerichtet. Schreibe uns an %@.',
    ja: 'このデバイスにはメールアカウントが設定されていません。%@ までメールでご連絡ください。',
    ko: '이 기기에는 메일 계정이 설정되어 있지 않습니다. %@으로 이메일을 보내 주세요.',
    'zh-Hans': '此设备未设置邮件账户。请发送邮件至 %@。',
  },
  'I just %@': {
    de: 'Ich habe gerade %@',
    ja: 'たった今%@',
    ko: '방금 %@',
    'zh-Hans': '我刚刚%@',
  },
  "I'm cleaning up my photo library": {
    de: 'Ich räume meine Fotomediathek auf',
    ja: '写真ライブラリを整理しています',
    ko: '사진 보관함을 정리하고 있습니다',
    'zh-Hans': '我正在清理我的照片图库',
  },
  '%@ with TidyByte — a private, on-device photo cleanup app. %@': {
    de: '%@ — mit TidyByte, einer privaten App zum Aufräumen deiner Fotos, die auf dem Gerät arbeitet. %@',
    ja: '%@ — 写真を端末内だけで整理できるプライベートなアプリ、TidyByteで。 %@',
    ko: '%@ — 기기에서만 사진을 정리하는 비공개 앱, TidyByte로. %@',
    'zh-Hans': '%@ — TidyByte 是一款在设备本地运行的私密照片清理应用。%@',
  },
  'Min size: %@': {
    de: 'Mindestgröße: %@',
    ja: '最小サイズ: %@',
    ko: '최소 크기: %@',
    'zh-Hans': '最小大小：%@',
  },
  'Swipe history cleared': {
    de: 'Wischverlauf gelöscht',
    ja: 'スワイプ履歴を消去しました',
    ko: '스와이프 기록을 지웠습니다',
    'zh-Hans': '已清除滑动记录',
  },
  'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.': {
    de: 'iOS bittet dich um Bestätigung. Gelöschte Objekte werden in Fotos nach „Zuletzt gelöscht“ verschoben, wo du sie 30 Tage lang wiederherstellen kannst.',
    ja: 'iOSが確認を求めます。削除した項目は「写真」の「最近削除した項目」に移動し、30日間は復元できます。',
    ko: 'iOS에서 확인을 요청합니다. 삭제한 항목은 사진 앱의 최근 삭제된 항목으로 이동하며, 30일 동안 복원할 수 있습니다.',
    'zh-Hans': 'iOS 会请你确认。已删除的项目会移到“照片”的“最近删除”，你可以在 30 天内恢复它们。',
  },
}

const P = {
  'cleared %lld photo': {
    de: { one: '%lld Foto bereinigt', other: '%lld Fotos bereinigt' },
    ja: { other: '%lld枚の写真をクリーンアップしました' },
    ko: { other: '%lld장의 사진을 정리했습니다' },
    'zh-Hans': { other: '清理了 %lld 张照片' },
  },
  'cleared %lld blurry photo': {
    de: { one: '%lld unscharfes Foto bereinigt', other: '%lld unscharfe Fotos bereinigt' },
    ja: { other: '%lld枚のぼやけた写真をクリーンアップしました' },
    ko: { other: '%lld장의 흐릿한 사진을 정리했습니다' },
    'zh-Hans': { other: '清理了 %lld 张模糊照片' },
  },
  'cleared %lld screenshot': {
    de: { one: '%lld Screenshot bereinigt', other: '%lld Screenshots bereinigt' },
    ja: { other: '%lld枚のスクリーンショットをクリーンアップしました' },
    ko: { other: '%lld장의 스크린샷을 정리했습니다' },
    'zh-Hans': { other: '清理了 %lld 张截屏' },
  },
  'cleared %lld large file': {
    de: { one: '%lld große Datei bereinigt', other: '%lld große Dateien bereinigt' },
    ja: { other: '%lld個の大きなファイルをクリーンアップしました' },
    ko: { other: '%lld개의 큰 파일을 정리했습니다' },
    'zh-Hans': { other: '清理了 %lld 个大文件' },
  },
  'cleared %lld burst frame': {
    de: { one: '%lld Serienbild bereinigt', other: '%lld Serienbilder bereinigt' },
    ja: { other: '%lldコマのバースト写真をクリーンアップしました' },
    ko: { other: '%lld개의 버스트 프레임을 정리했습니다' },
    'zh-Hans': { other: '清理了 %lld 个连拍帧' },
  },
  'cleared %lld item (%@)': {
    de: { one: '%lld Objekt bereinigt (%@)', other: '%lld Objekte bereinigt (%@)' },
    ja: { other: '%lld個の項目をクリーンアップしました（%@）' },
    ko: { other: '%lld개 항목을 정리했습니다(%@)' },
    'zh-Hans': { other: '清理了 %lld 个项目（%@）' },
  },
  'removed %lld duplicate': {
    de: { one: '%lld Duplikat entfernt', other: '%lld Duplikate entfernt' },
    ja: { other: '%lld個の重複を削除しました' },
    ko: { other: '%lld개의 중복 항목을 삭제했습니다' },
    'zh-Hans': { other: '删除了 %lld 个重复项目' },
  },
  'removed %lld similar photo': {
    de: { one: '%lld ähnliches Foto entfernt', other: '%lld ähnliche Fotos entfernt' },
    ja: { other: '%lld枚の類似写真を削除しました' },
    ko: { other: '%lld장의 유사한 사진을 삭제했습니다' },
    'zh-Hans': { other: '删除了 %lld 张相似照片' },
  },
  'compressed %lld photo': {
    de: { one: '%lld Foto komprimiert', other: '%lld Fotos komprimiert' },
    ja: { other: '%lld枚の写真を圧縮しました' },
    ko: { other: '%lld장의 사진을 압축했습니다' },
    'zh-Hans': { other: '压缩了 %lld 张照片' },
  },
  'compressed %lld video': {
    de: { one: '%lld Video komprimiert', other: '%lld Videos komprimiert' },
    ja: { other: '%lld本の動画を圧縮しました' },
    ko: { other: '%lld개의 동영상을 압축했습니다' },
    'zh-Hans': { other: '压缩了 %lld 个视频' },
  },
  'cleaned %lld burst photo': {
    de: { one: '%lld Serienfoto bereinigt', other: '%lld Serienfotos bereinigt' },
    ja: { other: '%lld枚のバースト写真を整理しました' },
    ko: { other: '%lld장의 버스트 사진을 정리했습니다' },
    'zh-Hans': { other: '清理了 %lld 张连拍照片' },
  },
  'converted %lld Live Photo': {
    de: { one: '%lld Live Photo konvertiert', other: '%lld Live Photos konvertiert' },
    ja: { other: '%lld枚のLive Photoを変換しました' },
    ko: { other: '%lld장의 Live Photo를 변환했습니다' },
    'zh-Hans': { other: '转换了 %lld 个 Live Photo' },
  },
  'reviewed %lld item': {
    de: { one: '%lld Objekt geprüft', other: '%lld Objekte geprüft' },
    ja: { other: '%lld個の項目を確認しました' },
    ko: { other: '%lld개 항목을 검토했습니다' },
    'zh-Hans': { other: '查看了 %lld 个项目' },
  },
}

function serializeStrings (strings) {
  const lines = Object.keys(strings)
    .sort(byCodeUnit)
    .map((k) => `    ${JSON.stringify(k)}: ${JSON.stringify(strings[k])}`)
  return `{\n  "strings": {\n${lines.join(',\n')}\n  },`
}

function serializePluralEntries (keys, lang) {
  return keys
    .map((key) => {
      const value = P[key][lang]
      const categories = Object.keys(value)
        .map((c) => `      ${JSON.stringify(c)}: ${JSON.stringify(value[c])}`)
        .join(',\n')
      return `    ${JSON.stringify(key)}: {\n${categories}\n    }`
    })
    .join(',\n')
}

function main () {
  if (KEYS.length !== 80) throw new Error(`expected 80 plain keys, got ${KEYS.length}`)
  if (PLURAL_KEYS.length !== 13) throw new Error(`expected 13 plural keys, got ${PLURAL_KEYS.length}`)
  for (const list of [KEYS, PLURAL_KEYS]) {
    const dupes = list.filter((k, i) => list.indexOf(k) !== i)
    if (dupes.length) throw new Error(`duplicate keys: ${JSON.stringify(dupes)}`)
  }

  const pluralKeyOrder = Object.keys(
    JSON.parse(readFileSync(join(here, '_plural-keys.json'), 'utf8'))
  )
  const missingFromOrder = PLURAL_KEYS.filter((k) => !pluralKeyOrder.includes(k))
  if (missingFromOrder.length) {
    throw new Error(`plural keys not in _plural-keys.json: ${JSON.stringify(missingFromOrder)}`)
  }

  for (const lang of LANGS) {
    const path = join(here, `${lang}.json`)
    const raw = readFileSync(path, 'utf8')
    const cut = raw.indexOf(PLURALS_MARKER)
    if (cut < 0) throw new Error(`${lang}: no "plurals" marker found`)
    const head = raw.slice(0, cut)
    const tail = raw.slice(cut)

    const parsed = JSON.parse(raw)
    const beforeStrings = { ...parsed.strings }
    const beforePlurals = { ...parsed.plurals }

    const strings = { ...parsed.strings }
    for (const key of KEYS) {
      const value = T[key]?.[lang]
      if (typeof value !== 'string' || value.length === 0) {
        throw new Error(`${lang}: missing plain translation for ${JSON.stringify(key)}`)
      }
      if (key in strings) throw new Error(`${lang}: plain key already present: ${JSON.stringify(key)}`)
      strings[key] = value
    }

    const newHead = serializeStrings(strings)
    const tailCut = tail.lastIndexOf('\n  }\n}\n')
    if (tailCut < 0) throw new Error(`${lang}: unexpected plurals block ending`)
    const newTail =
      tail.slice(0, tailCut) +
      ',\n' +
      serializePluralEntries(PLURAL_KEYS, lang) +
      '\n  }\n}\n'

    const out = newHead + newTail
    const reparsed = JSON.parse(out)

    // Nothing pre-existing may move: same keys, same values, byte-identical
    // `strings` block for everything that was already there.
    for (const [k, v] of Object.entries(beforeStrings)) {
      if (reparsed.strings[k] !== v) throw new Error(`${lang}: existing string changed: ${JSON.stringify(k)}`)
    }
    for (const [k, v] of Object.entries(beforePlurals)) {
      if (JSON.stringify(reparsed.plurals[k]) !== JSON.stringify(v)) {
        throw new Error(`${lang}: existing plural changed: ${JSON.stringify(k)}`)
      }
    }
    // Regenerating the block with only the pre-existing keys must reproduce the
    // bytes on disk exactly — otherwise the sort/indent convention has drifted.
    if (serializeStrings(beforeStrings) !== head) {
      throw new Error(`${lang}: regenerating the existing strings block is not byte-identical`)
    }

    writeFileSync(path, out)
    console.log(
      `${lang}: strings ${Object.keys(beforeStrings).length} -> ${Object.keys(strings).length}, ` +
        `plurals ${Object.keys(beforePlurals).length} -> ${Object.keys(reparsed.plurals).length}`
    )
  }
}

// Only run when invoked directly; the verifier imports the key lists.
if (process.argv[1] === fileURLToPath(import.meta.url)) main()
