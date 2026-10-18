# Translation batch 12 — 43 keys the prose audit found

These are the last untranslated strings in the app. They were **invisible until
now**: each one is user-facing text that never reached the String Catalog,
because it was built in code rather than written as a SwiftUI `Text` literal —
a `switch` that returned a `String`, a view-model `errorMessage`, an enum's
display label, a fragment interpolated into an alert body.

The code now routes every one of them through `L10n`, so they appear in the
catalog and need translating. Until then they render **English in all 20
languages**, and `check.mjs --strict` fails the build.

The exact key list is in `scripts/localization/translations/_batch12-keys.json`.
Read it — it is the authority. Do not add, rename, or reorder keys.

## What these strings are

They fall into a few groups, which matters because several are **sentence
fragments** rather than standalone sentences:

| group | examples | note |
|---|---|---|
| Filter labels | `Blur`, `Darkness`, `Brightness`, `Lens smudge confidence` | a tab/pill label |
| Keeper reasons | `Sharpest`, `Best exposed`, `Highest res`, `Most recent`, `Best overall`, `Your choice`, `Best` | shown in a pill on a photo |
| Comparison actions | `Keep as Best`, `Don't Delete`, `Best quality`, `Recommended: %@`, `Keeping this · %@` | button titles and status text |
| Empty states | `No Large Files`, `No Large Videos`, `No photos larger than %lld MB. Lower the threshold or switch to All/Videos.` | |
| Error / status | `Couldn't prepare the selected items to share.`, `Failed to save compressed photo to library.`, `Sizes unavailable`, ` known · %lld sizes unavailable` | |
| Replace-flow copy | `a new, smaller copy of each photo`, `the original photos`, `the Live Photos`, … | **fragments** — see below |
| The explainer template | the one key containing real newlines | **template** — see below |

## Sentence fragments — read this before translating them

Six keys are pieces slotted into a sentence that is assembled at runtime:

```
ReplaceOriginalsNotice.explainer(copies: "a new, smaller copy of each photo",
                                originals: "the original photos")
```

produces:

```
1. TidyByte saves <copies>.
2. When all copies are saved, iOS asks you to delete <originals>.
```

So `a new, smaller copy of each photo` must read correctly **after "TidyByte
saves"**, and `the original photos` must read correctly **after "delete"**. They
are not standalone sentences — do not capitalize them or add a full stop.

The same six fragments also appear in the video and Live Photo variants, where
the surrounding English differs only in the noun. Keep them parallel across the
three variants so the three alerts read consistently.

## The explainer template

One key contains **real newlines** (not the two characters `\` and `n`):

```
1. TidyByte saves %@.
2. When all copies are saved, iOS asks you to delete %@.

If you tap Don't Allow, you keep both versions. Deleted originals stay in Recently Deleted for 30 days.
```

Translate the whole thing as one string, and:

1. **Keep both `%@` placeholders**, in that order. They are the two fragments
   above, substituted in.
2. **Keep the two newlines and the blank line between the paragraphs.** Write the
   translation as a single JSON string value with `\n` escapes — the app renders
   the newlines, so the numbering and the paragraph break must survive.
3. Keep `1.` and `2.` as list markers.
4. `Don't Allow` is the **iOS button label**. Use the exact wording your
   language's iOS shows on that alert (the "Don't Allow" button of the delete
   confirmation), because the sentence tells the user which button to tap.

## Placeholders

`%lld` is a number, `%@` is text. They must appear exactly as many times as in
the English, and in a position where the sentence still parses. If your language
needs a different order, use positional specifiers (`%2$lld … %1$@`) — that is
supported and the validator understands it.

## Keep literal

`TidyByte`, `iPhone`, `iPad`, `iOS`, `Live Photo`/`Live Photos`, `iCloud`,
`Recently Deleted` (unless your language has an established iOS album name for
it, in which case use that — check the glossary), `MB`.

## Before you finish

Read your files back from disk and assert: `strings` count went up by exactly
43; every key in `_batch12-keys.json` is present and non-empty; placeholder
counts match the English for every key; the explainer template still contains
two `%@` and two `\n` plus a blank line; no pre-existing key changed; `plurals`
untouched.
