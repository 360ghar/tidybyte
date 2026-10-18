#!/usr/bin/env node
/**
 * Batch 8 verification — reads the four language files back from disk and
 * asserts the catalog contract, the brief's key lists, placeholder parity,
 * plural categories, that nothing pre-existing moved, and the glossary terms.
 *
 * Run: node scripts/localization/translations/_batch8-verify.mjs
 */

import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const LANGS = ['de', 'ja', 'ko', 'zh-Hans']
const CATEGORIES = {
  de: ['one', 'other'],
  ja: ['other'],
  ko: ['other'],
  'zh-Hans': ['other'],
}
const BACKUPS = {
  de: '/tmp/de.bak.json',
  ja: '/tmp/ja.bak.json',
  ko: '/tmp/ko.bak.json',
  'zh-Hans': '/tmp/zh-Hans.bak.json',
}

import { KEYS as PLAIN_KEYS, PLURAL_KEYS as PLURAL_LIST } from './_batch8-insert.mjs'

let failures = 0
const fail = (message) => {
  console.log(`FAIL: ${message}`)
  failures += 1
}

/** Every format specifier, with its explicit `%N$` position when present. */
function tokens (text) {
  const pattern = /%(?:(\d+)\$)?(?:\.(\d+))?(?:ll|l|h|hh|z|q)?([@difsuxXeEgGcCpaA]|%)/g
  const found = []
  let match
  let ordinal = 0
  while ((match = pattern.exec(text)) !== null) {
    if (match[3] === '%') continue
    ordinal += 1
    found.push({ position: match[1] ? Number(match[1]) : ordinal, type: match[3] })
  }
  return found
}

/** Mirrors check.mjs `argumentsMatch`: same order, or a valid positional map. */
function argumentsMatch (english, translated) {
  const a = tokens(english)
  const b = tokens(translated)
  if (a.length !== b.length) return false
  const byPosition = new Map(a.map((t) => [t.position, t.type]))
  const positional = b.some((t, i) => t.position !== i + 1)
  if (!positional) return a.every((t, i) => t.type === b[i].type)
  const seen = new Set()
  for (const t of b) {
    if (seen.has(t.position)) return false
    seen.add(t.position)
    if (byPosition.get(t.position) !== t.type) return false
  }
  return seen.size === a.length
}

const counts = (text) => ({
  lld: (text.match(/%lld/g) ?? []).length,
  at: (text.match(/%@/g) ?? []).length,
})

console.log(`plain keys in table:  ${PLAIN_KEYS.length}`)
console.log(`plural keys in table: ${PLURAL_LIST.length}\n`)

