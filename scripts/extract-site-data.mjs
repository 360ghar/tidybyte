#!/usr/bin/env node
/**
 * extract-site-data.mjs — ONE-TIME migration helper.
 *
 * Reads the final rendered HTML in site/ (source of truth for the Astro
 * migration, per the approved spec) and emits:
 *   src/data/pages.ts          per-route <head> metadata + JSON-LD blocks
 *   src/content/pages/*.html   verbatim <main>…</main> content per route
 *   src/chrome/header.html     verbatim .orchestration/landing/02-header.html
 *   src/chrome/footer.html     verbatim .orchestration/landing/12-footer.html
 *
 * Nothing is transformed: strings are copied exactly as they appear on
 * disk (entities, indentation, comments included). The Astro layout
 * reassembles pages around them byte-identically (verified by
 * scripts/verify-parity.mjs).
 *
 * Usage: node scripts/extract-site-data.mjs
 */
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SITE = join(ROOT, "site");
const OUT = join(ROOT, "src");

const ROUTES = [
  { route: "/", file: "index.html", name: "index" },
  { route: "/404", file: "404.html", name: "404" },
  { route: "/privacy", file: "privacy.html", name: "privacy" },
  { route: "/support", file: "support.html", name: "support" },
  { route: "/changelog", file: "changelog.html", name: "changelog" },
  { route: "/blog", file: "blog/index.html", name: "blog-index" },
];

// Fixed-trio scripts the layout always emits (theme non-defer, nav/site defer).
const BASE_SCRIPTS = new Set(["/assets/js/theme.js", "/assets/js/nav.js", "/assets/js/site.js"]);
// hash-assets.mjs fingerprints: styles.abcdef12.css → styles.css
const unhash = (src) => src.replace(/\/([\w-]+)\.[0-9a-f]{8}\.(js|css)$/, "/$1.$2");

function extract(html) {
  const meta = {};
  const need = (v, what) => {
    if (v === undefined) throw new Error(`missing ${what}`);
    return v;
  };
  meta.title = need(html.match(/<title>(.*?)<\/title>/s), "title")?.[1];
  meta.description = need(html.match(/<meta name="description" content="([^"]*)"/), "description")[1];
  meta.robots = html.match(/<meta name="robots" content="([^"]*)"/)?.[1] ?? "index, follow";
  meta.ogType = need(html.match(/<meta property="og:type" content="([^"]*)"/), "og:type")[1];
  meta.ogImage = need(html.match(/<meta property="og:image" content="([^"]*)"/), "og:image")[1];
  meta.ogWidth = html.match(/<meta property="og:image:width" content="([^"]*)"/)?.[1] ?? "1024";
  meta.ogHeight = html.match(/<meta property="og:image:height" content="([^"]*)"/)?.[1] ?? "630";
  meta.ogUrl = need(html.match(/<meta property="og:url" content="([^"]*)"/), "og:url")[1];
  meta.canonical = need(html.match(/<link rel="canonical" href="([^"]*)"/), "canonical")[1];
  meta.fontPreload = html.match(/<link rel="preload" href="([^"]*)" as="font" type="font\/woff2" crossorigin>/)?.[1] ?? null;
  meta.imagePreload = html.match(/<link rel="preload" as="image" href="([^"]*)" type="image\/avif">/)?.[1] ?? null;

  // Head scripts (theme/nav/site fixed trio + extras like blog.js), hash-normalised.
  const scriptSrcs = [...html.matchAll(/<script src="([^"]+)"(?: defer)?><\/script>/g)]
    .map((m) => unhash(m[1]));
  meta.extraScripts = scriptSrcs.filter((s) => !BASE_SCRIPTS.has(s));

  // JSON-LD region: everything between the last plain <script src> line and
  // </head>, verbatim (comments, blocks, and their exact blank-line spacing).
  const scriptRe = /<script src="[^"]+"(?: defer)?><\/script>/g;
  let lastScriptEnd = -1;
  for (const m of html.matchAll(scriptRe)) lastScriptEnd = m.index + m[0].length;
  const headEnd = html.indexOf("</head>");
  if (lastScriptEnd < 0 || headEnd < 0 || lastScriptEnd > headEnd) throw new Error("head structure not found");
  meta.headTail = html.slice(lastScriptEnd, headEnd);
  if (!meta.headTail.startsWith("\n")) throw new Error("headTail does not start with newline");

  // <main>…</main>: between the header/footer markers, minus one \n\n pad each side.
  const body = html.slice(html.indexOf("<body>"));
  const startMark = "<!-- END:header -->";
  const endMark = "<!-- BEGIN:footer -->";
  const a = body.indexOf(startMark) + startMark.length;
  const b = body.indexOf(endMark);
  if (a < startMark.length || b < 0) throw new Error("chrome markers not found");
  const seg = body.slice(a, b);
  if (!seg.startsWith("\n\n") || !seg.endsWith("\n\n")) throw new Error("main padding mismatch");
  meta.mainHtml = seg.slice(2, -2);
  if (!meta.mainHtml.startsWith("  <main")) throw new Error("main does not start with '  <main'");
  if (!meta.mainHtml.endsWith("</main>")) throw new Error("main does not end with </main>");
  return meta;
}

