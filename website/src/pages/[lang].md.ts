import type { APIRoute } from "astro";
import { SITE_LANGUAGES, languageBySlug } from "../data/languages";
import { localizedHomeContent, localizedHomeMeta } from "../lib/localized-page";
import { htmlToMarkdown, plainDescription, plainTitle, stripBodyH1 } from "../lib/llms";

// Clean-Markdown alternate for a localized landing page: /de.md beside /de,
// the same pattern as /photo-cleaner.md. seo-audit.mjs requires a Markdown
// file for every URL in the sitemap, and llms.txt promises one per page, so
// a language without it would fail the check.
export function getStaticPaths() {
  return SITE_LANGUAGES.map((l) => ({ params: { lang: l.slug } }));
}

export const GET: APIRoute = ({ params }) => {
  const lang = languageBySlug(params.lang as string);
  if (!lang) return new Response("Not found", { status: 404 });
  const meta = localizedHomeMeta(lang);
  const body = [
    `# ${plainTitle(meta)}`,
    "",
    `> ${plainDescription(meta)}`,
    "",
    stripBodyH1(htmlToMarkdown(localizedHomeContent(lang))),
    "",
    `Canonical URL: ${meta.canonical}`,
    "",
  ].join("\n");
  return new Response(body, {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
};
