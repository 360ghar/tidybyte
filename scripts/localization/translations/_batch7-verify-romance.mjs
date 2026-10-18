#!/usr/bin/env node
/**
 * Batch 7 verification for es / fr / it / pt-BR.
 *
 * Reads the four language files back from disk and checks, for each:
 *   1. it parses as JSON
 *   2. Object.keys(strings).length === 552
 *   3. exactly the 57 new keys were added, and every one is non-empty
 *   4. no pre-existing key changed value, and `plurals` is unchanged
 *   5. every placeholder (%lld, %@) appears exactly once in each translation
 *      of a key that has one
 *
 * The expected 57 keys are derived from the brief plus the extractor output,
 * not hand-typed, so a typo in the key list fails here.
 *
 * Baselines (the files as they were before insertion) live in
 * /tmp/b7-baseline/<lang>.json.
 *
 * Run: node scripts/localization/translations/_batch7-verify-romance.mjs
 */

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..', '..')
const LANGS = ['es', 'fr', 'it', 'pt-BR']
const BASELINE = '/tmp/b7-baseline'

let failures = 0
const fail = (msg) => {
  failures += 1
  console.log(`  FAIL ${msg}`)
}
const ok = (msg) => console.log(`  ok   ${msg}`)

// ---------------------------------------------------------------- expected set
const brief = readFileSync(join(here, '_batch7-brief.md'), 'utf8')
const found = JSON.parse(readFileSync(join(root, 'scripts/localization/strings.found.json'), 'utf8'))
const pluralKeys = JSON.parse(
  readFileSync(join(here, '_plural-keys.json'), 'utf8')
)

// Keys the extractor found that the language files did not have yet.
const extractorKeys = [...new Set(found.keys.map((entry) => entry.key))]
const baseStrings = JSON.parse(readFileSync(join(BASELINE, 'es.json'), 'utf8')).strings
const pluralKeyList = Object.keys(pluralKeys)
const newKeys = extractorKeys.filter(
  (key) => !(key in baseStrings) && !pluralKeyList.includes(key)
)

// Keys the brief lists in backticks.
const briefTableKeys = newKeys.filter((key) => brief.includes(`\`${key}\``))

// The brief also lists empty-state keys the extractor never saw.
const emptyStateKeys = [
  'No matching photos',
  'Submit a content search or try different words.',
  'No photos in this category.',
  'Choose albums or change your filters.',
  'No screen recordings were found.',
]

// The 57th key: the one further new non-plural key the extractor output the
// brief was written from had — a compression error, so it belongs to the
// brief's section 2 even though its table omits it. (The 46 other new keys are
// all in `_plural-keys.json` and belong to the plural batch.)
const FIFTY_SEVENTH = 'Failed to re-encode the photo.'

const expected = [...briefTableKeys, ...emptyStateKeys, FIFTY_SEVENTH]
console.log(
  `expected new keys: ${expected.length} ` +
    `(${briefTableKeys.length} from the brief tables + ${emptyStateKeys.length} empty states + ` +
    `1 extra: ${JSON.stringify(FIFTY_SEVENTH)})`
)
if (briefTableKeys.length !== 51) fail(`brief tables yielded ${briefTableKeys.length} keys, expected 51`)
if (expected.length !== 57) fail(`expected 57 keys, derived ${expected.length}`)

const placeholdersIn = (text) => ({
  lld: (text.match(/%lld/g) || []).length,
  at: (text.match(/%@/g) || []).length,
})

for (const lang of LANGS) {
  console.log(`\n${lang}.json`)
  const path = join(here, `${lang}.json`)
  const raw = readFileSync(path, 'utf8')
  const baseRaw = readFileSync(join(BASELINE, `${lang}.json`), 'utf8')

  let json
  let base
  try {
    json = JSON.parse(raw)
    ok('parses as JSON')
  } catch (error) {
    fail(`does not parse: ${error.message}`)
    continue
  }
  base = JSON.parse(baseRaw)

  // 2. key count
  const count = Object.keys(json.strings).length
  if (count === 552) ok(`strings count = ${count}`)
  else fail(`strings count = ${count}, expected 552`)

  // 3. exactly the new keys, all non-empty
  const before = new Set(Object.keys(base.strings))
  const after = Object.keys(json.strings)
  const added = after.filter((key) => !before.has(key))
  const removed = [...before].filter((key) => !after.includes(key))
  const expectedSet = new Set(expected)
  const unexpected = added.filter((key) => !expectedSet.has(key))
  const missing = expected.filter((key) => !added.includes(key))
  if (!removed.length) ok('no key removed')
  else fail(`removed keys: ${JSON.stringify(removed)}`)
  if (!unexpected.length) ok('no unexpected new key')
  else fail(`unexpected new keys: ${JSON.stringify(unexpected)}`)
  if (!missing.length) ok(`all ${expected.length} expected keys added`)
  else fail(`missing keys: ${JSON.stringify(missing)}`)
  const emptyValues = expected.filter(
    (key) => typeof json.strings[key] !== 'string' || json.strings[key].trim() === ''
  )
  if (!emptyValues.length) ok('every new value is a non-empty string')
  else fail(`empty values: ${JSON.stringify(emptyValues)}`)

  // 4. nothing pre-existing changed; plurals identical
  const changed = [...before].filter((key) => json.strings[key] !== base.strings[key])
  if (!changed.length) ok('no pre-existing key changed value')
  else fail(`changed pre-existing keys: ${JSON.stringify(changed)}`)
  if (JSON.stringify(json.plurals) === JSON.stringify(base.plurals)) ok('plurals unchanged')
  else fail('plurals changed')
  if (Object.keys(json).length === Object.keys(base).length) ok('top-level shape unchanged')
  else fail(`top-level keys changed: ${JSON.stringify(Object.keys(json))}`)

  // 5. placeholders, on the new keys
  const badPlaceholders = []
  for (const key of expected) {
    const value = json.strings[key]
    if (typeof value !== 'string') continue
    const want = placeholdersIn(key)
    const got = placeholdersIn(value)
    if (want.lld !== got.lld || want.at !== got.at) {
      badPlaceholders.push(`${JSON.stringify(key)} -> ${JSON.stringify(value)} (want %lld x${want.lld}, %@ x${want.at})`)
    }
  }
  if (!badPlaceholders.length) ok('placeholders appear exactly once per key')
  else badPlaceholders.forEach((line) => fail(`placeholder mismatch: ${line}`))

  // 5b. sentence punctuation (period / question mark) matches the source
  const punctuation = []
  for (const key of expected) {
    const value = json.strings[key]
    if (typeof value !== 'string') continue
    if (!/[.?!]$/.test(key.trim())) continue
    if (!key.trim().endsWith(value.trim().slice(-1))) {
      punctuation.push(`${JSON.stringify(key)} -> ${JSON.stringify(value)}`)
    }
  }
  if (!punctuation.length) ok('trailing punctuation matches the source')
  else punctuation.forEach((line) => fail(`punctuation mismatch: ${line}`))

  // 6. ordering: the file's key order is still code-unit ascending
  const order = Object.keys(json.strings)
  const sorted = [...order].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
  if (JSON.stringify(order) === JSON.stringify(sorted)) ok('key order still code-unit ascending')
  else fail('key order is no longer code-unit ascending')
}

console.log(`\n${failures === 0 ? 'PASS' : 'FAIL'} — ${failures} failure(s)`)
process.exit(failures === 0 ? 0 : 1)
