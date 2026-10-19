// Renderer for the tool landing pages (src/data/tools.ts).
//
// Each tool page is assembled from two halves:
//   - unique prose, authored in src/content/pages/tool-<slug>.html
//   - generated blocks (hero, quick answer, comparison table, trust strip,
//     FAQ, related links, CTA) built here from the tool definition
//
// The FAQ block is generated rather than authored so the visible questions
// and the FAQPage JSON-LD emitted by toolPageMeta() are always the same
// strings, which is what Google requires for FAQ rich results.
import { PAGES } from "../data/pages";
import { TOOLS, toolBySlug, plain, SCREENSHOT_SIZE, type Tool } from "../data/tools";

const APP_STORE = "https://apps.apple.com/in/app/tidybyte/id6775769763";

const contentFiles = import.meta.glob("../content/pages/*.html", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

const CHECK =
  '<svg aria-hidden="true" focusable="false" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" class="text-success"><path d="M5 12l5 5 9-11"/></svg>';

const APPLE_GLYPH =
  '<svg aria-hidden="true" focusable="false" width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M16.365 1.43c0 1.14-.46 2.23-1.21 3.05-.81.87-2.14 1.55-3.23 1.46-.14-1.1.4-2.25 1.16-3.04.85-.89 2.29-1.55 3.28-1.47Zm3.61 16.04c-.6 1.39-1.31 2.62-2.18 3.66-1.13 1.39-2.46 3.05-4.25 3.07-1.7.02-2.14-.99-4.46-.99-2.32 0-2.8 1.01-4.5.99-1.79-.02-3.15-1.6-4.28-2.99-2.6-3.2-4.59-9.05-1.92-12.99 1.32-1.95 3.69-3.18 6.25-3.22 1.78-.04 3.46 1.05 4.55 1.05 1.08 0 3.13-1.3 5.28-1.11.9.04 3.43.36 5.05 2.71-.13.08-3.02 1.76-2.99 5.25.04 4.17 3.66 5.55 3.45 5.57Z"/></svg>';

/** "2026-06-13T00:00:00Z" -> "June 13, 2026" */
function formatDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}

/** Blog card metadata pulled from the same page data the blog renders. */
function postCard(route: string): { title: string; date: string; image: string } | null {
  const meta = PAGES.find((p) => p.route === route);
  if (!meta) return null;
  const iso = meta.headTail.match(/"datePublished":\s*"([^"]+)"/)?.[1] ?? "";
  return {
    title: plain(meta.title.replace(/\s*\|\s*TidyByte\s*$/, "")),
    date: formatDate(iso),
    image: `/assets/img/blog/${route.slice("/blog/".length)}-card.webp`,
  };
}

function breadcrumb(t: Tool): string {
  const isHub = t.slug === "photo-cleaner";
  return (
    `<nav aria-label="Breadcrumb" class="container-prose mx-auto max-w-prose pt-6 text-sm">\n` +
    `  <ol class="flex flex-wrap items-center gap-1.5 text-muted">\n` +
    `    <li><a href="/" class="text-muted hover:text-ink hover:underline">Home</a></li>\n` +
    `    <li aria-hidden="true">/</li>\n` +
    (isHub
      ? `    <li><a href="/photo-cleaner" aria-current="page" class="text-ink">Photo cleaner</a></li>\n`
      : `    <li><a href="/photo-cleaner" class="text-muted hover:text-ink hover:underline">Photo cleaner</a></li>\n` +
        `    <li aria-hidden="true">/</li>\n` +
        `    <li aria-current="page" class="text-ink">${t.name}</li>\n`) +
    `  </ol>\n` +
    `</nav>\n`
  );
}

