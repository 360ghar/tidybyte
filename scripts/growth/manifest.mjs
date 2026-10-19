#!/usr/bin/env node
/**
 * manifest.mjs — the five App Store growth surfaces, their assets, and the copy
 * each one renders.
 *
 * This is the single source of truth for the growth pipeline. `build-assets.mjs`
 * renders from it, `check-assets.mjs` validates against it, and the CI gate reads
 * the same table, so an asset cannot ship at a size Apple rejects or in a
 * language the app does not support.
 *
 * ## Why the copy is pulled from what already exists
 *
 * Every string here resolves from one of two already-translated sources:
 *
 *   - `Tidybyte/Resources/Localizable.xcstrings` — 778 keys in 20 languages,
 *     the app's own UI wording.
 *   - `docs/appstore/listings.json` — the App Store listing fields, also in 20
 *     languages.
 *
 * Nothing is newly translated for marketing. That is deliberate: Apple requires
 * text in a creative asset to be localized for every language the app supports,
 * and a second, parallel translation of the same ideas would drift from the app.
 * Pulling from the catalog means the asset says exactly what the screen behind
 * it says, in the words the app already uses.
 *
 * When a surface needs copy that does not exist yet, add the key to the app's
 * own catalog and translate it there. Do not inline it here.
 */

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const CATALOG_PATH = join(ROOT, 'Tidybyte/Resources/Localizable.xcstrings');
const LISTINGS_PATH = join(ROOT, 'docs/appstore/listings.json');
const SHORTCUTS_PATH = join(ROOT, 'Tidybyte/Resources/AppShortcuts.xcstrings');

/**
 * Every non-art input a render reads.
 *
 * `build-assets.mjs` compares a cached PNG's mtime against the newest of these
 * plus the asset's own art, so editing the String Catalog, the listing data, or
 * this file (which carries the plan, the layouts and the font stacks) re-renders
 * instead of reporting the image "unchanged".
 */
export const RENDER_SOURCE_PATHS = [
  CATALOG_PATH,
  LISTINGS_PATH,
  SHORTCUTS_PATH,
  fileURLToPath(import.meta.url),
];

/** Must match `scripts/localization/plural-categories.mjs`. */
export const LANGUAGES = [
  'en', 'hi', 'bn', 'ta', 'te', 'mr', 'gu', 'kn', 'ml', 'pa',
  'es', 'fr', 'de', 'pt-BR', 'it', 'ja', 'ko', 'zh-Hans', 'ru', 'ar', 'he',
];

/**
 * Per-script font stacks for the text layer.
 *
 * Latin ships as `fredoka-var-latin.woff2`, which is the brand face and only
 * covers Latin. Everything else falls through to a macOS system face named
 * explicitly, because the generic `sans-serif` fallback picks a font with
 * incomplete shaping for several Indic scripts — conjuncts render as dotted
 * circles rather than joined glyphs.
 *
 * These are the fonts the App Store review team's own machine will have, so the
 * asset renders the way a native reader expects.
 */
export const FONT_STACKS = {
  en: "'Fredoka', -apple-system, 'Helvetica Neue', sans-serif",
  es: "'Fredoka', -apple-system, 'Helvetica Neue', sans-serif",
  fr: "'Fredoka', -apple-system, 'Helvetica Neue', sans-serif",
  de: "'Fredoka', -apple-system, 'Helvetica Neue', sans-serif",
  it: "'Fredoka', -apple-system, 'Helvetica Neue', sans-serif",
  'pt-BR': "'Fredoka', -apple-system, 'Helvetica Neue', sans-serif",
  ru: "'Fredoka', 'Helvetica Neue', -apple-system, sans-serif",
  hi: "'Kohinoor Devanagari', 'Devanagari Sangam MN', -apple-system, sans-serif",
  mr: "'Kohinoor Devanagari', 'Devanagari Sangam MN', -apple-system, sans-serif",
  bn: "'Bangla Sangam MN', 'Kohinoor Bangla', -apple-system, sans-serif",
  ta: "'Tamil Sangam MN', 'InaiMathi', -apple-system, sans-serif",
  te: "'Telugu Sangam MN', 'Kohinoor Telugu', -apple-system, sans-serif",
  gu: "'Gujarati Sangam MN', 'Kohinoor Gujarati', -apple-system, sans-serif",
  kn: "'Kannada Sangam MN', 'Kohinoor Kannada', -apple-system, sans-serif",
  ml: "'Malayalam Sangam MN', 'Kohinoor Malayalam', -apple-system, sans-serif",
  pa: "'Gurmukhi MN', 'Gurmukhi Sangam MN', -apple-system, sans-serif",
  ar: "'Geeza Pro', 'Al Bayan', -apple-system, sans-serif",
  he: "'Arial Hebrew', 'Lucida Grande', -apple-system, sans-serif",
  ja: "'Hiragino Sans', 'Hiragino Kaku Gothic ProN', -apple-system, sans-serif",
  ko: "'Apple SD Gothic Neo', -apple-system, sans-serif",
  'zh-Hans': "'PingFang SC', 'Hiragino Sans GB', -apple-system, sans-serif",
};

