#!/usr/bin/env node
/**
 * Turns the local media on disk into a list of App Store Connect placements.
 *
 * The asset library separates an asset from where it appears: upload a file
 * once, then create a placement per surface. This module describes the second
 * half — which file goes on which surface, in which language, as which
 * placement type and group.
 *
 * The placement type names here were read from Apple's reference data
 * (`GET /v1/appAssetLibraryRefData`). They are strings rather than an enum, and
 * the upload step re-reads the catalog at runtime rather than trusting this
 * table, so a new device family does not need a code change. If Apple renames a
 * type, `resolveTargets` fails loudly with the list of names it does offer
 * instead of silently uploading nothing.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const BUNDLE_ID = 'com.sakshammittal.tidybyte';

/**
 * Which App Store surface each growth surface targets.
 *
 * `placementType` values are candidates, not gospel. Apple exposes placement
 * types as strings in its reference data rather than as an enum, and it does
 * not document every name it uses — the product page header and event card
 * types are named in Apple's guides, but the search-results creative is not.
 * The upload step therefore tries each candidate in order against the live
 * catalog and reports the names Apple actually offers when none match, which
 * turns a guess into a one-line correction instead of a silent no-op.
 *
 * `targetKind` is the relationship name on the placement. `category` is set at
 * reservation time and cannot be changed afterwards, so it has to be right
 * before the first upload: screenshots and previews are
 * APP_SCREENSHOTS_AND_PREVIEWS, everything Apple calls a "creative" is
 * CREATIVE_ASSETS.
 */
const SURFACE_TARGETS = {
  'in-app-events': {
    placementTypesBySpec: {
      eventCard: ['EVENT_CARD_ASSET'],
      eventDetails: ['EVENT_DETAILS_ASSET'],
    },
    targetKind: 'appEventLocalization',
    category: 'CREATIVE_ASSETS',
    orderable: false,
  },
  'custom-product-pages': {
    placementTypesBySpec: { searchResults: ['APP_SCREENSHOT'] },
    targetKind: 'appCustomProductPageLocalization',
    category: 'APP_SCREENSHOTS_AND_PREVIEWS',
    orderable: true,
  },
  'product-page-optimization': {
    placementTypesBySpec: { searchResults: ['APP_SCREENSHOT'] },
    targetKind: 'appStoreVersionExperimentTreatmentLocalization',
    category: 'APP_SCREENSHOTS_AND_PREVIEWS',
    orderable: true,
  },
  'header-and-search': {
    placementTypesBySpec: {
      productPageHeader: ['PRODUCT_PAGE_HEADER_ASSET'],
      searchResults: ['SEARCH_RESULTS_ASSET', 'PRODUCT_PAGE_SEARCH_RESULTS_ASSET', 'SEARCH_RESULT_ASSET'],
    },
    targetKind: 'appStoreVersionLocalization',
    category: 'CREATIVE_ASSETS',
    orderable: true,
  },
  // Uploaded into the library so the other surfaces can reuse them. Whether
  // this surface also gets placements depends on what the account already
  // holds, so it is reported rather than assumed.
  'asset-library': {
    placementTypesBySpec: {
      productPageHeader: ['PRODUCT_PAGE_HEADER_ASSET'],
      searchResults: ['SEARCH_RESULTS_ASSET', 'PRODUCT_PAGE_SEARCH_RESULTS_ASSET', 'SEARCH_RESULT_ASSET'],
    },
    targetKind: 'appStoreVersionLocalization',
    category: 'CREATIVE_ASSETS',
    orderable: true,
    libraryOnly: true,
  },
};

/**
 * The device family each screenshot set targets.
 *
 * Apple names placement groups after the display, not the device: the iPhone
 * row that App Store Connect requires is the "medium display" set, and Apple
 * scales it for larger phones. The iPad 13-inch set is separate and mandatory
 * for an app that ships iPad. The upload step matches these prefixes against
 * the live group list rather than hard-coding the full identifier.
 */
const SCREENSHOT_FAMILIES = {
  iphone: { prefix: 'IPHONE_DYNAMIC_ISLAND', label: 'iPhone (Dynamic Island)' },
  ipad: { prefix: 'IPAD', label: 'iPad 13-inch' },
};

