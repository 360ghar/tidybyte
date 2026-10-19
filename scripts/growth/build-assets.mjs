#!/usr/bin/env node
/**
 * build-assets.mjs — render every growth asset for every supported language.
 *
 *   node scripts/growth/build-assets.mjs [--surface <id>] [--language <code>] [--force]
 *
 * ## What it produces
 *
 * Five App Store growth surfaces, each in all 20 shipped languages:
 *
 *   1. In-App Events        — a 16:9 card and a 9:16 details image per event
 *   2. Custom Product Pages — a 3:2 creative per page
 *   3. Asset Library        — a 21:9 product page header and a 3:2 search creative
 *   4. Product Page Optimization — a 3:2 treatment creative per variant
 *   5. Header and Search    — the same two Creative Assets, surfaced on their own
 *
 * Output goes to `docs/growth/<surface>/<language>/<asset>.png`, plus a
 * `manifest.json` per surface recording what was rendered and from which art and
 * copy. `check-assets.mjs` reads that manifest to validate against Apple's
 * accepted sizes without re-deriving anything.
 *
 * A `--language` run renders images but writes no manifest: a manifest describes
 * every language, so a one-language run would leave it claiming a single-language
 * asset set. `--surface` does write, because it skips the other surfaces entirely
 * and renders the one it does touch in every language.
 *
 * ## How the two layers combine
 *
 * The background is Agnes-generated art: text-free, brand-palette, and composed
 * with a deliberate empty region. The text is rendered by Chromium from HTML, on
 * top. That split exists because a diffusion model cannot render 20 scripts
 * reliably, while Apple requires every asset's text to be localized into every
 * supported language. Generating the art once and the type 20 times keeps both
 * halves honest.
 *
 * Font stacks are per-script and explicit. See `FONT_STACKS` in `manifest.mjs`
 * for why the generic `sans-serif` fallback is not good enough for the Indic
 * scripts.
 *
 * ## Copy
 *
 * Every string comes from the app's own String Catalog or the App Store listing
 * data. Nothing is newly translated here, so an asset cannot say something the
 * app does not. A key that is untranslated for a language is reported, and the
 * asset renders with the English source rather than being skipped — a visible
 * gap is better than a missing asset, as long as it is counted.
 */

import { chromium } from 'playwright';
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname, resolve as resolvePath } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ROOT,
  LANGUAGES,
  FONT_STACKS,
  RTL_LANGUAGES,
  RENDER_SOURCE_PATHS,
  SURFACES,
  SPECS,
  planAssets,
  loadSources,
  resolveCopy,
  artPath,
  artSide,
} from './manifest.mjs';

const OUT_ROOT = join(ROOT, 'docs/growth');
const FONT_LATIN = join(ROOT, 'public/assets/fonts/fredoka-var-latin.woff2');
const FONT_LATIN_EXT = join(ROOT, 'public/assets/fonts/fredoka-var-latin-ext.woff2');

/**
 * A fake origin for the page's own resources.
 *
 * `page.setContent` gives the page an `about:blank` origin, and Chromium refuses
 * to load `file://` subresources from there, so an `<img src="file://...">` and a
 * `@font-face` pointing at a `file://` URL both fail silently. The first attempt
 * at this renderer produced flat cream cards with no art and a system fallback
 * font, with no error anywhere.
 *
 * So every local file is served over this fake origin instead, through
 * `page.route`. The HTML references `${ORIGIN}/...` paths, and the handler reads
 * them off disk. Nothing is base64-inlined, so a 2.5 MB background does not
 * become a 3.4 MB string.
 *
 * What the fake origin buys is an `https` origin whose subresource loads are not
 * blocked. It is deliberately a different origin from the `about:blank` page, and
 * that costs nothing: `route.fulfill` writes the response straight into the
 * request, so the font and image loads never reach the network stack's CORS
 * check. No `Access-Control-Allow-Origin` header is needed, and adding one would
 * be superstition. Measured with a probe: fulfilling a cross-origin
 * `fredoka-var-latin.woff2` into an `about:blank` page yields an `@font-face`
 * status of `loaded`, a rendered width that differs from the fallback face, no
 * console errors, and no CORS header on the response.
 */
