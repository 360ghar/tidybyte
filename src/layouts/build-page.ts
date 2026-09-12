// Byte-exact port of .orchestration/rebuild_site.py's build_head() +
// chrome_wrap() + page assembly, fed with verbatim-extracted content
// (scripts/extract-site-data.mjs). Everything here must stay line-for-line
// compatible with the previously generated site/ output — the parity
// harness (scripts/verify-parity.mjs) fails on any byte drift.
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

/**
 * Port of build_head(). Note: jsonld blocks are emitted after an empty
 * line, each prefixed with "\n" — matching the original keep_jsonld
 * blocks' leading newline (produces the double blank line on disk).
 */
function buildHead(m: PageMeta): string {
  const lines = [
    "<!doctype html>",
    '<html lang="en">',
    "<head>",
    '  <meta charset="utf-8">',
    `  <title>${m.title}</title>`,
    `  <meta name="description" content="${m.description}">`,
    '  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
    '  <meta name="theme-color" content="#fffaf0">',
    `  <meta name="robots" content="${m.robots}">`,
    '  <meta name="author" content="TidyByte">',
    "",
    `  <meta property="og:type" content="${m.ogType}">`,
    '  <meta property="og:site_name" content="TidyByte">',
    '  <meta property="og:locale" content="en_US">',
    `  <meta property="og:title" content="${m.title}">`,
    `  <meta property="og:description" content="${m.description}">`,
    `  <meta property="og:image" content="${m.ogImage}">`,
    `  <meta property="og:image:width" content="${m.ogWidth}">`,
    `  <meta property="og:image:height" content="${m.ogHeight}">`,
    `  <meta property="og:url" content="${m.ogUrl}">`,
    "",
    '  <meta name="twitter:card" content="summary_large_image">',
    `  <meta name="twitter:title" content="${m.title}">`,
    `  <meta name="twitter:description" content="${m.description}">`,
    `  <meta name="twitter:image" content="${m.ogImage}">`,
    "",
    '  <link rel="icon" type="image/png" sizes="32x32" href="/assets/img/favicon-32.png">',
    '  <link rel="apple-touch-icon" href="/assets/img/apple-touch-icon.png">',
    `  <link rel="canonical" href="${m.canonical}">`,
  ];
  if (m.fontPreload) {
    lines.push(
      `  <link rel="preload" href="${m.fontPreload}" as="font" type="font/woff2" crossorigin>`,
    );
  }
  if (m.imagePreload) {
    // build_home inserted the hero preload before the stylesheet line.
    lines.push(`  <link rel="preload" as="image" href="${m.imagePreload}" type="image/avif">`);
  }
  lines.push('  <link rel="stylesheet" href="/assets/css/styles.css">');
  lines.push('  <script src="/assets/js/theme.js"></script>');
  lines.push('  <script src="/assets/js/nav.js" defer></script>');
  lines.push('  <script src="/assets/js/site.js" defer></script>');
  for (const s of m.extraScripts) {
    lines.push(`  <script src="${s}" defer></script>`);
  }
  // JSON-LD region captured verbatim from the source page (exact blank-line
  // spacing around Structured Data blocks varies by block type).
  return lines.join("\n") + m.headTail + "</head>";
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
  const main = contentFiles[key];
  if (!main) throw new Error(`missing content file ${key}`);
  return buildPage(meta, main, home);
}
