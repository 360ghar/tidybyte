import type { APIRoute } from "astro";
import { TOOLS, toolBySlug, plain } from "../data/tools";
import { PAGES } from "../data/pages";
import {
  contentFor,
  htmlToMarkdown,
  plainDescription,
  plainTitle,
  stripBodyH1,
  urlFor,
} from "../lib/llms";
import { renderToolMarkdown } from "../lib/tool-page";

// Clean-Markdown alternate for every non-post page: /<slug>.md, and
// /index.md for the home page. Same purpose as the blog alternates: an AI
// citation fetcher can read one page without parsing HTML.
// llms.txt promises this for every URL it lists, and seo-audit.mjs checks it.
const CORE_SLUGS = ["index", "blog", "mac", "support", "privacy", "changelog"];

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
    // The source content carries its own H1, so the body's copy is stripped
    // below: the heading here is the page's real title, and two H1s in one
    // document is what the reviewer flagged.
    `# ${tool ? plain(tool.h1) : plainTitle(meta)}`,
    "",
    // Tool pages get their description, comparison table and FAQs from
    // `renderToolMarkdown`, which opens with the same `> description`
    // blockquote, so emitting it here as well printed it twice.
    ...(tool
      ? [renderToolMarkdown(slug), "", "## Full page text", ""]
      : [`> ${plainDescription(meta)}`, ""]),
    stripBodyH1(htmlToMarkdown(contentFor(route))),
    "",
    `Canonical URL: ${urlFor(route)}`,
    "",
  ].join("\n");
  return new Response(body, {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
};
