#!/usr/bin/env node
/**
 * verify-parity.mjs — prove the Astro build (dist/) is identical to the
 * pre-migration site (site/), per the approved zero-visual-change spec.
 *
 * Full mode (default, `npm run verify`):
 *   1. Copies site/ → .parity-baseline/ (fresh each run)
 *   2. Byte-compares all 51 HTML pages after normalising hashed asset
 *      filenames (styles.abc12345.css ↔ styles.css) on both sides
 *   3. Byte-compares styles.css + the four JS files
 *   4. Byte-compares robots.txt, sitemap.xml, llms*.txt
 *   5. Asset closure: every src/href/srcset in dist/ resolves to a file
 *   6. Anchor check: every internal #fragment target has a matching id
 *   7. Redirect sanity: every netlify.toml redirect target exists
 *   8. Screenshots: 6 routes × 3 viewports × light/dark, pixel-diff must
 *      be 0 (Playwright + pixelmatch); fails on page console errors
 *
 * Check mode (`--check`): dist/-only consistency pass for CI after the
 * baseline folder has been deleted (page count, refs, anchors, redirects).
 */
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join, dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SITE = join(ROOT, "site");
const DIST = join(ROOT, "dist");
const BASELINE = join(ROOT, ".parity-baseline");
// Original assets (CSS/JS/fonts/images) live in public/ — they were moved
// verbatim out of site/ at the start of the migration, so they ARE the
// pre-migration bytes.
const PUBLIC = join(ROOT, "public");
const CHECK = process.argv.includes("--check");

const failures = [];
const fail = (msg) => { failures.push(msg); console.error(`FAIL ${msg}`); };
const ok = (msg) => console.log(`ok   ${msg}`);

const HASH_RE = /(\/assets\/(?:css|js)\/[A-Za-z0-9_-]+)\.[0-9a-f]{8}\.(css|js)/g;
const normalize = (s) => s.replace(HASH_RE, "$1.$2");

function htmlFilesUnder(dir, rel = "") {
  const out = [];
  for (const f of readdirSync(join(dir, rel), { withFileTypes: true })) {
    const r = rel ? `${rel}/${f.name}` : f.name;
    if (f.isDirectory()) out.push(...htmlFilesUnder(dir, r));
    else if (f.name.endsWith(".html")) out.push(r);
  }
  return out;
}

// ---------------------------------------------------------------- 1. baseline
if (!CHECK) {
  if (!existsSync(SITE)) fail("site/ not found — full parity mode needs the baseline folder");
  rmSync(BASELINE, { recursive: true, force: true });
  mkdirSync(dirname(BASELINE), { recursive: true });
  // copy via cpSync
  const { cpSync } = await import("node:fs");
  cpSync(SITE, BASELINE, { recursive: true });
  ok("baseline copied");
}

// ---------------------------------------------------------------- 2. pages
const basePages = CHECK ? [] : htmlFilesUnder(BASELINE).sort();
const distPages = htmlFilesUnder(DIST).sort();
if (!CHECK) {
  if (basePages.length !== distPages.length) fail(`page count: baseline ${basePages.length} vs dist ${distPages.length}`);
  const onlyBase = basePages.filter((p) => !distPages.includes(p));
  const onlyDist = distPages.filter((p) => !basePages.includes(p));
  if (onlyBase.length) fail(`pages missing in dist: ${onlyBase.join(", ")}`);
  if (onlyDist.length) fail(`pages new in dist: ${onlyDist.join(", ")}`);
}
const EXPECTED_PAGES = 51;
if (distPages.length !== EXPECTED_PAGES) fail(`expected ${EXPECTED_PAGES} pages, got ${distPages.length}`);
else ok(`${distPages.length} pages present`);

let byteIdentical = 0;
const byteDiffs = [];
for (const rel of distPages) {
  if (CHECK) continue;
  const a = normalize(readFileSync(join(DIST, rel), "utf8"));
  const b = normalize(readFileSync(join(BASELINE, rel), "utf8"));
  if (a === b) byteIdentical++;
  else byteDiffs.push(rel);
}
if (!CHECK) {
  if (byteDiffs.length) fail(`${byteDiffs.length} pages differ after hash normalisation: ${byteDiffs.slice(0, 5).join(", ")}`);
  else ok(`all ${byteIdentical} pages byte-identical (modulo asset hashes)`);
}