/** Languages written right to left. */
export const RTL_LANGUAGES = new Set(['ar', 'he']);

/**
 * Apple's accepted pixel dimensions per surface, and the size this pipeline
 * produces.
 *
 * `min`/`max` are Apple's bounds; `target` is what we render. Every target is
 * inside its bounds and is what `check-assets.mjs` asserts on. Sources:
 * App Store Connect Help — "In-App Events", "Custom Product Pages",
 * "Product Page Optimization", "Asset Library", "App Store product page".
 */
export const SPECS = {
  eventCard: {
    label: 'In-App Event card',
    ratio: '16:9',
    min: { width: 1920, height: 1080 },
    max: { width: 3840, height: 2160 },
    target: { width: 1920, height: 1080 },
    note: 'Shown in the event card on the product page and in search.',
  },
  eventDetails: {
    label: 'In-App Event details',
    ratio: '9:16',
    min: { width: 1080, height: 1920 },
    max: { width: 2160, height: 3840 },
    target: { width: 1080, height: 1920 },
    note: 'Shown after the user taps the event card.',
  },
  productPageHeader: {
    label: 'Product page header',
    ratio: '21:9',
    min: { width: 3840, height: 1646 },
    max: { width: 3840, height: 1646 },
    target: { width: 3840, height: 1646 },
    note: 'The only accepted 21:9 size. A universal 16:9 at 5244x2950 is the alternative.',
  },
  searchResults: {
    label: 'Search results creative',
    ratio: '3:2',
    min: { width: 1920, height: 1280 },
    max: { width: 3840, height: 2560 },
    target: { width: 2400, height: 1600 },
    note: 'Shown in App Store search results when the app is featured.',
  },
};

/**
 * Which Agnes background each surface's text layer composites over, and which
 * side of that background is clear enough to carry type.
 *
 * The art is text-free by design. Diffusion models cannot render 20 scripts
 * reliably, and Apple requires asset text localized into every supported
 * language, so the split is: Agnes paints the background, the renderer lays
 * crisp type on top.
 *
 * `side` is not decoration — it is read off the actual images. Each background
 * was generated with a deliberate empty region, and putting type on the wrong
 * side means the text sits on top of the subject. The value here matches where
 * that empty region actually is, so the two layers do not collide.
 */
const ART = {
  cleanup: { path: 'docs/growth/art/cleanup.png', side: 'left' },
  dupes: { path: 'docs/growth/art/duplicates.png', side: 'right' },
  shots: { path: 'docs/growth/art/screenshots.png', side: 'left' },
  search: { path: 'docs/growth/art/search.png', side: 'top' },
};

/** The image path for an art reference, for callers that only need the file. */
export function artPath(art) {
  return typeof art === 'string' ? art : art.path;
}

/** Which side of the artwork is empty, where type can go. */
export function artSide(art) {
  return typeof art === 'string' ? 'left' : art.side;
}


/**
 * Where each surface's copy comes from.
 *
 * `catalog` reads a key from the app's String Catalog. `listing` reads a field
 * from the App Store listing data. `literal` is for the app's own name, which is
 * never translated.
 */
function readCatalog() {
  return JSON.parse(readFileSync(CATALOG_PATH, 'utf8')).strings ?? {};
}

function readListings() {
  return JSON.parse(readFileSync(LISTINGS_PATH, 'utf8'));
}

function readShortcuts() {
  return JSON.parse(readFileSync(SHORTCUTS_PATH, 'utf8')).strings ?? {};
}

/**
 * Resolves one copy reference for one language.
 *
 * Returns the English source when a translation is missing, and records the miss
 * so the caller can report it. Falling back rather than failing is deliberate:
 * an asset in English is a better failure than no asset, but it must be visible
 * in the report so it gets fixed.
 */
