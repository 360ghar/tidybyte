// Batch 14 verification — re-reads de / es / fr / it / pt-BR FROM DISK and
// asserts every requirement. Diffs against the pre-write snapshot in
// /tmp/batch14-baseline/ to prove no pre-existing key changed.
//
//   node scripts/localization/translations/_batch14-verify-de-es-fr-it-ptbr.mjs

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = '/tmp/batch14-baseline';

const LANGS = ['de', 'es', 'fr', 'it', 'pt-BR'];
const EXPECTED_STRINGS = 707;
const EXPECTED_PLURALS = 66;

const wanted = JSON.parse(readFileSync(join(HERE, '_batch14-keys.json'), 'utf8'));
const plainKeys = Object.keys(wanted.plain);
const pluralKeys = Object.keys(wanted.plurals);
const couldntKeys = plainKeys.filter((k) => k.startsWith("Couldn't "));

let failures = 0;

function check(lang, label, ok, detail = '') {
  const tag = ok ? 'PASS' : 'FAIL';
  if (!ok) failures += 1;
  console.log(`  [${tag}] ${lang}  ${label}${detail ? `  ${detail}` : ''}`);
}

for (const lang of LANGS) {
  console.log(`\n=== ${lang} ===`);
  const raw = readFileSync(join(HERE, `${lang}.json`), 'utf8');
  const base = JSON.parse(readFileSync(join(BACKUP_DIR, `${lang}.json`), 'utf8'));

  let file;
  try {
    file = JSON.parse(raw);
    check(lang, 'parses as JSON', true);
  } catch (e) {
    check(lang, 'parses as JSON', false, e.message);
    continue;
  }

  const strings = file.strings;
  const plurals = file.plurals;

  // 2. counts
  const nStrings = Object.keys(strings).length;
  const nPlurals = Object.keys(plurals).length;
  check(lang, `strings == ${EXPECTED_STRINGS}`, nStrings === EXPECTED_STRINGS, `got ${nStrings}`);
  check(lang, `plurals == ${EXPECTED_PLURALS}`, nPlurals === EXPECTED_PLURALS, `got ${nPlurals}`);

  // 3. all 8 plain keys present, non-empty
  for (const key of plainKeys) {
    const value = strings[key];
    check(lang, `plain "${key}" non-empty`, typeof value === 'string' && value.trim() !== '', JSON.stringify(value));
  }

  // 7. Start here. keeps its trailing space
  const start = strings['Start here. '];
  check(lang, '"Start here. " value ends with a space', typeof start === 'string' && start.endsWith(' '), JSON.stringify(start));

  // 8. the four Couldn't sentences read as whole sentences
  for (const key of couldntKeys) {
    const value = strings[key];
    const endsOk = typeof value === 'string' && value.endsWith('.');
    const differsFromEnglish = value !== wanted.plain[key];
    check(lang, `"${key}" is a translated sentence`, endsOk && differsFromEnglish, JSON.stringify(value));
  }

  // 4. both plural keys present with the same category set the file's other
  //    plurals use (taken from the pre-write snapshot)
  const baselineCats = new Set();
  for (const forms of Object.values(base.plurals)) for (const c of Object.keys(forms)) baselineCats.add(c);
  const expectedCats = [...baselineCats].sort().join(',');
  for (const key of pluralKeys) {
    const forms = plurals[key];
    const present = forms && typeof forms === 'object';
    const cats = present ? Object.keys(forms).sort().join(',') : '';
    check(lang, `plural "${key}" category set == [${expectedCats}]`, cats === expectedCats, `got [${cats}]`);

    // 5. %lld exactly once per form
    if (present) {
      for (const [cat, form] of Object.entries(forms)) {
        const hits = (form.match(/%lld/g) ?? []).length;
        check(lang, `plural "${key}" [${cat}] has %lld once`, hits === 1, `got ${hits}: ${JSON.stringify(form)}`);
      }
    }
  }

  // 6. 0 pre-existing keys changed
  const baseStrings = base.strings;
  let changed = [];
  for (const [key, value] of Object.entries(baseStrings)) {
    if (!(key in strings)) changed.push(`removed ${JSON.stringify(key)}`);
    else if (strings[key] !== value) changed.push(`changed ${JSON.stringify(key)}`);
  }
  const addedStrings = Object.keys(strings).filter((k) => !(k in baseStrings));
  check(lang, '0 pre-existing strings changed/removed', changed.length === 0, changed.slice(0, 5).join('; '));
  const unexpectedAdded = addedStrings.filter((k) => !plainKeys.includes(k));
  check(lang, 'only the 8 new plain keys were added', unexpectedAdded.length === 0, unexpectedAdded.join('; '));

  let pluralChanged = [];
  for (const [key, value] of Object.entries(base.plurals)) {
    if (JSON.stringify(plurals[key]) !== JSON.stringify(value)) pluralChanged.push(key);
  }
  const addedPlurals = Object.keys(plurals).filter((k) => !(k in base.plurals));
  check(lang, '0 pre-existing plurals changed', pluralChanged.length === 0, pluralChanged.join('; '));
  check(
    lang,
    'only the 2 new plural keys were added',
    addedPlurals.length === 2 && addedPlurals.every((k) => pluralKeys.includes(k)),
    addedPlurals.join('; '),
  );

  // keys stay in code-point sort order
  const keys = Object.keys(strings);
  check(lang, 'strings keys remain code-point sorted', keys.join('\n') === [...keys].sort().join('\n'));
}

console.log(`\n${failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`}`);
process.exit(failures === 0 ? 0 : 1);