function hero(t: Tool): string {
  const isHub = t.slug === "photo-cleaner";
  return (
    `<section class="relative overflow-hidden">\n` +
    `  <div aria-hidden="true" class="absolute inset-x-0 -top-24 -z-10 h-[420px] bg-hero-glow"></div>\n` +
    `  <div class="container-prose grid items-center gap-12 pb-12 pt-10 sm:pt-14 lg:grid-cols-[1.05fr_0.95fr]">\n` +
    `    <div>\n` +
    `      <p class="badge">${t.badge}</p>\n` +
    `      <h1 class="h-display mt-4">${t.h1}</h1>\n` +
    `      <p class="lede mt-5 max-w-prose">${t.lede}</p>\n` +
    `      <div class="mt-7 flex flex-wrap items-center gap-3">\n` +
    `        <a href="${APP_STORE}" class="btn-primary" target="_blank" rel="noopener">${APPLE_GLYPH} Download TidyByte Free</a>\n` +
    (isHub
      ? `        <a href="/#how-it-works" class="btn-ghost">See how it works</a>\n`
      : `        <a href="/photo-cleaner" class="btn-ghost">All cleanup tools</a>\n`) +
    `      </div>\n` +
    `      <p class="mt-5 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted">\n` +
    `        <span class="inline-flex items-center gap-1.5">${CHECK}Free forever</span>\n` +
    `        <span class="inline-flex items-center gap-1.5">${CHECK}No ads, no subscription</span>\n` +
    `        <span class="inline-flex items-center gap-1.5">${CHECK}100% on-device</span>\n` +
    `      </p>\n` +
    `    </div>\n` +
    `    <figure class="mx-auto w-full max-w-[280px]">\n` +
    `      <div class="overflow-hidden rounded-[2rem] border border-hairline bg-surface-card shadow-pop">\n` +
    `        <picture>\n` +
    `          <source srcset="/assets/img/screenshots/${t.screenshot.name}-768.avif" type="image/avif">\n` +
    `          <img src="/assets/img/screenshots/${t.screenshot.name}-768.webp" alt="${t.screenshot.alt}" width="${SCREENSHOT_SIZE.w}" height="${SCREENSHOT_SIZE.h}" loading="eager" fetchpriority="high" decoding="async" class="block h-auto w-full">\n` +
    `        </picture>\n` +
    `      </div>\n` +
    `      <figcaption class="muted mt-3 text-center text-xs">${t.screenshot.caption}</figcaption>\n` +
    `    </figure>\n` +
    `  </div>\n` +
    `</section>\n`
  );
}

function quickAnswer(t: Tool): string {
  return (
    `<section class="container-prose mx-auto max-w-prose">\n` +
    `  <aside class="clay-card p-5 sm:p-6" data-quick-answer>\n` +
    `    <h2 class="font-display text-sm font-semibold uppercase tracking-[0.12em] text-muted">Quick answer</h2>\n` +
    `    <p class="mt-2 text-base leading-relaxed text-body sm:text-lg">${t.quickAnswer}</p>\n` +
    `  </aside>\n` +
    `</section>\n`
  );
}

function compareTable(t: Tool): string {
  const head = t.compare.columns
    .map(
      (c, i) =>
        `          <th scope="col" class="p-3 text-left align-bottom text-sm font-semibold ${i === 0 ? "text-ink" : "text-body"}">${c}</th>`,
    )
    .join("\n");
  const body = t.compare.rows
    .map((row) => {
      const cells = row.cells
        .map(
          (c, i) =>
            `            <td class="p-3 align-top text-sm ${i === 0 ? "font-medium text-ink" : "text-body"}">${c}</td>`,
        )
        .join("\n");
      return `        <tr>\n          <th scope="row" class="p-3 text-left align-top text-sm font-medium text-muted">${row.label}</th>\n${cells}\n        </tr>`;
    })
    .join("\n");
  return (
    `<section class="section pt-0">\n` +
    `  <div class="container-prose">\n` +
    `    <h2 class="h-section text-2xl sm:text-3xl">How it compares</h2>\n` +
    `    <div class="mt-6 overflow-x-auto rounded-2xl border border-hairline bg-surface-card">\n` +
    `      <table class="w-full min-w-[680px] border-collapse">\n` +
    `        <caption class="sr-only">${t.compare.caption}</caption>\n` +
    `        <thead class="border-b border-hairline bg-surface-soft">\n` +
    `        <tr>\n          <th scope="col" class="p-3 text-left align-bottom text-sm font-semibold text-muted">&nbsp;</th>\n${head}\n        </tr>\n` +
    `        </thead>\n` +
    `        <tbody class="divide-y divide-hairline">\n${body}\n        </tbody>\n` +
    `      </table>\n` +
    `    </div>\n` +
    `  </div>\n` +
    `</section>\n`
  );
}