for (const lang of LANGS) {
  const path = join(here, `${lang}.json`)
  const raw = readFileSync(path, 'utf8')
  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (error) {
    fail(`${lang}: does not parse as JSON (${error.message})`)
    continue
  }

  const strings = parsed.strings ?? {}
  const plurals = parsed.plurals ?? {}
  const stringKeys = Object.keys(strings)
  const pluralKeys = Object.keys(plurals)

  console.log(`=== ${lang} ===`)
  console.log(`strings: ${stringKeys.length} (target 632)`)
  console.log(`plurals: ${pluralKeys.length} (target 64)`)
  if (stringKeys.length !== 632) fail(`${lang}: strings count ${stringKeys.length} != 632`)
  if (pluralKeys.length !== 64) fail(`${lang}: plurals count ${pluralKeys.length} != 64`)

  // Every plain key present and non-empty.
  const missing = PLAIN_KEYS.filter((k) => typeof strings[k] !== 'string' || strings[k].length === 0)
  if (missing.length) fail(`${lang}: missing/empty plain keys: ${JSON.stringify(missing)}`)
  const emptyValues = PLAIN_KEYS.filter((k) => strings[k].trim().length === 0)
  if (emptyValues.length) fail(`${lang}: blank plain values: ${JSON.stringify(emptyValues)}`)
  console.log(`plain keys present and non-empty: ${PLAIN_KEYS.length - missing.length}/${PLAIN_KEYS.length}`)

  // Plural keys with exactly the required categories.
  const badCategories = []
  for (const key of PLURAL_LIST) {
    const value = plurals[key]
    if (!value || typeof value !== 'object') {
      badCategories.push(`${key}: missing`)
      continue
    }
    const actual = Object.keys(value).sort().join(',')
    const wanted = [...CATEGORIES[lang]].sort().join(',')
    if (actual !== wanted) badCategories.push(`${key}: [${actual}] != [${wanted}]`)
    for (const [c, v] of Object.entries(value)) {
      if (typeof v !== 'string' || v.length === 0) badCategories.push(`${key}.${c}: empty`)
    }
  }
  if (badCategories.length) fail(`${lang}: plural categories: ${JSON.stringify(badCategories)}`)
  console.log(`plural categories ok (${CATEGORIES[lang].join(', ')}): ${PLURAL_LIST.length - badCategories.length}/${PLURAL_LIST.length}`)

  // Placeholder parity, per form.
  const placeholderProblems = []
  const checkForm = (english, translated, label) => {
    if (!argumentsMatch(english, translated)) {
      placeholderProblems.push(`${label}: "${translated}" vs "${english}"`)
    }
    const en = counts(english)
    const tr = counts(translated)
    if (en.lld !== tr.lld || en.at !== tr.at) {
      placeholderProblems.push(`${label}: count ${JSON.stringify(tr)} != ${JSON.stringify(en)}`)
    }
  }
  for (const key of PLAIN_KEYS) checkForm(key, strings[key], `plain ${JSON.stringify(key)}`)
  for (const key of PLURAL_LIST) {
    for (const [category, value] of Object.entries(plurals[key])) {
      // Compare each category against the English form of the same category,
      // falling back to the English plural (what `other` holds for ja/ko/zh).
      checkForm(key, value, `plural ${JSON.stringify(key)}.${category}`)
    }
  }
  if (placeholderProblems.length) fail(`${lang}: placeholders: ${JSON.stringify(placeholderProblems, null, 1)}`)
  console.log(`placeholder parity: ${placeholderProblems.length === 0 ? 'ok' : `${placeholderProblems.length} problems`}`)

  // The three-placeholder key: exactly three %lld, no %@.
  const three = 'Deleted %lld of %lld items. %lld couldn\'t be deleted. Try again.'
  const threeCounts = counts(strings[three] ?? '')
  console.log(`3-placeholder key: ${JSON.stringify(strings[three])} -> %lld x${threeCounts.lld}, %@ x${threeCounts.at}`)
  if (threeCounts.lld !== 3 || threeCounts.at !== 0) {
    fail(`${lang}: "${three}" must carry exactly three %lld and no %@`)
  }
  const twoAt = '%@ with TidyByte — a private, on-device photo cleanup app. %@'
  const twoAtCounts = counts(strings[twoAt] ?? '')
  console.log(`share-text key: ${JSON.stringify(strings[twoAt])} -> %@ x${twoAtCounts.at}`)
  if (twoAtCounts.at !== 2 || twoAtCounts.lld !== 0) {
    fail(`${lang}: share-text key must carry exactly two %@`)
  }

  // Nothing pre-existing may have moved.
  const backup = JSON.parse(readFileSync(BACKUPS[lang], 'utf8'))
  const changedStrings = Object.entries(backup.strings).filter(([k, v]) => strings[k] !== v)
  const changedPlurals = Object.entries(backup.plurals).filter(
    ([k, v]) => JSON.stringify(plurals[k]) !== JSON.stringify(v)
  )
  const droppedStrings = Object.keys(backup.strings).filter((k) => !(k in strings))
  const droppedPlurals = Object.keys(backup.plurals).filter((k) => !(k in plurals))
  if (changedStrings.length) fail(`${lang}: pre-existing strings changed: ${JSON.stringify(changedStrings.map(([k]) => k))}`)
  if (changedPlurals.length) fail(`${lang}: pre-existing plurals changed: ${JSON.stringify(changedPlurals.map(([k]) => k))}`)
  if (droppedStrings.length) fail(`${lang}: pre-existing strings dropped: ${JSON.stringify(droppedStrings)}`)
  if (droppedPlurals.length) fail(`${lang}: pre-existing plurals dropped: ${JSON.stringify(droppedPlurals)}`)
  console.log(
    `pre-existing keys untouched: ${Object.keys(backup.strings).length} strings, ` +
      `${Object.keys(backup.plurals).length} plurals ` +
      `(${changedStrings.length + changedPlurals.length + droppedStrings.length + droppedPlurals.length} issues)`
  )

  // Glossary: the Live Photo term survives, and the recently-deleted term
  // matches the glossary value for this language.
  const livePhotoKeys = PLAIN_KEYS.filter((k) => /Live Photo/.test(k)).concat(
    PLURAL_LIST.filter((k) => /Live Photo/.test(k))
  )
  const liveProblems = []
  for (const key of livePhotoKeys) {
    const value = strings[key] ?? Object.values(plurals[key] ?? {}).join(' | ')
    if (!/Live Photo/.test(value)) liveProblems.push(`${key}: ${value}`)
  }
  if (liveProblems.length) fail(`${lang}: Live Photo term lost: ${JSON.stringify(liveProblems)}`)
  console.log(`Live Photo kept in ${livePhotoKeys.length} keys: ${liveProblems.length === 0 ? 'ok' : 'FAILED'}`)

  const glossary = JSON.parse(readFileSync(join(here, '_glossary.json'), 'utf8')).glossary
  const recentKeys = ['Moved to Recently Deleted', 'Recently Deleted', 'Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.', 'iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.']
  const recentProblems = recentKeys.filter((k) => !strings[k]?.includes(glossary['Recently Deleted'][lang]))
  if (recentProblems.length) fail(`${lang}: Recently Deleted term missing in ${JSON.stringify(recentProblems)}`)
  console.log(`Recently Deleted term ("${glossary['Recently Deleted'][lang]}"): ${recentProblems.length === 0 ? 'ok' : 'FAILED'}`)

  // Screenshot term, where the key is about screenshots.
  const shotKeys = PLAIN_KEYS.filter((k) => /screenshot/i.test(k)).concat(
    PLURAL_LIST.filter((k) => /screenshot/.test(k))
  )
  const shotProblems = []
  for (const key of shotKeys) {
    const value = strings[key] ?? Object.values(plurals[key] ?? {}).join(' | ')
    if (!value.includes(glossary.screenshot[lang])) shotProblems.push(`${key}: ${value}`)
  }
  if (shotProblems.length) fail(`${lang}: Screenshot term missing: ${JSON.stringify(shotProblems)}`)
  console.log(`Screenshot term ("${glossary.screenshot[lang]}"): ${shotProblems.length === 0 ? 'ok' : 'FAILED'}`)

  // The leading space on the burst label is load-bearing.
  if (!strings[' Favorites are kept.']?.startsWith(' ')) {
    fail(`${lang}: " Favorites are kept." lost its leading space`)
  }
  console.log(`leading space kept: ${strings[' Favorites are kept.']?.startsWith(' ') ? 'ok' : 'FAILED'}\n`)
}

console.log(failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`)
process.exit(failures === 0 ? 0 : 1)
