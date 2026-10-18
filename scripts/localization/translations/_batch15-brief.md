# Batch 15 — the 20 keys the defect sweep found

Same rules as batches 13 and 14: read the file, add only these keys, verify by
reading back from disk, report exact counts.

## What happened before this batch

Two parallel agents swept the app for localization defects and found a class the
catalog could not see: **user-visible English that never becomes a catalog key at
all**. In every case the catalog reported 100% coverage in all 20 languages while
the screen shipped English.

Four shapes, all now fixed:

1. **A `String` passed where SwiftUI wants a `LocalizedStringKey`.** `Text("literal")`
   localizes; `Text(someVariable)` renders verbatim. So `Text(category.name)`,
   `Text(exposureLabel(quality))`, `Label(accessory.title, …)` and
   `Text(presetLabel)` all shipped English. A related trap: an all-literal ternary
   *does* localize, but a ternary with a `String` branch does not — an explicit
   `var parts: [String] = [x ? "Video" : "Photo"]` silently killed both literals.

2. **English built in a view model.** The whole Storage dashboard composed its
   headings, win rows and breakdown labels as interpolated `String`s in
   `StorageDashboardViewModel` rather than through `L10n`.

3. **A fragment instead of a sentence.** `"\(size) cleaned up"` and
   `"\(message.text). \(action) available."` hand-assembled sentences from pieces,
   which no language can reorder.

4. **A join separator.** `parts.joined(separator: " and ")` hardcoded an English
   conjunction inside an otherwise-localized Siri dialog.

Several strings in this batch are **fragments that appear next to each other**, so
read the "shows as" column before translating — the surrounding text matters more
than the key alone.

## The 20 keys

Source of truth: `/tmp/batch15.json` (written by the sweep). 18 plain, 2 counted.

### Storage dashboard — breakdown sources

These label the rows of the storage breakdown chart.

| key | where it shows | notes |
|---|---|---|
| `Camera` | a breakdown row: photos taken with the camera | a source name, one word |
| `Photos & Videos` | legend row: the part of the library the app can clean | ampersand is fine to keep or replace with your language's "and" |
| `Apps, system & other` | legend row: everything the app cannot touch | three items in one label; keep it short |
| `estimated` | a small note under the legend meaning the split is approximate | lowercase, no period |

### Storage dashboard — reclaim wins

Each win row is a **title + detail pair**. The title counts items; the detail says
what tapping it would save.

| key | shows as | notes |
|---|---|---|
| `Free up %@` | the detail under a screenshots win | `%@` is a size like `1.2 GB` |
| `Save ~%@ by converting` | the detail under a Live Photos win | converting Live Photos to stills |
| `Compress to save ~%@` | the detail under a large-videos win | `~` is an approximation mark; keep an equivalent or drop it |
| `%@ total` | the detail under a saved-from-apps or large-files win | `%@` is a size |

### Storage dashboard — trend

| key | shows as | notes |
|---|---|---|
| `No change %@` | trend line, `%@` is a period like `in 30 days` | |
| `Library grew by %@ %@` | first `%@` is a size, second is the period | two `%@`s — do not reorder them relative to each other |
| `Library shrank by %@ %@` | same | |

### Media type and exposure

| key | where it shows | notes |
|---|---|---|
| `Photo` | VoiceOver announces a card as `"Photo, 12 Mar 2024, 2.4 MB"` | singular noun |
| `Video` | same for a video | singular noun |
| `Good` | exposure label: the photo is correctly exposed | **not** "good" as praise — it means *correctly exposed*. The sibling keys are `Too dark` and `Overexposed` |
| `Overexposed` | exposure label | the sibling `Too dark` already exists in your file — match its construction |

### Album and toast

| key | shows as | notes |
|---|---|---|
| `Failed to add to album: %@` | an error message; `%@` is the system's own error text | keep the colon, or use your language's equivalent |
| `%@. %@ available.` | VoiceOver for a toast: first `%@` is the message (`"Deleted 3 photos"`), second is the action (`"Undo"`) | two `%@`s. Reads as *"Deleted 3 photos. Undo available."* The action word is a button label from your file — `Undo` already exists |

### Siri dialog

| key | shows as | notes |
|---|---|---|
| `%@ and %@` | joins two item counts in a Siri answer: `"3 screenshots and 2 large files"` | a bare conjunction template. Both arguments are already-localized counted phrases from `%lld screenshot` / `%lld large file` |

### Counted strings (plurals)

Two keys, already added to `_plural-keys.json`. Supply **every plural category
your language requires** (the same set the other 68 plural keys use in your file).

| key | English `one` | English `other` |
|---|---|---|
| `%lld saved from apps` | `%lld saved from app` | `%lld saved from apps` |
| `%lld videos over %lld MB` | `%lld video over %lld MB` | `%lld videos over %lld MB` |

- `%lld saved from apps` is a breakdown row: photos that came from messaging apps.
- `%lld videos over %lld MB` counts videos larger than a size threshold; the
  threshold is in MB and the unit is not translated.
- Both forms carry **two** `%lld` in the second key and **one** in the first.
  Keep every `%lld` — a dropped one crashes `String(format:)`.

## Where to put them

- `scripts/localization/translations/<lang>.json`
- Plain strings go in `.strings` (the object is key-sorted; keep it that way).
- Counted strings go in `.plurals` as `{"one": "...", "other": "...", ...}`.
- Do **not** add the counted keys to `.strings`.
- Do not touch any other key, any `plurals` entry, or `_plural-keys.json`.

## Verification (mandatory, by reading back from disk)

1. File parses.
2. `strings` grew by exactly **18**; `plurals` grew by exactly **2**.
3. All 18 plain keys present and non-empty.
4. Both plural keys present with exactly the categories your language needs, and
   the same category set as the file's other plural entries.
5. `%lld` appears exactly once in each `%lld saved from apps` form and exactly
   twice in each `%lld videos over %lld MB` form.
6. `%@` count matches English in every plain key: `Free up %@` 1,
   `Save ~%@ by converting` 1, `Compress to save ~%@` 1, `%@ total` 1,
   `No change %@` 1, `Library grew by %@ %@` 2, `Library shrank by %@ %@` 2,
   `Failed to add to album: %@` 1, `%@. %@ available.` 2, `%@ and %@` 2.
7. No pre-existing key changed. Diff against a snapshot to prove it.

Report: the table of translations, any judgment call, and the verification
results.
