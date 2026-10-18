# Translation batch 7 — 57 new keys

These 57 strings reached the catalog when code that built text in `String`
variables was converted to go through `L10n`. They were always on screen; they
were simply invisible to the compiler's extractor, so they stayed English in
every language.

Write each one into your language's file at
`scripts/localization/translations/<lang>.json`, under `"strings"`. Keys are the
exact English source text. Do not add, rename, or reorder keys.

> **Correction (applies to the first run of this batch):** the tables below list
> 56 keys; the batch is **57**. The missing one is `"Failed to re-encode the
> photo."`, a photo-compression error that belongs in §2 with the other
> `Failed to …` messages. Every translator correctly caught this by deriving the
> set from the catalog instead of trusting the tables, so no file is short a key.
>
> **Second correction:** `"Screen Time"` was described below as a `keepLiteral`
> term. It is not, and should not be — the sentence tells the user to go change
> a setting, so it must use the name iOS actually shows in Settings. The
> glossary now carries a per-language value for it under `glossary["Screen
> Time"]`, and all 20 files use it.

## Non-negotiables

1. **Placeholders are load-bearing.** `%lld` is an integer, `%@` is a
   pre-formatted string (usually a file size like "1.5 GB" or a system error
   message). Reproduce each placeholder exactly once, in an order that reads
   naturally in your language. Two keys have a placeholder: `"Updated %lldd
   ago"`, `"Export failed: %@"`, `"Save failed: %@"`, `"Up to %@ to free on
   iPhone"`, and `"This item uses %@; review whether you need it."`
2. **Follow `_glossary.json`.** `keepLiteral` terms stay as-is (TidyByte, iOS,
   iPhone, iPad, HEIC, Live Photo(s), MB, iCloud). Use the glossary's
   per-language term for "screenshot", "duplicate", "compress", "Recently
   Deleted", and "Screen Time".
3. **Preserve the em dash `—`** where the English has one, unless your
   language's typography calls for a different break. Six keys have one.
4. **Voice: calm, plain, second person.** These are error messages, permission
   explanations, and search hints. Match Apple's own register in your language.
   No exclamation marks unless the English has one (none do).
5. **TidyByte is a proper noun** and never inflects for case or gender.

## The keys, by screen

### 1. Photo permission — five states plus a primer

The app shows one of these before or instead of the iOS photo prompt. `title`
is a heading; `message` is one or two sentences explaining the situation.

| Title | Message |
|---|---|
| `TidyByte Needs Your Photos` | `TidyByte reviews your library on this device to find what's worth cleaning up. Nothing is uploaded, and nothing changes without your say-so. iOS will ask for access next.` |
| `Photo Access Is On` | `TidyByte can review your library on this device. Nothing is uploaded, and nothing changes without your say-so.` |
| `Photo Access Is Off` | `iOS is blocking TidyByte from your library, and it will not ask again. Settings is the only way back — turn photo access on there and everything here starts working again.` |
| `Photo Access Is Restricted` | `A Screen Time or device-management restriction is blocking photo access. The Photos switch in Settings cannot change it — that restriction has to be lifted first.` |
| `TidyByte can only see the photos you picked. Add more whenever you want it to review the rest of your library.` | (body of the "Limited" state; its title is already translated) |

Plus the pre-prompt explainer:

| English | Notes |
|---|---|
| `Allow Photo Access?` | alert title, ends in a question mark |
| `iOS asks for photo access only once, and this is that ask. TidyByte then reviews your library on this device. Nothing is uploaded, and nothing changes without your review.` | body |
| `Not Now` | the decline button. Apple's own iOS uses this exact phrase in your language for permission prompts — match it. |

The three "Nothing is uploaded" sentences are privacy assurances. Keep them
concrete; do not soften them into marketing.

### 2. Compression errors

Shown in an error banner when a compression or conversion fails. Short, factual.