function trustStrip(): string {
  const facts = [
    ["Free forever", "No subscription, no in-app purchases, no ads."],
    ["Private by design", "No account, no analytics SDK, no network requests at all."],
    ["On-device only", "Apple Vision and Photos do the work; nothing is uploaded."],
    ["Open source", "MIT licensed on GitHub, so every claim is auditable."],
  ];
  return (
    `<section class="section pt-0">\n` +
    `  <div class="container-prose">\n` +
    `    <ul role="list" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">\n` +
    facts
      .map(
        ([title, body]) =>
          `      <li class="clay-card p-5">\n` +
          `        <p class="inline-flex items-center gap-2 font-display text-base font-semibold text-ink">${CHECK}${title}</p>\n` +
          `        <p class="muted mt-2 text-sm">${body}</p>\n` +
          `      </li>`,
      )
      .join("\n") +
    `\n    </ul>\n` +
    `  </div>\n` +
    `</section>\n`
  );
}

function faqBlock(t: Tool): string {
  const items = t.faqs
    .map(
      (f) =>
        `      <details class="clay-card group p-5 sm:p-6">\n` +
        `        <summary class="faq-summary">\n` +
        `          <span>${f.q}</span>\n` +
        `          <svg aria-hidden="true" focusable="false" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" class="faq-chev"><path d="m6 9 6 6 6-6"/></svg>\n` +
        `        </summary>\n` +
        `        <p class="muted mt-4">${f.a}</p>\n` +
        `      </details>`,
    )
    .join("\n");
  return (
    `<section id="faq" class="section scroll-mt-24 pt-0">\n` +
    `  <div class="container-prose">\n` +
    `    <h2 class="h-section text-2xl sm:text-3xl">Frequently asked questions</h2>\n` +
    `    <div data-faq-accordion class="mx-auto mt-8 max-w-3xl space-y-3">\n${items}\n    </div>\n` +
    `  </div>\n` +
    `</section>\n`
  );
}

function toolsGrid(current: Tool): string {
  // Related tools first, then everything else: the pages closest in intent
  // get the strongest internal links without dropping the full tool set.
  const rest = TOOLS.filter(
    (t) => t.slug !== current.slug && !current.relatedTools.includes(t.slug),
  );
  const ordered = [
    ...current.relatedTools
      .map((slug) => TOOLS.find((t) => t.slug === slug))
      .filter((t): t is Tool => t !== undefined),
    ...rest,
  ];
  return (
    `<section class="section pt-0">\n` +
    `  <div class="container-prose">\n` +
    `    <h2 class="h-section text-2xl sm:text-3xl">Every cleanup tool, in one free app</h2>\n` +
    `    <ul role="list" class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">\n` +
    ordered
      .map(
        (t) =>
          `      <li>\n` +
          `        <a href="/${t.slug}" class="clay-card flex h-full flex-col p-5 transition hover:-translate-y-0.5 hover:shadow-pop">\n` +
          `          <p class="font-display text-base font-semibold text-ink">${t.name}</p>\n` +
          `          <p class="muted mt-2 text-sm">${plain(t.lede)}</p>\n` +
          `        </a>\n` +
          `      </li>`,
      )
      .join("\n") +
    `\n    </ul>\n` +
    `  </div>\n` +
    `</section>\n`
  );
}

interface PostCard {
  route: string;
  title: string;
  date: string;
  image: string;
}

