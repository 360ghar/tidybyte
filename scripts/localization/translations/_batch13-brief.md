# Translation batch 13 — 16 picker labels, and a consistency fix

Two jobs. The second one is easy to miss and matters more than the first.

## Job 1 — the 16 keys

`scripts/localization/translations/_batch13-keys.json` is the authority. These
are segmented-control and menu labels:

| enum | keys | where it appears |
|---|---|---|
| `LargeFileFilter` | `All`, `Photos`, `Videos` | 3-segment control, Large Files and Chat Media |
| `LargeFileSortOrder` | `Largest`, `Newest`, `Oldest`, `Filename` | sort menu, Large Files |
| `DuplicateScanType` | `Exact`, `Visual`, `All` | 3-segment control, Duplicates |
| `BreakdownMode` | `By Year`, `By Source` | 2-segment control, Storage |
| `BlurSensitivity` | `Low`, `Medium`, `High` | 3-segment control, Settings |
| `CategorySensitivity` | `Strict`, `Balanced`, `Broad` | 3-segment control, Settings |

`All` is one key shared by two enums. Same word, same meaning — one translation.

### These must be short

Every one is a segment in a segmented control, where the segments share the
screen width and the text truncates rather than wraps. `Largest` / `Newest` /
`Oldest` / `Filename` is **four** segments on an iPhone. A translation
noticeably longer than the English will be clipped.

Where the English is one word, prefer one word. `By Year` / `By Source` are the
only two-segment labels and have the most room.

### Register

These are labels on a control, not sentences. Match the register of a settings
picker in your language's iOS, which is usually a bare noun or adjective. No
trailing punctuation, no capitalization beyond your language's norm.

## Job 2 — the empty-state strings that name these tabs

Three strings in the *previous* batch tell the user to switch to one of these
tabs by name:

```
No photos larger than %lld MB. Lower the threshold or switch to All/Videos.
No videos larger than %lld MB. Lower the threshold or switch to All/Photos.
No files larger than %lld MB. Lower the threshold to see more.
```

(The third names no tab and needs no change.)

**Your language may currently disagree with itself.** Some languages translated
the tab names inline when they were still English on screen; others deliberately
left `All/Videos` in English because naming a tab the user cannot find would be
worse. Now that the tabs are really being translated, the sentence and the
control have to agree: whatever you choose for `All`, `Photos` and `Videos` in
Job 1 is the exact wording that must appear in these two strings.

**So: translate the 16 keys first, then re-read your two empty-state strings and
fix them if the names do not match.** Use the same words in both places, with
whatever case or particle your grammar requires in the sentence.

If your language's inline names already match your new labels, leave those
strings alone and say so.

## How to work

Write a Node.js script. Add the 16 keys to `strings`; update the empty-state
strings only where they need it. Keep 2-space indent and the file's existing key
sort order.

## Verify before reporting

Read back from disk and assert:

- `strings` count went up by exactly 16 (and by 0 more, even if you edited a value)
- all 16 keys present and non-empty
- no pre-existing key changed **except** the empty-state strings you intentionally fixed
- `plurals` untouched
- for every one of the 16, the label is within a reasonable length of the English
  (report any that are more than ~1.5× the English)

Then report, per language: the 16 labels, and for the two empty-state strings
either "already matched" or the before/after value.