/**
 * The App Store locale each listings language maps to.
 *
 * The app ships 20 languages; the storefronts are 21 locales because English is
 * split (en-US is primary). The two lists are not the same thing and the app's
 * language codes are not all valid storefront codes — `en` and `ar` in
 * particular have no storefront of their own.
 */
export const LOCALE_BY_LANGUAGE = {
  ar: 'ar-SA',
  bn: 'bn-BD',
  de: 'de-DE',
  en: 'en-US',
  es: 'es-ES',
  fr: 'fr-FR',
  gu: 'gu-IN',
  he: 'he',
  hi: 'hi',
  it: 'it',
  ja: 'ja',
  kn: 'kn-IN',
  ko: 'ko',
  ml: 'ml-IN',
  mr: 'mr-IN',
  pa: 'pa-IN',
  'pt-BR': 'pt-BR',
  ru: 'ru',
  ta: 'ta-IN',
  te: 'te-IN',
  'zh-Hans': 'zh-Hans',
};

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

/**
 * Every media item we intend to publish, as a flat list.
 *
 * Growth assets are localized — each carries copy in one of 21 languages — so
 * each becomes a placement on that language's localization. Screenshots are
 * captured with an English UI and are therefore language-independent: they are
 * uploaded once against the primary locale and App Store Connect falls back to
 * them everywhere else.
 */
export function loadPlan() {
  const items = [];

  for (const [surface, target] of Object.entries(SURFACE_TARGETS)) {
    const manifestPath = join(ROOT, 'docs', 'growth', surface, 'manifest.json');
    let manifest;
    try {
      manifest = readJson(manifestPath);
    } catch {
      continue;
    }

    for (const asset of manifest.assets ?? []) {
      const candidates = target.placementTypesBySpec[asset.spec];
      if (!candidates) continue;
      items.push({
        surface,
        group: asset.group,
        spec: asset.spec,
        language: asset.language,
        locale: LOCALE_BY_LANGUAGE[asset.language] ?? null,
        file: join(ROOT, 'docs', 'growth', surface, asset.file),
        placementTypeCandidates: candidates,
        targetKind: target.targetKind,
        category: target.category,
        orderable: target.orderable,
        libraryOnly: Boolean(target.libraryOnly),
        width: asset.width,
        height: asset.height,
        ratio: asset.ratio,
      });
    }
  }

  for (const [family, meta] of Object.entries(SCREENSHOT_FAMILIES)) {
    const directory = join(ROOT, 'docs', 'screenshots', family);
    let names;
    try {
      // Screenshots are read from the directory rather than a manifest, because
      // the capture script writes a fixed numbered sequence.
      names = readdirSync(directory).filter((name) => name.endsWith('.png')).sort();
    } catch {
      continue;
    }
    for (const name of names) {
      items.push({
        surface: 'app-store-screenshots',
        group: family,
        spec: 'screenshot',
        language: 'en',
        locale: LOCALE_BY_LANGUAGE.en,
        file: join(directory, name),
        placementTypeCandidates: ['APP_SCREENSHOT'],
        targetKind: 'appStoreVersionLocalization',
        category: 'APP_SCREENSHOTS_AND_PREVIEWS',
        orderable: true,
        libraryOnly: false,
        familyPrefix: meta.prefix,
        familyLabel: meta.label,
        // Position in the gallery, taken from the numeric filename prefix.
        order: Number(name.slice(0, 2)),
      });
    }
  }

  return items;
}

/** A human-readable summary of a plan, for the dry run and the verify report. */
export function summarisePlan(items) {
  const bySurface = new Map();
  for (const item of items) {
    if (!bySurface.has(item.surface)) bySurface.set(item.surface, []);
    bySurface.get(item.surface).push(item);
  }

  const lines = [];
  lines.push(`  ${items.length} placement(s) across ${bySurface.size} surface(s)`);
  for (const [surface, group] of [...bySurface].sort()) {
    const languages = new Set(group.map((item) => item.language));
    const groups = new Set(group.map((item) => item.group));
    const types = new Set(group.flatMap((item) => item.placementTypeCandidates));
    lines.push(
      `    ${surface.padEnd(28)} ${String(group.length).padStart(3)} file(s)`
      + `  ${groups.size} group(s)  ${languages.size} language(s)  ${[...types].join(' | ')}`,
    );
  }
  return lines.join('\n');
}