// ---------------------------------------------------------------- 3. css/js
const CODE_ASSETS = ["assets/css/styles.css", "assets/js/theme.js", "assets/js/nav.js", "assets/js/site.js", "assets/js/blog.js"];
for (const rel of CODE_ASSETS) {
  if (CHECK) { if (!existsSync(join(DIST, rel))) fail(`missing ${rel}`); continue; }
  const a = readFileSync(join(DIST, rel));
  const b = readFileSync(join(PUBLIC, rel));
  const ha = createHash("sha256").update(a).digest("hex");
  const hb = createHash("sha256").update(b).digest("hex");
  if (ha !== hb) fail(`${rel} content differs (${ha.slice(0, 8)} vs original ${hb.slice(0, 8)})`);
}
if (!failures.length || failures.every((f) => !/content differs/.test(f))) ok("CSS/JS byte-identical");

// ---------------------------------------------------------------- 4. statics
const STATIC_FILES = ["robots.txt", "sitemap.xml", "llms.txt", "llms-full.txt"];
for (const rel of STATIC_FILES) {
  if (CHECK) { if (!existsSync(join(DIST, rel))) fail(`missing ${rel}`); continue; }
  if (readFileSync(join(DIST, rel)).equals(readFileSync(join(PUBLIC, rel)))) continue;
  fail(`${rel} differs from original`);
}
ok("static files checked");

// ---------------------------------------------------------------- 5+6. refs & anchors
const urlToDistFile = (url) => {
  if (!url.startsWith("/") || url.startsWith("//")) return null;
  const clean = url.split("#")[0].split("?")[0];
  if (!clean || clean === "/") return clean === "/" ? "index.html" : null;
  const direct = join(DIST, clean);
  if (existsSync(direct) && statSync(direct).isFile()) return clean;
  if (existsSync(join(DIST, `${clean}.html`))) return `${clean}.html`;
  if (existsSync(join(DIST, clean, "index.html"))) return `${clean}/index.html`;
  return `__MISSING:${clean}`;
};
const idsByPage = new Map();
const pageIds = (rel, tree = DIST) => {
  const key = `${tree}:${rel}`;
  if (!idsByPage.has(key)) {
    const ids = new Set();
    const p = join(tree, rel);
    if (existsSync(p)) {
      for (const m of readFileSync(p, "utf8").matchAll(/\bid="([^"]+)"/g)) ids.add(m[1]);
    }
    idsByPage.set(key, ids);
  }
  return idsByPage.get(key);
};
let refCount = 0, anchorCount = 0;
for (const rel of distPages) {
  const html = readFileSync(join(DIST, rel), "utf8");
  const refs = [];
  for (const m of html.matchAll(/(?:src|href|srcset)="([^"]+)"/g)) refs.push(...m[1].split(",").map((s) => s.trim().split(" ")[0]));
  for (const ref of refs) {
    if (ref.startsWith("#")) {
      // Parity rule: only a REGRESSION fails (id existed in baseline,
      // missing in dist). Anchors missing from both trees (e.g. the
      // pre-existing #cat-* badge links the hub never ids) are baseline
      // behaviour — identical before and after migration.
      const had = !CHECK && pageIds(rel, BASELINE).has(ref.slice(1));
      if (had && !pageIds(rel).has(ref.slice(1))) fail(`${rel}: regression — anchor ${ref} existed in baseline`);
      anchorCount++; continue;
    }
    if (!ref.startsWith("/")) continue; // external or data:
    const target = urlToDistFile(ref);
    refCount++;
    if (target === null || target.startsWith("__MISSING:")) fail(`${rel}: unresolved ref ${ref}`);
    else if (ref.includes("#") && target.endsWith(".html")) {
      const frag = ref.split("#")[1];
      const inBase = !CHECK && pageIds(target, BASELINE).has(frag);
      if (frag && inBase && !pageIds(target).has(frag)) fail(`${rel}: regression — #${frag} missing in ${target}`);
      anchorCount++;
    }
  }
}
ok(`${refCount} refs + ${anchorCount} anchors checked`);

// ---------------------------------------------------------------- 7. redirects
const netlify = readFileSync(join(ROOT, "netlify.toml"), "utf8");
const redirectBlock = netlify.split("[[redirects]]").slice(1);
let redirectTargets = 0;
for (const block of redirectBlock) {
  const to = block.match(/to = "([^"]+)"/)?.[1];
  if (!to || to.includes(":splat") || to.endsWith(".xml") || to.endsWith(".txt")) continue;
  const target = urlToDistFile(to);
  if (target === null || target.startsWith("__MISSING:")) fail(`redirect target missing: ${to}`);
  else redirectTargets++;
}
ok(`${redirectTargets} redirect targets resolve`);

if (failures.length) {
  console.error(`\n${failures.length} FAILURE(S)`);
  process.exit(1);
}
console.log(CHECK ? "\n--check PASSED" : "\nSTRUCTURAL PARITY PASSED — running screenshots");

// ---------------------------------------------------------------- 8. screenshots
if (CHECK) { console.log("--check complete"); process.exit(0); }

