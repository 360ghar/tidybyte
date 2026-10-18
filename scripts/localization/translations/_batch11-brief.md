# Translation batch 11 — landing page title and description

Two strings per language. They are the `<title>` and `<meta name="description">`
of the localized landing page — what a search engine shows. The page body is
already translated; these are the last English text on it.

Source: `scripts/localization/site/site-meta.json`

```json
"title":       "TidyByte &mdash; iPhone Storage Cleaner &amp; Photo Cleaner App"
"description": "TidyByte is a free iPhone storage cleaner and photo cleaner: swipe to delete junk, remove duplicates and screenshots, and compress videos. 100% on-device."
```

Write `scripts/localization/site/site-translations/<slug>.json.meta` — no, use
`<slug>.meta.json`, shaped exactly:

```json
{ "title": "…", "description": "…" }
```

The slug is the site's own, which is lowercase and sometimes hyphenated:
`de`, `ja`, `zh-Hans` is written `zh-hans`, `pt-BR` is written `pt-br`. Match the
existing filenames in `scripts/localization/site/site-translations/`.

## Hard limits — the SEO audit fails the build

| field | range | why |
|---|---|---|
| title | **≤ 65 characters** | longer is truncated in search results |
| description | **110–165 characters** | shorter wastes the snippet, longer is cut |

Count characters, not bytes and not words. These are enforced by
`scripts/seo-audit.mjs`; a value outside the range fails `npm run check`.

The limits are tight on purpose. **Cut meaning before you break a limit** — drop
the least important clause, not the most searched term. For the description, the
load-bearing parts are: it is free, it cleans photos/storage, and it is
on-device. Those three should survive in every language.

## Rules

1. **Keep `&mdash;` and `&amp;` as entities.** Both strings are injected into
   HTML, so a bare `&` would produce invalid markup. Use `&mdash;` for the dash
   between the app name and the tagline, and `&amp;` if your title needs an
   ampersand. Do not use a literal `—` or `&`.
2. **`TidyByte` stays as-is** at the start of the title, followed by the
   separator. It is the product name and the thing people search for.
3. **Do not translate** `TidyByte`, `iPhone`, `iPad`, `iOS`, `App Store`,
   `Live Photo`, `SHA-256`, `WhatsApp`, `Telegram`, `Vision`, `Photos`.
4. **Write for search, not for the brand.** The title is a search result: put the
   words a person would type to find this app. "Photo Cleaner" and "Storage
   Cleaner" are the two intents; if both do not fit, keep the one your market
   searches for more.
5. **The description is one sentence-ish.** Keep it a single flowing line — no
   line breaks, no bullet points, no trailing period required if your language
   does not use one.
6. **`100% on-device`** means all processing happens on the phone. Keep that
   claim accurate: no "cloud", no "online".
7. **Do not reuse the language endonym.** The current placeholder appends
   `(Deutsch)`, `(日本語)` and so on. Replace it entirely — the translation
   itself is what makes the page the right language now.

## Right-to-left (ar, he)

Everything above applies. Keep the `&mdash;` separator; it reads correctly in
both directions.
