// Batch 13 insertion for ja / ko / zh-Hans / ru.
//
// 16 keys, taken verbatim from _batch13-keys.json. Writes with the file's
// existing shape: { strings, plurals }, 2-space indent, strings keys in default
// lexicographic order, trailing newline, plurals untouched.
//
// These are segmented-control and menu labels, so they are short on purpose.
// Where the app already had a word for the same concept, the label reuses it:
//
//   ja  "Find exact & visual duplicates" -> 完全な重複と見た目の重複
//       "Find Similar Photos"            -> 類似した写真
//       => Exact = 完全一致, Visual = 類似 (類似 is the better standalone
//          label; the body text's 見た目 does not work alone on a segment)
//   ko  "Find exact & visual duplicates" -> 완전 중복과 시각적 중복
//       "Large File Threshold"           -> 대용량 파일 기준
//       => Exact = 완전 일치, Visual = 시각적 유사, Largest = 용량순
//   zh  "Find exact & visual duplicates" -> 查找精确和视觉重复项
//       => Exact = 精确, Visual = 视觉
//   ru  "Find exact & visual duplicates" -> Найти точные и визуальные дубликаты
//       => Exact = Точные, Visual = Визуальные
//
// The pre-existing "Balanced" key fixes the middle of Strict/Balanced/Broad:
// ja バランス, ko 균형, zh 均衡, ru Сбалансированно (adverb). The new Strict and
// Broad match that form: ja 厳しめ / 広め, ko 엄격 / 광범위, zh 严格 / 宽松,
// ru Строго / Широко.
//
// Where the labels sit (from the Swift source):
//   .segmented — All/Photos/Videos (Large Files), Exact/Visual/All (Duplicates),
//                By Year/By Source (Storage), Low/Medium/High + Strict/Balanced/
//                Broad (Settings)
//   .menu      — Largest/Newest/Oldest/Filename (Large Files) and the same
//                Newest/Oldest/Largest in the Screenshots header, so those four
//                have room; ru still keeps them tight for the header's
//                collapsed menu button.
import { readFileSync, writeFileSync, mkdirSync, existsSync, copyFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const KEYS = JSON.parse(readFileSync(join(dir, '_batch13-keys.json'), 'utf8'))

// Proof snapshot for the verify script: taken once, before any write.
const snapDir = '/tmp/tidybyte-batch13-orig'
if (!existsSync(snapDir)) mkdirSync(snapDir, { recursive: true })

const translations = {
  ja: {
    // すべて is what iOS ja shows for "All" in a segmented control, and it is
    // the word the two empty-state strings already quote.
    All: 'すべて',
    // 厳しめ / 広め pair with the existing バランス as a three-step scale.
    Broad: '広め',
    // 取得元別 (not ソース別: ソース reads as "sauce" out of context).
    'By Source': '取得元別',
    'By Year': '年別',
    Exact: '完全一致',
    // Sort menu, so the 〜順 suffix fits.
    Filename: 'ファイル名順',
    High: '高',
    Largest: '大きい順',
    Low: '低',
    Medium: '中',
    Newest: '新しい順',
    Oldest: '古い順',
    Photos: '写真',
    Strict: '厳しめ',
    Videos: 'ビデオ',
    Visual: '類似',
  },
  ko: {
    All: '모두',
    Broad: '광범위',
    'By Source': '출처별',
    'By Year': '연도별',
    Exact: '완전 일치',
    Filename: '파일명순',
    High: '높음',
    // 용량순 matches the app's own 대용량 파일 wording for size.
    Largest: '용량순',
    Low: '낮음',
    Medium: '보통',
    Newest: '최신순',
    Oldest: '오래된순',
    Photos: '사진',
    Strict: '엄격',
    Videos: '동영상',
    Visual: '시각적 유사',
  },
  'zh-Hans': {
    All: '全部',
    Broad: '宽松',
    'By Source': '按来源',
    'By Year': '按年份',
    Exact: '精确',
    Filename: '文件名',
    High: '高',
    Largest: '最大',
    Low: '低',
    Medium: '中',
    Newest: '最新',
    Oldest: '最早',
    Photos: '照片',
    Strict: '严格',
    Videos: '视频',
    Visual: '视觉',
  },
  ru: {
    All: 'Все',
    Broad: 'Широко',
    'By Source': 'По источникам',
    'By Year': 'По годам',
    Exact: 'Точные',
    // «По имени» is Apple ru's own wording for sorting by name.
    Filename: 'По имени',
    // Feminine, agreeing with «чувствительность» in «Чувствительность
    // определения размытия» / «Чувствительность умных категорий».
    High: 'Высокая',
    // «Сначала …» is the Russian idiom for a sort direction.
    Largest: 'Сначала большие',
    Low: 'Низкая',
    Medium: 'Средняя',
    Newest: 'Сначала новые',
    Oldest: 'Сначала старые',
    Photos: 'Фото',
    Strict: 'Строго',
    Videos: 'Видео',
    Visual: 'Визуальные',
  },
}

for (const lang of Object.keys(translations)) {
  const map = translations[lang]
  const keys = Object.keys(map)
  const unknown = keys.filter((k) => !KEYS.includes(k))
  const missing = KEYS.filter((k) => !(k in map))
  if (unknown.length) throw new Error(`${lang}: translation for unknown key(s): ${unknown.join(' | ')}`)
  if (missing.length) throw new Error(`${lang}: missing translation(s): ${missing.join(' | ')}`)
  if (keys.length !== 16) throw new Error(`${lang}: expected 16 translations, got ${keys.length}`)
  for (const k of keys) {
    const v = String(map[k])
    if (!v.trim()) throw new Error(`${lang}: empty value for ${JSON.stringify(k)}`)
    if (v !== v.trim()) throw new Error(`${lang}: untrimmed value for ${JSON.stringify(k)}`)
  }

  const path = join(dir, `${lang}.json`)
  const snapPath = join(snapDir, `${lang}.json`)
  if (!existsSync(snapPath)) copyFileSync(path, snapPath)

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

console.log('\nlabels:')
for (const lang of Object.keys(translations)) {
  console.log(`  ${lang}: ` + KEYS.map((k) => `${k}=${JSON.stringify(translations[lang][k])}`).join(', '))
}
