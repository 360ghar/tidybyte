// Batch 12 insertion for ja / ko / zh-Hans / ru.
//
// 43 keys, taken verbatim from _batch12-keys.json. Writes with the file's
// existing shape: { strings, plurals }, 2-space indent, strings keys in default
// lexicographic order, trailing newline, plurals untouched.
//
// Six of the keys are sentence fragments that slot into
// ReplaceOriginalsNotice.explainer(copies:originals:), and one key is the
// multi-line template itself (real newlines, two %@).
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const KEYS = JSON.parse(readFileSync(join(dir, '_batch12-keys.json'), 'utf8'))

// The template key, written with real newlines exactly as it appears in
// _batch12-keys.json.
const EXPLAINER =
  "1. TidyByte saves %@.\n2. When all copies are saved, iOS asks you to delete %@.\n\nIf you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days."

if (!KEYS.includes(EXPLAINER)) throw new Error('EXPLAINER key does not match _batch12-keys.json')

// "Don't Allow" below is the iOS alert button, so each language uses the
// wording its own iOS shows on the delete confirmation.
const translations = {
  ja: {
    ' known · %lld sizes unavailable': ' 判明分 · %lld件はサイズ不明',
    [EXPLAINER]:
      '1. TidyByteが%@を保存します。\n2. すべてのコピーの保存が完了すると、iOSが%@の削除を求めます。\n\n「許可しない」をタップすると、両方のバージョンが残ります。削除された元の項目は「最近削除した項目」に30日間残ります。',
    'Best': 'ベスト',
    'Best exposed': '露出が最適',
    'Best overall': '総合的に最良',
    'Best quality': '最高画質',
    'Blur': 'ぼやけ',
    'Brightness': '明るさ',
    "Couldn't prepare the selected items to share.": '選択した項目を共有する準備ができませんでした。',
    'Darkness': '暗さ',
    'Detected by file name heuristics — may include some camera photos':
      'ファイル名からの推定で検出 — カメラで撮影した写真が含まれる場合があります',
    "Don't Delete": '削除しない',
    'Failed to save compressed photo to library.': '圧縮した写真をライブラリに保存できませんでした。',
    'Failed to save compressed video to library.': '圧縮したビデオをライブラリに保存できませんでした。',
    'Highest res': '最高解像度',
    'In iCloud.': 'iCloudにあります。',
    'Keep as Best': 'ベストとして残す',
    'Keeping this · %@': 'これを残す · %@',
    'Lens smudge confidence': 'レンズの汚れの信頼度',
    'Live Photo.': 'Live Photoです。',
    'Most recent': '最新',
    'No Large Files': '大きいファイルはありません',
    'No Large Videos': '大きいビデオはありません',
    'No files larger than %lld MB. Lower the threshold to see more.':
      'サイズが%lld MBを超えるファイルはありません。しきい値を下げると表示されます。',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      'サイズが%lld MBを超える写真はありません。しきい値を下げるか、「すべて」/「ビデオ」に切り替えてください。',
    'No savings — kept original': '節約なし — 元のまま残しました',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      'サイズが%lld MBを超えるビデオはありません。しきい値を下げるか、「すべて」/「写真」に切り替えてください。',
    'Not loaded yet. Delete is off until it shows.':
      'まだ読み込まれていません。表示されるまで削除はできません。',
    'Original kept — both versions in your library':
      '元のまま残しました — 両方のバージョンがライブラリにあります',
    'Recommended: %@': '推奨: %@',
    'Sharpest': '最もシャープ',
    'Sizes unavailable': 'サイズ不明',
    'Step 1 of 2 · Saving copy %lld of %lld': 'ステップ 1/2 · コピー %lld/%lld を保存中',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      'ステップ 2/2 · iOSのアラートで元の項目の削除を確認してください',
    'Working…': '処理中…',
    'Your choice': 'あなたの選択',
    'Your library changed during analysis. Scan again for current results.':
      '解析中にライブラリが変更されました。最新の結果を得るには再スキャンしてください。',
    'a new, smaller copy of each photo': '各写真の小さくなった新しいコピー',
    'a new, smaller copy of each video': '各ビデオの小さくなった新しいコピー',
    'the Live Photos': '元のLive Photo',
    'the original photos': '元の写真',
    'the original videos': '元のビデオ',
    'the still image of each Live Photo as a new photo': '各Live Photoの静止画から作られた新しい写真',
  },
  ko: {
    ' known · %lld sizes unavailable': ' 확인됨 · %lld개는 크기를 알 수 없음',
    [EXPLAINER]:
      '1. TidyByte가 %@을 저장합니다.\n2. 모든 복사본이 저장되면 iOS가 %@ 삭제 여부를 묻습니다.\n\n"허용 안 함"을 탭하면 두 버전 모두 유지됩니다. 삭제된 원본은 30일 동안 최근 삭제된 항목에 남아 있습니다.',
    'Best': '최고',
    'Best exposed': '노출 최적',
    'Best overall': '종합 최고',
    'Best quality': '최고 품질',
    'Blur': '흐림',
    'Brightness': '밝음',
    "Couldn't prepare the selected items to share.": '선택한 항목을 공유할 준비를 하지 못했습니다.',
    'Darkness': '어두움',
    'Detected by file name heuristics — may include some camera photos':
      '파일 이름 추정으로 감지됨 — 카메라로 찍은 사진이 일부 포함될 수 있습니다',
    "Don't Delete": '삭제 안 함',
    'Failed to save compressed photo to library.': '압축한 사진을 사진 보관함에 저장하지 못했습니다.',
    'Failed to save compressed video to library.': '압축한 동영상을 사진 보관함에 저장하지 못했습니다.',
    'Highest res': '최고 해상도',
    'In iCloud.': 'iCloud에 있습니다.',
    'Keep as Best': '최고로 남기기',
    'Keeping this · %@': '이 항목 남기기 · %@',
    'Lens smudge confidence': '렌즈 얼룩 신뢰도',
    'Live Photo.': 'Live Photo입니다.',
    'Most recent': '최신',
    'No Large Files': '대용량 파일 없음',
    'No Large Videos': '대용량 동영상 없음',
    'No files larger than %lld MB. Lower the threshold to see more.':
      '%lld MB보다 큰 파일이 없습니다. 기준을 낮추면 더 볼 수 있습니다.',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      '%lld MB보다 큰 사진이 없습니다. 기준을 낮추거나 "모두"/"동영상"으로 전환하세요.',
    'No savings — kept original': '절약 없음 — 원본 유지됨',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      '%lld MB보다 큰 동영상이 없습니다. 기준을 낮추거나 "모두"/"사진"으로 전환하세요.',
    'Not loaded yet. Delete is off until it shows.':
      '아직 로드되지 않았습니다. 표시될 때까지 삭제할 수 없습니다.',
    'Original kept — both versions in your library':
      '원본 유지됨 — 두 버전 모두 보관함에 있음',
    'Recommended: %@': '권장: %@',
    'Sharpest': '가장 선명함',
    'Sizes unavailable': '크기를 알 수 없음',
    'Step 1 of 2 · Saving copy %lld of %lld': '1/2 단계 · 복사본 %lld/%lld 저장 중',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      '2/2 단계 · iOS 알림에서 원본 삭제를 확인하세요',
    'Working…': '작업 중…',
    'Your choice': '직접 선택',
    'Your library changed during analysis. Scan again for current results.':
      '분석 중에 사진 보관함이 변경되었습니다. 최신 결과를 보려면 다시 스캔하세요.',
    'a new, smaller copy of each photo': '각 사진의 더 작은 새 복사본',
    'a new, smaller copy of each video': '각 동영상의 더 작은 새 복사본',
    'the Live Photos': '원본 Live Photo',
    'the original photos': '원본 사진',
    'the original videos': '원본 동영상',
    'the still image of each Live Photo as a new photo': '각 Live Photo의 정지 이미지로 만든 새 사진',
  },
  'zh-Hans': {
    ' known · %lld sizes unavailable': ' 已知 · %lld 项大小不可用',
    [EXPLAINER]:
      '1. TidyByte 会保存%@。\n2. 所有副本保存完成后，iOS 会请求删除%@。\n\n如果你点按“不允许”，两个版本都会保留。删除的原件会在“最近删除”中保留 30 天。',
    'Best': '最佳',
    'Best exposed': '曝光最佳',
    'Best overall': '整体最佳',
    'Best quality': '最佳画质',
    'Blur': '模糊',
    'Brightness': '亮度',
    "Couldn't prepare the selected items to share.": '无法准备要共享的所选项目。',
    'Darkness': '暗度',
    'Detected by file name heuristics — may include some camera photos':
      '通过文件名推测检测 — 可能包含一些相机拍摄的照片',
    "Don't Delete": '不删除',
    'Failed to save compressed photo to library.': '无法将压缩后的照片存储到图库。',
    'Failed to save compressed video to library.': '无法将压缩后的视频存储到图库。',
    'Highest res': '最高分辨率',
    'In iCloud.': '在 iCloud 中。',
    'Keep as Best': '保留为最佳',
    'Keeping this · %@': '保留此项 · %@',
    'Lens smudge confidence': '镜头污渍置信度',
    'Live Photo.': 'Live Photo。',
    'Most recent': '最新',
    'No Large Files': '没有大体积文件',
    'No Large Videos': '没有大体积视频',
    'No files larger than %lld MB. Lower the threshold to see more.':
      '没有大于 %lld MB 的文件。降低阈值即可看到更多。',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      '没有大于 %lld MB 的照片。降低阈值或切换到“全部”/“视频”。',
    'No savings — kept original': '无节省 — 已保留原件',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      '没有大于 %lld MB 的视频。降低阈值或切换到“全部”/“照片”。',
    'Not loaded yet. Delete is off until it shows.': '尚未载入。显示之前无法删除。',
    'Original kept — both versions in your library': '原件已保留 — 两个版本都在你的图库中',
    'Recommended: %@': '建议：%@',
    'Sharpest': '最清晰',
    'Sizes unavailable': '大小不可用',
    'Step 1 of 2 · Saving copy %lld of %lld': '第 1/2 步 · 正在保存副本 %lld/%lld',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      '第 2/2 步 · 在 iOS 提醒中确认删除原件',
    'Working…': '正在处理…',
    'Your choice': '你的选择',
    'Your library changed during analysis. Scan again for current results.':
      '分析期间你的图库发生了变化。请重新扫描以获取最新结果。',
    'a new, smaller copy of each photo': '每张照片更小的新副本',
    'a new, smaller copy of each video': '每个视频更小的新副本',
    'the Live Photos': '原始 Live Photos',
    'the original photos': '原始照片',
    'the original videos': '原始视频',
    'the still image of each Live Photo as a new photo': '每个 Live Photo 的静帧生成的新照片',
  },
  ru: {
    ' known · %lld sizes unavailable': ' учтено · %lld размеров недоступно',
    [EXPLAINER]:
      '1. TidyByte сохраняет %@.\n2. Когда все копии сохранены, iOS предлагает удалить %@.\n\nЕсли нажать «Не разрешать», обе версии останутся у вас. Удаленные оригиналы хранятся в «Недавно удаленные» 30 дней.',
    'Best': 'Лучшее',
    'Best exposed': 'Лучшая экспозиция',
    'Best overall': 'Лучшее в целом',
    'Best quality': 'Лучшее качество',
    'Blur': 'Размытие',
    'Brightness': 'Яркость',
    "Couldn't prepare the selected items to share.":
      'Не удалось подготовить выбранные объекты для отправки.',
    'Darkness': 'Темнота',
    'Detected by file name heuristics — may include some camera photos':
      'Определено по имени файла — может включать фото с камеры',
    "Don't Delete": 'Не удалять',
    'Failed to save compressed photo to library.': 'Не удалось сохранить сжатое фото в медиатеку.',
    'Failed to save compressed video to library.': 'Не удалось сохранить сжатое видео в медиатеку.',
    'Highest res': 'Макс. разрешение',
    'In iCloud.': 'В iCloud.',
    'Keep as Best': 'Оставить как лучшее',
    'Keeping this · %@': 'Оставляем это · %@',
    'Lens smudge confidence': 'Достоверность загрязнения объектива',
    'Live Photo.': 'Live Photo.',
    'Most recent': 'Самое новое',
    'No Large Files': 'Больших файлов нет',
    'No Large Videos': 'Больших видео нет',
    'No files larger than %lld MB. Lower the threshold to see more.':
      'Нет файлов больше %lld MB. Снизьте порог, чтобы увидеть больше.',
    'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.':
      'Нет фото больше %lld MB. Снизьте порог или переключитесь на «Все»/«Видео».',
    'No savings — kept original': 'Без экономии — оригинал сохранен',
    'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.':
      'Нет видео больше %lld MB. Снизьте порог или переключитесь на «Все»/«Фото».',
    'Not loaded yet. Delete is off until it shows.':
      'Еще не загружено. Удаление недоступно, пока оно не появится.',
    'Original kept — both versions in your library':
      'Оригинал сохранен — обе версии в вашей медиатеке',
    'Recommended: %@': 'Рекомендуется: %@',
    'Sharpest': 'Самое четкое',
    'Sizes unavailable': 'Размеры недоступны',
    'Step 1 of 2 · Saving copy %lld of %lld': 'Шаг 1 из 2 · Сохранение копии %lld из %lld',
    'Step 2 of 2 · Confirm in the iOS alert to delete the originals':
      'Шаг 2 из 2 · Подтвердите удаление оригиналов в уведомлении iOS',
    'Working…': 'Обработка…',
    'Your choice': 'Ваш выбор',
    'Your library changed during analysis. Scan again for current results.':
      'Во время анализа медиатека изменилась. Повторите сканирование, чтобы получить актуальные результаты.',
    'a new, smaller copy of each photo': 'новую уменьшенную копию каждого фото',
    'a new, smaller copy of each video': 'новую уменьшенную копию каждого видео',
    'the Live Photos': 'оригинальные Live Photo',
    'the original photos': 'оригинальные фото',
    'the original videos': 'оригинальные видео',
    'the still image of each Live Photo as a new photo': 'новое фото из статичного кадра каждого Live Photo',
  },
}

