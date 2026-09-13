// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Static marketing site. HTML is minified at build time; pretty URLs use
// build.format 'preserve' (blog/index.astro -> blog/index.html,
// [slug].astro -> blog/<slug>.html) plus Netlify redirects.
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
        if (path === '/') {
          item.changefreq = 'weekly';
          item.priority = 1.0;
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
