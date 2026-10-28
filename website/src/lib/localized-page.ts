// Localized landing pages.
//
// Only the landing page is translated (TRANSLATED_ROUTES in
// src/data/languages.ts), and its head metadata is large — three JSON-LD
// entities and a FAQ block — so a localized page derives its meta from the
// English home entry instead of duplicating it 20 times. Pages.ts stays the
// single source for the entity graph; this module overrides only what
// belongs to the URL: canonical, og:url, the language the page declares,
// and (until real translations land) the title and description.
import type { PageMeta } from "../data/page-meta";
import { PAGES } from "../data/pages";
import { BASE_LANGUAGE, SITE_LANGUAGES, type SiteLanguage } from "../data/languages";
import { decodeEntities } from "./llms";

const SITE = "https://tidybyte.360ghar.com";

// Budgets scripts/seo-audit.mjs enforces: past them a search engine
// truncates the title and drops the description.
const TITLE_MAX = 65;
const DESCRIPTION_MAX = 165;

const contentFiles = import.meta.glob("../content/pages/*.html", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

/**
 * Translated `<title>` and `<meta name="description">`, one file per language.
 *
 * Kept beside the body translations under `scripts/localization/site/` rather
 * than in `src/`, because that directory is the pipeline's own and these files
 * are its input, not hand-written source. Missing files are tolerated: a
 * language whose meta has not been translated yet falls back to the tagged
 * English title instead of failing the build.
 */
const metaFiles = import.meta.glob(
  "../../scripts/localization/site/site-translations/*.meta.json",
  { import: "default", eager: true },
) as Record<string, { title: string; description: string }>;

/** Slug parsed out of a glob key such as `…/de.meta.json`. */
function metaForSlug(slug: string): { title: string; description: string } | undefined {
  const entry = Object.entries(metaFiles).find(([path]) =>
    path.endsWith(`/${slug}.meta.json`),
  );
  return entry?.[1];
}

/**
 * The FAQ question/answer pairs as they appear in a page body.
 *
 * Anchored on the `faq-summary` class rather than on the `<details>` element so
 * an unrelated disclosure elsewhere on the page cannot be picked up as a
 * question.
 */
function faqPairs(body: string): { question: string; answer: string }[] {
  const pattern =
    /<summary class="faq-summary">\s*<span>([\s\S]*?)<\/span>[\s\S]*?<\/summary>\s*<p class="muted mt-4">([\s\S]*?)<\/p>/g;
  return [...body.matchAll(pattern)].map((match) => ({
    // Tags first, then entities: an answer can carry inline links, and
    // `structured data` wants the sentence, not the anchor. Replacing the tag
    // with nothing rather than a space keeps "TidyByte</a>." from becoming
    // "TidyByte .".
    question: decodeEntities(match[1].replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim(),
    answer: decodeEntities(match[2].replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim(),
  }));
}

/** How many questions the English FAQ declares. */
function englishFaqCount(): number {
  return (homeMeta().headTail.match(/"@type": "Question"/g) ?? []).length;
}

/**
 * Rewrites the FAQPage JSON-LD to describe the page's own FAQ.
 *
 * The inherited block is English. Google requires FAQ structured data to match
 * what a reader can see, and the audit enforces it, so a translated page whose
 * schema still held the English questions would both fail the build and be
 * ineligible for the rich result.
 *
 * Rebuilt from the visible text rather than translated a second time: one
 * source for the question, so the schema cannot drift from the page.
 */
function withLocalizedFaq(headTail: string, body: string): string {
  const pairs = faqPairs(body);
  const expected = englishFaqCount();
  if (pairs.length !== expected) {
    throw new Error(
      `parsed ${pairs.length} FAQ pair(s) from the page body but the English FAQ declares ${expected} — the FAQ markup changed and the structured data would silently lose questions`,
    );
  }

  const json = JSON.stringify(
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      "@id": "https://tidybyte.360ghar.com/#faq",
      mainEntity: pairs.map(({ question, answer }) => ({
        "@type": "Question",
        name: question,
        acceptedAnswer: { "@type": "Answer", text: answer },
      })),
    },
    null,
    2,
  );

  const block = [
    "<!-- Structured Data: FAQPage (mirrors the visible FAQ on this page) -->",
    '  <script type="application/ld+json">',
    json
      .split("\n")
      .map((line) => `  ${line}`)
      .join("\n"),
    "  </script>",
  ].join("\n  ");

  return headTail.replace(
    /<!-- Structured Data: FAQPage[\s\S]*?<\/script>/,
    block,
  );
}

/** The English home entry every localized landing page is derived from. */
export function homeMeta(): PageMeta {
  const meta = PAGES.find((p) => p.route === "/");
  if (!meta) throw new Error("no page meta for /");
  return meta;
}

/**
 * Language that owns a route, or undefined when the route is English-only.
 * `/` is the base language; `/de` and `/pt-br` are its localized copies.
 * Anything deeper (`/blog/x`) is never translated today.
 */
export function languageForRoute(route: string): SiteLanguage | undefined {
  if (route === "/") return BASE_LANGUAGE;
  const slug = route.slice(1);
  if (!slug || slug.includes("/")) return undefined;
  return SITE_LANGUAGES.find((l) => l.slug === slug);
}

/**
 * The route as it exists in the base language, so `/de` maps back to `/`.
 * Used to key TRANSLATED_ROUTES and to recognise a localized home page as
 * a home page (it gets no breadcrumb, and it preloads the home hero).
 */
export function baseRoute(route: string): string {
  const lang = languageForRoute(route);
  return lang && lang.slug ? "/" : route;
}

/** Absolute URL of a route in one language, with no trailing slash. */
export function urlForRoute(lang: SiteLanguage, route: string): string {
  if (!lang.slug) return `${SITE}${route}`;
  return `${SITE}/${lang.slug}${route === "/" ? "" : route}`;
}

/**
 * Title or description with the language appended, for pages whose copy is
 * still English.
 *
 * Without the tag every language would share one title and one
 * description, and 21 pages competing for a single snippet is exactly what
 * hreflang exists to prevent — the audit rejects the duplicates outright.
 * The tag doubles as the visible "this file still needs translating" flag.
 *
 * It falls back to the BCP-47 code when the endonym does not fit:
 * "Português (Brasil)" costs 20 characters and would push both fields past
 * their budget, while "pt-BR" costs 7.
 */
function withLanguageTag(base: string, lang: SiteLanguage, max: number): string {
  const tagged = `${base} (${lang.endonym})`;
  return decodeEntities(tagged).length <= max ? tagged : `${base} (${lang.htmlLang})`;
}

/** Head metadata for `/de`, `/ja`, `/pt-br` … derived from the English home. */
export function localizedHomeMeta(lang: SiteLanguage): PageMeta {
  const base = homeMeta();
  const route = `/${lang.slug}`;
  // A translated title and description when they exist, the tagged English
  // otherwise. Falling back rather than throwing keeps a partially translated
  // set buildable — the same posture the body takes, except the body's
  // fallback is impossible by construction.
  const meta = metaForSlug(lang.slug);
  return {
    ...base,
    route,
    title: meta?.title ?? withLanguageTag(base.title, lang, TITLE_MAX),
    description: meta?.description ?? withLanguageTag(base.description, lang, DESCRIPTION_MAX),
    ogUrl: `${SITE}${route}`,
    canonical: `${SITE}${route}`,
    contentFile: `index.${lang.slug}`,
    // The JSON-LD entity graph is language-neutral apart from the language
    // each block declares, so only that field is rewritten. The @ids stay
    // English-rooted: they describe one app and one site, not 21. The FAQ is
    // the exception — it describes this page's own visible text, so it is
    // rebuilt from the body.
    headTail: withLocalizedFaq(
      base.headTail.replace(
        /"inLanguage": "en"/g,
        `"inLanguage": "${lang.htmlLang}"`,
      ),
      localizedHomeContent(lang),
    ),
  };
}

/**
 * `<main>` body for a localized landing page: the language's own copy of
 * src/content/pages/index.html. Falls back to nothing and throws loudly —
 * a missing file would otherwise render an English body under a `lang`
 * attribute that claims otherwise, which is worse than a failed build.
 */
export function localizedHomeContent(lang: SiteLanguage): string {
  const key = `../content/pages/index.${lang.slug}.html`;
  const raw = contentFiles[key];
  if (!raw) {
    throw new Error(
      `missing content file ${key} — copy src/content/pages/index.html to it and translate`,
    );
  }
  return raw;
}
