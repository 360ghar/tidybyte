#!/usr/bin/env node
// Builds the 20 localized landing pages from the English original plus the
// per-language string maps produced by the translation batches.
//
// Translating by hand-editing 20 copies of a 47 KB HTML file invites structural
// drift — a dropped `class`, a mangled SVG path, a stray `</div>`. This script
// takes the English file as the structural source of truth and replaces only
// the text that differs, so every localized page is guaranteed to have the same
// markup as the page the design was built and reviewed against.
//
// Run: node scripts/localization/site/build-site-translations.mjs
// In:  src/content/pages/index.html
//      scripts/localization/site/site-translations/<slug>.json
// Out: src/content/pages/index.<slug>.html

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { isKeepLiteral } from "./keep-literal.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const SOURCE = join(root, "src", "content", "pages", "index.html");
const TRANSLATIONS = join(here, "site-translations");

/// Attributes whose value is prose. Mirrors extract-site-strings.mjs.
const TEXT_ATTRIBUTES = ["alt", "title", "aria-label", "placeholder"];

/// Regions that must pass through untouched: a translation map can contain a
/// string that also appears inside a script or a comment, and replacing there
/// would corrupt code or a maintainer note.
const OPAQUE = /(<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<!--[\s\S]*?-->)/g;

const PLACEHOLDER_MARKER = /^<!-- PLACEHOLDER COPY[\s\S]*?-->\s*\n?/m;

/// Replaces every translatable text node and attribute in one chunk of markup.
///
/// A string that is not in the map is only a problem if it *should* have been
/// translated. Keep-literal strings (`Photos`, `GitHub`, the version) are absent
/// from every map by design, so they pass through without being reported.
function translateChunk(chunk, map, stats) {
  let out = chunk.replace(/>([^<>]+)</g, (match, text) => {
    const key = text.trim();
    if (!key || !(key in map)) {
      if (key && /[A-Za-z]/.test(key) && !isKeepLiteral(key)) stats.unmatched.add(key);
      return match;
    }
    stats.replaced.add(key);
    // Preserve the surrounding whitespace the source had, so indentation and
    // inline spacing survive.
    const leading = text.slice(0, text.length - text.trimStart().length);
    const trailing = text.slice(text.trimEnd().length);
    return `>${leading}${map[key]}${trailing}<`;
  });

  const attrPattern = new RegExp(`\\b(${TEXT_ATTRIBUTES.join("|")})="([^"]*)"`, "g");
  out = out.replace(attrPattern, (match, attr, value) => {
    const key = value.trim();
    if (!key || !(key in map)) {
      // Recorded exactly like the text-node branch above. Without this an
      // untranslated `alt`, `title`, `aria-label` or `placeholder` left the
      // English string on a page that declares another language and the build
      // stayed green, because `unmatched` is the only failure path.
      if (key && /[A-Za-z]/.test(key) && !isKeepLiteral(key)) stats.unmatched.add(key);
      return match;
    }
    stats.replaced.add(key);
    return `${attr}="${map[key]}"`;
  });

  return out;
}

/// Builds one page from one translation file.
///
/// `file` is the basename exactly as it is on disk (`pt-BR.json`,
/// `zh-Hans.json`), because the read has to survive Linux's case-sensitive
/// filesystem. The OUTPUT name is the lowercased slug, and that is
/// load-bearing rather than cosmetic: every consumer of the generated page is
/// lowercase. `src/data/languages.ts` keys the routes `pt-br` / `zh-hans`,
/// `src/lib/localized-page.ts` imports `index.${lang.slug}.html`, and the
/// tracked files are lowercase. Writing `index.pt-BR.html` happens to read
/// correctly on macOS/APFS (case-insensitive, so the write lands on the tracked
/// inode) and silently creates a duplicate on Linux CI, where the tracked page
/// then goes stale. `git diff` cannot see the duplicate because it is untracked.
function buildOne(file) {
  const map = JSON.parse(readFileSync(join(TRANSLATIONS, file), "utf8"));
  const slug = file.replace(/\.json$/, "").toLowerCase();
  const source = readFileSync(SOURCE, "utf8");
  const stats = { replaced: new Set(), unmatched: new Set() };

  const chunks = source.replace(PLACEHOLDER_MARKER, "").split(OPAQUE);
  const body = chunks
    .map((chunk, index) => (index % 2 === 1 ? chunk : translateChunk(chunk, map, stats)))
    .join("");

  // A key the page never uses means the map has drifted from the English file —
  // usually a copy that was reworded on one side only.
  const unused = Object.keys(map).filter((key) => !stats.replaced.has(key));

  writeFileSync(join(root, "src", "content", "pages", `index.${slug}.html`), body);

  return { slug, replaced: stats.replaced.size, unused, unmatched: [...stats.unmatched] };
}

if (!existsSync(TRANSLATIONS)) {
  console.error(`no translations directory: ${TRANSLATIONS}`);
  process.exit(1);
}

const files = readdirSync(TRANSLATIONS)
  // `*.meta.json` holds the title and description for a page, not the body
  // strings. Without excluding it the slug parses as `ar.meta` and the builder
  // writes a bogus `index.ar.meta.html` alongside the real page.
  .filter((name) => name.endsWith(".json") && !name.endsWith(".meta.json"))
  .sort();

if (files.length === 0) {
  console.error("no translation files found");
  process.exit(1);
}

let failed = false;

for (const file of files) {
  const result = buildOne(file);
  const notes = [];
  if (result.unused.length) notes.push(`${result.unused.length} unused key(s)`);
  if (result.unmatched.length) notes.push(`${result.unmatched.length} untranslated string(s)`);

  const status = notes.length ? `  ${notes.join(", ")}` : "";
  console.log(`index.${result.slug}.html: ${result.replaced} strings replaced${status}`);

  for (const key of result.unused) console.log(`    unused:      ${key.slice(0, 78)}`);
  for (const key of result.unmatched) console.log(`    untranslated: ${key.slice(0, 78)}`);

  // An unmatched English string would ship as English inside a page that
  // declares another language, which is the exact failure this pipeline exists
  // to prevent.
  if (result.unmatched.length) failed = true;
}

console.log(`\n${files.length} localized page(s) written`);
if (failed) {
  console.error("FAIL: some strings had no translation");
  process.exit(1);
}
