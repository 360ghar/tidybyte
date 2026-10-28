#!/usr/bin/env node
/**
 * seo-audit.mjs — verify the built site's search and answer-engine surface.
 *
 * Runs against dist/ after `npm run build`. Checks, per HTML file:
 *   1. exactly one <h1>
 *   2. <title> and meta description present, sane length, unique site-wide
 *   3. canonical URL == og:url
 *   4. every application/ld+json block parses
 *   5. FAQPage questions also appear as visible text (Google requires it)
 *   6. BreadcrumbList present on every indexable page
 *   7. internal links and image sources resolve to a file in dist/
 *   8. localized landing pages (/de, /ja …) declare the same hreflang set as
 *      the English home, and every alternate they claim is a page that exists
 *   9. every language copy sits in the sitemap at the home page's priority
 *
 * Usage: node scripts/seo-audit.mjs
 * Exits non-zero on any failure.
 */
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DIST = join(ROOT, "dist");

if (!existsSync(DIST)) {
  console.error("dist/ not found — run `npm run build` first.");
  process.exit(1);
}

function htmlFiles() {
  const out = [];
  for (const dir of [DIST, join(DIST, "blog")]) {
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir)) {
      if (f.endsWith(".html")) out.push(join(dir, f));
    }
  }
  return out.sort();
}

const problems = [];
const titles = new Map();
const descriptions = new Map();

// hreflang alternates, collected before the main pass: which pages declare
// them, and the landing-page set they define. The set is the contract the
// language copies have to agree on, so it has to exist before the checks
// that use it.
const alternates = new Map();
const htmlLangs = new Map();
for (const file of htmlFiles()) {
  const rel = file.slice(DIST.length + 1);
  const html = readFileSync(file, "utf8");
  htmlLangs.set(rel, html.match(/<html lang="([^"]+)"/)?.[1] ?? null);
  const links = [
    ...html.matchAll(/<link rel="alternate" hreflang="([^"]+)" href="([^"]+)"/g),
  ].map((m) => ({ hreflang: m[1], href: m[2] }));
  if (links.length) alternates.set(rel, links);
}
const landingPaths = new Set();
for (const links of alternates.values()) {
  for (const l of links) landingPaths.add(new URL(l.href).pathname);
}
/** The landing page in another language: the home page of that language. */
const isTranslatedHome = (rel) => landingPaths.has(rel === "index.html" ? "/" : `/${rel.replace(/\.html$/, "")}`);

/** Visible text: strip script/style, then tags, then collapse whitespace. */
function visibleText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#x27;|&rsquo;/g, "'")
    .replace(/&quot;|&rdquo;|&ldquo;/g, '"')
    .replace(/&mdash;/g, "—")
    .replace(/&ndash;/g, "–")
    .replace(/\s+/g, " ")
    .trim();
}

function decode(s) {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&#x27;|&rsquo;/g, "'")
    .replace(/&quot;|&rdquo;|&ldquo;/g, '"')
    .replace(/&mdash;/g, "—")
    .replace(/&ndash;/g, "–")
    .replace(/\s+/g, " ")
    .trim();
}

