#!/usr/bin/env node
/**
 * og-cards.mjs — render 1200x630 Open Graph cards for the tool landing pages.
 *
 * Every tool page declares /assets/img/og/<slug>.jpg as its og:image and
 * twitter:image (see toolPageMeta in src/data/tools.ts). Social scrapers and
 * answer engines fetch that file, so it has to exist and has to be a real
 * 1200x630 JPEG — an SVG or a square icon silently produces no card.
 *
 * Card content is read from the built HTML in dist/, so the image can never
 * advertise a title the page no longer uses. Run `npm run build` first.
 *
 * Usage: node scripts/og-cards.mjs [--check]
 *   --check: verify every tool page's og:image exists (no rendering)
 */
import { chromium } from "playwright";
import { readFileSync, existsSync, readdirSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DIST = join(ROOT, "dist");
const OUT = join(ROOT, "public/assets/img/og");
const FONT = pathToFileURL(join(ROOT, "public/assets/fonts/fredoka-var-latin.woff2")).href;
const CHECK = process.argv.includes("--check");

if (!existsSync(DIST)) {
  console.error("dist/ not found — run `npm run build` first.");
  process.exit(1);
}

/** Tool pages = top-level HTML files that reference an og card. */
function toolPages() {
  const pages = [];
  for (const f of readdirSync(DIST)) {
    if (!f.endsWith(".html")) continue;
    if (["index.html", "404.html"].includes(f)) continue;
    const html = readFileSync(join(DIST, f), "utf8");
    const og = html.match(/<meta property="og:image" content="[^"]*\/assets\/img\/og\/([^"]+)"/);
    if (!og) continue;
    const title = html.match(/<title>([\s\S]*?)<\/title>/)?.[1]?.trim() ?? "";
    const h1 = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/)?.[1]?.replace(/<[^>]+>/g, "").trim() ?? "";
    const badge = html.match(/<p class="badge">([\s\S]*?)<\/p>/)?.[1]?.replace(/<[^>]+>/g, "").trim() ?? "";
    pages.push({ slug: og[1].replace(/\.jpg$/, ""), title, h1, badge });
  }
  return pages.sort((a, b) => a.slug.localeCompare(b.slug));
}

const pages = toolPages();

if (CHECK) {
  let missing = 0;
  for (const p of pages) {
    if (!existsSync(join(OUT, `${p.slug}.jpg`))) {
      console.error(`missing og card: ${p.slug}.jpg`);
      missing++;
    }
  }
  if (missing) {
    console.error(`\n✗ ${missing} og card(s) missing — run \`node scripts/og-cards.mjs\``);
    process.exit(1);
  }
  console.log(`✓ ${pages.length} og cards present`);
  process.exit(0);
}

mkdirSync(OUT, { recursive: true });

const card = (p) => `<!doctype html>
<html><head><meta charset="utf-8"><style>
  @font-face { font-family: 'Fredoka'; src: url('${FONT}') format('woff2'); font-weight: 300 700; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    width: 1200px; height: 630px; overflow: hidden;
    background: #fffaf0; color: #26221a;
    font-family: 'Fredoka', system-ui, sans-serif;
    display: flex; flex-direction: column; justify-content: center; gap: 34px;
    align-items: flex-start;
    padding: 64px 72px 132px;
    position: relative;
  }
  .glow {
    position: absolute; inset: -180px -120px auto -120px; height: 520px;
    background: radial-gradient(ellipse 60% 100% at 30% 40%, rgba(255,77,139,.16), transparent 70%);
  }
  .blobs { position: absolute; right: -60px; bottom: -80px; opacity: .55; }
  .badge {
    display: inline-flex; align-items: center; gap: 10px;
    background: #ffe3ee; color: #8a1e46; border-radius: 999px;
    padding: 10px 20px; font-size: 22px; font-weight: 500;
  }
  h1 { font-size: 68px; line-height: 1.08; font-weight: 600; letter-spacing: -.02em; max-width: 980px; }
  .brand { display: flex; align-items: center; gap: 14px; font-size: 30px; font-weight: 600; }
  .dot { width: 12px; height: 12px; border-radius: 999px; background: #ff4d8b; }
  .foot {
    position: absolute; left: 72px; right: 72px; bottom: 56px;
    display: flex; align-items: flex-end; justify-content: space-between; gap: 24px;
  }
  .facts { font-size: 23px; color: #6b6152; max-width: 620px; line-height: 1.35; }
</style></head>
<body>
  <div class="glow"></div>
  <svg class="blobs" width="360" height="330" viewBox="0 0 320 300" fill="none" aria-hidden="true">
    <circle cx="200" cy="190" r="96" fill="#a4d4c5" opacity=".5"/>
    <circle cx="90" cy="120" r="54" fill="#b8a4ed" opacity=".5"/>
    <circle cx="250" cy="80" r="38" fill="#ffb084" opacity=".6"/>
    <path d="M40 240l4 10 10 4-10 4-4 10-4-10-10-4 10-4z" fill="#ff7aa2" opacity=".8"/>
  </svg>
  <span class="badge">${p.badge}</span>
  <h1>${p.h1}</h1>
  <div class="foot">
    <div class="facts">Free forever &middot; 100% on-device &middot; No ads, no subscription, no account</div>
    <div class="brand"><span>TidyByte</span><span class="dot"></span></div>
  </div>
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });

let written = 0;
for (const p of pages) {
  await page.setContent(card(p), { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: join(OUT, `${p.slug}.jpg`), type: "jpeg", quality: 84 });
  written++;
  console.log(`  ${p.slug}.jpg`);
}
await browser.close();
console.log(`\n✓ wrote ${written} og cards to public/assets/img/og/`);
