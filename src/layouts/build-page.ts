// Page assembly for the TidyByte marketing site.
//
// Head metadata comes from src/data/pages.ts (extracted once from the
// original static site); <main> bodies live in src/content/pages/*.html.
// This module applies site-wide SEO/GEO/AEO rules at render time so the
// per-page data files stay dumb:
//
// - /404 is never indexed.
// - og:image dimensions match the real file (the 1024px app icon is square).
// - og:image:alt + twitter:image:alt on every page.
// - article:published_time / article:modified_time on blog posts.
// - LCP image preload matches the file the page actually renders
//   (AVIF-first <picture> heroes on home and blog posts).
// - Speakable JSON-LD on articles (voice assistants + answer engines).
// - A visible "Quick answer" box on blog posts derived from the meta
//   description, giving featured-snippet and AI-citation extractors a
//   40-60 word direct answer near the top of the page.
import headerRaw from "../chrome/header.html?raw";
import footerRaw from "../chrome/footer.html?raw";
import { PAGES, type PageMeta } from "../data/pages";

const contentFiles = import.meta.glob("../content/pages/*.html", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

// Ported verbatim from rebuild_site.py SKIP_LINK.
const SKIP_LINK =
  '<a href="#main" class="sr-only focus:not-sr-only focus:fixed focus:left-3 ' +
  "focus:top-3 focus:z-50 focus:rounded-full focus:bg-primary focus:px-3 " +
  "focus:py-1.5 focus:text-sm focus:font-semibold focus:text-on-primary\">" +
  "Skip to content</a>";

const ICON_OG = "https://tidybyte.360ghar.com/assets/img/icon-1024.png";

/** Decode the small set of entities used in titles/descriptions. */
function decodeEntities(s: string): string {
  return s
    .replace(/&mdash;/g, " — ")
    .replace(/&ndash;/g, " – ")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&rdquo;/g, '"')
    .replace(/&ldquo;/g, '"')
    .replace(/&amp;/g, "&")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Pull datePublished/dateModified out of the Article JSON-LD block. */
function articleDates(m: PageMeta): { published: string | null; modified: string | null } {
  const pub = m.headTail.match(/"datePublished":\s*"([^"]+)"/)?.[1] ?? null;
  const mod = m.headTail.match(/"dateModified":\s*"([^"]+)"/)?.[1] ?? null;
  return { published: pub, modified: mod };
}

/**
 * LCP preload for the page's hero image. Must match the file the rendered
 * <img>/<picture> actually fetches, otherwise the preload is wasted.
 */
function imagePreloadTag(m: PageMeta): string | null {
  if (m.route === "/") {
    // Home hero is an AVIF-first <picture> (see src/content/pages/index.html);
    // AVIF is the LCP resource in every evergreen browser. Preload matches
    // by URL, so a plain href preload feeds the <source> request.
    return `  <link rel="preload" as="image" href="/assets/img/illustrations/hero-cleanup.avif" type="image/avif" fetchpriority="high">`;
  }
  if (m.route.startsWith("/blog/")) {
    // Blog heroes are AVIF-first <picture> blocks; AVIF is supported by all
    // evergreen browsers, so it is the LCP resource in practice.
    const slug = m.route.slice("/blog/".length);
    return `  <link rel="preload" as="image" href="/assets/img/blog/${slug}.avif" type="image/avif" fetchpriority="high">`;
  }
  return null;
}

/** Speakable block for answer engines: TL;DR + quick-answer selectors. */
function speakableScript(m: PageMeta): string {
  return (
    `\n  <!-- Structured Data: Speakable -->\n` +
    `  <script type="application/ld+json">\n` +
    `  {\n` +
    `    "@context": "https://schema.org",\n` +
    `    "@type": "WebPage",\n` +
    `    "@id": "${m.canonical}#webpage",\n` +
    `    "url": "${m.canonical}",\n` +
    `    "speakableSpecification": {\n` +
    `      "@type": "SpeakableSpecification",\n` +
    `      "cssSelector": ["[data-quick-answer]", ".lede"]\n` +
    `    }\n` +
    `  }\n` +
    `  </script>\n`
  );
}

