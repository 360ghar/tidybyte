# Deploy Checklist

Pre-launch checklist for the TidyByte marketing site. Run through end-to-end the first time you point a real domain at the site. The site is configured for `tidybyte.360ghar.com`.

## 1. Domain placeholder — done

`TODO_REPLACE_DOMAIN` has been replaced with `tidybyte.360ghar.com` across all HTML, `sitemap.xml`, and `robots.txt`. The contact email is hardcoded to `contact@sakshammittal.com`.

Verify nothing was missed:

```bash
grep -r 'TODO_REPLACE_DOMAIN' site/ docs/ || echo "all replaced"
```

## 2. Replace the App Store link

In `site/index.html` (hero CTA + footer CTA) there are comments like:

```html
<!-- TODO: replace with real App Store URL when published -->
<a href="#" ...>Download on the App Store</a>
```

Update the `href` on the next link from `#` to:

```
https://apps.apple.com/app/idYOUR_APP_ID
```

(Use the numeric App ID from App Store Connect, not the slug.)

## 3. Verify URLs match App Store Connect

The site exposes `/`, `/support`, `/privacy`. The same three URLs (plus the privacy-policy URL specifically) must be configured as the app's support and marketing URLs in App Store Connect. See [`docs/APP_STORE_LISTING.md`](docs/APP_STORE_LISTING.md) §6 for the field-by-field mapping.

## 4. Build and preview locally

```bash
npm install
npm run build
python3 site/serve.py
```

Open http://localhost:3000 and click through every page, every link, the support form, and the App Store CTA. Confirm:

- Hero CTA points at the live App Store URL
- Support form actually submits (Netlify Forms detection only works on a deploy, not locally — that's expected)
- Footer links resolve
- Mobile layout at 375px width is clean

## 5. Deploy to Netlify

Pick one:

**Option A — connect the GitHub repo (recommended for ongoing work):**
- New site → Import from Git → pick this repo
- `Publish directory = site`
- `Build command = npm run build`
- `Node version = 20`
- Netlify will deploy on every push to `main` and post a preview URL for every PR

**Option B — drag-and-drop:**
- `npm run build`
- Drag the `site/` folder onto https://app.netlify.com/drop
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

