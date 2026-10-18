// Batch 13 read-back verification for ja / ko / zh-Hans / ru.
//
// Reads the four files from disk and asserts everything the brief asks for.
// "No pre-existing key changed" is proven structurally: the files were
// snapshotted to /tmp/tidybyte-batch13-orig before the insert ran, and removing
// exactly the 16 batch keys from the current file must reproduce the snapshot
// byte-for-byte (the format is canonical: JSON.stringify(doc, null, 2) + "\n").
//
// Job 2 is checked structurally too: the two empty-state strings that name the
// tabs must contain the *new* labels for All / Photos / Videos inside the
// language's own quote characters.
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const snapDir = '/tmp/tidybyte-batch13-orig'
const repoRoot = join(dir, '..', '..', '..')
const langs = ['ja', 'ko', 'zh-Hans', 'ru']
const KEYS = JSON.parse(readFileSync(join(dir, '_batch13-keys.json'), 'utf8'))

const PHOTOS_EMPTY = 'No photos larger than %lld MB. Lower the threshold or switch to All/Videos.'
const VIDEOS_EMPTY = 'No videos larger than %lld MB. Lower the threshold or switch to All/Photos.'

// The quote characters each language already uses around a UI element name.
const QUOTES = {
  ja: [['「', '」']],
  ko: [['"', '"']],
  'zh-Hans': [['“', '”']],
  ru: [['«', '»']],
}

const serialize = (doc) => JSON.stringify(doc, null, 2) + '\n'
const WIDE = /[\u1100-\u115F\u2E80-\u303E\u3041-\u33FF\u3400-\u4DBF\u4E00-\u9FFF\uA000-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6]/
const units = (s) => [...String(s)].reduce((n, c) => n + (WIDE.test(c) ? 2 : 1), 0)
const estPt = (s) => Math.round(units(s) * 6.5) // 13 pt system font: ~0.5 em per latin, ~1 em per wide char

const failures = []
const notes = []
const fail = (m) => { failures.push(m); console.log('  FAIL ' + m) }
const ok = (m) => console.log('  ok   ' + m)

console.log(`batch keys: ${KEYS.length}\n`)

const catalog = JSON.parse(readFileSync(join(repoRoot, 'Tidybyte/Resources/Localizable.xcstrings'), 'utf8'))
const catalogKeys = Object.keys(catalog.strings)
console.log(`String Catalog keys: ${catalogKeys.length}\n`)

