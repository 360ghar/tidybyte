Astro marketing site for the TidyByte iOS app. Astro renders `src/` to
static HTML in `dist/`; Tailwind CSS for styling; no client-side framework.

## Structure

```
src/
├── pages/            # Astro routes: index, support, privacy, changelog,
│                     # 404, [page] (tool landing pages), [page].md
│                     # (Markdown for the tools + core pages),
│                     # blog/index, blog/[slug], blog/[slug].md,
│                     # llms.txt, llms-full.txt
├── content/pages/    # Page bodies as HTML: index, support, privacy,
│                     # changelog, 404, tool-<slug>.html per tool page,
│                     # + one blog-<slug>.html per post
├── layouts/build-page.ts  # Shared page shell (head, header, footer, JSON-LD)
├── chrome/           # header.html + footer.html partials
├── data/pages.ts     # Page/post metadata (titles, descriptions, dates)
├── data/tools.ts     # Tool landing pages: copy, comparison tables, FAQs
├── data/page-meta.ts # The PageMeta shape shared by both data files
├── lib/llms.ts       # llms.txt content builders
├── lib/tool-page.ts  # Renders a tool page's <main> from data/tools.ts
└── input.css         # Tailwind source (design tokens live here)
public/
├── assets/           # css/, js/, img/, fonts/ — copied to dist/ as-is
└── serve.py          # Local server for the built site (serves dist/)
dist/                 # Build output (never committed)
```

## Tool landing pages (SEO / GEO / AEO)

Each cleanup tool has its own landing page at a top-level URL
(`/storage-cleaner`, `/video-compression`, `/image-compression`, ...) so
commercial search intent has a page to land on, instead of the home page
competing with itself for every query. `/photo-cleaner` is the hub.

All of it is data-driven. `src/data/tools.ts` holds the copy, the comparison
table, and the FAQ list for each tool; `src/lib/tool-page.ts` renders the
hero, quick-answer box, table, trust strip, FAQ, tool grid and CTA; and
`src/pages/[page].astro` + `[page].md.ts` generate the routes. Authored prose
lives in `src/content/pages/tool-<slug>.html`.

The FAQ text lives in `tools.ts` rather than in the content file because the
same strings are emitted twice — once as visible `<details>` markup and once
inside the `FAQPage` JSON-LD — and Google requires the two to match. Adding a
tool page means adding one entry to `TOOLS` and one prose file; `llms.txt`,
the Markdown alternate, the OG card and the sitemap all follow. The sitemap's
priority list is the one thing that cannot follow automatically — the Astro
config cannot import `tools.ts` — so `seo-audit.mjs` fails if a tool page is
listed at the wrong priority.

Tool pages reference the app entity defined on the home page (`#app`, `#website`,
`#org`) rather than restating it, so answer engines resolve one product rather
than sixteen competing descriptions. Nothing on the site declares an
`aggregateRating` or `Review`: those require genuine visible reviews, and
inventing them is a policy violation.

For the off-site half of the strategy (listings, community, measurement), see
[`docs/GEO-Playbook.md`](../docs/GEO-Playbook.md).

## Theming (light / dark / system)

**Light is the default for every visitor.** The header toggle offers Light,
Dark, and System; Dark is remembered in `localStorage` under
`tidybyte-theme`, and System is an explicit opt-in that follows the OS.

- `assets/js/theme.js` — loaded **synchronously in `<head>`** (CSP forbids
  inline scripts). Applies the `dark` class to `<html>` before first paint
  so there is no flash, and keeps `<meta name="theme-color">` in sync
  (`#fffaf0` light / `#121212` dark).
- `assets/js/site.js` — deferred. Wires the toggle popover and the
  `data-reveal` scroll animations (honors `prefers-reduced-motion`).
