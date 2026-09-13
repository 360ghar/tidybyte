import type { APIRoute } from "astro";
import { PAGES } from "../data/pages";
import {
  blogPosts,
  plainDescription,
  plainTitle,
  urlFor,
} from "../lib/llms";

// Short machine-readable index. Points AI crawlers at the full text and
// the per-post Markdown routes. Regenerated every build from page data.
export const GET: APIRoute = () => {
  const top = PAGES.filter((p) => !p.route.startsWith("/blog/") && p.route !== "/404");
  const posts = blogPosts();
  const body = [
    "# TidyByte",
    "",
    "> Free iOS app that lets you swipe to delete junk photos, find duplicates, compress videos, and clean up your photo library — all 100% on-device, no account required.",
    "",
    "TidyByte is a free, open-source iPhone photo cleanup app (iOS 17+). It uses a Tinder-style swipe interface to let users quickly review and delete unwanted photos. It also includes smart cleanup tools for duplicates, similar photos, blurry shots, screenshots, large files, burst photos, Live Photos, and video/photo compression, plus an Activity & Savings history that tracks lifetime space freed. A Home Screen widget and Siri shortcuts jump straight into a cleanup. All processing uses Apple's Photos and Vision frameworks — no data ever leaves the device. There are no ads, no subscriptions, no in-app purchases, and no third-party dependencies.",
    "",
    "## Key Facts",
    "",
    "- Price: Free forever, no in-app purchases, no subscriptions",
    "- Platform: iPhone and iPad (iOS 17+), universal app",
    "- Privacy: 100% on-device processing, no analytics SDK, no backend, no tracking",
    "- Architecture: Built with Swift/SwiftUI, Apple frameworks only, no third-party dependencies",
    "- Extras: Home Screen widget (small + medium, with interactive buttons), Siri & Shortcuts intents, weekly cleanup reminders",
    "- License: MIT open source",
    "- Repository: https://github.com/360ghar/snap-clean-ios",
    "- Download: https://apps.apple.com/in/app/tidybyte/id6775769763",
    "",
    "Full site text: https://tidybyte.360ghar.com/llms-full.txt",
    "Each blog post is also available as clean Markdown at <post-url>.md",
    "",
    "## Pages",
    "",
    ...top.map((p) => `- [${plainTitle(p)}](${urlFor(p.route)}): ${plainDescription(p)}`),
    "",
    "## Blog",
    "",
    `${posts.length} in-depth guides on iPhone photo cleanup:`,
    "",
    ...posts.map((p) => `- [${plainTitle(p)}](${urlFor(p.route)}): ${plainDescription(p)}`),
    "## Optional",
    "",
    "- [GitHub Repository](https://github.com/360ghar/snap-clean-ios): Source code, issues, and contributions",
    "",
  ].join("\n");
  return new Response(body, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};
