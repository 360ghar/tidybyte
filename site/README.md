# TidyByte marketing site

Static marketing site for the TidyByte iOS app. Plain HTML + Tailwind CSS, no JavaScript framework, no build server.

## Structure

```
site/
├── index.html        # Landing page
├── support.html      # Contact / support form (Netlify Forms)
├── privacy.html      # Privacy policy
├── changelog.html    # Release notes
├── 404.html          # Not-found page
├── netlify.toml      # Netlify build + headers + redirects
├── sitemap.xml       # Search engine sitemap
├── robots.txt        # Crawler rules
└── assets/
    ├── css/styles.css   # Compiled Tailwind (generated)
    ├── img/             # Screenshots, icons
    └── js/              # nav.js, blog.js
```

## Local development

```bash
npm install
npm run dev          # watch src/input.css → site/assets/css/styles.css
```

Open `site/index.html` directly, or serve it:

```bash
# Recommended — mirrors the Netlify pretty-URL redirects
python3 site/serve.py                # http://localhost:3000
python3 site/serve.py 8080           # custom port

# Alternatives
npx serve site                       # http://localhost:3000
python3 -m http.server -d site       # http://localhost:8000
```

The `serve.py` wrapper handles the `/support`, `/privacy`, and `/changelog`
rewrites from `netlify.toml`, so the site behaves the same locally as on Netlify.
Raw `python3 -m http.server` will 404 on those pretty URLs (the Netlify
redirects only run on Netlify's infrastructure).

## Production build

```bash
npm run build        # minified Tailwind → site/assets/css/styles.css
```

The `site/` folder is the deployable artifact.

## Deploy to Netlify

**Option A — connect the repo:** New site → Import from Git → pick this repo. `Publish directory = site`, `Build command = npm run build`, `Node version = 20`. Netlify deploys on every push to `main`.

**Option B — drag and drop:** `npm run build`, then drag the `site/` folder onto https://app.netlify.com/drop.

## Before going live

All placeholders are resolved. The site is configured for the domain `tidybyte.360ghar.com` and the contact email `contact@sakshammittal.com`. Deploy checklist: [`../DEPLOY_CHECKLIST.md`](../DEPLOY_CHECKLIST.md).

## License

MIT — see [../LICENSE](../LICENSE).