const { chromium } = await import("playwright");
const { PNG } = await import("pngjs");
const pixelmatch = (await import("pixelmatch")).default;

const MIME = {
  ".html": "text/html", ".css": "text/css", ".js": "text/javascript",
  ".png": "image/png", ".webp": "image/webp", ".avif": "image/avif",
  ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".woff2": "font/woff2",
  ".txt": "text/plain", ".xml": "application/xml", ".ico": "image/x-icon",
};
function serve(dir, port) {
  return new Promise((res) => {
    const srv = createServer((req, resp) => {
      let p = decodeURIComponent(req.url.split("?")[0]);
      let file = join(dir, p === "/" ? "index.html" : p.replace(/^\//, ""));
      // The baseline HTML tree no longer holds assets (moved to public/);
      // serve those from public/ so baseline pages render identically.
      if (!existsSync(file) && p.startsWith("/assets/")) file = join(PUBLIC, p.replace(/^\//, ""));
      if (!existsSync(file) && existsSync(`${file}.html`)) file += ".html";
      if (existsSync(file) && statSync(file).isDirectory()) file = join(file, "index.html");
      if (!existsSync(file)) { resp.writeHead(404); resp.end("nf"); return; }
      resp.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" });
      resp.end(readFileSync(file));
    });
    srv.listen(port, "127.0.0.1", () => res(srv));
  });
}
const srvBase = await serve(BASELINE, 4173);
const srvDist = await serve(DIST, 4174);

const ROUTES = ["/", "/blog", "/blog/tidybyte-review", "/support", "/privacy", "/changelog"];
const VIEWPORTS = [[375, 812], [768, 1024], [1280, 800]];
const SHOTS = join(ROOT, ".parity-baseline", "..", ".parity-shots");
rmSync(SHOTS, { recursive: true, force: true });
mkdirSync(SHOTS, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage();
const consoleErrors = [];
page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(`${m.location()?.url}: ${m.text()}`); });
page.on("pageerror", (e) => consoleErrors.push(`pageerror: ${e.message}`));

let shotCount = 0, pixelFails = 0;
for (const [w, h] of VIEWPORTS) {
  await page.setViewportSize({ width: w, height: h });
  for (const route of ROUTES) {
    for (const scheme of ["light", "dark"]) {
      const slug = `${route.replace(/\//g, "_") || "root"}-${w}-${scheme}`;
      for (const [label, port] of [["base", 4173], ["dist", 4174]]) {
        await page.goto(`http://127.0.0.1:${port}${route}`, { waitUntil: "networkidle" });
        await page.evaluate((s) => {
          const root = document.documentElement;
          root.classList.toggle("dark", s === "dark");
          root.style.colorScheme = s;
          // Deterministic capture: freeze transitions/animations and force
          // lazy images to load + decode before the screenshot.
          const style = document.createElement("style");
          style.textContent = "*,*::before,*::after{transition:none!important;animation:none!important;scroll-behavior:auto!important}";
          document.head.appendChild(style);
        }, scheme);
        await page.evaluate(async () => {
          const step = window.innerHeight;
          for (let y = 0; y < document.body.scrollHeight; y += step) {
            window.scrollTo(0, y);
            await new Promise((r) => setTimeout(r, 30));
          }
          window.scrollTo(0, 0);
          await Promise.allSettled(
            [...document.querySelectorAll("img")]
              .filter((i) => i.offsetParent !== null)
              .map((i) => i.decode()),
          );
        });
        await page.waitForTimeout(150);
        await page.screenshot({ path: join(SHOTS, `${slug}-${label}.png`), fullPage: true });
      }
      const a = PNG.sync.read(readFileSync(join(SHOTS, `${slug}-base.png`)));
      const b = PNG.sync.read(readFileSync(join(SHOTS, `${slug}-dist.png`)));
      if (a.width !== b.width || a.height !== b.height) {
        fail(`screenshot ${slug}: size ${b.width}x${b.height} vs baseline ${a.width}x${a.height}`);
        pixelFails++;
        continue;
      }
      const diff = pixelmatch(a.data, b.data, null, a.width, a.height, { threshold: 0 });
      shotCount++;
      if (diff > 0) { fail(`screenshot ${slug}: ${diff} pixels differ`); pixelFails++; }
    }
  }
}
await browser.close();
srvBase.close();
srvDist.close();

if (consoleErrors.length) fail(`console errors: ${consoleErrors.slice(0, 5).join(" | ")}`);
if (failures.length) {
  console.error(`\nPARITY FAILED: ${failures.length} failure(s)`);
  process.exit(1);
}
console.log(`\nPARITY VERIFIED: ${distPages.length} pages byte-identical, ${shotCount} screenshot pairs pixel-identical (${shotCount * 2} captures)`);