export function resolveCopy(ref, language, sources, missing) {
  if (typeof ref === 'string') return ref;
  if (ref.literal) return ref.literal;

  if (ref.catalog) {
    const entry = sources.catalog[ref.catalog];
    if (!entry) {
      missing.push(`catalog key not found: ${JSON.stringify(ref.catalog)}`);
      return ref.catalog;
    }
    const unit = entry.localizations?.[language]?.stringUnit;
    if (!unit || unit.state === 'needs_review') {
      missing.push(`untranslated in ${language}: ${JSON.stringify(ref.catalog)}`);
      return entry.localizations?.en?.stringUnit?.value ?? ref.catalog;
    }
    return unit.value;
  }

  if (ref.listing) {
    const value = sources.listings[language]?.[ref.listing];
    if (!value) {
      missing.push(`listing field missing in ${language}: ${ref.listing}`);
      return sources.listings.en?.[ref.listing] ?? '';
    }
    return value;
  }

  if (ref.shortcut) {
    const entry = sources.shortcuts[ref.shortcut];
    if (!entry) {
      missing.push(`shortcut phrase not found: ${JSON.stringify(ref.shortcut)}`);
      return ref.shortcut;
    }
    const values = entry.localizations?.[language]?.stringSet?.values;
    if (!values || values.length === 0) {
      missing.push(`shortcut untranslated in ${language}: ${JSON.stringify(ref.shortcut)}`);
      return entry.localizations?.en?.stringSet?.values?.[0] ?? ref.shortcut;
    }
    // The first value is the primary utterance; strip the app-name token, which
    // only means something to Siri and would read as literal braces here.
    return values[0].replace(/\$\{applicationName\}/g, 'TidyByte');
  }

  throw new Error(`unrecognized copy reference: ${JSON.stringify(ref)}`);
}

export function loadSources() {
  return {
    catalog: readCatalog(),
    listings: readListings(),
    shortcuts: readShortcuts(),
  };
}

/**
 * The five surfaces.
 *
 * Each surface lists the assets it produces. `copy` holds the text slots; the
 * renderer decides where they sit, the manifest decides what they say.
 */
