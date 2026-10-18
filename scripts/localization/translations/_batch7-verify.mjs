// Independent read-back verification for batch 7 (de/ja/ko/zh-Hans).
//
// Reads the four translation files fresh from disk and checks them against:
//   * the pre-edit snapshots in /tmp/tidybyte-batch7-orig, and
//   * the shipped String Catalog, which is the independent source of truth for
//     which keys exist (the 57 new keys are the catalog keys the snapshot had
//     no entry for at all).
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const root = join(dir, '..', '..', '..')
const snapDir = '/tmp/tidybyte-batch7-orig'
const langs = ['de', 'ja', 'ko', 'zh-Hans']

const keepLiteral = ['TidyByte', 'iOS', 'iPhone', 'iPad', 'iCloud', 'HEIC', 'Live Photos', 'Live Photo', 'MB', 'Screen Time']
const placeholderRe = /%(?:\d+\$)?(?:\.\d+)?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g

const failures = []
const fail = (m) => { failures.push(m); console.log('FAIL: ' + m) }
const ok = (m) => console.log('  ok  ' + m)

function placeholders(text) {
  const out = []
  let m
  placeholderRe.lastIndex = 0
  while ((m = placeholderRe.exec(text)) !== null) out.push(m[1] === '%' ? '%%' : m[1])
  return out
}

// --- canonical key set, derived from the shipped catalog -------------------
const catalog = JSON.parse(readFileSync(join(root, 'Tidybyte/Resources/Localizable.xcstrings'), 'utf8'))
const catalogKeys = Object.keys(catalog.strings ?? {})
console.log(`String Catalog: ${catalogKeys.length} keys`)

const snapshots = {}
for (const l of langs) {
  const p = join(snapDir, `${l}.json`)
  if (!existsSync(p)) { console.log(`FATAL: missing snapshot ${p}`); process.exit(1) }
  snapshots[l] = JSON.parse(readFileSync(p, 'utf8'))
}

const snapshotKeys = new Set([...Object.keys(snapshots.de.strings), ...Object.keys(snapshots.de.plurals)])
const expectedNew = catalogKeys.filter((k) => !snapshotKeys.has(k))
console.log(`catalog keys with no entry in the pre-edit file: ${expectedNew.length}`)
if (expectedNew.length !== 57) fail(`expected 57 new keys, derived ${expectedNew.length}`)

const phKeys = expectedNew.filter((k) => placeholders(k).length > 0)
console.log(`new keys carrying placeholders: ${phKeys.length} (${phKeys.map((k) => placeholders(k).join('')).join(', ')})`)
console.log('')

