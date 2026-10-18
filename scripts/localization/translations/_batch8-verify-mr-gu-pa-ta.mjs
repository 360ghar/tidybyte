// Independent read-back verification for batch 8 (mr/gu/pa/ta).
//
// Reads the four files fresh from disk and compares against the pre-edit
// snapshots in /tmp/tidybyte-batch8-orig. The expected key lists are written
// out from `_batch8-brief.md` here (not imported from the insert script), and
// every one of them is also required to appear as a code span in the brief, so
// a typo in either place fails the run.
import { readFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const dir = dirname(fileURLToPath(import.meta.url))
const snapDir = '/tmp/tidybyte-batch8-orig'
const langs = ['mr', 'gu', 'pa', 'ta']

const GLOSSARY = JSON.parse(readFileSync(join(dir, '_glossary.json'), 'utf8')).glossary
const PLURAL_KEYS_FILE = JSON.parse(readFileSync(join(dir, '_plural-keys.json'), 'utf8'))

// --- Part B: the 80 plain keys, in brief order
const PLAIN_KEYS = [
  'Worst Shots',
  'Review low-scoring photos, lowest first',
  "Photos you haven't reviewed yet",
  'Every photo and video in your library',
  'Review photos and videos taken on or before a date',
  'Photos not organized into your albums',
  'Specific Album',
  'Review photos from a specific album',
  'Marked for deletion. Nothing is deleted until you confirm at the end.',
  'Delete is off until the photo loads.',
  'Pinch or double-tap a photo to inspect it',
  "That photo can't be undone anymore.",
  'Undo your newer actions first to reach that photo.',
  'Your library changed during analysis. Try Worst Shots again.',
  'No photo is waiting to be filed. Dismiss and try again.',
  'Still adding — please wait a moment and try again.',
  "Couldn't save your changes. Please try again.",
  'Added to albums',
  'Moved to Recently Deleted',
  'Kept',
  'Skipped',
  'Deleted',
  'Kept: your choice',
  'Kept: your pick in Photos',
  "Kept: iPhone's pick",
  'Kept: favorite',
  'Kept: highest resolution',
  'Kept: last frame',
  'Kept: auto pick',
  ' Favorites are kept.',
  'This keeps the starred frame of each burst and deletes the rest.',
  '1 burst cleaned down to a single photo.',
  '%lld bursts cleaned down to single photos.',
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
  'Recently Deleted',
  'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.',
  'Manage Apps & System Storage',
  'Open Settings ▸ General ▸ iPhone Storage',
  'Library figures below cover only the photos you selected; device totals cover the whole device.',
  'Find exact and near-duplicate photos',
  'Spot blurry, dark, and overexposed shots',
  'Surface the biggest files taking up space',
  'Delete only what you review and approve',
  'items, all time',
  'this month',
  'Size unknown',
  'Size unavailable',
  'cleaned up since you started using TidyByte',
  "Nothing measurable yet. Items stored only in iCloud don't report a size.",
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
  'I just %@',
  "I'm cleaning up my photo library",
  '%@ with TidyByte — a private, on-device photo cleanup app. %@',
  'Min size: %@',
  'Swipe history cleared',
  'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.',
]

// --- Part A: the 13 plural keys, keyed by English singular
const PLURAL_KEY_LIST = [
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

const KEEP_LITERAL = ['TidyByte', 'iPhone', 'iPad', 'iOS', 'iCloud', 'HEIC', 'Live Photo', 'Live Photos', 'MB', 'App Store']
const PLACEHOLDER_RE = /%(?:(\d+)\$)?(?:\.\d+)?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g

const failures = []
const fail = (m) => { failures.push(m); console.log('FAIL: ' + m) }
const ok = (m) => console.log('  ok  ' + m)

function placeholders(text) {
  const out = []
  let m
  PLACEHOLDER_RE.lastIndex = 0
  while ((m = PLACEHOLDER_RE.exec(text)) !== null) if (m[2] !== '%') out.push(m[2])
  return out
}
function countToken(text, token) {
  return text.split(token).length - 1
}

// --- structural expectations from the brief itself
const brief = readFileSync(join(dir, '_batch8-brief.md'), 'utf8')
const briefSpans = new Set()
for (const m of brief.matchAll(/`([^`]+)`/g)) briefSpans.add(m[1])
console.log(`brief code spans: ${briefSpans.size}`)
if (PLAIN_KEYS.length !== 80) fail(`plain key list is ${PLAIN_KEYS.length}, expected 80`)
if (PLURAL_KEY_LIST.length !== 13) fail(`plural key list is ${PLURAL_KEY_LIST.length}, expected 13`)
for (const k of PLAIN_KEYS) if (!briefSpans.has(k)) fail(`plain key not found in the brief: ${JSON.stringify(k)}`)
for (const k of PLURAL_KEY_LIST) if (!briefSpans.has(k)) fail(`plural key not found in the brief: ${JSON.stringify(k)}`)
const overlap = PLAIN_KEYS.filter((k) => PLURAL_KEY_LIST.includes(k))
if (overlap.length) fail(`key in both lists: ${overlap.join(' | ')}`)
if (new Set(PLAIN_KEYS).size !== PLAIN_KEYS.length) fail('duplicate entries in the plain key list')
if (failures.length === 0) ok(`80 plain + 13 plural keys derived, all present in the brief, no overlap`)

// the 13 must be the tail of `_plural-keys.json`, and its English forms must match
const pluralTail = Object.keys(PLURAL_KEYS_FILE).slice(-13)
if (JSON.stringify(pluralTail) !== JSON.stringify(PLURAL_KEY_LIST)) fail('plural key list does not match the tail of _plural-keys.json')
else ok('the 13 plural keys are exactly the tail of _plural-keys.json')
const englishPluralForms = {}
for (const k of PLURAL_KEY_LIST) {
  const entry = PLURAL_KEYS_FILE[k]
  if (!entry) { fail(`_plural-keys.json has no entry for ${JSON.stringify(k)}`); continue }
  englishPluralForms[k] = entry
  if (Object.keys(entry).sort().join(',') !== 'one,other') fail(`_plural-keys.json entry ${JSON.stringify(k)} is not one/other`)
}

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
  ok('parses as JSON')

  const n = Object.keys(s).length
  if (n === 632) ok('Object.keys(strings).length === 632')
  else fail(`${l}: strings key count ${n} !== 632`)
  const pn = Object.keys(doc.plurals ?? {}).length
  if (pn === 64) ok('Object.keys(plurals).length === 64')
  else fail(`${l}: plurals key count ${pn} !== 64`)

  // all 80 plain keys present and non-empty
  const missing = PLAIN_KEYS.filter((k) => !(k in s))
  const empty = PLAIN_KEYS.filter((k) => k in s && !String(s[k]).trim())
  if (!missing.length && !empty.length) ok('all 80 plain keys present and non-empty')
  else {
    if (missing.length) fail(`${l}: missing plain keys: ${missing.join(' | ')}`)
    if (empty.length) fail(`${l}: empty plain values: ${empty.join(' | ')}`)
  }

  // all 13 plural keys present with exactly one/other
  const pMissing = PLURAL_KEY_LIST.filter((k) => !(k in (doc.plurals ?? {})))
  if (pMissing.length) fail(`${l}: missing plural keys: ${pMissing.join(' | ')}`)
  const catBad = []
  for (const k of PLURAL_KEY_LIST) {
    const v = doc.plurals?.[k]
    if (!v) continue
    const cats = Object.keys(v).sort().join(',')
    if (cats !== 'one,other') catBad.push(`${k} -> [${cats}]`)
    for (const c of ['one', 'other']) if (!String(v[c] ?? '').trim()) catBad.push(`${k}.${c} is empty`)
  }
  if (!pMissing.length && !catBad.length) ok('all 13 plural keys present, each exactly one + other, both non-empty')
  else if (catBad.length) fail(`${l}: plural category problems: ${catBad.join(' | ')}`)

  // no pre-existing key changed value (strings and plurals)
  const priorKeys = Object.keys(before.strings)
  const changed = priorKeys.filter((k) => s[k] !== before.strings[k])
  if (changed.length === 0) ok(`all ${priorKeys.length} pre-existing string keys unchanged (no drops, no edits)`)
  else fail(`${l}: pre-existing string keys changed/dropped: ${changed.join(' | ')}`)
  const priorPluralKeys = Object.keys(before.plurals)
  const pChanged = priorPluralKeys.filter((k) => JSON.stringify(doc.plurals?.[k]) !== JSON.stringify(before.plurals[k]))
  if (pChanged.length === 0) ok(`all ${priorPluralKeys.length} pre-existing plural keys unchanged`)
  else fail(`${l}: pre-existing plural keys changed: ${pChanged.join(' | ')}`)

  // strings keys still sorted the way the file was
  const keys = Object.keys(s)
  if (JSON.stringify(keys) === JSON.stringify([...keys].sort())) ok('strings keys sorted as before')
  else fail(`${l}: strings keys not sorted`)

  // placeholder parity, counted not just set
  const phBad = []
  for (const k of PLAIN_KEYS) {
    const want = placeholders(k)
    const got = placeholders(String(s[k]))
    if (JSON.stringify(want) !== JSON.stringify(got)) phBad.push(`${k} -> want [${want}] got [${got}]`)
    for (const token of ['%lld', '%@']) {
      const wc = countToken(k, token)
      const gc = countToken(String(s[k]), token)
      if (wc !== gc) phBad.push(`${k} -> ${token} x${wc} in source, x${gc} in translation`)
    }
  }
  for (const k of PLURAL_KEY_LIST) {
    const forms = englishPluralForms[k] ?? {}
    for (const cat of ['one', 'other']) {
      const src = forms[cat] ?? ''
      const dst = String(doc.plurals?.[k]?.[cat] ?? '')
      const want = placeholders(src)
      const got = placeholders(dst)
      if (JSON.stringify(want) !== JSON.stringify(got)) phBad.push(`${k}.${cat} -> want [${want}] got [${got}]`)
      for (const token of ['%lld', '%@']) {
        const wc = countToken(src, token)
        const gc = countToken(dst, token)
        if (wc !== gc) phBad.push(`${k}.${cat} -> ${token} x${wc} in source, x${gc} in translation`)
      }
    }
  }
  if (phBad.length === 0) ok('placeholder parity: %lld and %@ appear exactly as often as in the source, in every plain key and every plural form')
  else fail(`${l}: placeholder mismatch: ${phBad.join(' | ')}`)

  // the three-placeholder key, named explicitly
  const three = String(s["Deleted %lld of %lld items. %lld couldn't be deleted. Try again."])
  if (countToken(three, '%lld') === 3) ok(`"Deleted %lld of %lld items. %lld couldn't be deleted. Try again." carries exactly three %lld -> ${JSON.stringify(three)}`)
  else fail(`${l}: three-placeholder key has ${countToken(three, '%lld')} %lld`)

  // glossary terms: Live Photo(s), Recently Deleted, screenshot, duplicate, compress
  const litBad = []
  for (const k of [...PLAIN_KEYS, ...PLURAL_KEY_LIST]) {
    for (const term of KEEP_LITERAL) {
      if (!k.includes(term)) continue
      const forms = PLURAL_KEY_LIST.includes(k)
        ? ['one', 'other'].map((c) => String(doc.plurals?.[k]?.[c] ?? ''))
        : [String(s[k])]
      for (const form of forms) if (!form.includes(term)) litBad.push(`${k}: lost "${term}"`)
    }
  }
  if (litBad.length === 0) ok('keepLiteral terms (TidyByte / iPhone / iOS / iCloud / Live Photo(s) / MB) preserved')
  else fail(`${l}: ${litBad.join(' | ')}`)

  const rd = GLOSSARY['Recently Deleted'][l]
  const rdKeys = ['Recently Deleted', 'Moved to Recently Deleted', 'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.', 'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.']
  const rdBad = rdKeys.filter((k) => !String(s[k]).includes(rd))
  if (rdBad.length === 0) ok(`glossary "Recently Deleted" (${rd}) used in all ${rdKeys.length} keys that name the album`)
  else fail(`${l}: glossary Recently Deleted missing from: ${rdBad.join(' | ')}`)

  const scr = GLOSSARY.screenshot[l]
  const scrKeys = ['cleared %lld screenshot']
  const scrBad = scrKeys.filter((k) => !['one', 'other'].every((c) => String(doc.plurals?.[k]?.[c] ?? '').includes(scr)))
  if (scrBad.length === 0) ok(`glossary "screenshot" (${scr}) used in the screenshot plural`)
  else fail(`${l}: glossary screenshot missing from: ${scrBad.join(' | ')}`)

  const dup = GLOSSARY.duplicate[l]
  if (['one', 'other'].every((c) => String(doc.plurals?.['removed %lld duplicate']?.[c] ?? '').includes(dup))) ok(`glossary "duplicate" (${dup}) used in "removed %lld duplicate"`)
  else fail(`${l}: glossary duplicate missing from "removed %lld duplicate"`)

  // em dash and the ▸ glyph survive
  const dashKeys = PLAIN_KEYS.filter((k) => k.includes('—'))
  const dashBad = dashKeys.filter((k) => !String(s[k]).includes('—'))
  if (dashBad.length === 0) ok(`em dash preserved in all ${dashKeys.length} keys that have one`)
  else fail(`${l}: em dash lost: ${dashBad.join(' | ')}`)
  if (String(s['Open Settings ▸ General ▸ iPhone Storage']).includes('▸')) ok('U+25B8 ▸ preserved in "Open Settings ▸ General ▸ iPhone Storage"')
  else fail(`${l}: ▸ lost`)

  // leading space on the appended burst sentence
  if (String(s[' Favorites are kept.']).startsWith(' ')) ok('" Favorites are kept." keeps its leading space')
  else fail(`${l}: leading space lost on " Favorites are kept."`)

  // trailing punctuation matches the source on every new key
  const punBad = []
  for (const k of PLAIN_KEYS) {
    const src = k.match(/[.?!]$/)?.[0] ?? ''
    const dst = String(s[k]).match(/[.?!]$/)?.[0] ?? ''
    if (src !== dst) punBad.push(`${k} -> source "${src}" translation "${dst}"`)
  }
  if (punBad.length === 0) ok('trailing punctuation matches the source on all 80 plain keys')
  else fail(`${l}: punctuation mismatch: ${punBad.join(' | ')}`)

  // nothing left in English
  const identical = [...PLAIN_KEYS.filter((k) => s[k] === k), ...PLURAL_KEY_LIST.filter((k) => ['one', 'other'].every((c) => doc.plurals?.[k]?.[c] === englishPluralForms[k]?.[c]))]
  if (identical.length === 0) ok('no value left as the English source')
  else fail(`${l}: untranslated values: ${identical.join(' | ')}`)

  console.log('')
}

console.log(failures.length === 0
  ? 'ALL CHECKS PASSED for mr, gu, pa, ta (632 strings / 64 plurals each, read back from disk)'
  : `${failures.length} FAILURE(S)`)
process.exit(failures.length === 0 ? 0 : 1)
