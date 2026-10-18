#!/usr/bin/env node
/**
 * Collects the keys Xcode's own extractor saw, straight from `.stringsdata`.
 *
 *   node scripts/localization/collect-xcode-keys.mjs --derived <DerivedData>
 *
 * Writes `scripts/localization/strings.xcode.json`. `build-catalog.mjs` reads it
 * to decide which catalog keys are still live.
 *
 * Why this exists
 * ---------------
 * `xcstringstool sync` does not remove a catalog key that no longer appears in
 * any `.stringsdata` — it only ever adds and re-states. So a key whose source
 * text was deleted, or rewritten into a different shape, stays in the catalog
 * forever, carrying 20 translations and reporting 100% coverage for a string
 * nothing looks up. That is worse than a missing translation: the denominator
 * grows, every language's percentage is flattered, and the dead entry hides the
 * fact that a live string is untranslated.
 *
 * A real example: `"Couldn't %@ this %@%@."` was assembled at the call site from
 * five fragments. Rewriting it as four whole sentences left the old key in the
 * catalog, translated into 20 languages, for a lookup that no longer exists.
 *
 * `.stringsdata` is a small JSON file per compiled source:
 *
 *   {"version":1,"tables":{"Localizable":[{"comment":"","key":"Skip", ...}]},
 *    "source":"/path/to/OnboardingView.swift"}
 *
 * so the key set is readable directly, with no need to interpret Xcode's state
 * machine. Files are matched to the two targets that share the catalog.
 */
import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = join(ROOT, 'scripts/localization/strings.xcode.json');

/** Targets whose strings merge into `Tidybyte/Resources/Localizable.xcstrings`. */
const TARGETS = ['Tidybyte.build', 'TidybyteWidget.build'];

function parseArgs() {
  const args = process.argv.slice(2);
  const derivedIndex = args.indexOf('--derived');
  if (derivedIndex === -1 || !args[derivedIndex + 1]) {
    console.error('usage: collect-xcode-keys.mjs --derived <DerivedData path>');
    process.exit(2);
  }
  return { derived: args[derivedIndex + 1] };
}

function walk(dir, out = []) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) walk(path, out);
    else if (entry.name.endsWith('.stringsdata')) out.push(path);
  }
  return out;
}

function main() {
  const { derived } = parseArgs();

  const found = walk(derived).filter((path) =>
    TARGETS.some((target) => path.includes(`/${target}/`)),
  );

  if (found.length === 0) {
    console.error(`FAIL: no .stringsdata under ${derived}`);
    console.error('      Build first — without Xcode\'s keys the catalog would be pruned');
    console.error('      down to the code-built ones.');
    process.exit(1);
  }

  const keys = new Set();
  const perFile = [];
  for (const path of found) {
    let data;
    try {
      data = JSON.parse(readFileSync(path, 'utf8'));
    } catch {
      continue;
    }
    let count = 0;
    for (const table of Object.values(data.tables ?? {})) {
      for (const entry of table ?? []) {
        // Xcode emits an empty key for interpolation-only calls; it is not a
        // real lookup and `build-catalog.mjs` drops it too.
        if (entry.key && entry.key.trim()) {
          keys.add(entry.key);
          count += 1;
        }
      }
    }
    perFile.push({ file: relative(ROOT, path), keys: count });
  }

  writeFileSync(
    OUT,
    JSON.stringify(
      {
        keys: [...keys].sort(),
        total: keys.size,
        // Kept so a stale collection is obvious: this is what the build saw.
        files: perFile.length,
      },
      null,
      2,
    ) + '\n',
  );

  console.log(`Xcode keys collected: ${keys.size} (from ${perFile.length} .stringsdata files)`);
}

main();