for (const l of langs) {
  const raw = readFileSync(join(dir, `${l}.json`), 'utf8')
  let doc
  try { doc = JSON.parse(raw) } catch (e) { fail(`${l}: JSON.parse failed: ${e.message}`); continue }

  const s = doc.strings
  const before = snapshots[l]
  console.log(`--- ${l}.json (${raw.length} bytes on disk)`)

  // 1. parses + shape
  if (!s || typeof s !== 'object') { fail(`${l}: no strings object`); continue }
  if (!doc.plurals || Object.keys(doc.plurals).length !== 51) fail(`${l}: plurals block not 51 keys`)
  else ok('parses; plurals block intact (51 keys)')

  // 2. count
  const n = Object.keys(s).length
  if (n === 552) ok('Object.keys(strings).length === 552')
  else fail(`${l}: key count ${n} !== 552`)

  // 3. all 57 new keys present and non-empty
  const missing = expectedNew.filter((k) => !(k in s))
  const empty = expectedNew.filter((k) => k in s && !String(s[k]).trim())
  if (missing.length === 0 && empty.length === 0) ok('all 57 new keys present and non-empty')
  else {
    if (missing.length) fail(`${l}: missing keys: ${missing.join(' | ')}`)
    if (empty.length) fail(`${l}: empty values: ${empty.join(' | ')}`)
  }

  // 4. no pre-existing key changed value; no pre-existing key dropped
  const priorKeys = Object.keys(before.strings)
  const changed = priorKeys.filter((k) => s[k] !== before.strings[k])
  if (changed.length === 0) ok(`all ${priorKeys.length} pre-existing keys unchanged (no drops, no edits)`)
  else fail(`${l}: pre-existing keys changed/dropped: ${changed.join(' | ')}`)

  // 5. nothing changed in plurals
  if (JSON.stringify(doc.plurals) !== JSON.stringify(before.plurals)) fail(`${l}: plurals changed`)
  else ok('plurals deep-equal to the pre-edit snapshot')

  // 6. key order still the file's default code-unit sort
  const keys = Object.keys(s)
  if (JSON.stringify(keys) === JSON.stringify([...keys].sort())) ok('strings keys sorted as before')
  else fail(`${l}: strings keys not sorted`)

  // 7. every placeholder appears exactly once per translation, matching English
  const badPh = []
  for (const k of phKeys) {
    const want = placeholders(k).sort().join(',')
    const got = placeholders(String(s[k])).sort().join(',')
    if (want !== got) badPh.push(`${k} -> want [${want}] got [${got}]`)
    const once = placeholders(String(s[k])).length === 1
    if (!once) badPh.push(`${k} -> placeholder count ${placeholders(String(s[k])).length} !== 1`)
  }
  if (badPh.length === 0) ok(`placeholder parity: all ${phKeys.length} placeholder keys carry each specifier exactly once`)
  else fail(`${l}: placeholder mismatch: ${badPh.join(' | ')}`)

  // 8. trailing punctuation matches the English source, allowing the
  // full-width equivalents ja/zh-Hans use (。？！) for . ? !
  const normalizePunct = (t) => t.replace(/。/g, '.').replace(/？/g, '?').replace(/！/g, '!')
  const tail = (t) => (normalizePunct(t).match(/[.?!]+$/) ?? [''])[0]
  const punctBad = []
  for (const k of expectedNew) {
    if (tail(k) !== tail(String(s[k]))) punctBad.push(`${k} -> want "${tail(k)}" got "${tail(String(s[k]))}"`)
  }
  if (punctBad.length === 0) ok('trailing punctuation matches the English source on all 57 keys')
  else fail(`${l}: punctuation mismatch: ${punctBad.join(' | ')}`)

  // 9. keepLiteral terms not translated away
  const litBad = []
  for (const k of expectedNew) {
    for (const term of keepLiteral) {
      if (!k.includes(term)) continue
      if (!String(s[k]).includes(term)) litBad.push(`${k}: lost "${term}"`)
    }
  }
  if (litBad.length === 0) ok('keepLiteral terms (TidyByte/iOS/iPhone/iCloud/Screen Time) preserved')
  else fail(`${l}: ${litBad.join(' | ')}`)

  // 10. em dash kept where the source has one
  const dashKeys = expectedNew.filter((k) => k.includes('—'))
  const dashBad = dashKeys.filter((k) => !String(s[k]).includes('—'))
  if (dashBad.length === 0) ok(`em dash preserved on all ${dashKeys.length} keys that have one`)
  else fail(`${l}: em dash lost: ${dashBad.join(' | ')}`)

  // 11. no value accidentally left in English
  const identical = expectedNew.filter((k) => s[k] === k)
  if (identical.length === 0) ok('no value left as the English source')
  else fail(`${l}: untranslated values: ${identical.join(' | ')}`)

  // 12. end-to-end: every catalog key now resolves for this language
  const resolvable = new Set([...Object.keys(s), ...Object.keys(doc.plurals)])
  const unresolved = catalogKeys.filter((k) => !resolvable.has(k))
  if (unresolved.length === 0) ok(`all ${catalogKeys.length} catalog keys resolve (0 untranslated)`)
  else fail(`${l}: ${unresolved.length} catalog keys still unresolved: ${unresolved.join(' | ')}`)

  console.log('')
}

console.log(failures.length === 0
  ? 'ALL CHECKS PASSED for de, ja, ko, zh-Hans (552 keys each, read back from disk)'
  : `${failures.length} FAILURE(S)`)
process.exit(failures.length === 0 ? 0 : 1)
