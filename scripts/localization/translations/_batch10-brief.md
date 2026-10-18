# Translation batch 10 — App Store listing + website landing page

Two deliverables per language. They are different kinds of writing and should
not share sentences: the App Store listing is read by someone deciding whether
to install, the landing page is read by someone already on the site.

---

## Deliverable A — App Store listing

File: `docs/appstore/listings.json`

Add or replace the entry for your language code, keeping the shape of `en`:

```json
"<code>": {
  "name": "TidyByte",
  "subtitle": "...",
  "promotionalText": "...",
  "description": "...",
  "keywords": "...",
  "whatsNew": "..."
}
```

### Character limits (hard — `check-listings.mjs` fails the build)

| field | limit |
|---|---|
| name | 30 |
| subtitle | 30 |
| promotionalText | 170 |
| description | 4000 |
| keywords | 100 |
| whatsNew | 4000 |

Count characters, not words. The subtitle is the tightest and the most
important: it is what appears under the app name in search results.

### Field-by-field

- **name** — stays `TidyByte` in every language. It is the product name.
- **subtitle** — translate the sense of `Photo cleaner, free space`. It must fit
  30 characters, so it will often need to be shorter than the English. Do not
  pad it. Do not repeat the word "TidyByte".
- **promotionalText** — the short pitch above the description. This is the one
  field you can change without a new build, so write it as current, active
  marketing copy.
- **description** — the full listing. Translate the whole thing, including the
  `Features:` bullet list and the closing line. Keep the blank lines between
  paragraphs and keep the `•` bullets.
- **keywords** — **not a translation.** This is the App Store search index, a
  comma-separated list with no spaces after the commas. Write the terms a
  speaker of your language would actually type into App Store search to find a
  photo-cleanup app: the local words for storage, duplicate, screenshot,
  cleanup, compress, and so on. Do not transliterate the English list. Do not
  repeat a word that already appears in your `name` or `subtitle` — Apple
  indexes those fields too, so a repeat wastes a slot. Stay within 100
  characters including commas.
- **whatsNew** — the release notes for 1.0.5. Translate the sense; keep
  `on-device`/`on-device AI` accurate (it means the processing happens on the
  phone, not in the cloud).

**Do not translate:** `TidyByte`, `iPhone`, `iPad`, `iOS`, `App Store`, `Live
Photo`, `Live Photos`, `SHA-256`, `WhatsApp`, `Telegram`, `Vision`, `Photos`
(Apple's framework).

---

## Deliverable B — website landing page

File: `scripts/localization/site/site-translations/<lang>.json`

Read `scripts/localization/site/site-strings.json`. It has a `strings` array of
108 English strings taken from `src/content/pages/index.html` — the hero, the
feature sections, the privacy section, the FAQ, the footer.

Produce a JSON object mapping **each English string exactly as written** to its
translation:

```json
{
  "The best free iPhone storage cleaner and photo cleaner.": "…",
  "Swipe left to delete, swipe right to keep — and reclaim gigabytes in minutes. …": "…"
}
```

Every key must appear, copied byte-for-byte from `site-strings.json`. A key that
does not match exactly is a string that silently stays English on the live site.

### Rules

1. **Keep HTML entities as entities.** Several strings contain `&mdash;`,
   `&middot;`, `&amp;`, `&rarr;`, `&rsquo;`. These are inserted into HTML
   verbatim, so a literal `—` would work but `&mdash;` is what the file uses.
   Keep whichever your language's typography calls for, but do not leave a
   broken entity such as a bare `&`.
2. **Numbered headings keep their number.** `01 &mdash; How it works` → keep
   `01` and the separator, translate the rest. Same for `02` … `07`.
3. **Attributes are alt text and titles.** Strings that read like descriptions
   of a screenshot (`Clay-style illustration of a phone tossing photo cards into
   a sorting tray on green hills.`) are `alt` text for a screen reader. Translate
   them as descriptions of the image, not as marketing copy.
4. **Match the register of the English.** The page is confident and plain: short
   sentences, no corporate filler, no exclamation marks. Do not make it more
   formal or more salesy than the source.
5. **`64 GB`** stays `64 GB`. Unit symbols are not translated.
6. **Keep it short where the English is short.** These strings sit in buttons,
   badges and headings with fixed layout. A translation 40% longer than the
   English will break the button.
7. **Do not translate:** `TidyByte`, `iPhone`, `iPad`, `iOS 17+`, `App Store`,
   `GitHub`, `Vision`, `Photos`, `SHA-256`, `WhatsApp`, `Telegram`, `1.0.5`.
   These were already filtered out of `site-strings.json` — if you see one,
   leave it as-is.

---

## Right-to-left languages (ar, he)

Everything above applies. The site mirrors the whole layout for RTL, so keep
punctuation and any trailing arrows sensible in a right-to-left reading order.

---

## Before you finish

Verify by reading your files back from disk:

- `listings.json` parses; your language key exists; all six fields present and
  non-empty; each field within its limit.
- `site-translations/<lang>.json` parses; it has exactly 108 keys; every key is
  byte-identical to one in `site-strings.json`; no key is missing and none is
  extra; no value is empty or left as the English source.
