# Translation batch 8 — 93 new keys

These keys reached the catalog when the last round of code-built `String`s was
converted to go through `L10n`. They are a mixed bag: cleanup-tool screens,
swipe-review messages, the celebration card, and the App Store share text.

Write each into `scripts/localization/translations/<lang>.json`. There are two
places to write, and putting a key in the wrong one fails the build:

- **`"strings"`** — 80 plain keys. Key is the exact English text.
- **`"plurals"`** — 13 counted keys. Key is the English **singular**, and the
  value is an object of CLDR plural categories.

Do not add, rename, or reorder keys.

## Non-negotiables

1. **Placeholders are load-bearing.** `%lld` is an integer, `%@` is a
   pre-formatted string (a file size like "1.5 GB", a count, or a system
   message). Each placeholder appears exactly once per form. If your
   translation moves a placeholder relative to another, use positional syntax
   (`%2$lld … %1$@`) — only one key in this batch has two placeholders, and only
   if you reorder them.
2. **Follow `_glossary.json`.** `keepLiteral`: TidyByte, iOS, iPhone, iPad,
   HEIC, Live Photo(s), MB, iCloud, Screen Time is *not* keep-literal (see the
   glossary's own `Screen Time` entry — use the name iOS shows in Settings).
   Use the glossary's per-language term for screenshot, duplicate, compress,
   Recently Deleted.
3. **The `—` em dash** stays where English has one, unless your language's
   typography wants a different break.
4. **Voice: calm, plain, second person.** Apple's register, not marketing.
5. **TidyByte never inflects** for case or gender.

## Part A — the 13 plural keys

Write these into `"plurals"`. Each value needs exactly the categories your
language requires (this is enforced by `check.mjs`):

| Language | Categories |
|---|---|
| hi, bn, ta, te, mr, gu, kn, ml, pa, es, fr, de, pt-BR, it | `one`, `other` |
| ja, ko, zh-Hans | `other` only |
| ru | `one`, `few`, `many`, `other` |
| ar | `zero`, `one`, `two`, `few`, `many`, `other` |
| he | `one`, `two`, `other` |

| English singular | English plural | Shown when |
|---|---|---|
| `cleared %lld photo` | `cleared %lld photos` | Smart Categories deletion finished |
| `cleared %lld blurry photo` | `cleared %lld blurry photos` | Blurry Photos deletion finished |
| `cleared %lld screenshot` | `cleared %lld screenshots` | Screenshot cleaner finished |
| `cleared %lld large file` | `cleared %lld large files` | Large Files finished |
| `cleared %lld burst frame` | `cleared %lld burst frames` | Burst frames cleared |
| `cleared %lld item (%@)` | `cleared %lld items (%@)` | Swipe session committed a deletion; `%@` is a total size |
| `removed %lld duplicate` | `removed %lld duplicates` | Duplicate finder finished |
| `removed %lld similar photo` | `removed %lld similar photos` | Similar photos finished |
| `compressed %lld photo` | `compressed %lld photos` | Photo compression finished |
| `compressed %lld video` | `compressed %lld videos` | Video compression finished |
| `cleaned %lld burst photo` | `cleaned %lld burst photos` | Burst auto-clean finished |
| `converted %lld Live Photo` | `converted %lld Live Photos` | Live Photo conversion finished |
| `reviewed %lld item` | `reviewed %lld items` | Swipe session ended with no deletions |

These all appear on the celebration card as the line describing what the user
just accomplished, and the same string is used as the share text. Keep them
short and in the past tense — the user reads it as a statement of what they did.

`Live Photo` / `Live Photos` stays as the glossary term in every language,
including its plural form.

## Part B — the 80 plain keys

### Swipe home — filter cards

Each card has a title and a one-line description of what the filter does.

| Title | Description |
|---|---|
| `Worst Shots` | `Review low-scoring photos, lowest first` |
| `Photos you haven't reviewed yet` | (this is a description; its title `Not Swiped Yet` is already translated) |
| `Every photo and video in your library` | (description for `All Media`) |
| `Review photos and videos taken on or before a date` | (description for `Photos Before a Date`) |
| `Photos not organized into your albums` | (description for `Not in Any User Album`) |
| `Specific Album` | `Review photos from a specific album` |

### Swipe session — messages and undo

| English | When |
|---|---|
| `Marked for deletion. Nothing is deleted until you confirm at the end.` | after a left swipe |
| `Delete is off until the photo loads.` | the asset is still downloading |
| `Pinch or double-tap a photo to inspect it` | first-run hint |
| `That photo can't be undone anymore.` | undo limit reached |
| `Undo your newer actions first to reach that photo.` | out-of-order undo |
| `Your library changed during analysis. Try Worst Shots again.` | library mutated mid-scan |
| `No photo is waiting to be filed. Dismiss and try again.` | album filing had nothing pending |
| `Still adding — please wait a moment and try again.` | double-tap guard |
| `Couldn't save your changes. Please try again.` | SwiftData write failed |

### Session completion — result rows

Short labels on the summary rows after a swipe session.

| English | Notes |
|---|---|
| `Added to albums` | |
| `Moved to Recently Deleted` | use the glossary term for Recently Deleted |
| `Kept` | |
| `Skipped` | |
| `Deleted` | |

### Burst cleaner — keeper reasons

The star on the kept frame, plus a one-line reason. These are short labels next
to a photo, so keep them terse.

| English | Notes |
|---|---|
| `Kept: your choice` | the user picked it |
| `Kept: your pick in Photos` | the user picked it in the Photos app |
| `Kept: iPhone's pick` | the camera decided |
| `Kept: favorite` | it is favorited |
| `Kept: highest resolution` | the largest of the burst |
| `Kept: last frame` | the newest of the burst |
| `Kept: auto pick` | automatic fallback |
| ` Favorites are kept.` | **leading space is intentional** — appended to a preceding sentence. Keep a leading space. |
| `This keeps the starred frame of each burst and deletes the rest.` | auto-clean explanation |

### Burst cleaner — result

| English | Notes |
|---|---|
| `1 burst cleaned down to a single photo.` | singular, no placeholder |
| `%lld bursts cleaned down to single photos.` | plural, `%lld` is the count. Not a plural-variation key — write it as one form. |

### Errors

`LocalizedError` descriptions shown in error banners.

| English | Notes |
|---|---|
| `Album not found.` | |
| `Failed to create album.` | |
| `Couldn't modify the album. Please try again.` | |
| `Nothing was deleted.` | |
| `Live Photo not found.` | |
| `Could not find still image in Live Photo.` | |
| `Invalid image data.` | |
| `Timed out loading the photo (it may still be in iCloud). Please try again.` | |
| `The compressed copy is missing from your library.` | |
| `The converted still is missing from your library.` | |
| `Copies kept. Both versions are in your library; delete either one in Photos.` | |
| `Deleted %lld of %lld items. %lld couldn't be deleted. Try again.` | **three placeholders.** If you reorder any of them, use positional syntax. |
| `Your library changed. Scan again before searching.` | |
| `Removed changed or unavailable photos. Scan again to include new or edited photos.` | |

### Storage dashboard and permission screen

| English | Notes |
|---|---|
| `Recently Deleted` | use the glossary term |
| `Space comes back when it is emptied. In Photos, open Albums, then Recently Deleted.` | |
| `Manage Apps & System Storage` | |
| `Open Settings ▸ General ▸ iPhone Storage` | keep the `▸` (U+25B8) |
| `Library figures below cover only the photos you selected; device totals cover the whole device.` | limited-library banner |
| `Find exact and near-duplicate photos` | capability bullet |
| `Spot blurry, dark, and overexposed shots` | capability bullet |
| `Surface the biggest files taking up space` | capability bullet |
| `Delete only what you review and approve` | capability bullet |

### Activity and savings

| English | Notes |
|---|---|
| `items, all time` | stat pill label |
| `this month` | stat pill label |
| `Size unknown` | |
| `Size unavailable` | shown when a file's size cannot be read |
| `cleaned up since you started using TidyByte` | caption under the total |
| `Nothing measurable yet. Items stored only in iCloud don't report a size.` | empty state |

### Rate prompt and feedback

| English | Notes |
|---|---|
| `Enjoying TidyByte?` | prompt title |
| `Thanks for the support` | after rating |
| `What should we fix?` | feedback step title |
| `Tell us what got in the way.` | feedback step body |
| `Send Feedback` | button |
| `Yes` | button |
| `Not really` | button. The gentle decline, not a blunt "No". |
| `Not now` | button |
| `Your rating helps other people find TidyByte.` | rationale line |
| `You just %@.` | `%@` is a stat line like "removed 24 duplicates" |
| `The message couldn't be sent. Try again, or email us at %@.` | `%@` is an email address, kept verbatim |
| `No mail account is set up on this device. Email us at %@.` | same |

### Share text

The user posts this to social media, so it must read naturally in your language
— it is public-facing copy, not UI chrome.

| English | Notes |
|---|---|
| `I just %@` | `%@` is a stat line. Reads as "I just removed 24 duplicates". |
| `I'm cleaning up my photo library` | used when there is no stat line |
| `%@ with TidyByte — a private, on-device photo cleanup app. %@` | first `%@` is the deed above, second is the App Store URL. Keep the URL verbatim and keep the em dash. |

### Misc

| English | Notes |
|---|---|
| `Min size: %@` | large-file threshold label; `%@` is a size |
| `Swipe history cleared` | toast |
| `iOS will ask you to confirm. Deleted items go to Recently Deleted in Photos, where you can restore them for 30 days.` | confirmation explanation. `iOS` stays `iOS`. |

## Right-to-left languages (ar, he)

Everything above applies. The burst keeper reasons (`Kept: …`) are labels beside
a photo — keep them short. The share text must read naturally in RTL social
feeds; the URL stays a URL.