for (const lang of Object.keys(translations)) {
  const map = translations[lang]
  const keys = Object.keys(map)
  const unknown = keys.filter((k) => !KEYS.includes(k))
  const missing = KEYS.filter((k) => !(k in map))
  if (unknown.length) throw new Error(`${lang}: translation for unknown key(s): ${unknown.join(' | ')}`)
  if (missing.length) throw new Error(`${lang}: missing translation(s): ${missing.join(' | ')}`)
  if (keys.length !== 43) throw new Error(`${lang}: expected 43 translations, got ${keys.length}`)

  const path = join(dir, `${lang}.json`)
  const doc = JSON.parse(readFileSync(path, 'utf8'))
  const before = Object.keys(doc.strings).length

  for (const k of keys) {
    if (k in doc.strings) throw new Error(`${lang}: key already present: ${JSON.stringify(k)}`)
    doc.strings[k] = map[k]
  }

  const sorted = {}
  for (const k of Object.keys(doc.strings).sort()) sorted[k] = doc.strings[k]
  doc.strings = sorted

  writeFileSync(path, JSON.stringify(doc, null, 2) + '\n')
  console.log(`${lang}.json: strings ${before} -> ${Object.keys(doc.strings).length}, plurals ${Object.keys(doc.plurals).length} (untouched)`)
}
