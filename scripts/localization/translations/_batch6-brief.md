# Translation batch 6 — 64 new keys

These 64 strings were just picked up by the compiler's extractor after the
shared components (`EmptyStateView`, `ToolIdleView`, `ToolScanningView`,
`ToolErrorBanner`) changed their display parameters from `String` to
`LocalizedStringKey`. They were already on screen — they simply never reached
the catalog, so they stayed English in every language.

Write each one into your language's file at
`scripts/localization/translations/<lang>.json`, under `"strings"`. Keys are
the exact English source text, including punctuation and trailing ellipses.
Do not add, rename, or reorder keys.

## Non-negotiables

1. **Placeholders are load-bearing.** `%lld` is an integer, `%@` is a
   pre-formatted string. Reproduce every placeholder exactly once. Never
   translate, reorder without positional syntax, or drop one. Only one key in
   this batch has a placeholder.
2. **Follow `_glossary.json`.** Terms in `keepLiteral` stay as-is (TidyByte,
   iOS, iPhone, iPad, HEIC, Live Photo(s), MB, iCloud). Use the glossary's
   per-language term for "screenshot", "duplicate", "compress", and the rest.
3. **Preserve trailing `...`.** Three keys are progress labels ending in an
   ellipsis (`"Analyzing photos..."`). Keep three dots, not a single ellipsis
   character.
4. **Voice: calm, plain, second person.** These are empty states, button
   labels, and one-line explanations. Match the register of Apple's own iOS
   strings in your language — no marketing tone, no exclamation marks unless
   the English has one.
5. **TidyByte is a proper noun** and never inflects for case or gender.

## The keys

### Tool idle screens — title, one-line description, button, hint

These four lines appear together on a tool's landing screen. `title` is the
screen heading, `message` describes what the tool does, `primaryTitle` is the
start button, `primaryHint` is small print under it.

| English | Role |
|---|---|
| `Find Duplicate Photos` | heading |
| `Scan your library for exact and visually similar duplicates.` | description |
| `Start Scan` | button |
| `Scans your whole library for duplicates` | hint |
| `Find Similar Photos` | heading |
| `Groups photos taken within %lld seconds of each other.` | description, `%lld` = integer seconds |
| `Scans your library for photos taken close together` | hint |
| `Detect Low-Quality Photos` | heading |
| `Find blurry, too dark, and overexposed photos.` | description |
| `Start Analysis` | button |
| `Scans your library for out-of-focus and poorly lit photos` | hint |
| `Organize by Content` | heading |
| `Group photos into memes, documents, food, pets, nature, selfies and media saved from other apps.` | description |
| `Scans your library and sorts photos by what's in them` | hint |

### Progress labels — keep the ellipsis

| English | When shown |
|---|---|
| `Analyzing photos...` | blur/exposure analysis running |
| `Grouping similar photos...` | feature-print clustering running |
| `Sorting photos...` | content classification running |
| `Scanning for duplicates...` | duplicate hashing running |

### Empty states — heading and body

Every one of these is a heading plus one or two sentences shown when a list has
nothing in it. Keep the heading short — it renders in a large bold font and
must not wrap awkwardly.

| Heading | Body |
|---|---|
| `No Savings Yet` | `Space you free up with any cleanup tool shows up here.` |
| `No Duplicates Found` | `Your photo library is clean!` |
| `No Similar Photos Found` | `Your library looks clean!` |
| `No Burst Photos` | `You don't have any burst photo groups.` |
| `No Live Photos` | `You don't have any Live Photos in your library.` |
| `No Screenshots` | `You don't have any screenshots in your library.` |
| `No Videos` | `You don't have any videos in your library.` |
| `No Photos` | `You don't have any photos to compress.` |
| `No Large Photos` | `No photos over 2 MB are left to compress. HEIC photos are already small.` |
| `No Media` | `Your library is empty.` |
| `No Albums` | `No albums with photos were found.` |
| `No History` | `Compressed photos and videos will appear here.` |
| `Nothing to Sort` | `We couldn't sort any photos into categories.` |
| `All Clear` | `No issues found in this category.` |
| `No matching media` | (no body — filters matched nothing) |

`No Savings Yet` is about reclaimed disk space: the screen totals how much
space the user has freed up. `No Large Photos` means "there is nothing left to
compress" — it is a success state, not an error.

### Buttons and short labels

| English | Notes |
|---|---|
| `Scan Again` | re-run a finished scan |
| `Show All Photos` | clear a filter |
| `No more items` | end of a full-screen preview sequence |
| `No more Live Photos` | same, for Live Photos |
| `File Size` | metadata row label |
| `Resolution` | metadata row label, e.g. "4032 × 3024" |
| `Something went wrong` | default error banner title |
| `Deletion Error` | error banner title |
| `Not Enough Space` | error banner title |
| `No Issues` | (not in this batch — ignore) |

### Error bodies

| English | Notes |
|---|---|
| `There isn't enough free space to compress the selected photos. Free up some space and try again.` | photos |
| `There isn't enough free space to compress the selected videos. Free up some space and try again.` | videos |

The two differ only in `photos` / `videos`. Keep them parallel so they read as
one message with a noun swapped.

### Onboarding — three screens

These render full-screen during first launch. Each is a heading plus a body.

| Heading | Body |
|---|---|
| `Swipe Through Your Library` | `Review one photo at a time. Swipe left to delete, right to keep, or up to file it into an album — and undo anything by mistake.` |
| `Nothing Leaves Your Device` | `TidyByte has no account and no servers. Every scan, comparison, and analysis runs right here on this device.` |
| `Access to Your Photos` | `TidyByte reads your library to find duplicates, blurry shots, and oversized files. It only ever changes what you approve. iOS will ask for permission next.` |

The first body names three gestures: left = delete, right = keep, up = file
into an album. Use your language's natural words for swipe gestures and keep
the left/right/up mapping intact — it is a literal instruction.

The third body says iOS will ask for permission next. `iOS` stays `iOS`.

## Right-to-left languages (ar, he)

Everything above applies, plus: the three swipe directions in the onboarding
body must keep their **physical** meaning. Left is still left on screen. If
your language would normally phrase a swipe by the direction of content travel
rather than the finger, phrase it by the finger.
