#!/usr/bin/env node
/**
 * hash-assets.mjs — content-hash the site's CSS/JS and rewrite references.
 *
 * Why: netlify.toml serves /assets/* as immutable for a year. The CSS/JS
 * ship at fixed URLs, so without hashed filenames returning visitors keep
 * stale CSS/JS after a deploy.
 *
 * What it does (runs on dist/ at the end of `npm run build`):
 *   1. Hashes dist/assets/css/styles.css + dist/assets/js/{theme,nav,site,blog}.js
 *      (sha256, first 8 hex chars) and writes sibling copies, e.g.
 *      styles.3fa9c1e2.css. Stale hashed copies are deleted.
 *   2. Rewrites the references in all 51 HTML files. Idempotent: the regex
 *      matches both the fixed name and any previous hash.
 *
 * dist/ is a build output and is never committed.
 *
 * Usage: node scripts/hash-assets.mjs [--check]
 *   --check: fail if any asset reference points at a missing file.
 */
import { createHash } from "node:crypto";
import { readdirSync, readFileSync, writeFileSync, unlinkSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SITE = join(ROOT, "dist");
const CHECK = process.argv.includes("--check");

// [source file, url base without extension, extension]
const ASSETS = [
  ["assets/css/styles.css", "/assets/css/styles", ".css"],
  ["assets/js/theme.js", "/assets/js/theme", ".js"],
  ["assets/js/nav.js", "/assets/js/nav", ".js"],
  ["assets/js/site.js", "/assets/js/site", ".js"],
  ["assets/js/blog.js", "/assets/js/blog", ".js"],
];

function hashFile(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex").slice(0, 8);
}

function htmlFiles() {
  const out = [];
  for (const dir of [SITE, join(SITE, "blog")]) {
    if (!existsSync(dir)) continue;
    for (const f of readdirSync(dir)) {
      if (f.endsWith(".html")) out.push(join(dir, f));
    }
  }
  return out;
}

let failed = false;

if (!existsSync(SITE)) {
  console.error("dist/ not found — run `npm run build` first.");
  process.exit(1);
}

// 1. Hash (skip in --check; still validate below).
const renamed = new Map(); // url base -> hashed url
if (!CHECK) {
  for (const [rel, base, ext] of ASSETS) {
    const src = join(SITE, rel);
    if (!existsSync(src)) {
      console.error(`MISSING source (run tailwind first?): ${rel}`);
      failed = true;
      continue;
    }
    const hash = hashFile(src);
    const dir = join(SITE, dirname(rel));
    const stem = rel.split("/").pop().replace(ext, "");
    // Delete stale hashes of this asset, keep the fixed file + current hash.
    for (const f of readdirSync(dir)) {
      if (f.startsWith(stem + ".") && f.endsWith(ext) && f !== stem + ext && f !== `${stem}.${hash}${ext}`) {
        unlinkSync(join(dir, f));
        console.log(`rm ${rel.replace(stem + ext, f)}`);
      }
    }
    const hashedName = `${stem}.${hash}${ext}`;
    writeFileSync(join(dir, hashedName), readFileSync(src));
    renamed.set(base, `${base}.${hash}${ext}`);
    console.log(`${rel} -> ${dirname(rel)}/${hashedName}`);
  }
  if (failed) process.exit(1);

  // 2. Rewrite references (idempotent).
  const pages = htmlFiles();
  let touched = 0;
  for (const page of pages) {
    let html = readFileSync(page, "utf8");
    const before = html;
    for (const [base, hashed] of renamed) {
      const ext = hashed.slice(hashed.lastIndexOf("."));
      const re = new RegExp(`(${base.replace(/\//g, "\\/")})(?:\\.[0-9a-f]{8})?\\${ext}`, "g");
      html = html.replace(re, hashed);
    }
    if (html !== before) {
      writeFileSync(page, html);
      touched++;
    }
  }
  console.log(`rewrote refs in ${touched}/${pages.length} pages`);
}

// 3. Validate: every asset ref resolves to a file on disk.
const pages = htmlFiles();
for (const page of pages) {
  const html = readFileSync(page, "utf8");
  for (const m of html.matchAll(/"(?:\/assets\/(?:css|js)\/[^"]+)"/g)) {
    const url = m[0].slice(1, -1).split("?")[0].split("#")[0];
    if (!existsSync(join(SITE, url))) {
      console.error(`BROKEN ref in ${page}: ${url}`);
      failed = true;
    }
  }
}
if (failed) {
  console.error(CHECK ? "--check FAILED" : "hash-assets FAILED");
  process.exit(1);
}
console.log(CHECK ? `--check OK (${pages.length} pages)` : "all refs resolve");
