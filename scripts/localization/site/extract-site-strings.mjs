#!/usr/bin/env node
// Extracts the translatable strings from the English landing page.
//
// The landing page is HTML, so most of the file is markup: Tailwind classes,
// SVG paths, data attributes. Only text nodes and a handful of text-bearing
// attributes change between languages. Translating by hand-editing 20 copies of
// a 47 KB file invites structural drift, so this script pulls out the strings
// that actually need translating and `build-site-translations.mjs` puts them
// back into a copy of the English file.
//
// Run: node scripts/localization/site/extract-site-strings.mjs
// Out: scripts/localization/site/site-strings.json  { source, strings: [...] }

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { KEEP_LITERAL } from "./keep-literal.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..", "..");
const SOURCE = join(root, "src", "content", "pages", "index.html");

/// Attributes whose value is prose and must be translated.
const TEXT_ATTRIBUTES = ["alt", "title", "aria-label", "placeholder"];

/// True when a string is prose a human should translate.
function isTranslatable(text) {
  if (!text) return false;
  // A bare entity, punctuation or number carries no meaning to translate.
  if (!/[A-Za-z]/.test(text)) return false;
  // Every character is inside a tag-ish run, e.g. an inline SVG title.
  if (/^[&;\s\d.,:;·—–-]+$/.test(text)) return false;
  return true;
}

const html = readFileSync(SOURCE, "utf8");

// Comments hold notes for maintainers, not user-visible copy.
const body = html
  .replace(/<script[\s\S]*?<\/script>/g, "")
  .replace(/<style[\s\S]*?<\/style>/g, "")
  .replace(/<!--[\s\S]*?-->/g, "");

const found = new Set();

// Every inline tag is a hard boundary: `>([^<>]+)<` cannot see across an `<a>`,
// a `<strong>` or a `<span>`. A sentence that wraps a link therefore reaches a
// translator as fragments ("Open an issue on", "or use the contact form on the",
// "page."), and that is deliberate: keeping the markup out of the string is what
// lets the builder put translations back into the English page without parsing
// HTML, and it keeps a mistranslated href out of the map entirely.
//
// The cost is real and is not fixable here: fragments cannot be reordered, so an
// SOV language (Tamil, Telugu, Kannada, Malayalam) glues them back in English
// order and the sentence reads as translated English. Where word order matters,
// write the sentence as one full sentence inside a single text node instead of
// splitting it around a link.
for (const match of body.matchAll(/>([^<>]+)</g)) {
  const text = match[1].trim();
  if (isTranslatable(text)) found.add(text);
}

const attrPattern = new RegExp(
  `\\b(${TEXT_ATTRIBUTES.join("|")})="([^"]*)"`,
  "g",
);
for (const match of body.matchAll(attrPattern)) {
  const text = match[2].trim();
  if (isTranslatable(text)) found.add(text);
}

const strings = [...found].filter((text) => !KEEP_LITERAL.has(text)).sort();

mkdirSync(here, { recursive: true });
writeFileSync(
  join(here, "site-strings.json"),
  `${JSON.stringify({ source: "src/content/pages/index.html", strings }, null, 2)}\n`,
);

console.log(`site-strings.json: ${strings.length} strings`);
console.log(`  skipped ${KEEP_LITERAL.size} keep-literal entries`);

// --- Head metadata -------------------------------------------------------
//
// The title and description live in src/data/pages.ts, not in the HTML, so the
// body extract above cannot see them. They still need translating: a German
// page whose body is German but whose search-result title is English is a page
// that ranks for nothing, and 21 pages sharing one English title compete for a
// single snippet.
//
// Parsed with a regex rather than imported because pages.ts is TypeScript and
// this script is plain Node with no build step. Anchored on `route: "/"` so it
// cannot pick up a tool page's meta.

const PAGES = join(root, "src", "data", "pages.ts");
const pagesSource = readFileSync(PAGES, "utf8");

const homeIndex = pagesSource.indexOf('route: "/"');
if (homeIndex < 0) throw new Error(`no home entry (route: "/") in ${PAGES}`);

const homeBlock = pagesSource.slice(homeIndex, homeIndex + 900);
const field = (name) => {
  const match = homeBlock.match(new RegExp(`\\n\\s*${name}: "((?:[^"\\\\]|\\\\.)*)"`));
  if (!match) throw new Error(`no ${name} on the home entry in ${PAGES}`);
  return match[1];
};

const meta = { title: field("title"), description: field("description") };

writeFileSync(
  join(here, "site-meta.json"),
  `${JSON.stringify(
    {
      source: "src/data/pages.ts",
      limits: { title: 65, description: 165 },
      meta,
    },
    null,
    2,
  )}\n`,
);

console.log(`site-meta.json: title ${meta.title.length}/65, description ${meta.description.length}/165`);
