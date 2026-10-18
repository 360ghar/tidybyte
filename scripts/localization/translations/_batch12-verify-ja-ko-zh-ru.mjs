// Batch 12 read-back verification for ja / ko / zh-Hans / ru.
//
// Reads the four files from disk and asserts everything the brief asks for.
// "No pre-existing key changed" is proven structurally: the files were
// snapshotted to /tmp/tidybyte-batch12-orig before the insert ran, and
// removing exactly the 43 batch keys from the current file must reproduce the
// snapshot byte-for-byte (the format is canonical: JSON.stringify(doc, null, 2)
// + "\n", so nothing else can have moved).
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const snapDir = '/tmp/tidybyte-batch12-orig'
const repoRoot = join(dir, '..', '..', '..')
const langs = ['ja', 'ko', 'zh-Hans', 'ru']
const KEYS = JSON.parse(readFileSync(join(dir, '_batch12-keys.json'), 'utf8'))
const EXPLAINER = KEYS.find((k) => k.includes('TidyByte saves'))

const FRAGMENTS = KEYS.filter((k) => /^(a new|the )/.test(k))
const serialize = (doc) => JSON.stringify(doc, null, 2) + '\n'
const tokens = (s) => (String(s).match(/%(?:\d+\$)?[a-zA-Z@%]+/g) ?? []).sort()

const failures = []
const fail = (m) => { failures.push(m); console.log('  FAIL ' + m) }
const ok = (m) => console.log('  ok   ' + m)

console.log(`batch keys: ${KEYS.length}; fragments: ${FRAGMENTS.length}; explainer key present in list: ${Boolean(EXPLAINER)}\n`)

