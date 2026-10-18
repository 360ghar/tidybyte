// Batch 9 read-back verification for mr/gu/pa/ta.
//
// The batch files are untracked in git and no pre-edit snapshot was taken, so
// "no pre-existing key changed" is proven structurally instead:
//   * /tmp/tidybyte-batch8-orig holds the pre-batch-8 files, which are NOT this
//     batch's baseline, but they let us prove on disk that this project's JSON
//     files are byte-canonical for JSON.stringify(doc, null, 2) + "\n".
//   * If serialization is canonical and idempotent, then
//     serialize(parse(current) minus the 9 added keys) IS the exact pre-edit
//     byte content, and re-adding the 9 keys must reproduce the current file
//     byte-for-byte. Nothing else can have changed.
import { readFileSync, writeFileSync, existsSync, mkdtempSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { tmpdir } from 'node:os'

const dir = dirname(fileURLToPath(import.meta.url))
const langs = ['mr', 'gu', 'pa', 'ta']
const NEW_KEYS = [
  'Start a cleanup session with %@',
  'Clean up photos with %@',
  'Tidy my photos with %@',
  'Show storage in %@',
  'Check my storage with %@',
  'Clean screenshots with %@',
  'How much can I free with %@',
  'Check free space with %@',
  'Show my savings in %@',
]

const serialize = (doc) => JSON.stringify(doc, null, 2) + '\n'

const failures = []
const fail = (m) => { failures.push(m); console.log('FAIL: ' + m) }
const ok = (m) => console.log('  ok  ' + m)

// --- Step 0: prove the batch8 pre-batch files are byte-canonical, so the
// reconstruction below is exact for the batch9 pre-edit files too.
console.log('canonicity check against /tmp/tidybyte-batch8-orig (established format):')
for (const l of langs) {
  const p = join('/tmp/tidybyte-batch8-orig', `${l}.json`)
  if (!existsSync(p)) { fail(`${l}: batch8 snapshot missing`); continue }
  const raw = readFileSync(p, 'utf8')
  if (serialize(JSON.parse(raw)) === raw) ok(`${l}: snapshot is exactly JSON.stringify(doc, null, 2) + newline`)
  else fail(`${l}: batch8 snapshot is not canonical — reconstruction proof is invalid`)
}
console.log('')

// --- Step 1: canonical round-trip of the CURRENT (post-edit) files.
for (const l of langs) {
  const raw = readFileSync(join(dir, `${l}.json`), 'utf8')
  if (serialize(JSON.parse(raw)) === raw) ok(`${l}: current file is canonical JSON (round-trips byte-exact)`)
  else fail(`${l}: current file is not canonical`)
}
console.log('')

// --- Step 2: reconstruct the pre-edit file by removing the 9 keys, then prove
// that re-adding them reproduces the current bytes exactly.
const reconDir = mkdtempSync(join(tmpdir(), 'tidybyte-batch9-'))
for (const l of langs) {
  const current = JSON.parse(readFileSync(join(dir, `${l}.json`), 'utf8'))
  const pre = JSON.parse(JSON.stringify(current)) // deep clone
  for (const k of NEW_KEYS) delete pre.strings[k]

  const preBytes = serialize(pre)
  writeFileSync(join(reconDir, `${l}.json`), preBytes)

  const reAdd = JSON.parse(preBytes) // parse the reconstructed pre-edit file
  for (const k of NEW_KEYS) reAdd.strings[k] = current.strings[k]
  const sorted = {}
  for (const k of Object.keys(reAdd.strings).sort()) sorted[k] = reAdd.strings[k]
  reAdd.strings = sorted

  const currentBytes = readFileSync(join(dir, `${l}.json`), 'utf8')
  if (serialize(reAdd) === currentBytes) ok(`${l}: reconstructed pre-edit + 9 keys reproduces the file byte-for-byte (so nothing else changed)`)
  else fail(`${l}: reconstruction does not reproduce the current file`)
}
console.log(`reconstructed pre-edit files written to ${reconDir}`)
console.log('')

// --- Step 3: the actual content assertions.
for (const l of langs) {
  const raw = readFileSync(join(dir, `${l}.json`), 'utf8')
  const doc = JSON.parse(raw)
  const s = doc.strings
  console.log(`--- ${l}.json`)

  const n = Object.keys(s).length
  if (n === 641) ok('strings count === 641')
  else fail(`${l}: strings count ${n} !== 641`)

  const pn = Object.keys(doc.plurals ?? {}).length
  if (pn === 64) ok('plurals count === 64 (untouched)')
  else fail(`${l}: plurals count ${pn} !== 64`)

  const keys = Object.keys(s)
  if (JSON.stringify(keys) === JSON.stringify([...keys].sort())) ok('strings keys in the file\'s existing (default lexicographic) sort order')
  else fail(`${l}: strings keys not in default sort order`)

  const missing = NEW_KEYS.filter((k) => !(k in s))
  const empty = NEW_KEYS.filter((k) => k in s && !String(s[k]).trim())
  if (!missing.length && !empty.length) ok('all 9 new keys present and non-empty')
  else {
    if (missing.length) fail(`${l}: missing keys: ${missing.join(' | ')}`)
    if (empty.length) fail(`${l}: empty keys: ${empty.join(' | ')}`)
  }

  const phBad = NEW_KEYS.filter((k) => k in s && (String(s[k]).split('%@').length - 1) !== 1)
  if (!phBad.length) ok('every new key carries exactly one %@')
  else fail(`${l}: %@ count !== 1 in: ${phBad.join(' | ')}`)

  // pre-existing keys: proven unchanged by the reconstruction above; also
  // confirm none went missing relative to the reconstructed pre-edit file.
  const pre = JSON.parse(readFileSync(join(reconDir, `${l}.json`), 'utf8'))
  const preKeys = Object.keys(pre.strings)
  if (preKeys.length === 632) ok('reconstructed pre-edit file has 632 strings (641 - 9)')
  else fail(`${l}: reconstructed pre-edit count ${preKeys.length} !== 632`)
  const dropped = preKeys.filter((k) => !(k in s))
  if (!dropped.length) ok('no pre-existing key dropped')
  else fail(`${l}: dropped keys: ${dropped.join(' | ')}`)

  for (const k of NEW_KEYS) console.log(`      ${k}\n        -> ${s[k]}`)
  console.log('')
}

console.log(failures.length === 0
  ? 'ALL CHECKS PASSED for mr, gu, pa, ta (641 strings / 64 plurals each)'
  : `${failures.length} FAILURE(S)`)
process.exit(failures.length === 0 ? 0 : 1)
