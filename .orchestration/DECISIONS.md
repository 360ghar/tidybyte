# TidyByte site — canonical decisions (Phase 0 contract)

Every agent MUST follow this file. It exists so parallel work converges instead of diverging.
Ownership: no agent edits `site/index.html`, `src/input.css`, or `tailwind.config.js`.

## 1. Design tokens (already in `src/input.css` — use, don't redefine)

Theme-flipping: `bg-canvas` `bg-surface-soft` `bg-surface-card` `bg-surface-dark` `border-hairline` `border-hairline-strong` `text-ink` `text-body` `text-muted` `text-muted-soft` `bg-primary` `text-on-primary` `text-success` `text-destructive`.
Fixed palette: `clay-pink` `clay-rose` `clay-teal` `clay-lav` `clay-peach` `clay-ochre` `clay-mint` `clay-cream` and on-colour text tokens `text-clay-pink-ink` `text-clay-pink-soft` `text-clay-lav-ink` `text-clay-lav-soft` `text-clay-peach-ink` `text-clay-peach-soft` `text-clay-ochre-ink` `text-clay-ochre-soft` `text-clay-rose-ink` `text-clay-rose-soft` `text-clay-mint-ink` `text-clay-mint-soft`.
App category dots: `bg-brand-photo` `bg-brand-video` `bg-brand-screenshot` `bg-brand-live` `bg-brand-other`.

Component classes: `container-prose` `clay-card` `btn-primary` `btn-ghost` `btn-on-color` `badge` `eyebrow` `eyebrow-on-dark` `h-display` `h-section` `h-section-on-dark` `section` `section-tight` `lede` `muted` `link` `nav-link` `faq-summary`.

Rules:
- `glass-card` is retired. Use `clay-card`.
- Never use raw `zinc-*`, `white/NN` outside saturated cards, or arbitrary hex text colours. On saturated tiles use the `clay-*-ink` / `clay-*-soft` tokens.
- Success/green is `text-success`; red is `text-destructive`. No `[#1f7a4d]`-style hexes.

## 2. Canonical icons

One source of truth. Copy these exact SVGs. All stroke icons: `viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"`. Sizes: 12 (status dot) · 16 (inline) · 18 (menu/accordion) · 20 (nav) · 22 (feature tile).

**chevron-down (the ONLY accordion affordance, rotates 180 on open):**
```html
<svg aria-hidden="true" focusable="false" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" class="faq-chev"><path d="m6 9 6 6 6-6"/></svg>
```
**check (inline yes, 16):** `<path d="M5 12l5 5 9-11"/>`
**github (fill, 20):** `viewBox="0 0 24 24" fill="currentColor"` path `M12 .5C5.73.5.74 5.49.74 11.76c0 4.96 3.22 9.16 7.68 10.65.56.1.77-.24.77-.55v-1.93c-3.12.68-3.78-1.5-3.78-1.5-.51-1.3-1.25-1.65-1.25-1.65-1.02-.7.08-.69.08-.69 1.13.08 1.72 1.16 1.72 1.16 1 1.72 2.63 1.22 3.27.93.1-.73.39-1.23.71-1.51-2.49-.28-5.12-1.25-5.12-5.55 0-1.23.44-2.23 1.16-3.02-.12-.28-.5-1.43.11-2.98 0 0 .95-.3 3.1 1.15.9-.25 1.86-.38 2.82-.39.96.01 1.92.14 2.82.39 2.15-1.45 3.1-1.15 3.1-1.15.61 1.55.23 2.7.11 2.98.72.79 1.16 1.79 1.16 3.02 0 4.31-2.64 5.27-5.15 5.54.4.34.76 1.02.76 2.06v3.05c0 .31.2.66.78.55 4.46-1.49 7.67-5.69 7.67-10.65C23.26 5.49 18.27.5 12 .5Z`
**apple (fill, 16):** `M16.365 1.43c0 1.14-.46 2.23-1.21 3.05-.81.87-2.14 1.55-3.23 1.46-.14-1.1.4-2.25 1.16-3.04.85-.89 2.29-1.55 3.28-1.47Zm3.61 16.04c-.6 1.39-1.31 2.62-2.18 3.66-1.13 1.39-2.46 3.05-4.25 3.07-1.7.02-2.14-.99-4.46-.99-2.32 0-2.8 1.01-4.5.99-1.79-.02-3.15-1.6-4.28-2.99-2.6-3.2-4.59-9.05-1.92-12.99 1.32-1.95 3.69-3.18 6.25-3.22 1.78-.04 3.46 1.05 4.55 1.05 1.08 0 3.13-1.3 5.28-1.11.9.04 3.43.36 5.05 2.71-.13.08-3.02 1.76-2.99 5.25.04 4.17 3.66 5.55 3.45 5.57Z`
**sun (18, toggle) / moon (18) / monitor (18, menu "System") / menu (20):** keep current paths, normalise to the attribute block above.
Theme-toggle button shows sun with `class="block dark:hidden"`, moon with `class="hidden dark:block"`.

