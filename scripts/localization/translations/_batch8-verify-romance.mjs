#!/usr/bin/env node
/**
 * Batch 8 verification for es / fr / it / pt-BR.
 *
 * Reads the four language files back from disk and checks, for each:
 *   1. it parses as JSON
 *   2. Object.keys(strings).length === 632 and Object.keys(plurals).length === 64
 *   3. exactly the 80 expected plain keys were added, all non-empty
 *   4. exactly the 13 expected plural keys were added, each with `one` + `other`
 *   5. no pre-existing key changed value and no pre-existing plural changed
 *   6. every placeholder (%lld, %@) appears exactly once per form — including
 *      the three-`%lld` key `Deleted %lld of %lld items. …`
 *   7. `Live Photo` / `Live Photos` stayed literal
 *   8. key order: `strings` still code-unit ascending; `plurals` unchanged order
 *      with the 13 new keys appended in `_plural-keys.json` order
 *
 * The expected key sets are derived from the extractor output and
 * `_plural-keys.json`, not hand-typed, so a typo in a key name fails here.
 *
 * Baselines (the files as they were before insertion) live in
 * /tmp/b8-baseline/<lang>.json.
 *
 * Run: node scripts/localization/translations/_batch8-verify-romance.mjs
 */

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..', '..', '..')
const LANGS = ['es', 'fr', 'it', 'pt-BR']
const BASELINE = '/tmp/b8-baseline'

let failures = 0
const fail = (msg) => {
  failures += 1
  console.log(`  FAIL ${msg}`)
}
const ok = (msg) => console.log(`  ok   ${msg}`)

// ---------------------------------------------------------------- expected set
const found = JSON.parse(readFileSync(join(root, 'scripts/localization/strings.found.json'), 'utf8'))
const catalog = JSON.parse(readFileSync(join(root, 'Tidybyte/Resources/Localizable.xcstrings'), 'utf8'))
const pluralCatalog = JSON.parse(readFileSync(join(here, '_plural-keys.json'), 'utf8'))
const brief = readFileSync(join(here, '_batch8-brief.md'), 'utf8')

const pluralKeyList = Object.keys(pluralCatalog)
const baseStrings = JSON.parse(readFileSync(join(BASELINE, 'es.json'), 'utf8')).strings
const basePlurals = JSON.parse(readFileSync(join(BASELINE, 'es.json'), 'utf8')).plurals

const universe = new Set([
  ...Object.keys(catalog.strings ?? {}),
  ...found.keys.map((entry) => entry.key),
])
const newKeys = [...universe].filter(
  (key) => key.trim() && !(key in baseStrings) && !(key in basePlurals),
)
// The extractor also picks up keys from later batches (the App Intents / Siri
// phrases in `TidybyteShortcuts.swift`). Batch 8 is exactly the keys this
// batch's brief lists, so derive the expectation from the brief, not from
// "anything new".
const batchKeys = newKeys.filter((key) => brief.includes(`\`${key}\``))
const outOfBatch = newKeys.filter((key) => !brief.includes(`\`${key}\``))
const expectedPlain = batchKeys.filter((key) => !pluralKeyList.includes(key))
const expectedPlurals = batchKeys.filter((key) => pluralKeyList.includes(key))

console.log(
  `expected: ${expectedPlain.length} plain keys, ${expectedPlurals.length} plural keys ` +
    `(${outOfBatch.length} newer extractor keys belong to a later batch)`,
)
if (expectedPlain.length !== 80) fail(`derived ${expectedPlain.length} plain keys, expected 80`)
if (expectedPlurals.length !== 13) fail(`derived ${expectedPlurals.length} plural keys, expected 13`)
if (outOfBatch.length) console.log(`  info not in this batch: ${JSON.stringify(outOfBatch)}`)

