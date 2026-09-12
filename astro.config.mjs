// @ts-check
import { defineConfig } from 'astro/config';

// Zero-drift port of the Netlify static site. Output must match the
// previously generated site/ byte-for-byte (modulo asset hashes), so:
// - compressHTML: false    → Astro must not collapse authored whitespace
// - build.format:preserve' → blog/index.astro emits blog/index.html and
//   [slug].astro emits blog/<slug>.html, matching the baseline tree
export default defineConfig({
  site: 'https://tidybyte.360ghar.com',
  output: 'static',
  compressHTML: false,
  trailingSlash: 'never',
  build: { format: 'preserve' },
});