for (const file of htmlFiles()) {
  const rel = file.slice(DIST.length + 1);
  const html = readFileSync(file, "utf8");
  const isNoIndex = /<meta name="robots" content="noindex/.test(html);
  const fail = (msg) => problems.push(`${rel}: ${msg}`);

  // 1. one h1
  const h1s = html.match(/<h1[\s>]/g) ?? [];
  if (h1s.length !== 1) fail(`expected exactly one <h1>, found ${h1s.length}`);

  // 2. title + description
  const title = html.match(/<title>([\s\S]*?)<\/title>/)?.[1]?.trim() ?? "";
  const desc = html.match(/<meta name="description" content="([^"]*)"/)?.[1]?.trim() ?? "";
  if (!title) fail("missing <title>");
  else {
    if (decode(title).length > 65) fail(`title is ${decode(title).length} chars: "${decode(title)}"`);
    const prev = titles.get(title);
    if (prev) fail(`duplicate title (also on ${prev})`);
    else titles.set(title, rel);
  }
  if (!desc) fail("missing meta description");
  else if (!isNoIndex) {
    const len = decode(desc).length;
    if (len < 110 || len > 165) fail(`description is ${len} chars`);
    const prev = descriptions.get(desc);
    if (prev) fail(`duplicate description (also on ${prev})`);
    else descriptions.set(desc, rel);
  }

  // 3. canonical == og:url
  const canonical = html.match(/<link rel="canonical" href="([^"]+)"/)?.[1];
  const ogUrl = html.match(/<meta property="og:url" content="([^"]+)"/)?.[1];
  if (!canonical) fail("missing canonical");
  if (canonical && ogUrl && canonical !== ogUrl) fail(`canonical ${canonical} != og:url ${ogUrl}`);

  // 4. JSON-LD parses
  const blocks = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  const types = new Set();
  for (const [, body] of blocks) {
    try {
      const parsed = JSON.parse(body);
      types.add(parsed["@type"]);
    } catch (e) {
      fail(`JSON-LD does not parse: ${String(e).slice(0, 80)}`);
    }
  }

  // 4b. tool pages reference the app entity and their OG card exists
  if (rel === "photo-cleaner.html") {
    if (!types.has("ItemList")) fail("hub page is missing the ItemList JSON-LD");
  }
  const ogCard = html.match(/<meta property="og:image" content="[^"]*\/assets\/img\/og\/([^"]+)"/);
  if (ogCard) {
    if (!existsSync(join(DIST, "assets/img/og", ogCard[1]))) {
      fail(`og:image card not built: ${ogCard[1]}`);
    }
    if (!html.includes('"@id": "https://tidybyte.360ghar.com/#app"')) {
      fail("tool page does not reference the #app entity");
    }
  }

  // 5. FAQ questions appear as visible text
  const text = visibleText(html);
  for (const [, body] of blocks) {
    let parsed;
    try {
      parsed = JSON.parse(body);
    } catch {
      continue;
    }
    if (parsed["@type"] === "FAQPage") {
      for (const q of parsed.mainEntity ?? []) {
        const raw = String(q.name);
        // A newline or a stray "+" in a question name means the string was
        // pasted together with a line-continuation artifact. Search engines
        // read the name verbatim, and it would also show in the visible FAQ.
        if (/[\n\r]/.test(raw) || /\s\+\s*$/.test(raw)) {
          fail(`FAQ question name contains a line artifact: ${JSON.stringify(raw.slice(0, 60))}`);
        }
        if (raw !== raw.trim()) {
          fail(`FAQ question name has untrimmed whitespace: ${JSON.stringify(raw.slice(0, 60))}`);
        }
        const name = decode(raw);
        if (!text.includes(name)) fail(`FAQ question not visible on page: "${name.slice(0, 60)}"`);
      }
    }
  }

  // 6. breadcrumbs on indexable pages (the home page is the trail's root,
  //    and so is each of its language copies: the trail would lead a reader
  //    who cannot read English back to the English page)
  if (!isNoIndex && rel !== "404.html" && !isTranslatedHome(rel) && !types.has("BreadcrumbList")) {
    fail("missing BreadcrumbList JSON-LD");
  }

  // 6b. every indexable page declares what a voice assistant should read,
  //     and carries the visible answer the Speakable selector points at.
  //     Note: the selector string itself appears in every Speakable block, so
  //     this must match the rendered element, not the text "data-quick-answer".
  if (!isNoIndex && rel !== "404.html") {
    if (!html.includes("SpeakableSpecification")) fail("missing Speakable specification");
    if (!/<aside[^>]*\sdata-quick-answer/.test(html)) {
      fail("Speakable targets [data-quick-answer] but no such element is rendered");
    }
  }

  // 7. internal links and images resolve
  const refs = [
    ...[...html.matchAll(/(?:href|src)="(\/[^"#?]*)[^"]*"/g)].map((m) => m[1]),
  ];
  for (const ref of new Set(refs)) {
    if (ref.startsWith("/assets/")) {
      const p = join(DIST, ref.slice(1));
      if (!existsSync(p)) fail(`missing asset ${ref}`);
      continue;
    }
    const clean = ref.replace(/\/$/, "");
    if (clean === "") continue;
    const candidates = [
      join(DIST, `${clean.slice(1)}.html`),
      join(DIST, clean.slice(1), "index.html"),
      join(DIST, clean.slice(1)),
    ];
    if (!candidates.some((c) => existsSync(c) && statSync(c).isFile())) {
      fail(`dead internal link ${ref}`);
    }
  }
}

// 8. Localized landing pages. hreflang only works when it is reciprocal: a
//    page that points at /de while /de points somewhere else is worse than
//    no hreflang at all, because a search engine then picks a canonical for
//    the cluster on its own. The English home is the anchor — every other
//    copy must declare exactly the same set of alternates.
const reference = alternates.get("index.html");
if (!reference) {
  problems.push("index.html: no hreflang alternates — the English home anchors the language set");
} else {
  const referenceHrefs = reference.map((l) => l.href).sort().join("\n");
  if (!reference.some((l) => l.hreflang === "x-default")) {
    problems.push("index.html: hreflang set has no x-default entry");
  }
  for (const [rel, links] of alternates) {
    if (links.map((l) => l.href).sort().join("\n") !== referenceHrefs) {
      problems.push(
        `${rel}: hreflang set differs from index.html (${links.length} links vs ${reference.length})`,
      );
      continue;
    }
    const self = links.find(
      (l) => new URL(l.href).pathname === `/${rel.replace(/\.html$/, "")}`,
    );
    const htmlLang = htmlLangs.get(rel);
    if (self && htmlLang && self.hreflang !== htmlLang) {
      problems.push(
        `${rel}: <html lang="${htmlLang}"> disagrees with its own hreflang="${self.hreflang}"`,
      );
    }
  }
  // Every alternate the set claims has to be a page that shipped.
  for (const link of reference) {
    const path = new URL(link.href).pathname;
    const file = path === "/" ? "index.html" : `${path.slice(1)}.html`;
    if (!existsSync(join(DIST, file))) {
      problems.push(`index.html claims hreflang="${link.hreflang}" ${link.href}, but dist/${file} is missing`);
    }
  }
}

// sitemap sanity
const sitemap = join(DIST, "sitemap-0.xml");
if (!existsSync(sitemap)) {
  problems.push("dist/sitemap-0.xml missing");
} else {
  const xml = readFileSync(sitemap, "utf8");
  const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
  if (locs.length < 60) problems.push(`sitemap has only ${locs.length} URLs`);
  for (const loc of locs) {
    if (!loc.startsWith("https://tidybyte.360ghar.com/")) {
      problems.push(`sitemap URL on unexpected host: ${loc}`);
    }
  }
  const toolUrls = locs.filter((u) =>
    /tidybyte\.360ghar\.com\/(storage-cleaner|photo-cleaner|video-compression|image-compression)/.test(u),
  );
  if (toolUrls.length < 4) problems.push("tool landing pages missing from sitemap");

  // 9. A localized landing page is the same page as "/" in another language,
  //    so it carries the same priority. The slug list is duplicated in
  //    astro.config.mjs (the config cannot import src/data/languages.ts); a
  //    language added there without updating it would silently drop to 0.3.
  for (const path of landingPaths) {
    const url = `https://tidybyte.360ghar.com${path}`;
    const entry = xml.match(
      new RegExp(`<url>\\s*<loc>${url.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}</loc>\\s*<changefreq>([^<]+)</changefreq>\\s*<priority>([^<]+)</priority>`),
    );
    if (!entry) {
      problems.push(`landing page missing or malformed in sitemap: ${url}`);
    } else if (entry[2] !== "1.0") {
      problems.push(`landing page ${url} has priority ${entry[2]}, expected 1.0`);
    }
  }
  // Every top-level HTML page except the 404 must be listed.
  const locSet = new Set(locs);
  for (const f of readdirSync(DIST)) {
    if (!f.endsWith(".html")) continue;
    if (f === "index.html" || f === "404.html") continue;
    const url = `https://tidybyte.360ghar.com/${f.replace(/\.html$/, "")}`;
    if (!locSet.has(url)) problems.push(`not in sitemap: ${url}`);
  }
  // Tool landing pages carry commercial intent, so they must keep priority
  // 0.9. The slug list lives in astro.config.mjs; a new tool page added
  // without updating it would silently drop to 0.3, which this catches.
  for (const f of readdirSync(DIST)) {
    if (!f.endsWith(".html")) continue;
    const html = readFileSync(join(DIST, f), "utf8");
    if (!/\/assets\/img\/og\//.test(html)) continue; // not a tool page
    const url = `https://tidybyte.360ghar.com/${f.replace(/\.html$/, "")}`;
    const entry = xml.match(
      new RegExp(`<url>\\s*<loc>${url.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}</loc>\\s*<changefreq>([^<]+)</changefreq>\\s*<priority>([^<]+)</priority>`),
    );
    if (!entry) {
      problems.push(`tool page missing or malformed in sitemap: ${url}`);
    } else if (entry[2] !== "0.9") {
      problems.push(`tool page ${url} has priority ${entry[2]}, expected 0.9`);
    }
  }
  console.log(`sitemap: ${locs.length} URLs, ${toolUrls.length}/4 spot-checked tool pages present`);

  // llms.txt promises clean Markdown for every page it lists, so every
  // sitemap URL must resolve to a generated .md file.
  const missingMd = [];
  for (const loc of locs) {
    const rel = loc.replace("https://tidybyte.360ghar.com/", "").replace(/\/$/, "");
    const md = rel === "" ? "index.md" : `${rel}.md`;
    if (!existsSync(join(DIST, md))) missingMd.push(md);
  }
  if (missingMd.length) {
    problems.push(`llms.txt promises Markdown but these are missing: ${missingMd.join(", ")}`);
  }
}

if (problems.length) {
  console.error(`\n✗ ${problems.length} problem(s):`);
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log(`✓ audit clean across ${htmlFiles().length} HTML files`);