function relatedPosts(t: Tool): string {
  // Keep the route alongside its card: filtering out an unresolved post must
  // not shift the remaining cards onto the wrong links.
  const cards = t.relatedPosts
    .map((route): PostCard | null => {
      const c = postCard(route);
      return c ? { route, ...c } : null;
    })
    .filter((c): c is PostCard => c !== null);
  if (cards.length === 0) return "";
  return (
    `<section class="section pt-0">\n` +
    `  <div class="container-prose">\n` +
    `    <h2 class="h-section text-2xl sm:text-3xl">Keep reading</h2>\n` +
    `    <div class="mt-6 grid gap-4 sm:grid-cols-3">\n` +
    cards
      .map(
        (c) =>
          `      <a href="${c.route}" class="clay-card group overflow-hidden transition hover:-translate-y-0.5 hover:shadow-pop">\n` +
          `        <img src="${c.image}" alt="" width="640" height="427" loading="lazy" decoding="async" class="block aspect-[3/2] h-auto w-full object-cover">\n` +
          `        <div class="p-4">\n` +
          `          <h3 class="font-display text-base font-medium leading-snug text-ink group-hover:underline">${c.title}</h3>\n` +
          `          <p class="muted mt-2 text-xs">${c.date}</p>\n` +
          `        </div>\n` +
          `      </a>`,
      )
      .join("\n") +
    `\n    </div>\n` +
    `  </div>\n` +
    `</section>\n`
  );
}

function finalCta(t: Tool): string {
  return (
    `<section class="section-tight">\n` +
    `  <div class="container-prose">\n` +
    `    <div class="relative overflow-hidden rounded-[2rem] bg-surface-soft p-8 text-center sm:p-12">\n` +
    `      <div class="relative z-10 mx-auto max-w-xl">\n` +
    `        <h2 class="h-display">${t.ctaHeading}</h2>\n` +
    `        <p class="lede mt-4">${t.ctaBody}</p>\n` +
    `        <div class="mt-7 flex flex-wrap items-center justify-center gap-3">\n` +
    `          <a href="${APP_STORE}" class="btn-primary" target="_blank" rel="noopener">${APPLE_GLYPH} Download TidyByte Free</a>\n` +
    `          <a href="/blog" class="btn-ghost">Read the cleanup guides</a>\n` +
    `        </div>\n` +
    `      </div>\n` +
    `    </div>\n` +
    `  </div>\n` +
    `</section>\n`
  );
}

/** Unique prose for the page, authored in src/content/pages/tool-<slug>.html. */
function toolProse(slug: string): string {
  const tool = toolBySlug(slug);
  if (!tool) throw new Error(`unknown tool slug ${slug}`);
  const key = `../content/pages/tool-${slug}.html`;
  const raw = contentFiles[key];
  if (!raw) throw new Error(`missing content file ${key}`);
  return raw.trimEnd();
}

/** Full <main> body for a tool route. */
export function renderToolMain(slug: string): string {
  const t = toolBySlug(slug);
  if (!t) throw new Error(`unknown tool slug ${slug}`);
  return (
    `  <main id="main">\n` +
    breadcrumb(t) +
    hero(t) +
    quickAnswer(t) +
    toolProse(slug) +
    `\n` +
    compareTable(t) +
    trustStrip() +
    faqBlock(t) +
    toolsGrid(t) +
    relatedPosts(t) +
    finalCta(t) +
    `  </main>`
  );
}

/** Markdown rendering of a tool page for /llms-full.txt and /<slug>.md. */
export function renderToolMarkdown(slug: string): string {
  const t = toolBySlug(slug);
  if (!t) throw new Error(`unknown tool slug ${slug}`);
  const lines: string[] = [];
  lines.push(`> ${plain(t.description)}`, "");
  lines.push(`## Quick answer`, "", plain(t.quickAnswer), "");
  lines.push(`## How it compares`, "", `| | ${t.compare.columns.join(" | ")} |`, `| --- | --- | --- | --- |`);
  for (const row of t.compare.rows) {
    lines.push(`| ${row.label} | ${row.cells.map(plain).join(" | ")} |`);
  }
  lines.push("", `## Frequently asked questions`, "");
  for (const f of t.faqs) {
    lines.push(`### ${plain(f.q)}`, "", plain(f.a), "");
  }
  return lines.join("\n");
}
