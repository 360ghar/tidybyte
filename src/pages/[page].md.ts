import type { APIRoute } from "astro";
import { TOOLS, toolBySlug, plain } from "../data/tools";
import { PAGES } from "../data/pages";
import {
  contentFor,
  htmlToMarkdown,
  plainDescription,
  plainTitle,
  urlFor,
} from "../lib/llms";
import { renderToolMarkdown } from "../lib/tool-page";

// Clean-Markdown alternate for every non-post page: /<slug>.md, and
// /index.md for the home page. Same purpose as the blog alternates: an AI
// citation fetcher can read one page without parsing HTML.
// llms.txt promises this for every URL it lists, and seo-audit.mjs checks it.
const CORE_SLUGS = ["index", "blog", "support", "privacy", "changelog"];

export function getStaticPaths() {
  return [
    ...TOOLS.map((t) => ({ params: { page: t.slug } })),
    ...CORE_SLUGS.map((page) => ({ params: { page } })),
  ];
}

export const GET: APIRoute = ({ params }) => {
  const slug = params.page as string;
  const route = slug === "index" ? "/" : `/${slug}`;
  const meta = PAGES.find((p) => p.route === route);
  if (!meta) return new Response("Not found", { status: 404 });
  const tool = toolBySlug(slug);
  const body = [
    // The document's H1 should match the page's visible H1. For tools that is
    // the keyword H1, not the SEO title (which carries a "| TidyByte" suffix).
    `# ${tool ? plain(tool.h1) : plainTitle(meta)}`,
    "",
    `> ${plainDescription(meta)}`,
    "",
    // Tool pages get their comparison table and FAQs rendered from the same
    // source the HTML uses, so the two can never drift apart.
    ...(tool ? [renderToolMarkdown(slug), "", "## Full page text", ""] : []),
    htmlToMarkdown(contentFor(route)),
    "",
    `Canonical URL: ${urlFor(route)}`,
    "",
  ].join("\n");
  return new Response(body, {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
};