function tsString(s) {
  // Emit as a template literal only if needed; JSON-escape is enough for all
  // our values (they contain no backticks; ${ cannot appear in escaped JSON).
  return JSON.stringify(s);
}

const pages = [];
for (const r of ROUTES) {
  const html = readFileSync(join(SITE, r.file), "utf8");
  pages.push([r, extract(html)]);
}
const postFiles = readdirSync(join(SITE, "blog")).filter((f) => f.endsWith(".html") && f !== "index.html").sort();
for (const f of postFiles) {
  const slug = f.replace(/\.html$/, "");
  const html = readFileSync(join(SITE, "blog", f), "utf8");
  pages.push([{ route: `/blog/${slug}`, name: `blog-${slug}` }, extract(html)]);
}

mkdirSync(join(OUT, "data"), { recursive: true });
mkdirSync(join(OUT, "content", "pages"), { recursive: true });
mkdirSync(join(OUT, "chrome"), { recursive: true });

let ts = `// GENERATED by scripts/extract-site-data.mjs — do not edit by hand.
// Head metadata + JSON-LD extracted verbatim from the rendered site/ pages
// (entities included; the layout re-emits these strings byte-for-byte).

export interface PageMeta {
  route: string;
  title: string;
  description: string;
  robots: string;
  ogType: string;
  ogImage: string;
  ogWidth: string;
  ogHeight: string;
  ogUrl: string;
  canonical: string;
  fontPreload: string | null;
  imagePreload: string | null;
  extraScripts: string[];
  headTail: string;
  contentFile: string;
}

export const PAGES: PageMeta[] = [
`;
for (const [r, m] of pages) {
  ts += `  {\n`;
  ts += `    route: ${tsString(r.route)},\n`;
  ts += `    title: ${tsString(m.title)},\n`;
  ts += `    description: ${tsString(m.description)},\n`;
  ts += `    robots: ${tsString(m.robots)},\n`;
  ts += `    ogType: ${tsString(m.ogType)},\n`;
  ts += `    ogImage: ${tsString(m.ogImage)},\n`;
  ts += `    ogWidth: ${tsString(m.ogWidth)},\n`;
  ts += `    ogHeight: ${tsString(m.ogHeight)},\n`;
  ts += `    ogUrl: ${tsString(m.ogUrl)},\n`;
  ts += `    canonical: ${tsString(m.canonical)},\n`;
  ts += `    fontPreload: ${m.fontPreload ? tsString(m.fontPreload) : "null"},\n`;
  ts += `    imagePreload: ${m.imagePreload ? tsString(m.imagePreload) : "null"},\n`;
  ts += `    extraScripts: ${JSON.stringify(m.extraScripts)},\n`;
  ts += `    headTail: ${JSON.stringify(m.headTail)},\n`;
  ts += `    contentFile: ${tsString(r.name)},\n`;
  ts += `  },\n`;
}
ts += `];\n`;
writeFileSync(join(OUT, "data", "pages.ts"), ts);

for (const [r, m] of pages) {
  writeFileSync(join(OUT, "content", "pages", `${r.name}.html`), m.mainHtml);
}

writeFileSync(join(OUT, "chrome", "header.html"),
  readFileSync(join(ROOT, ".orchestration", "landing", "02-header.html")));
writeFileSync(join(OUT, "chrome", "footer.html"),
  readFileSync(join(ROOT, ".orchestration", "landing", "12-footer.html")));

console.log(`extracted ${pages.length} pages (${postFiles.length} posts), chrome 2 fragments`);
