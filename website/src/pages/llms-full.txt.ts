import type { APIRoute } from "astro";
import { PAGES } from "../data/pages";
import { TOOLS } from "../data/tools";
import {
  blogPosts,
  contentFor,
  htmlToMarkdown,
  plainDescription,
  plainTitle,
  urlFor,
} from "../lib/llms";
import { renderToolMarkdown } from "../lib/tool-page";

// Complete machine-readable site text. Content only — no header/footer
// chrome — regenerated every build from the same files the HTML renders.
export const GET: APIRoute = () => {
  const sections: string[] = [
    "# TidyByte — Full Site Content",
    "",
    "Free iPhone storage cleaner, photo cleaner and image compressor. 100% on-device, no ads, no subscription, no account, MIT open source.",
    "",
    "Download on the App Store: https://apps.apple.com/in/app/tidybyte/id6775769763",
    "",
  ];
  const core = PAGES.filter(
    (p) =>
      !p.route.startsWith("/blog/") &&
      p.route !== "/404" &&
      !TOOLS.some((t) => p.route === `/${t.slug}`),
  );
  for (const p of core) {
    sections.push(
      `## ${plainTitle(p)}`,
      `URL: ${urlFor(p.route)}`,
      "",
      htmlToMarkdown(contentFor(p.route)),
      "",
      "---",
      "",
    );
  }
  // Tool landing pages: structured blocks (quick answer, comparison, FAQ)
  // first, then the authored prose, so an extractor gets the direct answer
  // before the long copy.
  for (const t of TOOLS) {
    const route = `/${t.slug}`;
    sections.push(
      `## ${t.name} — ${urlFor(route)}`,
      "",
      renderToolMarkdown(t.slug),
      "",
      "### Full page text",
      "",
      htmlToMarkdown(contentFor(route)),
      "",
      "---",
      "",
    );
  }
  for (const p of blogPosts()) {
    sections.push(
      `## ${plainTitle(p)}`,
      `URL: ${urlFor(p.route)}`,
      `Markdown: ${urlFor(p.route)}.md`,
      "",
      plainDescription(p),
      "",
      htmlToMarkdown(contentFor(p.route)),
      "",
      "---",
      "",
    );
  }
  return new Response(sections.join("\n"), {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};