const ORIGIN = 'https://growth.local';

const args = process.argv.slice(2);
const onlySurface = args.includes('--surface') ? args[args.indexOf('--surface') + 1] : null;
const onlyLanguage = args.includes('--language') ? args[args.indexOf('--language') + 1] : null;
const force = args.includes('--force');

/** Brand palette, from `tailwind.config.js`. */
const BRAND = {
  pink: '#ff4d8b',
  cream: '#fffaf0',
  ink: '#26221a',
  inkSoft: '#6b6152',
};

/**
 * The type scale for one surface, as a fraction of the canvas height.
 *
 * Expressed as fractions rather than pixels because the same layout has to work
 * at 1080, 1600, 1646, and 1920 tall. A fixed px size would be unreadable on the
 * 21:9 header and oversized on the 9:16 details image.
 */
function typeScale(spec) {
  const h = spec.target.height;
  return {
    headline: Math.round(h * 0.088),
    sub: Math.round(h * 0.038),
    brand: Math.round(h * 0.030),
    pad: Math.round(h * 0.085),
  };
}

/**
 * Where the text block sits, per surface shape.
 *
 * These are the layouts that read correctly on each aspect ratio. A 21:9 banner
 * puts the type on one side and lets the art fill the other; a 9:16 details
 * image stacks the art above the type, because at that height a side-by-side
 * split would leave the type a narrow column.
 *
 * `side` is the side the TEXT occupies, which is the empty side of the art.
 */
function layout(specId, side) {
  switch (specId) {
    case 'eventCard':
      return { flow: 'side', side, justify: 'center' };
    case 'eventDetails':
      return { flow: 'stack', side: 'bottom', justify: 'flex-end' };
    case 'productPageHeader':
      // The 21:9 header is short and wide, so the art reads better as a band on
      // one end than as a backdrop the type sits on.
      return { flow: 'side', side: side === 'top' ? 'left' : side, justify: 'center' };
    case 'searchResults':
      return { flow: 'side', side: side === 'top' ? 'left' : side, justify: 'center' };
    default:
      return { flow: 'side', side: 'left', justify: 'center' };
  }
}

/** The fraction of the canvas the text column occupies on a side layout. */
const TEXT_COLUMN = 0.56;


/**
 * Builds the HTML for one asset.
 *
 * The art is placed with `object-fit: cover` so it fills the canvas without
 * distortion regardless of the aspect mismatch between the 16:9 source and, say,
 * the 21:9 header. A scrim in the brand cream or pink is laid over the art on
 * the text side so the type stays legible no matter how the art landed.
 */