| English | When |
|---|---|
| `Photo not found.` | asset was deleted mid-run |
| `This item can't be compressed as a photo.` | wrong media type |
| `Failed to load the photo.` | decode failure |
| `Photo size unknown (iCloud-only) — skipped.` | not downloaded from iCloud |
| `Video not found.` | asset was deleted mid-run |
| `Couldn't load the video (it may still be in iCloud). Please try again.` | download timeout |
| `Video size unknown (iCloud-only) — skipped.` | not downloaded from iCloud |
| `Failed to create export session.` | AVFoundation setup failed |
| `Exported file was empty.` | export produced nothing |
| `Failed to read file size.` | filesystem read failed |
| `Cancelled.` | user cancelled. One word. |
| `Unknown error` | last-resort fallback, no trailing period |
| `Save failed: %@` | `%@` is a system error message. Keep the colon. |
| `Export failed: %@` | same |
| `Already compressed` | item was compressed in an earlier run; no trailing period |
| `Size unknown (iCloud-only) — skipped` | batch-skip reason; no trailing period |

`"…— skipped"` reads as a clause after a dash: "not available, so skipped".
Keep it that terse.

### 3. Local AI and search messages

Shown under the content-search field on the Smart Categories screen.

| English | Notes |
|---|---|
| `Local AI is unavailable.` | Apple Intelligence not enabled |
| `This language is not supported by local AI.` | the typed search language has no Apple Intelligence support |
| `Local AI could not interpret this search.` | model failed |
| `Use 300 characters or fewer.` | input validation. `300` is a literal number, not a placeholder. |
| `Search supports visible content only, such as dogs on a beach. Dates, places, names, and text are not indexed.` | explains the limitation. Keep "dogs on a beach" as an example of visible content — translate the example, it is not a technical term. |
| `Some requested concepts were not found in this scan. Try a simpler content search.` | partial match |
| `Searching labels across all scanned categories.` | progress line |
| `Using label search across scanned photos.` | fallback path is running |
| `These words do not form a supported label search. Try visible content such as dog or beach. Label search does not support dates, names, or exclusions.` | no match at all |

"Label search" is the fallback that matches photo content labels rather than
running the model. It is not a term the user has to learn; keep it plain.

### 4. Swipe review reasons

One line on the swipe card explaining why an item is worth a look. These are
statements about the image, not instructions.

| English | Notes |
|---|---|
| `This photo may be out of focus.` | |
| `This photo has very low brightness.` | underexposed |
| `This photo has very high brightness.` | overexposed |
| `A lens smudge may have reduced image clarity.` | |
| `This photo received a low visual-quality score.` | an aesthetic score, not a technical defect |
| `Review whether you still need this screenshot.` | |
| `Review whether you still need this screen recording.` | |
| `This item uses %@; review whether you need it.` | `%@` is a file size. Keep the semicolon. |

The last four are phrased as a gentle prompt to decide, never as "delete this".

### 5. Appearance picker and widget

| English | Notes |
|---|---|
| `Light` | appearance option |
| `Dark` | appearance option |
| `Nothing to free on iPhone` | widget headline, success state |
| `Up to %@ to free on iPhone` | widget headline, `%@` is a size like "7.6 GB" |
| `Open TidyByte to refresh` | widget nudge, shown after a week |
| `Updated %lldd ago` | widget age, `%lld` is a number of days and `d` is the abbreviation. Render the `d` as your language's day abbreviation, or restructure so the number and unit read naturally. |

`Light` and `Dark` are UI options, not nouns about light. Use whatever iOS
itself calls these in your language's Display & Brightness settings.

### 6. Two empty-state fixes

| English | Notes |
|---|---|
| `No matching photos` | search returned nothing |
| `Submit a content search or try different words.` | body for the above |
| `No photos in this category.` | category is genuinely empty |
| `Choose albums or change your filters.` | chat-media tool, nothing matched |
| `No screen recordings were found.` | screen-recordings tool, nothing found |

`"No matching photos"` and `"No photos in this category."` are different states
on the same screen — one means "your filter excluded everything", the other
means "this category is empty". Keep them distinguishable.

## Right-to-left languages (ar, he)

Everything above applies. The permission messages explain what to do in
**Settings**, so use the exact word your language's iOS uses for the Settings
app. The em dashes become natural clause breaks in RTL typography; keep the
logical structure even if the dash itself is dropped.
