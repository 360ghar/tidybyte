// Independent read-back verification for batch 6 (mr/gu/pa/ta).
// Reads the four files fresh from disk and compares against the pre-edit
// snapshots in /tmp/tidybyte-batch6-orig. Derives the expected 64 new keys
// from de.json (already-completed language) rather than from the insert script.
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const snapDir = '/tmp/tidybyte-batch6-orig'
const langs = ['mr', 'gu', 'pa', 'ta']

const keepLiteral = ['TidyByte', 'iOS', 'iPhone', 'iPad', 'HEIC', 'Live Photos', 'Live Photo', 'MB', 'iCloud']
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

const reference = JSON.parse(readFileSync(join(dir, 'de.json'), 'utf8')).strings
const snapshots = {}
for (const l of langs) {
  const p = join(snapDir, `${l}.json`)
  if (!existsSync(p)) { console.log(`FATAL: missing snapshot ${p}`); process.exit(1) }
  snapshots[l] = JSON.parse(readFileSync(p, 'utf8'))
}

// Canonical new-key set = keys present in the finished de.json but not in the
// pre-edit snapshot of these files.
const expectedNew = Object.keys(reference).filter((k) => !(k in snapshots.mr.strings))
console.log(`canonical new keys derived from de.json: ${expectedNew.length}`)
if (expectedNew.length !== 64) fail(`expected 64 new keys, derived ${expectedNew.length}`)
const phKey = 'Groups photos taken within %lld seconds of each other.'
if (!expectedNew.includes(phKey)) fail('the %lld key is missing from the derived set')
console.log(`placeholder key present in derived set: ${expectedNew.includes(phKey)}`)
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
  if (n === 495) ok(`Object.keys(strings).length === 495`)
  else fail(`${l}: key count ${n} !== 495`)

  // 3. all 64 new keys present and non-empty
  const missing = expectedNew.filter((k) => !(k in s))
  const empty = expectedNew.filter((k) => k in s && !String(s[k]).trim())
  if (missing.length === 0 && empty.length === 0) ok(`all 64 new keys present and non-empty`)
  else {
    if (missing.length) fail(`${l}: missing keys: ${missing.join(' | ')}`)
    if (empty.length) fail(`${l}: empty values: ${empty.join(' | ')}`)
  }

  // 4. no pre-existing key changed value; no pre-existing key dropped
  const priorKeys = Object.keys(before.strings)
  const changed = priorKeys.filter((k) => s[k] !== before.strings[k])
  if (changed.length === 0) ok(`all ${priorKeys.length} pre-existing keys unchanged (no drops, no edits)`)
  else fail(`${l}: pre-existing keys changed/dropped: ${changed.join(' | ')}`)

  // 5. nothing removed from plurals
  if (JSON.stringify(doc.plurals) !== JSON.stringify(before.plurals)) fail(`${l}: plurals changed`)
  else ok('plurals byte-identical to snapshot')

  // 6. key order still sorted
  const keys = Object.keys(s)
  if (JSON.stringify(keys) === JSON.stringify([...keys].sort())) ok('strings keys sorted as before')
  else fail(`${l}: strings keys not sorted`)

  // 7. placeholder parity vs English source, exactly once each
  const badPh = []
  for (const k of expectedNew) {
    const want = placeholders(k).sort().join(',')
    const got = placeholders(String(s[k])).sort().join(',')
    if (want !== got) badPh.push(`${k} -> want [${want}] got [${got}]`)
  }
  if (badPh.length === 0) ok('placeholder parity: %lld appears exactly once in the one key that has it')
  else fail(`${l}: placeholder mismatch: ${badPh.join(' | ')}`)

  // 8. trailing "..." preserved on the four progress labels
  const ell = expectedNew.filter((k) => k.endsWith('...'))
  const badEll = ell.filter((k) => !String(s[k]).endsWith('...'))
  if (badEll.length === 0) ok(`trailing "..." kept on all ${ell.length} progress labels`)
  else fail(`${l}: lost ellipsis on: ${badEll.join(' | ')}`)

  // 9. keepLiteral terms not translated away
  const litBad = []
  for (const k of expectedNew) {
    for (const term of keepLiteral) {
      if (!k.includes(term)) continue
      if (!String(s[k]).includes(term)) litBad.push(`${k}: lost "${term}"`)
    }
  }
  if (litBad.length === 0) ok('keepLiteral terms (TidyByte/iOS/HEIC/Live Photos/MB) preserved')
  else fail(`${l}: ${litBad.join(' | ')}`)

  // 10. em dash kept where the source has one
  const dashBad = expectedNew.filter((k) => k.includes('—') && !String(s[k]).includes('—'))
  if (dashBad.length === 0) ok('em dash preserved in the swipe onboarding body')
  else fail(`${l}: em dash lost: ${dashBad.join(' | ')}`)

  // 11. no value accidentally left in English (identical to source) unless it
  // is a bare token
  const identical = expectedNew.filter((k) => s[k] === k && !/^(MB|HEIC|iOS|Live Photos)$/.test(k))
  if (identical.length === 0) ok('no value left as the English source')
  else fail(`${l}: untranslated values: ${identical.join(' | ')}`)

  console.log('')
}

console.log(failures.length === 0
  ? 'ALL CHECKS PASSED for mr, gu, pa, ta (495 keys each, read back from disk)'
  : `${failures.length} FAILURE(S)`)
process.exit(failures.length === 0 ? 0 : 1)
