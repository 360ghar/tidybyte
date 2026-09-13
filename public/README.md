Astro marketing site for the TidyByte iOS app. Astro renders `src/` to
static HTML in `dist/`; Tailwind CSS for styling; no client-side framework.

## Structure

```
src/
├── pages/            # Astro routes: index, support, privacy, changelog,
│                     # 404, blog/index, blog/[slug], llms.txt, llms-full.txt
├── content/pages/    # Page bodies as HTML: index, support, privacy,
│                     # changelog, 404 + one blog-<slug>.html per post
├── layouts/build-page.ts  # Shared page shell (head, header, footer)
├── chrome/           # header.html + footer.html partials
├── data/pages.ts     # Page/post metadata (titles, descriptions, dates)
├── lib/llms.ts       # llms.txt content builders
└── input.css         # Tailwind source (design tokens live here)
public/
├── assets/           # css/, js/, img/, fonts/ — copied to dist/ as-is
└── serve.py          # Local server for the built site (serves dist/)
dist/                 # Build output (never committed)
```

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

The `serve.py` wrapper handles the `/support`, `/privacy`, and `/changelog`
rewrites from `netlify.toml`, so the site behaves the same locally as on Netlify.
Raw `python3 -m http.server` will 404 on those pretty URLs (the Netlify
redirects only run on Netlify's infrastructure).

## Production build

```bash
npm run build        # astro build → dist/; minified Tailwind →
                     # dist/assets/css/styles.css; hash-assets.mjs fingerprints CSS/JS
npm run check        # verify asset references resolve in dist/ (build first)
```

The `dist/` folder is the deployable artifact (never committed).

## Deploy to Netlify

**Option A — connect the repo:** New site → Import from Git → pick this repo. `Publish directory = dist`, `Build command = npm run build`, `Node version = 22`. Netlify deploys on every push to `main`.

**Option B — drag and drop:** `npm run build`, then drag the `dist/` folder onto https://app.netlify.com/drop.

## Before going live

All placeholders are resolved. The site is configured for the domain `tidybyte.360ghar.com` and the contact email `contact@sakshammittal.com`. Deploy checklist: [`../DEPLOY_CHECKLIST.md`](../DEPLOY_CHECKLIST.md).

## License

MIT — see [../LICENSE](../LICENSE).
