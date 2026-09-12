# Deploy Checklist

Pre-launch checklist for the TidyByte marketing site. Run through end-to-end the first time you point a real domain at the site. The site is configured for `tidybyte.360ghar.com`.

## 0. Site architecture (Astro)

The site is a zero-runtime-JS Astro static build. Output is byte-compatible with the pre-Astro generated site — proven during the migration by `scripts/verify-parity.mjs` full mode (51 pages + CSS/JS byte-identical, 36 screenshot pairs pixel-identical). Ongoing CI guard: `npm run check`.

- `src/pages/` — routes (`index`, `404`, `privacy`, `support`, `changelog`, `blog/index`, `blog/[slug]`). Each renders an assembled document string.
- `src/layouts/build-page.ts` — the page assembler: `<head>` template, header/footer chrome, byte-compatible with the original generator.
- `src/content/pages/*.html` — verbatim page body content (the file you edit to change page copy).
- `src/chrome/{header,footer}.html` — single-source header/footer shared by all pages.
- `src/data/pages.ts` — per-page `<head>` metadata + JSON-LD (add an entry + a content file when publishing a new post).
- `public/` — static assets served as-is (images, fonts, the four JS files, robots/sitemap/llms).
- Build order: `astro build` renders `dist/` → Tailwind CLI writes `dist/assets/css/styles.css` → `hash-assets.mjs` fingerprints CSS/JS and rewrites references.
- Editing page copy: change `src/content/pages/<page>.html`, run `npm run dev` (or `build && preview`).

## 1. Domain placeholder — done

`TODO_REPLACE_DOMAIN` has been replaced with `tidybyte.360ghar.com` across all HTML, `sitemap.xml`, and `robots.txt`. The contact email is hardcoded to `contact@sakshammittal.com`.

Verify nothing was missed:

```bash
grep -r 'TODO_REPLACE_DOMAIN' src/ public/ docs/ || echo "all replaced"
```

## 2. Replace the App Store link

In `src/content/pages/index.html` (hero CTA + footer CTA) there are comments like:

```html
<!-- TODO: replace with real App Store URL when published -->
<a href="#" ...>Download on the App Store</a>
```

Update the `href` on the next link from `#` to:

```
https://apps.apple.com/in/app/tidybyte/id6775769763
```

## 3. Verify URLs match App Store Connect

The site exposes `/`, `/support`, `/privacy`. The same three URLs (plus the privacy-policy URL specifically) must be configured as the app's support and marketing URLs in App Store Connect. See [`docs/APP_STORE_LISTING.md`](docs/APP_STORE_LISTING.md) §6 for the field-by-field mapping.

## 4. Build and preview locally

```bash
npm install
npm run build
npm run preview
```

Open http://localhost:4321 and click through every page, every link, the support form, and the App Store CTA. Confirm:

- Hero CTA points at the live App Store URL
- Support form actually submits (Netlify Forms detection only works on a deploy, not locally — that's expected)
- Footer links resolve
- Mobile layout at 375px width is clean

## 5. Deploy to Netlify

Pick one:

**Option A — connect the GitHub repo (recommended for ongoing work):**
- New site → Import from Git → pick this repo
- `Publish directory = dist` (set in the root `netlify.toml`)
- `Build command = npm run build` (astro build + Tailwind + asset hashing)
- `Node version = 20`
- Netlify will deploy on every push to `main` and post a preview URL for every PR

**Option B — drag-and-drop:**
- `npm run build`
- Drag the `dist/` folder onto https://app.netlify.com/drop
- Netlify gives you a temporary `*.netlify.app` URL

## 6. Set the custom domain

In the Netlify dashboard:

- **Domain settings → Add domain alias →** enter `tidybyte.360ghar.com`
- Follow the DNS instructions Netlify shows (CNAME for the subdomain, or Netlify DNS for the apex)
- Netlify auto-provisions a Let's Encrypt TLS certificate within a few minutes

## 7. Sanity-check after deploy

Tick each:

- [ ] `https://tidybyte.360ghar.com/` loads
- [ ] `https://tidybyte.360ghar.com/support` loads
- [ ] `https://tidybyte.360ghar.com/privacy` loads
- [ ] `https://tidybyte.360ghar.com/changelog` loads
- [ ] `https://tidybyte.360ghar.com/sitemap.xml` loads
- [ ] `https://tidybyte.360ghar.com/robots.txt` loads
- [ ] Support form actually submits to Netlify Forms — check the **Forms** tab in the Netlify dashboard, submit a test message, confirm it appears
- [ ] Lighthouse (Chrome DevTools → Lighthouse) on `/`: Performance ≥ 95, Accessibility ≥ 95, SEO ≥ 95, Best Practices ≥ 95
- [ ] Open `/` on a real iPhone in Safari — hero and screenshots look right
- [ ] Test from a private/incognito window — no stale CDN cache

## 8. (One-time) submit sitemap to search engines

- Google Search Console → Sitemaps → submit `https://tidybyte.360ghar.com/sitemap.xml`
- Bing Webmaster Tools → Sitemaps → submit the same