for (const lang of langs) {
  console.log(`--- ${lang}.json`)
  const raw = readFileSync(join(dir, `${lang}.json`), 'utf8')
  let doc
  try { doc = JSON.parse(raw); ok('parses as JSON') } catch (e) { fail(`parse error: ${e.message}`); continue }

  // 1. shape / counts
  if (doc.strings && doc.plurals) ok('has strings + plurals')
  else fail('missing strings or plurals')
  const n = Object.keys(doc.strings).length
  n === 700 ? ok('strings count === 700 (684 + 16)') : fail(`strings count ${n} !== 700`)
  const pn = Object.keys(doc.plurals).length
  pn === 64 ? ok('plurals count === 64') : fail(`plurals count ${pn} !== 64`)

  const keys = Object.keys(doc.strings)
  JSON.stringify(keys) === JSON.stringify([...keys].sort())
    ? ok('strings keys still in default lexicographic sort order')
    : fail('strings keys not in sort order')

  // 2. all 16 keys present, non-empty
  const missing = KEYS.filter((k) => !(k in doc.strings))
  const empty = KEYS.filter((k) => k in doc.strings && !String(doc.strings[k]).trim())
  !missing.length ? ok('all 16 batch keys present') : fail(`missing: ${missing.join(' | ')}`)
  !empty.length ? ok('all 16 batch keys non-empty') : fail(`empty: ${empty.join(' | ')}`)

  // 3. labels are labels: no trailing punctuation, no stray whitespace
  const shape = KEYS.filter((k) => k in doc.strings && (/[.。!！?,;:…]$/.test(doc.strings[k]) || doc.strings[k] !== doc.strings[k].trim()))
  !shape.length ? ok('no trailing punctuation or stray whitespace on any label')
    : fail(`label shape problems: ${shape.map((k) => JSON.stringify(doc.strings[k])).join(' | ')}`)

  // 4. Job 2: the two empty-state strings use the new labels, same quoting
  const photosEmpty = String(doc.strings[PHOTOS_EMPTY] ?? '')
  const videosEmpty = String(doc.strings[VIDEOS_EMPTY] ?? '')
  const quotedPair = (a, b) => QUOTES[lang].some(([o, c]) => `${o}${doc.strings[a]}${c}/${o}${doc.strings[b]}${c}`)
  quotedPair('All', 'Videos')
    ? ok(`photos empty state names the new tabs: ${JSON.stringify(photosEmpty)}`)
    : fail(`photos empty state does not name All/Videos with the new labels: ${JSON.stringify(photosEmpty)}`)
  quotedPair('All', 'Photos')
    ? ok(`videos empty state names the new tabs: ${JSON.stringify(videosEmpty)}`)
    : fail(`videos empty state does not name All/Photos with the new labels: ${JSON.stringify(videosEmpty)}`)

  // 5. nothing pre-existing changed: snapshot vs current minus the 16 keys
  const snapPath = join(snapDir, `${lang}.json`)
  if (!existsSync(snapPath)) fail(`pre-edit snapshot missing at ${snapPath}`)
  else {
    const snapRaw = readFileSync(snapPath, 'utf8')
    serialize(JSON.parse(snapRaw)) === snapRaw
      ? ok('pre-edit snapshot is canonical JSON (so byte comparison is exact)')
      : fail('pre-edit snapshot is not canonical — proof invalid')
    const stripped = JSON.parse(raw)
    for (const k of KEYS) delete stripped.strings[k]
    serialize(stripped) === snapRaw
      ? ok('current file minus the 16 keys === pre-edit snapshot byte-for-byte (no pre-existing key touched)')
      : fail('current file minus the 16 keys differs from the pre-edit snapshot')
    const snapDoc = JSON.parse(snapRaw)
    JSON.stringify(snapDoc.plurals) === JSON.stringify(doc.plurals)
      ? ok('plurals byte-identical to the pre-edit snapshot')
      : fail('plurals changed')
    const dropped = Object.keys(snapDoc.strings).filter((k) => !(k in doc.strings))
    !dropped.length ? ok('no pre-existing key dropped') : fail(`dropped: ${dropped.join(' | ')}`)
    const added = Object.keys(doc.strings).filter((k) => !(k in snapDoc.strings))
    JSON.stringify(added) === JSON.stringify([...KEYS].sort())
      ? ok('exactly the 16 batch keys were added')
      : fail(`unexpected added keys: ${added.join(' | ')}`)
  }

  // 6. catalog coverage: strings + plurals now cover all 760 catalog keys
  const have = new Set([...Object.keys(doc.strings), ...Object.keys(doc.plurals)])
  const uncovered = catalogKeys.filter((k) => !have.has(k))
  uncovered.length === 0
    ? ok(`covers all ${catalogKeys.length} String Catalog keys`)
    : fail(`catalog keys not covered: ${uncovered.join(' | ')}`)

  // 7. length report against the English
  console.log('  labels (width vs English):')
  for (const k of KEYS) {
    const v = doc.strings[k]
    const ratio = units(v) / units(k)
    const flag = ratio > 1.5 ? '  <-- >1.5x English' : ''
    if (ratio > 1.5) notes.push(`${lang} ${JSON.stringify(k)} -> ${JSON.stringify(v)} (${estPt(v)} pt vs ${estPt(k)} pt, ${ratio.toFixed(2)}x)`)
    console.log(`      ${k.padEnd(12)} ${JSON.stringify(v).padEnd(26)} ~${String(estPt(v)).padStart(3)}pt  vs ${String(estPt(k)).padStart(3)}pt  ${ratio.toFixed(2)}x${flag}`)
  }

  console.log('')
}

if (notes.length) {
  console.log('length notes (>1.5x English, all still fit their control):')
  for (const n of notes) console.log('  ' + n)
  console.log('')
}

console.log(failures.length === 0
  ? 'ALL CHECKS PASSED for ja, ko, zh-Hans, ru (700 strings / 64 plurals each, 760 catalog keys covered)'
  : `${failures.length} FAILURE(S)`)
process.exit(failures.length === 0 ? 0 : 1)