function renderHtml({ spec, specId, art, copy, language, surfaceId }) {
  const scale = typeScale(spec);
  const rtl = RTL_LANGUAGES.has(language);
  // The art's empty region is a PHYSICAL side, so the text column is positioned
  // with physical `left`/`right` rather than logical `inset-inline-*`.
  //
  // Logical properties flip under `dir="rtl"`, which would mirror the column
  // away from the art's empty half: Arabic rendered with the type on the right
  // while the art's clear half was also on the right, putting the copy on top of
  // the subject. Physical positioning is the correct model here because the
  // constraint comes from the image, not from the reading direction. The
  // paragraph's own alignment still follows `dir`, so RTL text is still
  // right-aligned inside its column.
  const side = artSide(art);
  const l = layout(specId, side);
  // Served through `page.route`, not `file://` — see `ORIGIN`.
  const artUrl = `${ORIGIN}/${artPath(art)}`;
  const latinUrl = `${ORIGIN}/public/assets/fonts/fredoka-var-latin.woff2`;
  const latinExtUrl = `${ORIGIN}/public/assets/fonts/fredoka-var-latin-ext.woff2`;

  // The text block is placed on the empty side of the art. For a `side` layout
  // that is a horizontal half; for a `stack` layout it is the lower portion.
  const isStack = l.flow === 'stack';
  const sideIsLeft = l.side === 'left';

  const slots = Object.entries(copy);
  const [primarySlot, ...restSlots] = slots;
  const primary = primarySlot?.[1] ?? '';

  // The 9:16 details image has room for the name and one line, not three. The
  // `long` description belongs on the card, where there is width for it.
  const rest = restSlots
    .filter(({ 0: slot }) => !(specId === 'eventDetails' && (slot === 'long' || slot === 'promo')))
    .map(([slot, value]) => ({ slot, value }));

  // The brand mark is part of the text flow rather than absolutely positioned,
  // so it can never land on top of the copy when a translation runs long.
  const brand = '<div class="brand">TidyByte</div>';

  const subBlocks = rest
    .filter(({ slot }) => slot !== 'brand' && slot !== 'label')
    .map(({ slot, value }) => `<p class="slot-${slot}">${escapeHtml(value)}</p>`)
    .join('\n');

  return `<!doctype html>
<html lang="${language}" dir="${rtl ? 'rtl' : 'ltr'}">
<head><meta charset="utf-8"><style>
  @font-face { font-family: 'Fredoka'; src: url('${latinUrl}') format('woff2'); font-weight: 300 700; unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
  @font-face { font-family: 'Fredoka'; src: url('${latinExtUrl}') format('woff2'); font-weight: 300 700; unicode-range: U+0100-02AF, U+0304, U+0308, U+0329, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: ${spec.target.width}px; height: ${spec.target.height}px; overflow: hidden; }
  body {
    position: relative;
    font-family: ${FONT_STACKS[language] ?? FONT_STACKS.en};
    background: ${BRAND.cream};
    -webkit-font-smoothing: antialiased;
  }
  .art { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
  .scrim {
    position: absolute; inset: 0;
    background: ${
      isStack
        ? `linear-gradient(to top, ${BRAND.cream} 0%, rgba(255,250,240,.97) 26%, rgba(255,250,240,.62) 44%, rgba(255,250,240,0) 62%)`
        : sideIsLeft
          ? `linear-gradient(to right, ${BRAND.cream} 0%, rgba(255,250,240,.96) 30%, rgba(255,250,240,.55) 48%, rgba(255,250,240,0) 66%)`
          : `linear-gradient(to left, ${BRAND.cream} 0%, rgba(255,250,240,.96) 30%, rgba(255,250,240,.55) 48%, rgba(255,250,240,0) 66%)`
    };
  }
  .copy {
    position: absolute;
    top: 0; bottom: 0;
    ${isStack
      ? 'left: 0; right: 0;'
      : sideIsLeft
        ? 'left: 0;'
        : 'right: 0;'}
    width: ${isStack ? '100%' : `${Math.round(TEXT_COLUMN * 100)}%`};
    display: flex; flex-direction: column;
    justify-content: ${l.justify};
    align-items: ${isStack ? 'center' : 'flex-start'};
    text-align: ${isStack ? 'center' : 'start'};
    gap: ${Math.round(scale.sub * 0.45)}px;
    padding: ${isStack ? `${scale.pad}px ${scale.pad * 0.7}px ${Math.round(scale.pad * 0.6)}px` : `${scale.pad}px`};
    color: ${BRAND.ink};
  }
  .headline {
    font-size: ${scale.headline}px; line-height: 1.1; font-weight: 600;
    letter-spacing: -0.02em; max-width: 92%;
    text-wrap: balance;
  }
  .slot-sub, .slot-short, .slot-tagline, .slot-long, .slot-promo {
    font-size: ${scale.sub}px; line-height: 1.35; font-weight: 400;
    color: ${BRAND.inkSoft}; max-width: 88%;
  }
  .slot-name { font-size: ${scale.headline}px; line-height: 1.1; font-weight: 600; letter-spacing: -0.02em; }
  .brand {
    display: flex; align-items: center; gap: ${Math.round(scale.brand * 0.4)}px;
    font-size: ${scale.brand}px; font-weight: 600; color: ${BRAND.ink};
    margin-top: ${Math.round(scale.sub * 0.6)}px;
  }
  .brand::before {
    content: ''; width: ${Math.round(scale.brand * 0.34)}px; height: ${Math.round(scale.brand * 0.34)}px;
    border-radius: 999px; background: ${BRAND.pink};
  }
</style></head>
<body>
  <img class="art" src="${artUrl}" alt="">
  <div class="scrim"></div>
  <div class="copy">
    <h1 class="headline">${escapeHtml(primary)}</h1>
    ${subBlocks}
    ${brand}
  </div>
</body></html>`;
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function main() {
  const plan = planAssets().filter((a) => !onlySurface || a.surface === onlySurface);
  const languages = LANGUAGES.filter((l) => !onlyLanguage || l === onlyLanguage);

  if (plan.length === 0) {
    console.error(`No assets match --surface ${onlySurface}`);
    process.exit(1);
  }

  // The art has to exist before anything renders; a missing file would silently
  // produce a flat cream card with no product imagery.
  const artFiles = new Set(plan.map((a) => artPath(a.art)));
  let missingArt = 0;
  for (const rel of artFiles) {
    if (!existsSync(join(ROOT, rel))) {
      console.error(`missing art: ${rel}`);
      missingArt += 1;
    }
  }
  if (missingArt > 0) {
    console.error(`\n${missingArt} background(s) missing. Generate them with the agnes-ai skill first.`);
    process.exit(1);
  }

  const sources = loadSources();
  // The newest mtime among the copy sources and `manifest.mjs` itself. Read once:
  // nothing in this run edits them.
  const sourcesMtime = Math.max(...RENDER_SOURCE_PATHS.map((p) => statSync(p).mtimeMs));
  const browser = await chromium.launch();
  const missing = [];
  const written = [];
  const perSurface = new Map();

  /**
   * Serves every local file the page asks for, from disk.
   *
   * The path in the URL is repo-relative, so it is resolved against `ROOT` and
   * checked to still be inside it — a URL like `${ORIGIN}/../../etc/passwd` must
   * not read off the filesystem.
   */
  const serve = async (route) => {
    const url = new URL(route.request().url());
    const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    const abs = resolvePath(ROOT, rel);
    if (!abs.startsWith(`${ROOT}/`) || !existsSync(abs)) {
      await route.fulfill({ status: 404, body: 'not found' });
      return;
    }
    const type = abs.endsWith('.woff2') ? 'font/woff2'
      : abs.endsWith('.png') ? 'image/png'
        : abs.endsWith('.jpg') || abs.endsWith('.jpeg') ? 'image/jpeg'
          : 'application/octet-stream';
    await route.fulfill({ status: 200, contentType: type, body: readFileSync(abs) });
  };

  for (const asset of plan) {
    const dir = join(OUT_ROOT, asset.surface, 'by-language');
    mkdirSync(dir, { recursive: true });

    for (const language of languages) {
      const copy = {};
      for (const [slot, ref] of Object.entries(asset.copy)) {
        copy[slot] = resolveCopy(ref, language, sources, missing);
      }

      const html = renderHtml({
        spec: asset.spec,
        specId: asset.specId,
        art: asset.art,
        copy,
        language,
        surfaceId: asset.surface,
      });

      const fileName = `${asset.group}--${asset.specId}--${language}.png`;
      const outPath = join(dir, fileName);

      // The art is not the only input. The copy resolves from the String Catalog
      // and the listings data, and the layout and font stacks come from
      // `manifest.mjs`, so a string edit with the art untouched has to invalidate
      // the cached PNG. Comparing the art alone made `npm run growth` report every
      // image "unchanged" and keep the old text on disk, which matters because
      // these PNGs are gitignored: the stale files are exactly what
      // `publish:media` uploads.
      const inputMtime = Math.max(
        statSync(join(ROOT, artPath(asset.art))).mtimeMs,
        sourcesMtime,
      );
      if (!force && existsSync(outPath) && statSync(outPath).mtimeMs > inputMtime) {
        // Already rendered from this art and these sources.
        written.push({ ...asset, language, path: outPath, cached: true });
        continue;
      }

      const page = await browser.newPage({
        viewport: { width: asset.spec.target.width, height: asset.spec.target.height },
        deviceScaleFactor: 1,
      });
      await page.route(`${ORIGIN}/**`, serve);
      await page.setContent(html, { waitUntil: 'load' });
      // `load` fires before an image necessarily decodes, and the fonts arrive
      // over the same route, so wait for both explicitly — otherwise the capture
      // is a cream card with fallback type, which is exactly the bug the ORIGIN
      // comment describes.
      await page.evaluate(async () => {
        await Promise.all(
          [...document.images].map((img) => (img.complete ? undefined : img.decode().catch(() => {}))),
        );
        await document.fonts.ready;
      });
      await page.screenshot({
        path: outPath,
        type: 'png',
        // Playwright captures with an alpha channel by default. Apple rejects
        // assets with transparency, so the background is forced opaque.
        omitBackground: false,
      });
      await page.close();

      written.push({ ...asset, language, path: outPath, cached: false });
    }

    const key = asset.surface;
    perSurface.set(key, (perSurface.get(key) ?? 0) + languages.length);
  }

  await browser.close();

  // A filtered run must never rewrite a manifest, because a manifest describes
  // the full language set: `--language hi` would replace 20 languages with 1 and
  // `check-assets.mjs` would then fail on the 19 it thinks went missing. Nothing
  // is lost by skipping the write, since the manifest is derived output and the
  // unfiltered run regenerates it.
  //
  // `--surface` is different and still writes: every other surface is skipped
  // outright by the filter above, and the one that renders renders in all
  // languages, so its manifest comes out complete.
  if (languages.length !== LANGUAGES.length) {
    const asked = onlyLanguage ?? "(no language)";
    console.log(`\n--language ${asked} ran alone, so no manifest.json was written: a manifest describes all ${LANGUAGES.length} languages.`);
  } else {
    // A per-surface manifest, so `check-assets.mjs` validates what was actually
    // written rather than re-deriving the plan.
    for (const surface of SURFACES) {
      const assets = written.filter((w) => w.surface === surface.id);
      if (assets.length === 0) continue;
      const dir = join(OUT_ROOT, surface.id);
      mkdirSync(dir, { recursive: true });
      writeFileSync(
        join(dir, 'manifest.json'),
        JSON.stringify(
          {
            surface: surface.id,
            title: surface.title,
            purpose: surface.purpose,
            generatedFrom: {
              art: [...new Set(assets.map((a) => artPath(a.art)))],
              copy: 'Tidybyte/Resources/Localizable.xcstrings + docs/appstore/listings.json',
            },
            assets: assets
              .map((a) => ({
                group: a.group,
                spec: a.specId,
                specLabel: a.spec.label,
                ratio: a.spec.ratio,
                width: a.spec.target.width,
                height: a.spec.target.height,
                language: a.language,
                file: `by-language/${a.group}--${a.specId}--${a.language}.png`,
              }))
              .sort((x, y) => x.group.localeCompare(y.group) || x.spec.localeCompare(y.spec) || x.language.localeCompare(y.language)),
          },
          null,
          2,
        ) + '\n',
      );
    }
  }

  const fresh = written.filter((w) => !w.cached).length;
  console.log(`Rendered ${written.length} image(s) — ${fresh} new, ${written.length - fresh} unchanged`);
  for (const [surface, count] of [...perSurface].sort()) {
    console.log(`  ${surface.padEnd(28)} ${count}`);
  }
  console.log(`Output: ${OUT_ROOT.replace(`${ROOT}/`, '')}/<surface>/by-language/`);

  if (missing.length > 0) {
    const unique = [...new Set(missing)];
    console.log(`\n${unique.length} copy fallback(s) — these rendered in English:`);
    for (const m of unique.slice(0, 30)) console.log(`  ${m}`);
    if (unique.length > 30) console.log(`  … and ${unique.length - 30} more`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