## 3. Copy rules

- **Casing:** sentence case everywhere (headings, buttons, labels). Proper nouns keep caps.
- **App Store CTA label:** exactly `Download TidyByte Free` on every page. Header short form: `Get the app`.
- **Text logo (every page, including blog):** `<a href="/" class="font-display text-lg font-semibold tracking-tight text-ink">TidyByte<span aria-hidden="true" class="text-clay-pink">.</span></a>` — Fredoka, pink dot, no exceptions.
- **Dates:** `<time datetime="YYYY-MM-DD">Month D, YYYY</time>` + `· N min read`. N comes from `.orchestration/posts-raw.json` (`read_min`), never hand-written.
- **Claims — mandatory rewrites:**
  | Do not write | Write instead |
  |---|---|
  | Audited by anyone. Trusted by you. | Read every line that touches your photos. |
  | no network calls of any kind | no analytics SDK, no backend, no tracking |
  | clear in one tap (destructive flows) | clear them in one pass |
  | Made with care. Runs entirely on your device. | No account. No analytics. Nothing to cancel. |
  | Trusted by you / trusted by teams | (delete — no rating exists to cite) |
  | 100% on-device (4th+ repetition on one page) | keep it once per page, cut repeats |
- Em dash: use `&mdash;`. Apostrophes: `&rsquo;`. Number ranges: en dash `&ndash;`.
- Provable claims only. No invented ratings, user counts, or third-party audits.

## 4. Image markup

```html
<figure class="mt-8">
  <picture>
    <source srcset="/assets/img/blog/SLUG.avif" type="image/avif">
    <img src="/assets/img/blog/SLUG.webp" alt="ALT describing the illustration" width="1400" height="933" loading="lazy" decoding="async" class="block h-auto w-full rounded-2xl border border-hairline">
  </picture>
  <figcaption class="muted mt-2 text-center text-xs">CAPTION</figcaption>
</figure>
```
Alt text must describe the scene, not say "illustration". Hero image of a post uses `loading="eager" fetchpriority="high"` and sits directly under the header; inline images use `loading="lazy"`.

## 5. Post template skeleton

See `.orchestration/POST_TEMPLATE.html` — the single template for all 45 posts. Agents fill placeholders and keep the post's existing body content (headings, tables, lists, FAQ text) intact unless a claim rewrite applies.

## 6. Self-verification required from every agent (report format)

1. `grep` proof that banned patterns are gone from files you own (`glass-card`, `bg-night`, `zinc-`, `[#`-hexes, `!text-`, `hover:text-white`).
2. List of files changed with a one-line summary each.
3. Anything you could not finish, as an explicit `DEFERRED:` list — never silently skipped.
4. Report format: `## Result` / `## Files changed` / `## Self-checks` / `## Deferred` / `## Notes for orchestrator`.
