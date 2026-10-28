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
// - A BreadcrumbList block on any route whose data file does not define
//   one, so every page states its position in the site hierarchy.
// - Localized landing pages (/de, /ja, /pt-br …) render the same page as /
//   through this same path: `<html lang>` and `dir` follow the language,
//   og:locale follows it too, and every translated route emits `hreflang`
//   alternates so the 21 copies do not compete for one query.
// - Tool landing pages (src/data/tools.ts) are assembled by
//   src/lib/tool-page.ts and rendered through this same head/chrome path.
import headerRaw from "../chrome/header.html?raw";
import footerRaw from "../chrome/footer.html?raw";
import { PAGES, type PageMeta } from "../data/pages";
import { TOOL_ROUTES } from "../data/tools";
import {
  ALL_LANGUAGES,
  BASE_LANGUAGE,
  TRANSLATED_ROUTES,
  type SiteLanguage,
} from "../data/languages";
import {
  baseRoute,
  languageForRoute,
  localizedHomeContent,
  localizedHomeMeta,
  urlForRoute,
} from "../lib/localized-page";
import { renderToolMain } from "../lib/tool-page";

const contentFiles = import.meta.glob("../content/pages/*.html", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

// Ported from rebuild_site.py SKIP_LINK. The inset is logical (`start-3`) so
// the skip link stays in the reading-start corner on the RTL pages.
const SKIP_LINK =
  '<a href="#main" class="sr-only focus:not-sr-only focus:fixed focus:start-3 ' +
  "focus:top-3 focus:z-50 focus:rounded-full focus:bg-primary focus:px-3 " +
  "focus:py-1.5 focus:text-sm focus:font-semibold focus:text-on-primary\">" +
  "Skip to content</a>";

const ICON_OG = "https://tidybyte.360ghar.com/assets/img/icon-1024.png";

/** Placeholder an author drops where the quick-answer box should render. */
const MARKER = "<!-- quick-answer -->";

/** Placeholder in src/chrome/header.html where the language switcher renders. */
const LANG_SWITCHER_MARKER = "<!-- lang-switcher -->";

/** Decode the small set of entities used in titles/descriptions. */
function decodeEntities(s: string): string {
  return s
    .replace(/&mdash;/g, " — ")
    .replace(/&ndash;/g, " – ")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&rdquo;/g, '"')
    .replace(/&ldquo;/g, '"')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
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
  // baseRoute() so /de preloads the same hero as / — it renders the same
  // markup, and without this the localized pages would each ship a hero
  // with no preload.
  if (baseRoute(m.route) === "/") {
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

/**
 * BreadcrumbList for routes whose data file does not carry one (blog posts
 * and the tool pages already do). Blog posts sit under /blog; every other
 * page is one level below the home page. The trail matches the visible
 * breadcrumbs the pages render.
 */
function breadcrumbScript(m: PageMeta): string {
  const name =
    decodeEntities(m.title)
      .replace(/\s*[—–|-]\s*TidyByte\s*$/i, "")
      .trim() || "TidyByte";
  const items: { name: string; url: string }[] = [
    { name: "Home", url: "https://tidybyte.360ghar.com/" },
  ];
  if (m.route.startsWith("/blog/")) {
    items.push({ name: "Blog", url: "https://tidybyte.360ghar.com/blog" });
  }
  items.push({ name, url: m.canonical });
  const body = items
    .map(
      (it, i) =>
        `      {\n        "@type": "ListItem",\n        "position": ${i + 1},\n        "name": ${JSON.stringify(it.name)},\n        "item": "${it.url}"\n      }`,
    )
    .join(",\n");
  return (
    `\n  <!-- Structured Data: BreadcrumbList -->\n` +
    `  <script type="application/ld+json">\n` +
    `  {\n` +
    `    "@context": "https://schema.org",\n` +
    `    "@type": "BreadcrumbList",\n` +
    `    "itemListElement": [\n${body}\n    ]\n` +
    `  }\n` +
    `  </script>\n`
  );
}

/**
 * `hreflang` alternates for a route that exists in more than one language.
 *
 * This is what keeps 21 near-identical landing pages from competing with
 * each other: every copy states where its siblings live and which language
 * they are in, so a search engine serves the one the visitor can read.
 * `x-default` points at English, the copy someone whose language has no
 * translation should land on.
 *
 * Emitted only for routes in TRANSLATED_ROUTES. Claiming an alternate that
 * 404s is a search-engine penalty, and the blog is English-only.
 */
function hreflangTags(route: string): string[] {
  const base = baseRoute(route);
  if (!TRANSLATED_ROUTES.includes(base)) return [];
  return [
    ...ALL_LANGUAGES.map(
      (l) => `  <link rel="alternate" hreflang="${l.htmlLang}" href="${urlForRoute(l, base)}">`,
    ),
    `  <link rel="alternate" hreflang="x-default" href="${urlForRoute(BASE_LANGUAGE, base)}">`,
  ];
}

/**
 * og:locale for the page plus og:locale:alternate for the other languages
 * it exists in. Social cards have no hreflang, so the locale pair is the
 * only thing telling a crawler these pages are the same page in another
 * language.
 */
function ogLocaleTags(lang: SiteLanguage, route: string): string[] {
  const lines = [`  <meta property="og:locale" content="${lang.ogLocale}">`];
  if (TRANSLATED_ROUTES.includes(baseRoute(route))) {
    for (const l of ALL_LANGUAGES) {
      if (l.code === lang.code) continue;
      lines.push(`  <meta property="og:locale:alternate" content="${l.ogLocale}">`);
    }
  }
  return lines;
}

function buildHead(m: PageMeta, lang: SiteLanguage): string {
  // /404 must never appear in search results.
  const robots = m.route === "/404" ? "noindex, follow" : m.robots;
  // The app icon is square; several pages declared it as 1024x630.
  const ogWidth = m.ogImage === ICON_OG ? "1024" : m.ogWidth;
  const ogHeight = m.ogImage === ICON_OG ? "1024" : m.ogHeight;
  const ogAlt = decodeEntities(m.title);
  const { published, modified } = articleDates(m);

  const lines = [
    "<!doctype html>",
    // `lang` is what a screen reader reads the page aloud in and what a
    // search engine files the page under; `dir` mirrors the layout for
    // Arabic and Hebrew.
    `<html lang="${lang.htmlLang}"${lang.rtl ? ' dir="rtl"' : ""}>`,
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
    ...ogLocaleTags(lang, m.route),
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
    ...hreflangTags(m.route),
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
  // JSON-LD region from the data file, plus Speakable for articles and a
  // BreadcrumbList for any route that does not already define one.
  let tail =
    m.ogType === "article" ? m.headTail + speakableScript(m) : m.headTail;
  // Speakable for the remaining content pages (home, support, privacy,
  // changelog, blog hub). Blog posts get it above; tool pages declare their
  // own inside the WebPage block, so they are skipped here to avoid a second
  // WebPage entity with the same @id.
  if (
    m.route !== "/404" &&
    m.ogType !== "article" &&
    !m.headTail.includes("SpeakableSpecification")
  ) {
    tail += speakableScript(m);
  }
  // A localized landing page (/de) is the home page of that language, so it
  // gets no breadcrumb either: a trail leading back to an English page the
  // visitor cannot read is worse than no trail.
  if (
    !TRANSLATED_ROUTES.includes(baseRoute(m.route)) &&
    m.route !== "/404" &&
    !m.headTail.includes("BreadcrumbList")
  ) {
    tail += breadcrumbScript(m);
  }
  return lines.join("\n") + tail + "</head>";
}

/**
 * Visible "Quick answer" box. Featured snippets, voice assistants, and AI
 * citations all prefer a short direct answer near the top; the meta
 * description already is one, so it is reused verbatim.
 *
 * Placement is decided by an explicit marker, in this order:
 *   1. `<!-- quick-answer -->` in the content file, if the author placed one
 *   2. `</figure>`  — blog posts (under the hero image)
 *   3. `</header>`  — pages with a header block (support, privacy, changelog)
 * If none is present the box is skipped; scripts/seo-audit.mjs fails the
 * check when an indexable page ends up without one.
 */
function injectQuickAnswer(mainHtml: string, m: PageMeta): string {
  if (m.route === "/404") return mainHtml;
  if (mainHtml.includes("data-quick-answer")) return mainHtml;
  const box =
    `  <aside class="clay-card mt-8 p-5 sm:p-6" data-quick-answer>\n` +
    `    <h2 class="font-display text-sm font-semibold uppercase tracking-[0.12em] text-muted">Quick answer</h2>\n` +
    `    <p class="mt-2 text-base leading-relaxed text-body sm:text-lg">${m.description}</p>\n` +
    `  </aside>\n`;
  if (mainHtml.includes(MARKER)) {
    return mainHtml.replace(MARKER, box.trimEnd());
  }
  const fallback = m.route.startsWith("/blog/") ? "</figure>" : "</header>";
  const i = mainHtml.indexOf(fallback);
  if (i < 0) return mainHtml;
  return (
    mainHtml.slice(0, i + fallback.length) +
    "\n\n" +
    box +
    mainHtml.slice(i + fallback.length)
  );
}

/**
 * Language switcher markup, injected into the header where the placeholder
 * `<!-- lang-switcher -->` sits.
 *
 * Every language is listed by its endonym: someone who cannot read the page
 * they are on still has to recognise their own language in the list, and
 * "German" does not do that for a German speaker. Each link also carries
 * `lang`, so a screen reader switches voice for the endonym instead of
 * reading Devanagari with an English phoneme set.
 *
 * A native <details> disclosure opens with no JS. The panel is positioned
 * with a logical inset and the rows align with `text-start`, so it mirrors
 * on its own under RTL. It anchors to the header's control group rather than
 * to the button (see src/chrome/header.html): on a phone the button sits
 * well inside the viewport, and a 21-language panel hung off it would run
 * off the screen edge.
 */
function languageSwitcher(current: SiteLanguage): string {
  const item = (l: SiteLanguage) => {
    const isCurrent = l.code === current.code;
    return (
      `<li>` +
      `<a href="${urlForRoute(l, "/")}" hreflang="${l.htmlLang}" lang="${l.htmlLang}"` +
      (isCurrent ? ' aria-current="true"' : "") +
      ` class="flex items-center gap-2 rounded-lg px-3 py-1.5 text-start text-sm transition hover:bg-canvas focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-clay-pink/50 ${isCurrent ? "font-semibold text-ink" : "text-body"}">` +
      `<span>${l.endonym}</span>` +
      (isCurrent
        ? '<span aria-hidden="true" class="ms-auto h-1.5 w-1.5 rounded-full bg-clay-pink"></span>'
        : "") +
      `</a>` +
      `</li>`
    );
  };
  return (
    `<details class="lang-menu">\n` +
    `  <summary class="icon-btn inline-flex h-9 items-center justify-center gap-1.5 rounded-full px-2 text-body transition hover:bg-surface-card hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-clay-pink/50" aria-label="Language — ${current.endonym}">\n` +
    `    <svg aria-hidden="true" focusable="false" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18a15 15 0 0 1 0-18"/></svg>\n` +
    `    <span lang="${current.htmlLang}" class="hidden text-xs font-semibold sm:inline">${current.endonym}</span>\n` +
    `    <svg aria-hidden="true" focusable="false" class="hidden sm:block" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>\n` +
    `  </summary>\n` +
    `  <div class="absolute end-0 top-11 z-50 max-h-[70vh] w-56 overflow-y-auto rounded-xl border border-hairline bg-surface-card p-1 shadow-pop">\n` +
    `    <p id="lang-menu-label" class="px-3 py-1.5 text-xs font-semibold uppercase tracking-[0.12em] text-muted">Language</p>\n` +
    `    <ul aria-labelledby="lang-menu-label">\n      ` +
    ALL_LANGUAGES.map(item).join("\n      ") +
    `\n    </ul>\n` +
    `  </div>\n` +
    `</details>`
  );
}

/** Port of chrome_wrap(). Subpages get /#-prefixed section anchors. */
function chromeWrap(bodyMain: string, home: boolean, lang: SiteLanguage): string {
  let header = headerRaw;
  if (!home) {
    header = header.replace(/href="#(features|how-it-works|faq)"/g, 'href="/#$1"');
  }
  // Which language is current is per-page state, so the switcher is built
  // here rather than frozen into the shared header markup.
  header = header.replace(LANG_SWITCHER_MARKER, languageSwitcher(lang));
  return (
    `${SKIP_LINK}\n` +
    `<!-- BEGIN:header -->\n${header}<!-- END:header -->\n\n` +
    `${bodyMain}\n\n` +
    `<!-- BEGIN:footer -->\n${footerRaw}<!-- END:footer -->\n`
  );
}

export function buildPage(
  m: PageMeta,
  mainHtml: string,
  options: { home?: boolean; language?: SiteLanguage } = {},
): string {
  const lang = options.language ?? BASE_LANGUAGE;
  return (
    buildHead(m, lang) +
    "\n\n<body>\n" +
    chromeWrap(mainHtml, options.home ?? false, lang) +
    "\n\n</body>\n</html>\n"
  );
}

/** Assemble the final document for a route from the extracted content. */
export function renderRoute(route: string, home = false): string {
  const lang = languageForRoute(route);
  // A localized landing page is the same page as `/` — same body shape,
  // same in-page anchors — in another language. Its meta is derived, and
  // `home` is forced true so the header anchors stay in-page.
  if (lang && lang.slug) {
    const meta = localizedHomeMeta(lang);
    const main = injectQuickAnswer(localizedHomeContent(lang), meta);
    return buildPage(meta, main, { home: true, language: lang });
  }
  const meta = PAGES.find((p) => p.route === route);
  if (!meta) throw new Error(`no page meta for route ${route}`);
  // Tool landing pages build their own <main>; everything else renders the
  // authored content file.
  if (TOOL_ROUTES.includes(route)) {
    return buildPage(meta, renderToolMain(route.slice(1)), { language: lang ?? BASE_LANGUAGE });
  }
  const key = `../content/pages/${meta.contentFile}.html`;
  const raw = contentFiles[key];
  if (!raw) throw new Error(`missing content file ${key}`);
  const main = injectQuickAnswer(raw, meta);
  return buildPage(meta, main, { home, language: lang ?? BASE_LANGUAGE });
}