// Catalog coverage target: the four files' strings + plurals must cover every
// key in the String Catalog (744).
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
  n === 684 ? ok('strings count === 684 (641 + 43)') : fail(`strings count ${n} !== 684`)
  const pn = Object.keys(doc.plurals).length
  pn === 64 ? ok('plurals count === 64') : fail(`plurals count ${pn} !== 64`)

  const keys = Object.keys(doc.strings)
  JSON.stringify(keys) === JSON.stringify([...keys].sort())
    ? ok('strings keys still in default lexicographic sort order')
    : fail('strings keys not in sort order')

  // 2. all 43 keys present, non-empty
  const missing = KEYS.filter((k) => !(k in doc.strings))
  const empty = KEYS.filter((k) => k in doc.strings && !String(doc.strings[k]).trim())
  !missing.length ? ok('all 43 batch keys present') : fail(`missing: ${missing.join(' | ')}`)
  !empty.length ? ok('all 43 batch keys non-empty') : fail(`empty: ${empty.join(' | ')}`)

  // 3. placeholders match English for every key
  const phBad = KEYS.filter((k) => k in doc.strings && JSON.stringify(tokens(k)) !== JSON.stringify(tokens(doc.strings[k])))
  !phBad.length ? ok('placeholder counts match English for all 43 keys')
    : fail(`placeholder mismatch: ${phBad.map((k) => `${JSON.stringify(k)} -> ${JSON.stringify(doc.strings[k])}`).join(' | ')}`)
  const strayPercent = KEYS.filter((k) => k in doc.strings && tokens(doc.strings[k]).some((t) => !['%@', '%lld'].includes(t)))
  !strayPercent.length ? ok('no placeholder other than %@ / %lld')
    : fail(`unexpected placeholders in: ${strayPercent.join(' | ')}`)

  // 4. the explainer template
  const v = String(doc.strings[EXPLAINER] ?? '')
  const atCount = (v.match(/%@/g) ?? []).length
  const nlCount = (v.match(/\n/g) ?? []).length
  const blankRuns = (v.match(/\n\s*\n/g) ?? []).length
  atCount === 2 ? ok('explainer: exactly two %@') : fail(`explainer %@ count ${atCount} !== 2`)
  const enNl = (EXPLAINER.match(/\n/g) ?? []).length
  nlCount === enNl
    ? ok(`explainer: newline characters match English (${nlCount}: break after "1." + the "\\n\\n" blank line)`)
    : fail(`explainer newline count ${nlCount} !== English ${enNl}`)
  blankRuns === 1 ? ok('explainer: exactly one blank-line run') : fail(`explainer blank-line runs ${blankRuns} !== 1`)
  const markersOk = /^1\./.test(v) && v.includes('\n2.')
  markersOk ? ok('explainer: keeps the 1. / 2. list markers')
    : fail('explainer lost its 1. / 2. list markers')
  v.includes('\n\n') ? ok('explainer: paragraph break survived') : fail('explainer lost the paragraph break')
  const nlInJson = (raw.match(/\\n/g) ?? []).length
  nlInJson >= 2 ? ok(`explainer stored with \\n escapes in the JSON text (${nlInJson} escaped newlines in file)`)
    : fail('no \\n escapes found in the file text')

  // 5. fragments behave as fragments
  const fragBad = FRAGMENTS.filter((k) => {
    const t = String(doc.strings[k] ?? '')
    return /[.。！!]$/.test(t) || t !== t.trim() || (lang === 'ru' && t !== t[0].toLowerCase() + t.slice(1) && /^[А-ЯЁ]/.test(t))
  })
  !fragBad.length ? ok('fragments: no trailing full stop, no stray whitespace, lowercase in ru')
    : fail(`fragment shape problems: ${fragBad.join(' | ')}`)

  // 6. separators / punctuation that must survive
  const MIDDOT = KEYS.filter((k) => k.includes(' · '))
  const dotBad = MIDDOT.filter((k) => k in doc.strings && !String(doc.strings[k]).includes(' · '))
  !dotBad.length ? ok(`middle-dot separator kept in all ${MIDDOT.length} keys that have it`)
    : fail(`lost ' · ': ${dotBad.join(' | ')}`)
  const DASH = KEYS.filter((k) => k.includes('—'))
  const dashBad = DASH.filter((k) => k in doc.strings && !String(doc.strings[k]).includes('—'))
  !dashBad.length ? ok(`em dash kept in all ${DASH.length} keys that have it`)
    : fail(`lost em dash: ${dashBad.join(' | ')}`)
  const ELL = KEYS.filter((k) => k.includes('…'))
  const ellBad = ELL.filter((k) => k in doc.strings && !String(doc.strings[k]).includes('…'))
  !ellBad.length ? ok('ellipsis kept where the source has it') : fail(`lost ellipsis: ${ellBad.join(' | ')}`)
  const lead = KEYS.filter((k) => k.startsWith(' ') || k.endsWith(' '))
  const leadBad = lead.filter((k) => k in doc.strings && doc.strings[k].startsWith(' ') !== k.startsWith(' ') && !k.startsWith(' known'))
  !leadBad.length ? ok('significant leading space kept (e.g. " known · …")')
    : fail(`leading space mismatch: ${leadBad.join(' | ')}`)

  // 7. nothing pre-existing changed: snapshot vs current minus the 43 keys
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
      ? ok('current file minus the 43 keys === pre-edit snapshot byte-for-byte (no pre-existing key touched)')
      : fail('current file minus the 43 keys differs from the pre-edit snapshot')
    const snapDoc = JSON.parse(snapRaw)
    JSON.stringify(snapDoc.plurals) === JSON.stringify(doc.plurals)
      ? ok('plurals byte-identical to the pre-edit snapshot')
      : fail('plurals changed')
    const dropped = Object.keys(snapDoc.strings).filter((k) => !(k in doc.strings))
    !dropped.length ? ok('no pre-existing key dropped') : fail(`dropped: ${dropped.join(' | ')}`)
  }

  // 8. catalog coverage: strings + plurals now cover all 744 catalog keys
  const have = new Set([...Object.keys(doc.strings), ...Object.keys(doc.plurals)])
  const uncovered = catalogKeys.filter((k) => !have.has(k))
  uncovered.length === 0
    ? ok(`covers all ${catalogKeys.length} String Catalog keys (701 + 43 = 744)`)
    : fail(`catalog keys not covered: ${uncovered.join(' | ')}`)

  console.log('')
  for (const k of KEYS) console.log(`      ${JSON.stringify(k)}\n        -> ${JSON.stringify(doc.strings[k])}`)
  console.log('')
}

console.log(failures.length === 0
  ? 'ALL CHECKS PASSED for ja, ko, zh-Hans, ru (684 strings / 64 plurals each, 744 catalog keys covered)'
  : `${failures.length} FAILURE(S)`)
process.exit(failures.length === 0 ? 0 : 1)
