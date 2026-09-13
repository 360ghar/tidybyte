// Shared helpers for the machine-readable routes:
//   /llms.txt, /llms-full.txt (src/pages/llms*.txt.ts)
//   /blog/<slug>.md            (src/pages/blog/[slug].md.ts)
//
// Text is derived from the same content files the HTML pages render, so
// it can never go stale. Header/footer chrome is excluded by construction
// (chrome lives outside the content files), keeping AI context clean.
import { PAGES, type PageMeta } from "../data/pages";

const contentFiles = import.meta.glob("../content/pages/*.html", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

const SITE = "https://tidybyte.360ghar.com";

export function contentFor(route: string): string {
  const meta = PAGES.find((p) => p.route === route);
  if (!meta) throw new Error(`no page meta for route ${route}`);
  const raw = contentFiles[`../content/pages/${meta.contentFile}.html`];
  if (!raw) throw new Error(`missing content file ${meta.contentFile}`);
  return raw;
}

export function decodeEntities(s: string): string {
  return s
    .replace(/&mdash;/g, "\u2014")
    .replace(/&ndash;/g, "\u2013")
    .replace(/&rsquo;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&rdquo;/g, '"')
    .replace(/&ldquo;/g, '"')
    .replace(/&quot;/g, '"')
    .replace(/&hellip;/g, "…")
    .replace(/&larr;/g, "←")
    .replace(/&gt;/g, ">")
    .replace(/&lt;/g, "<")
    .replace(/&amp;/g, "&")
    .replace(/&nbsp;/g, " ")
    .replace(/&middot;/g, "\u00b7")
    .replace(/&rarr;/g, "\u2192");
}

function absolutize(url: string): string {
  if (url.startsWith("http")) return url;
  if (url.startsWith("/")) return SITE + url;
  if (url.startsWith("#")) return url;
  return url;
}

/**
 * Minimal HTML-to-Markdown for article bodies. Keeps headings, paragraphs,
 * list items, and links; drops images, SVGs, scripts, and styling wrappers.
 */
export function htmlToMarkdown(html: string): string {
  let s = html;
  // Drop non-content subtrees: breadcrumbs, in-page TOC (anchor-only links),
  // figures/SVGs (images carry no text AI needs here).
  s = s.replace(/<nav aria-label="Breadcrumb"[\s\S]*?<\/nav>/g, "");
  s = s.replace(/<nav aria-labelledby="toc-h"[\s\S]*?<\/nav>/g, "");
  s = s.replace(/<figure[\s\S]*?<\/figure>/g, "");
  s = s.replace(/<svg[\s\S]*?<\/svg>/g, "");
  s = s.replace(/<picture[\s\S]*?<\/picture>/g, "");
  // Links -> [text](url) before tags are stripped.
  s = s.replace(
    /<a\s[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/g,
    (_m, href: string, text: string) => {
      const t = text.replace(/<[^>]+>/g, "").trim();
      if (!t) return "";
      if (href.startsWith("#")) return t;
      return `[${t}](${absolutize(href)})`;
    },
  );
  // Block structure.
  s = s.replace(/<h1[^>]*>([\s\S]*?)<\/h1>/g, "\n# $1\n");
  s = s.replace(/<h2[^>]*>([\s\S]*?)<\/h2>/g, "\n## $1\n");
  s = s.replace(/<h3[^>]*>([\s\S]*?)<\/h3>/g, "\n### $1\n");
  s = s.replace(/<\/p>/g, "\n\n");
  s = s.replace(/<br\s*\/?>/g, "\n");
  s = s.replace(/<li[^>]*>/g, "\n- ");
  // Tables -> pipe rows: `<tr>` opens a row, each cell adds a separator.
  // Source files indent table markup, so join cell boundaries first —
  // otherwise each cell lands on its own line.
  s = s.replace(/<\/(td|th)>\s+<(td|th)([^>]*)>/g, "</$1><$2$3>");
  s = s.replace(/<tr([^>]*)>\s+/g, "<tr$1>");
  s = s.replace(/\s+<\/(tr)>/g, "</$1>");
  s = s.replace(/<tr[^>]*>/g, "\n| ");
  s = s.replace(/<\/(th|td)>/g, " | ");
  s = s.replace(/<\/(li|ul|ol|section|div|article|aside|main|nav|figure|figcaption|details|summary|table|thead|tbody|tfoot|tr)>/g, "\n");
  s = s.replace(/<[^>]+>/g, "");
  s = decodeEntities(s);
  // Collapse runs of blank lines, trim each line, drop trailing pipes.
  s = s
    .split("\n")
    .map((l) =>
      l
        .trim()
        .replace(/ {2,}/g, " ")
        .replace(/\s+\|\s*$/, ""),
    )
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return s;
}

/** Absolute URL for a route (pretty URL form, matching canonical). */
export function urlFor(route: string): string {
  return route === "/" ? `${SITE}/` : `${SITE}${route}`;
}

export function blogPosts(): PageMeta[] {
  return PAGES.filter((p) => p.route.startsWith("/blog/")).sort((a, b) =>
    a.route.localeCompare(b.route),
  );
}

export function plainTitle(m: PageMeta): string {
  return decodeEntities(m.title.replace(/<[^>]+>/g, ""))
    .replace(/\s+/g, " ")
    .trim();
}

export function plainDescription(m: PageMeta): string {
  return decodeEntities(m.description.replace(/<[^>]+>/g, ""))
    .replace(/\s+/g, " ")
    .trim();
}
