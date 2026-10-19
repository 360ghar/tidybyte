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
 * The URLs every localization shares.
 *
 * App Store Connect requires a support URL and a privacy policy URL; a version
 * cannot be submitted without them, and the rejection names `supportUrl` on
 * every localization rather than on one, so a missing value reads as twenty
 * separate errors.
 *
 * The same English URL serves every storefront. That is normal and allowed —
 * Apple does not require a localized support page, only one that resolves.
 *
 * These live here rather than in `listings.json` because that file is the
 * translated copy, and a URL is not translated. `docs/APP_STORE_LISTING.md` §6
 * documents the same values for a human.
 */
export const SUPPORT_URL = 'https://tidybyte.360ghar.com/support';
export const MARKETING_URL = 'https://tidybyte.360ghar.com';
export const PRIVACY_POLICY_URL = 'https://tidybyte.360ghar.com/privacy';

/**
 * Which App Store surface each growth surface targets.
 *
 * `placementType` values are candidates, not gospel. Apple exposes placement
 * types as strings in its reference data rather than as an enum, and the names
 * are not all guessable — the search-results creative is
 * `APP_STORE_SEARCH_RESULTS_ASSET` and the event details image is
 * `EVENT_DETAILS_PAGE_ASSET`, neither of which is the obvious guess. The upload
 * step therefore resolves each candidate against the live catalog and reports
 * the names Apple actually offers when none match, which turns a wrong guess
 * into a one-line fix instead of a silent no-op.
 *
 * Verified against `GET /v1/appAssetLibraryRefData` on 2026-10-18: all four
 * creative types live in the `DEFAULT_PROFILE` group and allow exactly one
 * asset each. Screenshots have their own per-display groups.
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
      eventDetails: ['EVENT_DETAILS_PAGE_ASSET', 'EVENT_DETAILS_ASSET'],
    },
    targetKind: 'appEventLocalization',
    category: 'CREATIVE_ASSETS',
    orderable: false,
  },
  'custom-product-pages': {
    // The 3:2 artwork is the search-results creative, not a screenshot. Custom
    // product pages accept both types, and sending the creative as
    // APP_SCREENSHOT fails: screenshots are validated against device
    // dimensions, and 2400x1600 is not one.
    placementTypesBySpec: { searchResults: ['APP_STORE_SEARCH_RESULTS_ASSET'] },
    targetKind: 'appCustomProductPageLocalization',
    category: 'CREATIVE_ASSETS',
    orderable: true,
  },
  'product-page-optimization': {
    placementTypesBySpec: { searchResults: ['APP_STORE_SEARCH_RESULTS_ASSET'] },
    targetKind: 'appStoreVersionExperimentTreatmentLocalization',
    category: 'CREATIVE_ASSETS',
    orderable: true,
  },
  'header-and-search': {
    placementTypesBySpec: {
      productPageHeader: ['PRODUCT_PAGE_HEADER_ASSET'],
      searchResults: ['APP_STORE_SEARCH_RESULTS_ASSET'],
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
      searchResults: ['APP_STORE_SEARCH_RESULTS_ASSET'],
    },
    targetKind: 'appStoreVersionLocalization',
    category: 'CREATIVE_ASSETS',
    orderable: true,
    libraryOnly: true,
  },
};

/**
 * The device family each screenshot set targets, and the group it belongs to.
 *
 * Apple names placement groups after the display, not the device. The iPhone
 * row App Store Connect requires is the "medium display" set — Apple scales it
 * for larger phones — so `IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE` is the correct
 * target for 1206x2622 screenshots, not the LARGE variant. The iPad 13-inch set
 * is separate and mandatory for an app that ships iPad.
 *
 * `group` is checked against the live catalog and the upload fails loudly if it
 * is absent, so an Apple rename shows up as an error rather than as media
 * landing on the wrong display.
 */
