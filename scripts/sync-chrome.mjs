#!/usr/bin/env node
/**
 * sync-chrome.mjs — keep the header/footer identical across all 51 pages.
 *
 * The canonical chrome lives in .orchestration/landing/02-header.html and
 * 12-footer.html (single source of truth — no src/templates copy). Every
 * page carries <!-- BEGIN:header --> / <!-- END:header --> markers (emitted
 * by .orchestration/rebuild_site.py); this script replaces only the text
 * between the markers, so hand edits to page bodies are never touched.
 *
 * Subpages (everything except site/index.html) get the /#-prefixed variant:
 * the fragment's in-page anchors (#features, #how-it-works, #faq) would
 * otherwise resolve to /blog#features etc. and 404 the section.
 *
 * Usage: node scripts/sync-chrome.mjs [--check]
 *   --check: exit 1 if any page drifted (CI guard).
 */
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const LAND = join(ROOT, ".orchestration", "landing");
const SITE = join(ROOT, "site");
const CHECK = process.argv.includes("--check");

const headerFrag = readFileSync(join(LAND, "02-header.html"), "utf8");
const footerFrag = readFileSync(join(LAND, "12-footer.html"), "utf8");
// Homepage header/footer are exactly the fragments (byte-identical).
const homeHeader = headerFrag;
const subHeader = headerFrag.replace(/href="#(features|how-it-works|faq)"/g, 'href="/#$1"');

function pages() {
  const out = [];
  for (const dir of [SITE, join(SITE, "blog")]) {
    for (const f of readdirSync(dir)) {
      if (f.endsWith(".html")) out.push(join(dir, f));
    }
  }
  return out;
}

function swap(html, name, expected) {
  const re = new RegExp(`(<!-- BEGIN:${name} -->\\n)[\\s\\S]*?(<!-- END:${name} -->)`);
  if (!re.test(html)) {
    console.error(`MISSING markers: ${name}`);
    return { html, changed: "missing" };
  }
  const next = html.replace(re, `$1${expected}$2`);
  return { html: next, changed: next !== html ? "updated" : "clean" };
}

let dirty = 0;
let missing = 0;
for (const page of pages()) {
  const home = page === join(SITE, "index.html");
  let html = readFileSync(page, "utf8");
  const h = swap(html, "header", home ? homeHeader : subHeader);
  if (h.changed === "missing") { missing++; continue; }
  const f = swap(h.html, "footer", footerFrag);
  if (f.changed === "missing") { missing++; continue; }
  if (h.changed === "updated" || f.changed === "updated") {
    dirty++;
    if (CHECK) console.log(`DRIFT: ${page}`);
    else { writeFileSync(page, f.html); console.log(`synced ${page}`); }
  }
}
console.log(`${pages().length} pages checked${CHECK ? "" : `, ${dirty} synced`}`);
if (missing > 0) { console.error(`${missing} pages missing markers`); process.exit(1); }
if (CHECK && dirty > 0) { console.error("chrome drift detected"); process.exit(1); }
