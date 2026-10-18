// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Static marketing site. HTML is minified at build time; pretty URLs use
// build.format 'preserve' (blog/index.astro -> blog/index.html,
// [slug].astro -> blog/<slug>.html) plus Netlify redirects.
//
// Tool landing pages (src/data/tools.ts, rendered by src/pages/[page].astro)
// get their own sitemap priority: they carry the commercial intent, so they
// rank above blog posts but below the home page. The slug list is duplicated
// here because the Astro config cannot import the app's TypeScript data;
// scripts/seo-audit.mjs fails the build check if a built page is missing
// from the sitemap, which keeps the two in sync.
const TOOL_ROUTES = [
  "/photo-cleaner",
  "/storage-cleaner",
  "/duplicate-photo-cleaner",
  "/similar-photo-cleaner",
  "/screenshot-cleaner",
  "/screen-recording-cleaner",
  "/chat-media-cleaner",
  "/blurry-photo-cleaner",
  "/large-file-cleaner",
  "/burst-photo-cleaner",
  "/live-photo-converter",
  "/video-compression",
  "/image-compression",
  "/photo-organizer",
  "/on-device-ai-photo-search",
  "/free-photo-cleaner-no-subscription",
];

// Language slugs, mirrored from src/data/languages.ts (the Astro config
// cannot import the site's TypeScript data). Localized landing pages carry
// the same commercial intent as "/", so they get the same priority.
const LANG_ROUTES = [
  '/hi', '/bn', '/ta', '/te', '/mr', '/gu', '/kn', '/ml', '/pa',
  '/es', '/fr', '/de', '/pt-br', '/it', '/ja', '/ko', '/zh-hans',
  '/ru', '/ar', '/he',
];

export default defineConfig({
  site: 'https://tidybyte.360ghar.com',
  output: 'static',
  compressHTML: true,
  trailingSlash: 'never',
  build: { format: 'preserve' },
  integrations: [
    sitemap({
      // Machine-readable alternates and the 404 page are not search content.
      filter: (page) => !/\/404\/?$/.test(page) && !/\.(txt|md)\/?$/.test(page),
      serialize(item) {
        const path = new URL(item.url).pathname;
        // Localized landing pages are the same page as "/" in another
        // language: same priority, and the hreflang block in the HTML is
        // what tells a crawler they are alternates rather than 21 pages
        // fighting for one query.
        if (path === '/' || LANG_ROUTES.includes(path)) {
          item.changefreq = 'weekly';
          item.priority = 1.0;
        } else if (TOOL_ROUTES.includes(path)) {
          item.changefreq = 'monthly';
          item.priority = 0.9;
        } else if (path === '/blog') {
          item.changefreq = 'weekly';
          item.priority = 0.8;
        } else if (path.startsWith('/blog/')) {
          item.changefreq = 'monthly';
          item.priority = 0.7;
        } else if (path === '/support') {
          item.changefreq = 'monthly';
          item.priority = 0.6;
        } else if (path === '/changelog') {
          item.changefreq = 'monthly';
          item.priority = 0.5;
        } else {
          item.changefreq = 'yearly';
          item.priority = 0.3;
        }
        return item;
      },
    }),
  ],
});
