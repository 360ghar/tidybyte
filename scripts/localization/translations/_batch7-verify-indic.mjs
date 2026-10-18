// Independent read-back verification for batch 7 (mr/gu/pa/ta).
// Reads the four files fresh from disk and compares against the pre-edit
// snapshots in /tmp/tidybyte-batch7-orig. The expected 57 new keys are derived
// from the batch-7 brief, plus the one key the brief's enumeration omits
// ("Failed to re-encode the photo." — the `encodeFailed` case of the same
// converted `errorDescription` switch).
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const snapDir = '/tmp/tidybyte-batch7-orig'
const langs = ['mr', 'gu', 'pa', 'ta']

const keepLiteral = ['TidyByte', 'iOS', 'iPhone', 'iPad', 'HEIC', 'Live Photos', 'Live Photo', 'MB', 'iCloud', 'Screen Time']
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

// Canonical new-key set: the brief's table cells, plus the omitted key.
const brief = readFileSync(join(dir, '_batch7-brief.md'), 'utf8')
const briefKeys = []
for (const line of brief.split('\n')) {
  if (!line.trim().startsWith('|')) continue
  for (const cell of line.split('|').slice(1, -1).map((s) => s.trim())) {
    const m = cell.match(/^`([^`]+)`$/)
    if (m) briefKeys.push(m[1])
  }
}
const expectedNew = [...new Set([...briefKeys, 'Failed to re-encode the photo.'])]

console.log(`brief table keys: ${new Set(briefKeys).size}`)
console.log(`canonical new keys: ${expectedNew.length}`)
if (expectedNew.length !== 57) fail(`expected 57 new keys, derived ${expectedNew.length}`)
const phKeys = expectedNew.filter((k) => placeholders(k).length > 0)
console.log(`keys carrying a placeholder: ${phKeys.length} -> ${phKeys.map((k) => JSON.stringify(k)).join(', ')}`)
console.log(`keys with an em dash: ${expectedNew.filter((k) => k.includes('—')).length}`)
console.log('')

const snapshots = {}
for (const l of langs) {
  const p = join(snapDir, `${l}.json`)
  if (!existsSync(p)) { console.log(`FATAL: missing snapshot ${p}`); process.exit(1) }
  snapshots[l] = JSON.parse(readFileSync(p, 'utf8'))
}

for (const l of langs) {
  const raw = readFileSync(join(dir, `${l}.json`), 'utf8')
  let doc
  try { doc = JSON.parse(raw) } catch (e) { fail(`${l}: JSON.parse failed: ${e.message}`); continue }

  const s = doc.strings
  const before = snapshots[l]
  console.log(`--- ${l}.json (${raw.length} bytes on disk)`)

  if (!s || typeof s !== 'object') { fail(`${l}: no strings object`); continue }
  if (!doc.plurals || Object.keys(doc.plurals).length !== 51) fail(`${l}: plurals block not 51 keys`)
  else ok('parses; plurals block intact (51 keys)')

  const n = Object.keys(s).length
  if (n === 552) ok('Object.keys(strings).length === 552')
  else fail(`${l}: key count ${n} !== 552`)

  const missing = expectedNew.filter((k) => !(k in s))
  const empty = expectedNew.filter((k) => k in s && !String(s[k]).trim())
  if (missing.length === 0 && empty.length === 0) ok('all 57 new keys present and non-empty')
  else {
    if (missing.length) fail(`${l}: missing keys: ${missing.join(' | ')}`)
    if (empty.length) fail(`${l}: empty values: ${empty.join(' | ')}`)
  }

  const priorKeys = Object.keys(before.strings)
  const changed = priorKeys.filter((k) => s[k] !== before.strings[k])
  if (changed.length === 0) ok(`all ${priorKeys.length} pre-existing keys unchanged (no drops, no edits)`)
  else fail(`${l}: pre-existing keys changed/dropped: ${changed.join(' | ')}`)

  if (JSON.stringify(doc.plurals) !== JSON.stringify(before.plurals)) fail(`${l}: plurals changed`)
  else ok('plurals byte-identical to snapshot')

  const keys = Object.keys(s)
  if (JSON.stringify(keys) === JSON.stringify([...keys].sort())) ok('strings keys sorted as before')
  else fail(`${l}: strings keys not sorted`)

  const badPh = []
  for (const k of expectedNew) {
    const want = placeholders(k).sort().join(',')
    const got = placeholders(String(s[k])).sort().join(',')
    if (want !== got) badPh.push(`${k} -> want [${want}] got [${got}]`)
  }
  if (badPh.length === 0) ok('placeholder parity: each %lld / %@ appears exactly once, in every key that has one')
  else fail(`${l}: placeholder mismatch: ${badPh.join(' | ')}`)

  const dashBad = expectedNew.filter((k) => k.includes('—') && !String(s[k]).includes('—'))
  if (dashBad.length === 0) ok('em dash preserved in all 5 keys that have one')
  else fail(`${l}: em dash lost: ${dashBad.join(' | ')}`)

  const litBad = []
  for (const k of expectedNew) {
    for (const term of keepLiteral) {
      if (!k.includes(term)) continue
      if (!String(s[k]).includes(term)) litBad.push(`${k}: lost "${term}"`)
    }
  }
  if (litBad.length === 0) ok('keepLiteral terms (TidyByte/iOS/iPhone/iCloud/Screen Time) preserved')
  else fail(`${l}: ${litBad.join(' | ')}`)

  const identical = expectedNew.filter((k) => s[k] === k)
  if (identical.length === 0) ok('no value left as the English source')
  else fail(`${l}: untranslated values: ${identical.join(' | ')}`)

  // punctuation parity: no added/removed trailing periods, no stray "!"
  const punBad = []
  for (const k of expectedNew) {
    const src = k.match(/[.?!]$/)?.[0] ?? ''
    const dst = String(s[k]).match(/[.?!]$/)?.[0] ?? ''
    if (src !== dst) punBad.push(`${k} -> source "${src}" translation "${dst}"`)
  }
  if (punBad.length === 0) ok('trailing punctuation matches the source on all 57 keys')
  else fail(`${l}: punctuation mismatch: ${punBad.join(' | ')}`)

  console.log('')
}

console.log(failures.length === 0
  ? 'ALL CHECKS PASSED for mr, gu, pa, ta (552 keys each, read back from disk)'
  : `${failures.length} FAILURE(S)`)
process.exit(failures.length === 0 ? 0 : 1)