function buildHead(m: PageMeta): string {
  // /404 must never appear in search results.
  const robots = m.route === "/404" ? "noindex, follow" : m.robots;
  // The app icon is square; several pages declared it as 1024x630.
  const ogWidth = m.ogImage === ICON_OG ? "1024" : m.ogWidth;
  const ogHeight = m.ogImage === ICON_OG ? "1024" : m.ogHeight;
  const ogAlt = decodeEntities(m.title);
  const { published, modified } = articleDates(m);

  const lines = [
    "<!doctype html>",
    '<html lang="en">',
    "<head>",
    '  <meta charset="utf-8">',
    `  <title>${m.title}</title>`,
    `  <meta name="description" content="${m.description}">`,
    '  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
    '  <meta name="theme-color" content="#fffaf0">',
    `  <meta name="robots" content="${robots}">`,
    '  <meta name="author" content="TidyByte">',
    "",
    `  <meta property="og:type" content="${m.ogType}">`,
    '  <meta property="og:site_name" content="TidyByte">',
    '  <meta property="og:locale" content="en_US">',
    `  <meta property="og:title" content="${m.title}">`,
    `  <meta property="og:description" content="${m.description}">`,
    `  <meta property="og:image" content="${m.ogImage}">`,
    `  <meta property="og:image:width" content="${ogWidth}">`,
    `  <meta property="og:image:height" content="${ogHeight}">`,
    `  <meta property="og:image:alt" content="${ogAlt}">`,
    `  <meta property="og:url" content="${m.ogUrl}">`,
    "",
    '  <meta name="twitter:card" content="summary_large_image">',
    `  <meta name="twitter:title" content="${m.title}">`,
    `  <meta name="twitter:description" content="${m.description}">`,
    `  <meta name="twitter:image" content="${m.ogImage}">`,
    `  <meta name="twitter:image:alt" content="${ogAlt}">`,
    "",
    '  <link rel="icon" type="image/png" sizes="32x32" href="/assets/img/favicon-32.png">',
    '  <link rel="apple-touch-icon" href="/assets/img/apple-touch-icon.png">',
    `  <link rel="canonical" href="${m.canonical}">`,
  ];
  if (published) {
    lines.push(`  <meta property="article:published_time" content="${published}">`);
  }
  if (modified) {
    lines.push(`  <meta property="article:modified_time" content="${modified}">`);
  }
  if (m.fontPreload) {
    lines.push(
      `  <link rel="preload" href="${m.fontPreload}" as="font" type="font/woff2" crossorigin>`,
    );
  }
  const heroPreload = imagePreloadTag(m);
  if (heroPreload) {
    lines.push(heroPreload);
  }
  lines.push('  <link rel="stylesheet" href="/assets/css/styles.css">');
  lines.push('  <script src="/assets/js/theme.js"></script>');
  lines.push('  <script src="/assets/js/nav.js" defer></script>');
  lines.push('  <script src="/assets/js/site.js" defer></script>');
  for (const s of m.extraScripts) {
    lines.push(`  <script src="${s}" defer></script>`);
  }
  // JSON-LD region from the data file, plus Speakable for articles.
  const tail =
    m.ogType === "article" ? m.headTail + speakableScript(m) : m.headTail;
  return lines.join("\n") + tail + "</head>";
}

/**
 * Visible "Quick answer" box injected after the hero <figure> on blog
 * posts. Featured snippets, voice assistants, and AI citations all prefer
 * a short direct answer near the top; the meta description already is one.
 */
function injectQuickAnswer(mainHtml: string, m: PageMeta): string {
  if (!m.route.startsWith("/blog/")) return mainHtml;
  if (mainHtml.includes("data-quick-answer")) return mainHtml;
  const box =
    `  <aside class="clay-card mt-8 p-5 sm:p-6" data-quick-answer>\n` +
    `    <h2 class="font-display text-sm font-semibold uppercase tracking-[0.12em] text-muted">Quick answer</h2>\n` +
    `    <p class="mt-2 text-base leading-relaxed text-body sm:text-lg">${m.description}</p>\n` +
    `  </aside>\n`;
  const marker = "</figure>";
  const i = mainHtml.indexOf(marker);
  if (i < 0) return mainHtml;
  return mainHtml.slice(0, i + marker.length) + "\n\n" + box + mainHtml.slice(i + marker.length);
}

/** Port of chrome_wrap(). Subpages get /#-prefixed section anchors. */
function chromeWrap(bodyMain: string, home: boolean): string {
  let header = headerRaw;
  if (!home) {
    header = header.replace(/href="#(features|how-it-works|faq)"/g, 'href="/#$1"');
  }
  return (
    `${SKIP_LINK}\n` +
    `<!-- BEGIN:header -->\n${header}<!-- END:header -->\n\n` +
    `${bodyMain}\n\n` +
    `<!-- BEGIN:footer -->\n${footerRaw}<!-- END:footer -->\n`
  );
}

export function buildPage(m: PageMeta, mainHtml: string, home = false): string {
  return (
    buildHead(m) +
    "\n\n<body>\n" +
    chromeWrap(mainHtml, home) +
    "\n\n</body>\n</html>\n"
  );
}

/** Assemble the final document for a route from the extracted content. */
export function renderRoute(route: string, home = false): string {
  const meta = PAGES.find((p) => p.route === route);
  if (!meta) throw new Error(`no page meta for route ${route}`);
  const key = `../content/pages/${meta.contentFile}.html`;
  const raw = contentFiles[key];
  if (!raw) throw new Error(`missing content file ${key}`);
  const main = injectQuickAnswer(raw, meta);
  return buildPage(meta, main, home);
}