/**
 * The iPhone Duo family, or families.
 *
 * Apple's published screenshot specification lists **one** "iPhone Duo" entry
 * carrying all four accepted sizes — 1398x2034 / 2034x1398 for the outer display
 * and 2007x2853 / 2853x2007 for the inner — with no per-display requirement
 * note, and the Duo badge is described as one badge on the product page. So the
 * default model here is **one** Duo group whose files come from both capture
 * directories, `docs/screenshots/duo-outer/` and `docs/screenshots/duo-inner/`.
 * The capture script still writes them per display, because a display is a
 * capture concern; the upload collapses them into one row.
 *
 * **The group id itself is still unknown offline.** Apple's reference data is
 * the only place it exists, and reading it needs an API key: the one in this repo
 * is empty, so `publish:verify` has never dumped a catalog containing the Duo
 * row. A guessed id would either fail loudly anyway or — worse — collide with an
 * existing group, so it defaults to null and the family is skipped unless `--duo`
 * is passed. With `--duo` and no id, `loadPlan` throws rather than uploading to
 * the wrong display.
 *
 * Escape hatch, for the case the live catalog disagrees with the published spec:
 * set **both** `TIDYBYTE_DUO_OUTER_GROUP_ID` and `TIDYBYTE_DUO_INNER_GROUP_ID`
 * and the model splits into two families, one directory each, exactly as it was
 * before. Setting only one of the two is not a split — it falls back to the
 * single-group model, which then has no id and fails loudly. A half-split is
 * never taken by accident. `npm run publish:verify` is what settles which shape
 * is real.
 */
function duoFamilies() {
  const single = process.env.TIDYBYTE_DUO_GROUP_ID || null;
  const outer = process.env.TIDYBYTE_DUO_OUTER_GROUP_ID || null;
  const inner = process.env.TIDYBYTE_DUO_INNER_GROUP_ID || null;

  if (outer && inner) {
    return {
      duoOuter: {
        group: outer,
        label: 'iPhone Duo (outer display)',
        dirs: ['duo-outer'],
        duo: true,
      },
      duoInner: {
        group: inner,
        label: 'iPhone Duo (inner display)',
        dirs: ['duo-inner'],
        duo: true,
      },
    };
  }

  return {
    duo: {
      group: single,
      label: 'iPhone Duo',
      // One App Store Connect row, both captured displays. Either directory may
      // be absent; at least one file across the two is required.
      dirs: ['duo-outer', 'duo-inner'],
      duo: true,
    },
  };
}

const SCREENSHOT_FAMILIES = {
  iphone: {
    group: 'IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE',
    label: 'iPhone with Dynamic Island (medium display)',
    dirs: ['iphone'],
  },
  ipad: {
    group: 'IPAD_13_PROFILE',
    label: 'iPad 13-inch',
    dirs: ['ipad'],
  },
  ...duoFamilies(),
};

/** The directories the Duo families read from, for the "no files" error. */
export const DUO_DIRS = ['duo-outer', 'duo-inner'];

/**
 * The App Store Connect cap on screenshots per device-size row.
 *
 * Apple's screenshot spec allows **up to 10 screenshots per group**, and a
 * placement group is one device-size row on the product page. A Duo submission
 * is graded as a single row, so `duo-outer/` and `duo-inner/` together may hold
 * at most 10 files — the same limit `publish.mjs media` states when it explains
 * why inherited placements leave no room. The capture default is 5 per display
 * (5 + 5 = 10); see `--screens` in `scripts/growth/shoot-screenshots.mjs`.
 */
export const MAX_SCREENSHOTS_PER_GROUP = 10;

/**
 * What to do when a Duo group holds more screenshots than the platform accepts.
 *
 * This is checked in `loadPlan`, before any network call, so an oversized set
 * fails with a count instead of uploading the first 10 and dropping the rest
 * into `failures` — a half-applied upload is worse than no upload.
 */
