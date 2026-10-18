# Localization pipeline

TidyByte ships 20 languages besides English. Three surfaces are translated and
each has its own pipeline:

| surface | source | translations | output |
|---|---|---|---|
| iOS app | Swift source | `translations/<code>.json` | `Tidybyte/Resources/Localizable.xcstrings` |
| App Store listing | `docs/appstore/listings.json` | same file, per-language keys | pasted into App Store Connect |
| Website | `src/content/pages/index.html` + `src/data/pages.ts` | `site/site-translations/<slug>.json` | `src/content/pages/index.<slug>.html` |

## Why English text is the key

Every catalog uses the English string as the lookup key rather than a symbolic
identifier like `settings.language.title`. It means:

- a missing translation falls back to readable English, not to a bare key;
- a translator sees the source in the file they are editing;
- a reworded English string shows up as a missing key, which is loud, instead of
  as a silently stale translation, which is not.

The cost is that changing English wording invalidates the translation, and that
is the intended trade.

## App strings

```sh
./scripts/localization/refresh.sh
```

One command, six steps: sync the catalog with the Swift source, extract
literals the compiler cannot see, collect Xcode's own key set, rebuild the
catalog from the JSON files, check coverage, and report. Run it after any change
to user-facing strings, then commit the result. CI runs the same script and
fails if it produces a diff, so a string change that skips this step fails the
build.

Individual steps:

| script | what it does |
|---|---|
| `extract.mjs` | finds translatable literals in Swift, including `L10n` calls, App Shortcut phrases, and `INFOPLIST_KEY_*UsageDescription` values |
| `collect-xcode-keys.mjs` | reads the keys Xcode's extractor saw out of the build's `.stringsdata`, so `build-catalog.mjs` can tell a live key from a dead one |
| `build-catalog.mjs` | merges `translations/*.json` into `Localizable.xcstrings`, and prunes keys no call site can reach |
| `check.mjs` | coverage, placeholder parity, and Info.plist key resolution |

### Why the catalog is pruned

`xcstringstool sync` only ever adds and re-states. A key whose source text was
deleted, or rewritten into a different shape, stays in the catalog forever —
carrying 20 translations and reporting 100% coverage for a string nothing looks
up. That is worse than a missing translation: the denominator grows, every
language's percentage is flattered, and a genuinely untranslated string hides
inside the total.

`build-catalog.mjs` therefore computes the set of keys something can actually
look up — Xcode's literals, this repo's `L10n` calls, and the counted strings in
`_plural-keys.json` — and drops anything else. It prints what it removed.

Pruning needs `strings.xcode.json`, which `collect-xcode-keys.mjs` writes from
the build output. Without it a live Xcode key is indistinguishable from a stale
one, so pruning is skipped and the script says so. `refresh.sh` always runs the
collector first.

### Where the build output comes from

`refresh.sh` uses a repo-local `build/LocalizationDerivedData` by default, not
`~/Library/Developer/Xcode/DerivedData`. That shared directory holds build trees
from every checkout and configuration, so a lookup there can read a
`.stringsdata` left behind by an unrelated build and merge keys from source that
no longer exists. The CI gate is `git diff --exit-code` on the catalog, which
only means anything if the catalog is a pure function of the source.

Override with `DERIVED_DATA_PATH` if you like, but the build and the lookup
always use the same value — they did not once, and the catalog silently grew a
dead key.

`extract.mjs` keeps two escape hatches:

- `INTENTIONAL_LITERALS` — strings that look translatable but are not (log
  messages, LLM prompts, PhotoKit predicates).
- `PROSE_EXCLUDED_FILES` — whole files that are not user-facing.

Adding to either is how you silence a false positive. Do not silence a real one.

### The one pattern that hides a string completely

```swift
// WRONG — the key is computed, so no scan can see it
var displayName: String { L10n.string(rawValue) }

// RIGHT — write the cases out; the switch is also exhaustive at compile time
var displayName: String {
    switch self {
    case .all: L10n.string("All")
    case .photos: L10n.string("Photos")
    case .videos: L10n.string("Videos")
    }
}
```

The first form localizes correctly at runtime and works in English, which is
exactly what makes it dangerous: the string never reaches the catalog, never
appears in a coverage number, and ships English in all 20 languages with
everything green. Seven enums had this shape and sixteen keys were missing
entirely.

`extract.mjs` now scans for `L10n.*(rawValue)` and fails on it, so the pattern
cannot come back. See `scanComputedKeys`.

## App Store listing

`docs/appstore/listings.json` holds one entry per language with the six App Store
fields. `make-listings.mjs` writes it, `check-listings.mjs` validates it:

```sh
node scripts/localization/check-listings.mjs --strict
```

`--strict` fails on any language missing a field; without it, only limits are
checked. The validator enforces the per-field character limits in `_limits`, that
keywords have no space after a comma, and that no keyword repeats a word already
in that language's name or subtitle — Apple indexes all three together, so a
repeat wastes a slot.

**`keywords` is not a translation.** It is the search index, and it is written
from scratch per language from the terms a speaker would actually type.

## Website

```sh
node scripts/localization/site/extract-site-strings.mjs   # English -> JSON
node scripts/localization/site/build-site-translations.mjs # JSON -> 20 HTML pages
```

The extractor pulls translatable text nodes and `alt`/`title`/`aria-label`
attributes out of `index.html`, plus the title and description from
`src/data/pages.ts`. The builder takes the **English HTML as the structural
source of truth** and replaces only the text, so every localized page has the
same markup as the page the design was reviewed against. Hand-editing 20 copies
of a 47 KB file is how structural drift happens.

The builder fails if any English string has no translation, which is the point:
a page that declares `lang="de"` while rendering English is worse than one that
does not exist.

`site/keep-literal.mjs` lists strings that stay English everywhere (product and
framework names, the version). Both the extractor and the builder read it, so a
keep-literal string is neither asked for nor reported as missing.

### Adding a language

1. Add it to `src/data/languages.ts` (slug, `htmlLang`, endonym, RTL flag).
2. Add the app strings to `translations/<code>.json` and run `refresh.sh`.
3. Add the listing to `docs/appstore/listings.json`.
4. Add `site-translations/<slug>.json` and `<slug>.meta.json`, then run the
   builder.
5. Add the `/<slug>` → `/<slug>.html` rewrite to `netlify.toml`.

`seo-audit.mjs` fails if the language lists in `languages.ts`, `astro.config.mjs`
and `netlify.toml` drift apart.

## Translating

Batches are dispatched to translators with a brief in `translations/_batch*.md`.
Each brief states the key set, the glossary terms, and what stays literal. A
translator must read the file back from disk and verify counts and placeholder
parity before reporting — a batch once reported success having written nothing,
which is why read-back verification is mandatory and not optional.

`translations/_glossary.json` is the shared term list. When a term's translation
is decided once (screenshot, Recently Deleted, Screen Time), it goes here so the
next batch does not re-decide it.

**Machine-drafted translations have not had a native review pass.** The
glossary, placeholder parity, and structural checks catch mechanical errors;
they cannot catch register, gender agreement, or a term that is technically
correct but unused in a market. Each batch's brief records the judgment calls
its translator flagged — those are the places to start a review.
