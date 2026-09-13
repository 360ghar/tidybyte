import type { APIRoute } from "astro";
import { PAGES } from "../../data/pages";
import {
  blogPosts,
  contentFor,
  htmlToMarkdown,
  plainDescription,
  plainTitle,
  urlFor,
} from "../../lib/llms";

// Clean-Markdown alternate for each blog post: /blog/<slug>.md.
// Lets AI citations fetchers read one post without scraping HTML.
export function getStaticPaths() {
  return blogPosts().map((p) => ({
    params: { slug: p.route.slice("/blog/".length) },
  }));
}

export const GET: APIRoute = ({ params }) => {
  const route = `/blog/${params.slug}`;
  const meta = PAGES.find((p) => p.route === route);
  if (!meta) return new Response("Not found", { status: 404 });
  const body = [
    `# ${plainTitle(meta)}`,
    "",
    `> ${plainDescription(meta)}`,
    "",
    `Canonical URL: ${urlFor(route)}`,
    "",
    htmlToMarkdown(contentFor(route)),
    "",
  ].join("\n");
  return new Response(body, {
    headers: { "Content-Type": "text/markdown; charset=utf-8" },
  });
};