export function duoCapHelp({ count, label }) {
  return [
    `The Duo group "${label}" holds ${count} screenshot(s), over App Store Connect's`,
    `limit of ${MAX_SCREENSHOTS_PER_GROUP} per device-size row.`,
    '',
    '  A Duo submission is graded as ONE row, so both captured displays count',
    '  against the same cap. The capture default is 5 per display (5 + 5 = 10).',
    '',
    '  Capture a smaller set, then re-run:',
    '',
    '    npm run screenshots:duo -- --screens swipe-home,cleanup-tools,cleanup-duplicates,storage-dashboard,activity-savings',
    '',
    '  or delete PNGs from docs/screenshots/duo-outer/ and docs/screenshots/duo-inner/.',
  ].join('\n');
}

/**
 * What to do when `--duo` is passed before the Duo group id is known.
 *
 * The single-group route leads, because that is what Apple's spec describes. The
 * two-id split is named as the fallback, not as an equal option: it exists for
 * the case the catalog shows two groups, and choosing it before checking would
 * be guessing.
 */
export const DUO_GROUP_HELP = [
  'iPhone Duo screenshots are enabled (--duo), but the App Store Connect group id',
  'for the Duo display is not known yet, and it cannot be discovered offline.',
  '',
  '  1. Run:   npm run publish:verify',
  '  2. In the `appAssetLibraryRefData` dump it prints, find the APP_SCREENSHOT group',
  '     for the Duo display. It looks like:',
  '',
  '       <group-id>                                        IOS   <display-class>',
  '',
  '  3. Export the id and re-run:',
  '',
  '       TIDYBYTE_DUO_GROUP_ID=<id> npm run publish:media -- --duo',
  '',
  '  Apple\'s screenshot spec lists one iPhone Duo entry with all four sizes, so one',
  '  group is expected. If the dump really shows two APP_SCREENSHOT groups for the',
  '  Duo displays, use the split instead:',
  '',
  '       TIDYBYTE_DUO_OUTER_GROUP_ID=<outer-id> \\',
  '         TIDYBYTE_DUO_INNER_GROUP_ID=<inner-id> \\',
  '         npm run publish:media -- --duo',
  '',
  '  (or paste the id(s) into scripts/publish/plan.mjs, in `duoFamilies`)',
].join('\n');

/**
 * What to do when `--duo` is passed but no Duo screenshot exists on disk.
 */
export const DUO_EMPTY_HELP = [
  `iPhone Duo screenshots are enabled (--duo), but there are no PNGs in ${DUO_DIRS.join('/ or ')}/.`,
  '',
  '  Capture them first (needs the iOS 27.1 runtime):',
  '',
  '    npm run screenshots:duo',
  '',
  '  Or point the plan at the directories you have.',
].join('\n');

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
 *
 * `duo` gates the iPhone Duo family. It defaults to whether `--duo` is in the
 * process arguments, so `publish.mjs media` needs no change to honour it: a run
 * without the flag produces the same placements it always has, and a run with it
 * fails loudly until the Duo group id is filled in.
 *
 * A Duo family is also checked against `MAX_SCREENSHOTS_PER_GROUP` here, from
 * the files actually present, so an oversized set throws before the upload —
 * see `duoCapHelp`.
 */