- Tokens live in `src/input.css` as CSS variables (`:root` = light,
  `.dark` = dark). `tailwind.config.js` binds Tailwind colors to them
  (`bg-canvas`, `text-ink`, `text-body`, `text-muted`, `border-hairline`,
  `bg-surface-card`, ...), so utilities flip automatically — no per-element
  `dark:` variants.
- The dark theme is a near-black neutral grey (`canvas #121212`,
  cards `#1e1e1e`); only the saturated `clay-*` brand cards keep their
  fixed hues in both themes.
- `primary` / `on-primary` flip too: near-black button with white text in
  light, cream button with dark text in dark. Use them (not `text-white`)
  on primary surfaces — skip links and the changelog dots already do.
- `success` / `destructive` flip as well (green/red verdict text in
  comparison tables) — never hardcode those hexes.
- Text on saturated `clay-*` cards uses the on-colour tokens
  (`text-clay-pink-ink`, `text-clay-peach-soft`, ...) instead of white or
  `text-ink`.
- `data-reveal` scroll animations only hide content under `html.js`
  (class set by `theme.js`), so a script failure can never blank a page.
- Display face: Fredoka variable font, self-hosted in `assets/fonts/`
  (licensed under the SIL Open Font License, `assets/fonts/OFL.txt`).

When adding a page: include `theme.js` before the stylesheet, `site.js`
after `nav.js`, keep exactly one `theme-color` meta, and use the semantic
tokens above instead of raw `zinc`/`white` utilities.

## Local development

```bash
npm install
npm run dev          # astro dev + watch src/input.css → public/assets/css/styles.css
```

Astro serves the site at http://localhost:4321. To preview the production
build instead:

```bash
npm run build
python3 public/serve.py                # http://localhost:3000, serves dist/
python3 public/serve.py 8080           # custom port
```

The `serve.py` wrapper handles the `/support`, `/privacy`, `/changelog` and
tool-page rewrites from `netlify.toml`, so the site behaves the same locally as
on Netlify. Raw `python3 -m http.server` will 404 on those pretty URLs (the
Netlify redirects only run on Netlify's infrastructure).

## Production build

```bash
npm run build        # astro build → dist/; minified Tailwind →
                     # dist/assets/css/styles.css; hash-assets.mjs fingerprints CSS/JS
npm run check        # hash-assets --check + seo-audit + og-card check (build first)
npm run og           # regenerate the 1200x630 OG cards after changing page titles
```

`npm run check` runs three validators against `dist/`:

- **`hash-assets.mjs --check`** — every fingerprinted CSS/JS reference resolves.
- **`seo-audit.mjs`** — per page: exactly one `<h1>`, unique title and
  description within length limits, `canonical == og:url`, every JSON-LD block
  parses, every `FAQPage` question also appears as visible text, a
  `BreadcrumbList` exists, the `Speakable` selector actually matches a
  rendered `[data-quick-answer]` element, all internal links and images
  resolve, and the sitemap lists every page at the right priority. Every
  sitemap URL must also resolve to a generated `.md` alternate, because
  `llms.txt` promises one.
- **`og-cards.mjs --check`** — every tool page's `og:image` was actually built.

The `og` script renders cards with Playwright (Chromium), reading titles from
the built HTML so a card can never advertise a title the page no longer uses.

The `dist/` folder is the deployable artifact (never committed).

## Deploy to Netlify

**Option A — connect the repo:** New site → Import from Git → pick this repo. `Publish directory = dist`, `Build command = npm run build`, `Node version = 22`. Netlify deploys on every push to `main`.

**Option B — drag and drop:** `npm run build`, then drag the `dist/` folder onto https://app.netlify.com/drop.

## Before going live

All placeholders are resolved. The site is configured for the domain `tidybyte.360ghar.com` and the contact email `contact@sakshammittal.com`. Deploy checklist: [`../DEPLOY_CHECKLIST.md`](../DEPLOY_CHECKLIST.md).

## License

MIT — see [../LICENSE](../LICENSE).
