import type { APIRoute } from "astro";
import { PAGES } from "../data/pages";
import {
  blogPosts,
  contentFor,
  htmlToMarkdown,
  plainDescription,
  plainTitle,
  urlFor,
} from "../lib/llms";

// Complete machine-readable site text. Content only — no header/footer
// chrome — regenerated every build from the same files the HTML renders.
export const GET: APIRoute = () => {
  const sections: string[] = [
    "# TidyByte — Full Site Content",
    "",
    "Download on the App Store: https://apps.apple.com/in/app/tidybyte/id6775769763",
    "",
  ];
  const top = PAGES.filter((p) => !p.route.startsWith("/blog/") && p.route !== "/404");
  for (const p of top) {
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