export const SURFACES = [
  {
    id: 'in-app-events',
    title: 'In-App Events',
    purpose:
      'Timed events shown on the product page, in search, and in the Today-style '
      + 'event feed. Each event needs a card image and a details image, and both '
      + 'must be localized. Apple allows 10 live events at a time.',
    specs: ['eventCard', 'eventDetails'],
    events: [
      {
        id: 'duplicate-finder',
        art: ART.dupes,
        copy: {
          name: { catalog: 'Duplicates' },
          short: { catalog: 'Find exact & visual duplicates' },
          long: { catalog: 'Screenshots and large files add up. Take a few minutes to review them.' },
        },
      },
      {
        id: 'screenshot-cleanup',
        art: ART.shots,
        copy: {
          name: { catalog: 'Clean Screenshots' },
          short: { catalog: 'Screenshots' },
          long: { catalog: 'Screenshots and large files add up. Take a few minutes to review them.' },
        },
      },
      {
        id: 'storage-checkup',
        art: ART.cleanup,
        copy: {
          name: { catalog: 'Storage' },
          short: { catalog: 'Free Up Space' },
          long: { catalog: 'Space you free up with any cleanup tool shows up here.' },
        },
      },
    ],
  },
  {
    id: 'custom-product-pages',
    title: 'Custom Product Pages',
    purpose:
      'Up to 70 additional product pages, each with its own URL, promotional text, '
      + 'and screenshot set. Used for paid campaigns and feature-specific landing. '
      + 'Each page needs its own review.',
    specs: ['searchResults'],
    pages: [
      {
        id: 'duplicate-photos',
        art: ART.dupes,
        copy: {
          name: { catalog: 'Duplicates' },
          tagline: { catalog: 'Find exact & visual duplicates' },
          promo: { listing: 'promotionalText' },
        },
      },
      {
        id: 'screenshot-cleaner',
        art: ART.shots,
        copy: {
          name: { catalog: 'Clean Screenshots' },
          tagline: { catalog: 'Screenshots' },
          promo: { listing: 'promotionalText' },
        },
      },
      {
        id: 'storage-dashboard',
        art: ART.cleanup,
        copy: {
          name: { catalog: 'Storage' },
          tagline: { catalog: 'Free Up Space' },
          promo: { listing: 'promotionalText' },
        },
      },
      {
        id: 'swipe-cleanup',
        art: ART.cleanup,
        copy: {
          name: { catalog: 'Cleanup' },
          tagline: { catalog: "Decide what's worth keeping" },
          promo: { listing: 'promotionalText' },
        },
      },
    ],
  },
  {
    id: 'asset-library',
    title: 'Asset Library',
    purpose:
      'The central store for screenshots and Creative Assets. Creative Assets '
      + '(product page header, search results, in-app events) live here and can be '
      + 'submitted on their own, without a new app version.',
    specs: ['productPageHeader', 'searchResults'],
    assets: [
      {
        id: 'product-page-header',
        spec: 'productPageHeader',
        art: ART.cleanup,
        copy: {
          headline: { catalog: 'Free Up Space' },
          sub: { catalog: 'All processing happens on your device.' },
          brand: { literal: 'TidyByte' },
        },
      },
      {
        id: 'search-results',
        spec: 'searchResults',
        art: ART.search,
        copy: {
          headline: { listing: 'name' },
          sub: { listing: 'subtitle' },
        },
      },
    ],
  },
  {
    id: 'product-page-optimization',
    title: 'Product Page Optimization',
    purpose:
      'A/B tests of the product page. What this pipeline produces is the original '
      + 'plus three treatments, each a 3:2 search-results creative with different '
      + 'framing: privacy (free up space), duplicates, and screenshots. Apple also '
      + 'lets a test vary the icon, the screenshots, the previews, or the product '
      + 'page header; those variants are not produced here, and an icon test needs a '
      + '1024x1024 icon already inside the uploaded binary. Not available on custom '
      + 'product pages.',
    specs: ['searchResults'],
    treatments: [
      {
        id: 'treatment-a-privacy',
        art: ART.cleanup,
        copy: {
          headline: { catalog: 'Free Up Space' },
          sub: { catalog: 'All processing happens on your device.' },
          label: { literal: 'A' },
        },
      },
      {
        id: 'treatment-b-duplicates',
        art: ART.dupes,
        copy: {
          headline: { catalog: 'Find exact & visual duplicates' },
          sub: { catalog: 'All processing happens on your device.' },
          label: { literal: 'B' },
        },
      },
      {
        id: 'treatment-c-screenshots',
        art: ART.shots,
        copy: {
          headline: { catalog: 'Clean Screenshots' },
          sub: { catalog: 'All processing happens on your device.' },
          label: { literal: 'C' },
        },
      },
    ],
  },
  {
    id: 'header-and-search',
    title: 'Header and Search Results',
    purpose:
      'The two Creative Assets that frame the product page: the 21:9 header that '
      + 'sits above the gallery, and the 3:2 creative shown in search results.',
    specs: ['productPageHeader', 'searchResults'],
    assets: [
      {
        id: 'header',
        spec: 'productPageHeader',
        art: ART.cleanup,
        copy: {
          headline: { catalog: 'Free Up Space' },
          sub: { catalog: 'All processing happens on your device.' },
        },
      },
      {
        id: 'search',
        spec: 'searchResults',
        art: ART.search,
        copy: {
          headline: { listing: 'name' },
          sub: { listing: 'subtitle' },
        },
      },
    ],
  },
];

/** Every asset this pipeline produces, flattened, with its spec resolved. */
export function planAssets() {
  const plan = [];
  for (const surface of SURFACES) {
    const groups = [];
    if (surface.events) groups.push(...surface.events.map((e) => ({ ...e, kind: 'event' })));
    if (surface.pages) groups.push(...surface.pages.map((e) => ({ ...e, kind: 'page' })));
    if (surface.assets) groups.push(...surface.assets.map((e) => ({ ...e, kind: 'asset' })));
    if (surface.treatments) groups.push(...surface.treatments.map((e) => ({ ...e, kind: 'treatment' })));

    for (const group of groups) {
      // An event produces two images — a card and a details image — so it uses
      // the surface's whole spec list. Everything else produces one image: the
      // group's own `spec` when it names one, otherwise the surface's first spec.
      const specs = surface.id === 'in-app-events' ? surface.specs : [group.spec ?? surface.specs[0]];
      for (const specId of specs) {
        if (!SPECS[specId]) {
          throw new Error(`unknown spec ${JSON.stringify(specId)} on ${surface.id}/${group.id}`);
        }
        plan.push({
          surface: surface.id,
          surfaceTitle: surface.title,
          group: group.id,
          kind: group.kind,
          specId,
          spec: SPECS[specId],
          art: group.art,
          copy: group.copy,
        });
      }
    }
  }
  return plan;
}