export function loadPlan({ duo = process.argv.includes('--duo') } = {}) {
  if (duo) {
    const unresolved = Object.entries(SCREENSHOT_FAMILIES)
      .filter(([, meta]) => meta.duo && !meta.group)
      .map(([key]) => key);
    if (unresolved.length > 0) throw new Error(DUO_GROUP_HELP);
  }

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

  let duoFiles = 0;
  // Screenshots per App Store Connect group, for the cap check below. Only the
  // Duo families are tracked: an iPhone or iPad row has its own limit and its
  // single directory never approaches it.
  const duoGroupCounts = new Map();
  for (const [family, meta] of Object.entries(SCREENSHOT_FAMILIES)) {
    if (meta.duo && !duo) continue;
    // A family reads one or more directories. The Duo family reads both capture
    // directories into the single App Store Connect row; the escape-hatch split
    // gives each family one directory again.
    for (const [dirIndex, dirName] of meta.dirs.entries()) {
      const directory = join(ROOT, 'docs', 'screenshots', dirName);
      let names;
      try {
        // Screenshots are read from the directory rather than a manifest, because
        // the capture script writes a fixed numbered sequence.
        names = readdirSync(directory).filter((name) => name.endsWith('.png')).sort();
      } catch {
        // A missing directory is not an error: the outer or inner display may
        // not have been captured yet. The check below catches "neither".
        continue;
      }
      for (const name of names) {
        if (meta.duo) {
          duoFiles += 1;
          const seen = duoGroupCounts.get(meta.group) ?? { count: 0, label: meta.label };
          seen.count += 1;
          duoGroupCounts.set(meta.group, seen);
        }
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
          groupId: meta.group,
          familyLabel: meta.label,
          // Position in the gallery, taken from the numeric filename prefix.
          // Both Duo directories number their files from 01, so the directory
          // index offsets the second one — outer 1.., then inner 101.. — which
          // keeps one group's sequence deterministic instead of tied.
          order: Number(name.slice(0, 2)) + dirIndex * 100,
        });
      }
    }
  }

  // "Either directory may be absent" still means something has to be there: a
  // silent zero would upload nothing and report success.
  if (duo && duoFiles === 0) throw new Error(DUO_EMPTY_HELP);

  // The per-row cap, checked here so it fires before `cmdMedia` makes a call.
  // An oversized set would otherwise upload the first 10 and report the rest as
  // failures, half-applying the request.
  for (const { count, label } of duoGroupCounts.values()) {
    if (count > MAX_SCREENSHOTS_PER_GROUP) {
      throw new Error(duoCapHelp({ count, label }));
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

/**
 * The desired gallery position of every planned screenshot, keyed two ways.
 *
 * **Hash first.** An uploaded asset's `referenceName` is the sha256 of its bytes,
 * so it identifies one file uniquely across every device family. A basename does
 * not: the Duo capture writes `01-swipe-home.png` into both `duo-outer/` and
 * `duo-inner/`, and in the single-group model both feed one App Store Connect
 * group. Keying by basename alone silently kept only the last of the two and left
 * that pair's order to whatever Apple returned.
 *
 * **Basename second, and only when it is unique.** It is the fallback for an
 * asset whose `referenceName` is missing. A basename that appears more than once
 * in the plan maps to `null` rather than to a guess, so the caller can tell
 * "ambiguous" from "unknown".
 *
 * Lives here rather than in `publish.mjs` so the ordering can be exercised
 * offline: `publish.mjs order` needs live credentials, and the one thing worth
 * checking about it is pure.
 */
export function orderLookups(items, { readFile, createHash } = {}) {
  const byHash = new Map();
  const byName = new Map();
  for (const item of items) {
    if (!item.order) continue;
    if (readFile && createHash) {
      byHash.set(createHash('sha256').update(readFile(item.file)).digest('hex'), item.order);
    }
    const name = item.file.split('/').pop();
    byName.set(name, byName.has(name) ? null : item.order);
  }
  return { byHash, byName };
}

/**
 * The placement ids for one group, in the order they should display.
 *
 * `placements` is the placements response for one localization, with `included`
 * carrying the image assets. Position comes from `orderLookups`; a placement the
 * plan does not know sorts last, and name-then-id keeps even those deterministic
 * rather than leaving the order to Apple's response sequence.
 */
export function orderSequence(placements, lookups) {
  const assetFor = (imageId) => {
    if (!imageId) return null;
    return placements.included?.find(
      (entry) => entry.type === 'appAssetLibraryImages' && entry.id === imageId,
    ) ?? null;
  };

  return placements.data
    .map((placement) => {
      const asset = assetFor(placement.relationships?.image?.data?.id);
      const hash = asset?.attributes?.referenceName ?? null;
      const name = asset?.attributes?.fileName ?? null;
      const position = lookups.byHash.get(hash)
        ?? (name != null ? lookups.byName.get(name) : null)
        ?? 99;
      return { id: placement.id, position, name: name ?? hash ?? '' };
    })
    .sort((a, b) => a.position - b.position
      || a.name.localeCompare(b.name)
      || a.id.localeCompare(b.id));
}