const counts = (text) => ({
  lld: (text.match(/%lld/g) || []).length,
  at: (text.match(/%@/g) || []).length,
})
const byCodeUnit = (a, b) => (a < b ? -1 : a > b ? 1 : 0)
const livePhotoOk = (text) => {
  // `Live Photo` / `Live Photos` must appear verbatim, and no leftover `Live`
  // may remain once they are removed (which would mean a partial translation).
  const stripped = text.replace(/Live Photos/g, '').replace(/Live Photo/g, '')
  return /Live Photo/.test(text) && !/\bLive\b/i.test(stripped)
}

for (const lang of LANGS) {
  console.log(`\n${lang}.json`)
  const raw = readFileSync(join(here, `${lang}.json`), 'utf8')
  const baseRaw = readFileSync(join(BASELINE, `${lang}.json`), 'utf8')

  let json
  try {
    json = JSON.parse(raw)
    ok('parses as JSON')
  } catch (error) {
    fail(`does not parse: ${error.message}`)
    continue
  }
  const base = JSON.parse(baseRaw)

  // 2. key counts
  const stringCount = Object.keys(json.strings).length
  const pluralCount = Object.keys(json.plurals).length
  if (stringCount === 632) ok(`strings count = ${stringCount}`)
  else fail(`strings count = ${stringCount}, expected 632`)
  if (pluralCount === 64) ok(`plurals count = ${pluralCount}`)
  else fail(`plurals count = ${pluralCount}, expected 64`)

  // 3. exactly the expected plain keys, all non-empty
  const before = new Set(Object.keys(base.strings))
  const after = Object.keys(json.strings)
  const addedPlain = after.filter((key) => !before.has(key))
  const removed = [...before].filter((key) => !after.includes(key))
  const expectedPlainSet = new Set(expectedPlain)
  const unexpectedPlain = addedPlain.filter((key) => !expectedPlainSet.has(key))
  const missingPlain = expectedPlain.filter((key) => !addedPlain.includes(key))
  if (!removed.length) ok('no key removed')
  else fail(`removed keys: ${JSON.stringify(removed)}`)
  if (!unexpectedPlain.length) ok('no unexpected new plain key')
  else fail(`unexpected new plain keys: ${JSON.stringify(unexpectedPlain)}`)
  if (!missingPlain.length) ok(`all ${expectedPlain.length} expected plain keys added`)
  else fail(`missing plain keys: ${JSON.stringify(missingPlain)}`)
  const emptyPlain = expectedPlain.filter(
    (key) => typeof json.strings[key] !== 'string' || json.strings[key].trim() === '',
  )
  if (!emptyPlain.length) ok('every new plain value is a non-empty string')
  else fail(`empty plain values: ${JSON.stringify(emptyPlain)}`)

  // 4. exactly the expected plural keys, each with one + other
  const beforePlurals = new Set(Object.keys(base.plurals))
  const addedPlurals = Object.keys(json.plurals).filter((key) => !beforePlurals.has(key))
  const expectedPluralSet = new Set(expectedPlurals)
  const unexpectedPlurals = addedPlurals.filter((key) => !expectedPluralSet.has(key))
  const missingPlurals = expectedPlurals.filter((key) => !addedPlurals.includes(key))
  if (!unexpectedPlurals.length) ok('no unexpected new plural key')
  else fail(`unexpected new plural keys: ${JSON.stringify(unexpectedPlurals)}`)
  if (!missingPlurals.length) ok(`all ${expectedPlurals.length} expected plural keys added`)
  else fail(`missing plural keys: ${JSON.stringify(missingPlurals)}`)
  const badCategories = expectedPlurals.filter((key) => {
    const forms = json.plurals[key]
    return !forms || Object.keys(forms).sort().join(',') !== 'one,other'
  })
  if (!badCategories.length) ok('every new plural has exactly one + other')
  else fail(`plural categories wrong: ${JSON.stringify(badCategories)}`)
  const emptyPluralForms = []
  for (const key of expectedPlurals) {
    for (const [category, value] of Object.entries(json.plurals[key] ?? {})) {
      if (typeof value !== 'string' || value.trim() === '') {
        emptyPluralForms.push(`${key} [${category}]`)
      }
    }
  }
  if (!emptyPluralForms.length) ok('every new plural form is non-empty')
  else fail(`empty plural forms: ${JSON.stringify(emptyPluralForms)}`)

  // 5. nothing pre-existing changed
  const changedStrings = [...before].filter((key) => json.strings[key] !== base.strings[key])
  if (!changedStrings.length) ok('no pre-existing string changed value')
  else fail(`changed pre-existing strings: ${JSON.stringify(changedStrings)}`)
  const changedPlurals = Object.keys(base.plurals).filter(
    (key) => JSON.stringify(json.plurals[key]) !== JSON.stringify(base.plurals[key]),
  )
  if (!changedPlurals.length) ok('no pre-existing plural changed value')
  else fail(`changed pre-existing plurals: ${JSON.stringify(changedPlurals)}`)
  if (Object.keys(json).length === Object.keys(base).length) ok('top-level shape unchanged')
  else fail(`top-level keys changed: ${JSON.stringify(Object.keys(json))}`)

  // 6. placeholders, exactly once per form
  const badPlaceholders = []
  const checkForm = (key, label, value) => {
    if (typeof value !== 'string') return
    const want = counts(key)
    const got = counts(value)
    if (want.lld !== got.lld || want.at !== got.at) {
      badPlaceholders.push(
        `${JSON.stringify(key)} ${label} -> ${JSON.stringify(value)} (want %lld x${want.lld}, %@ x${want.at}; got %lld x${got.lld}, %@ x${got.at})`,
      )
    }
  }
  for (const key of expectedPlain) checkForm(key, '', json.strings[key])
  for (const key of expectedPlurals) {
    for (const [category, value] of Object.entries(json.plurals[key] ?? {})) {
      checkForm(key, `[${category}]`, value)
    }
  }
  if (!badPlaceholders.length) ok('placeholders appear exactly once per form')
  else badPlaceholders.forEach((line) => fail(`placeholder mismatch: ${line}`))

  // 6b. the three-placeholder key specifically
  const three = 'Deleted %lld of %lld items. %lld couldn\'t be deleted. Try again.'
  const threeValue = json.strings[three]
  if (threeValue && counts(threeValue).lld === 3) ok('three-%lld key carries exactly three %lld')
  else fail(`three-%lld key has ${counts(threeValue ?? '').lld}: ${JSON.stringify(threeValue)}`)

  // 7. Live Photo stays literal
  const liveKeys = [
    ...expectedPlain.filter((key) => /Live Photo/.test(key)),
    ...expectedPlurals.filter((key) => /Live Photo/.test(key)),
  ]
  const badLive = liveKeys.filter((key) => {
    const values =
      key in json.strings ? [json.strings[key]] : Object.values(json.plurals[key] ?? {})
    return values.some((value) => !livePhotoOk(value))
  })
  if (!badLive.length) ok(`Live Photo / Live Photos kept literal (${liveKeys.length} keys)`)
  else fail(`Live Photo translated: ${JSON.stringify(badLive)}`)

  // 8. ordering
  const order = Object.keys(json.strings)
  if (JSON.stringify(order) === JSON.stringify([...order].sort(byCodeUnit))) {
    ok('string key order still code-unit ascending')
  } else {
    fail('string key order is no longer code-unit ascending')
  }
  const pluralOrder = Object.keys(json.plurals)
  // Existing order kept, then the 13 new keys in `_plural-keys.json` order.
  const wantedPluralOrder = [
    ...Object.keys(base.plurals),
    ...pluralKeyList.filter((key) => !(key in base.plurals)),
  ]
  if (JSON.stringify(pluralOrder) === JSON.stringify(wantedPluralOrder)) {
    ok('plural key order: existing order kept, new keys appended in catalog order')
  } else {
    fail('plural key order changed')
  }
}

console.log(`\n${failures === 0 ? 'PASS' : 'FAIL'} — ${failures} failure(s)`)
process.exit(failures === 0 ? 0 : 1)
