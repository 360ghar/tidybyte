# Batch 14 — final 10 keys

Same rules as batch 13: read the file, add only these keys, verify by reading back
from disk, report exact counts.

## What happened before this batch

A guard added to `extract.mjs` found a bug class nobody had seen: a string literal
nested inside an interpolation of a localizable call.

```swift
// Looks localized. Is not.
Text("Couldn't \(asset.isLocallyAvailable ? "load" : "download") this \(...).")
```

`Text` treats the outer literal as a key (`"Couldn't %@ this %@%@."`) and renders
the nested `String`s verbatim. Every language got `"load"` / `"video"` in English.
The German template was `"%@ dieses %@%@ nicht möglich."`, so a German user read
**"load dieses video nicht möglich."** — no language can reorder a sentence it
never sees whole.

Those call sites are now four whole sentences, which is where the last four keys
come from. A dead key (`"Couldn't %@ this %@%@."`) was pruned from the catalog at
the same time; the catalog is now **767 keys, 66 of them plural**.

## The 10 keys

Source of truth: `_batch14-keys.json`. Eight plain strings, two counted.

### Plain strings

| key | where it shows | notes |
|---|---|---|
| `Mixed` | Photo/Video Compression: the quality picker's label when the selected items have different presets, so there is no single one to name | a word, not a status. Must read naturally as `"Quality: <Mixed>"` |
| `Start here. ` | VoiceOver prefix on the cleanup card the app recommends starting with | **keep the trailing space** — it is a prefix glued to the tool name |
| `Untitled` | album name fallback when PhotoKit returns no title | Photos shows its own name for these; match what iOS uses if your language has one |
| `media` | filename fallback in accessibility labels: `"Preview media, 2.4 MB"`, `"Select media"` | lowercase noun, no article |
| `Couldn't load this photo.` | swipe card when a photo fails to load from the device | full sentence, ends with a period |
| `Couldn't load this video.` | same, video | |
| `Couldn't download this photo from iCloud.` | same, but the asset is iCloud-only | "download" is the iCloud transfer, not a purchase |
| `Couldn't download this video from iCloud.` | same, video | |

### Counted strings (plurals)

Two keys, added to `_plural-keys.json`. Supply **every plural category your
language requires** (the same set the other 66 plural keys use in your file).

| key | English `one` | English `other` |
|---|---|---|
| `%lld exact copies` | `%lld exact copy` | `%lld exact copies` |
| `%lld look-alike photos` | `%lld look-alike photo` | `%lld look-alike photos` |

These render as the header of a duplicate group: a group of 3 identical files
reads `"3 exact copies"`, a group of visually similar ones reads
`"3 look-alike photos"`.

- Keep `%lld` exactly once in each form.
- `exact` vs `look-alike` distinguishes byte-identical from visually similar —
  use the same words your file already uses for the Duplicates screen's two scan
  types (`Exact` / `Visual` keys exist from batch 13, and the tool description
  "Find exact & visual duplicates").
- The English key name is the `other` form; that is the file's existing
  convention (`"%lld items"` carries `one`/`other`).

## Where to put them

- `scripts/localization/translations/<lang>.json`
- Plain strings go in `.strings` (the object is key-sorted; keep it that way).
- Counted strings go in `.plurals` as `{"one": "...", "other": "...", ...}`.
- Do **not** add the counted keys to `.strings`.
- Do not touch any other key, any `plurals` entry, or `_plural-keys.json`.

## Verification (mandatory, by reading back from disk)

1. File parses.
2. `strings` = **707** (699 + 8). `plurals` = **66** (64 + 2).
3. All 8 plain keys present, non-empty, byte-identical to the English where the
   language does not translate that term (a proper noun or a technical label).
4. Both plural keys present with exactly the categories your language needs, and
   the same category set as the file's other plural entries.
5. `%lld` appears exactly once in every plural form.
6. No pre-existing key changed. Diff against a snapshot to prove it.
7. `Start here. ` still ends with a space.
8. The four `Couldn't ...` sentences end with the language's sentence-ending
   punctuation, and are not built from fragments.

Report: the table of translations, any judgment call, and the verification
results.
