#!/usr/bin/env node
/**
 * Publishes TidyByte to App Store Connect: build, media, details, submission.
 *
 * Commands are separate on purpose. Uploading a build, replacing the screenshot
 * gallery, and submitting for review are three different decisions with three
 * different blast radii, and running them as one opaque command makes it easy
 * to submit something you have not looked at.
 *
 *   verify   read-only report on the live account          (verify.mjs)
 *   build    upload the signed IPA
 *   details  update subtitle, keywords, description, promo text, what's new
 *   media    upload assets to the library and place them on every surface
 *   submit   create a review submission and submit the version
 *   all      build, then details, then media, then submit
 *
 * Every command takes --dry-run, which prints the calls it would make and
 * changes nothing. Start there.
 *
 * Credentials (see asc.mjs):
 *   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
 */

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { createInterface } from 'node:readline/promises';
import { basename, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { AscError, createClient, credentialsFromEnv, findApp } from './asc.mjs';
import {
  BUNDLE_ID, MARKETING_URL, PRIVACY_POLICY_URL, SUPPORT_URL, loadPlan,
  orderLookups, orderSequence,
} from './plan.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const LISTINGS_PATH = join(ROOT, 'docs', 'appstore', 'listings.json');
const DEFAULT_IPA = join(ROOT, 'build', 'archive', 'export', 'Tidybyte.ipa');

const args = process.argv.slice(2);
const command = args.find((a) => !a.startsWith('-')) ?? 'verify';
const dryRun = args.includes('--dry-run');
const assumeYes = args.includes('--yes');

function heading(text) {
  console.log(`\n${text}`);
  console.log('-'.repeat(text.length));
}

/** Prints the call instead of making it, under --dry-run. */
function plan(method, path, detail) {
  console.log(`  [dry-run] ${method} ${path}${detail ? `  ${detail}` : ''}`);
}

async function confirm(question) {
  if (assumeYes) return true;
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const answer = await rl.question(`${question} [y/N] `);
    return answer.trim().toLowerCase() === 'y' || answer.trim().toLowerCase() === 'yes';
  } finally {
    rl.close();
  }
}

function loadListings() {
  return JSON.parse(readFileSync(LISTINGS_PATH, 'utf8'));
}

async function connect() {
  const client = createClient({ ...credentialsFromEnv(), log: console.log });
  const app = await findApp(client, BUNDLE_ID);
  return { client, app, appId: app.id };
}

/** Reads the version string from project.yml, so there is one source of truth. */
function marketingVersion() {
  const yml = readFileSync(join(ROOT, 'project.yml'), 'utf8');
  const match = yml.match(/^\s*MARKETING_VERSION:\s*"?([^"\n]+?)"?\s*$/m);
  if (!match) throw new Error('No MARKETING_VERSION found in project.yml.');
  return match[1].trim();
}

/**
 * The app info record, which holds the fields that apply across all versions.
 *
 * The subtitle lives here rather than on the version, and there is normally one
 * record. An editable one is preferred when it exists, because some fields can
 * only be changed while the app is not live.
 */
async function findAppInfo(client, appId) {
  const infos = await client.getAll(`/v1/apps/${appId}/appInfos?limit=20`);
  return infos.find((info) => info.attributes?.appStoreState === 'PREPARE_FOR_SUBMISSION')
    ?? infos[0]
    ?? null;
}

/**
 * Creates the version and localizations needed before anything can be written.
 *
 * Separate from `details` so the structural change — a new version, twenty new
 * store locales — is a step you take deliberately, and can inspect before the
 * copy and media land on top of it.
 */
async function cmdPrepare() {
  const { client, appId } = await connect();
  const listings = loadListings();
  const { LOCALE_BY_LANGUAGE } = await import('./plan.mjs');
  const wanted = Object.keys(listings).filter((key) => !key.startsWith('_'));
  const locales = wanted.map((language) => LOCALE_BY_LANGUAGE[language] ?? language);

  heading(`Version ${marketingVersion()}`);
  const existing = await client.getAll(
    `/v1/apps/${appId}/appStoreVersions?limit=50`
    + '&fields[appStoreVersions]=versionString,appStoreState',
  );
  const already = existing.find(
    (v) => v.attributes.versionString === marketingVersion()
      && v.attributes.appStoreState === 'PREPARE_FOR_SUBMISSION',
  );
  if (already) {
    console.log(`  ${marketingVersion()} already exists and is editable`);
  } else if (dryRun) {
    plan('POST', '/v1/appStoreVersions', `create ${marketingVersion()} (IOS, AFTER_APPROVAL release)`);
  }

  const version = dryRun && !already
    ? { id: 'dry-run', attributes: { versionString: marketingVersion() } }
    : await ensureEditableVersion(client, appId, { create: !dryRun });

  heading(`Store localizations (${locales.length} wanted)`);
  if (dryRun) {
    const current = already
      ? await client.getAll(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`)
      : [];
    const have = new Set(current.map((l) => l.attributes.locale));
    for (const locale of locales) {
      if (have.has(locale)) console.log(`  ${locale.padEnd(9)} exists`);
      else plan('POST', '/v1/appStoreVersionLocalizations', locale);
    }
    const appInfo = await findAppInfo(client, appId);
    if (appInfo) {
      const infoLocs = await client.getAll(`/v1/appInfos/${appInfo.id}/appInfoLocalizations?limit=200`);
      const haveInfo = new Set(infoLocs.map((l) => l.attributes.locale));
      console.log('\n  App info (subtitle):');
      for (const locale of locales) {
        if (haveInfo.has(locale)) console.log(`    ${locale.padEnd(9)} exists`);
        else plan('POST', '/v1/appInfoLocalizations', locale);
      }
    }
    return;
  }

  const appInfo = await findAppInfo(client, appId);
  const report = await ensureLocalizations(client, {
    version,
    appInfoId: appInfo?.id,
    locales,
    create: true,
  });

  console.log(`  ${report.existing.length} already present`);
  if (report.created.length > 0) console.log(`  created: ${report.created.join(', ')}`);
  if (report.failed.length > 0) {
    console.log(`  FAILED (${report.failed.length}):`);
    for (const failure of report.failed) console.log(`    ${failure}`);
    console.log('\n  Apple rejects a locale it does not support. Fix the mapping in');
    console.log('  plan.mjs LOCALE_BY_LANGUAGE and re-run.');
  }

  heading('Next');
  console.log(`  npm run archive            # build ${marketingVersion()} (build from project.yml)`);
  console.log('  npm run publish:build      # upload the IPA');
  console.log('  npm run publish:details    # copy, into all localizations');
  console.log('  npm run publish:media      # assets and placements');
  console.log('  npm run publish:submit     # submit for review');
}

/** The version we are allowed to write to, creating it when asked. */
async function ensureEditableVersion(client, appId, { create = false } = {}) {
  const wanted = marketingVersion();
  const versions = await client.getAll(
    `/v1/apps/${appId}/appStoreVersions?limit=50`
    + '&fields[appStoreVersions]=versionString,appStoreState,platform,createdDate',
  );

  const editable = versions.filter((v) => v.attributes?.appStoreState === 'PREPARE_FOR_SUBMISSION');
  if (editable.length > 0) {
    const exact = editable.find((v) => v.attributes.versionString === wanted);
    if (exact) return exact;
    // Another version is editable. Using it would edit the wrong release, so say
    // so rather than silently picking one.
    const others = editable.map((v) => v.attributes.versionString).join(', ');
    throw new Error(
      `Version ${wanted} does not exist, but ${others} is editable.\n`
      + 'Finish or discard that version first, or set MARKETING_VERSION to match it.',
    );
  }

  if (!create) {
    const states = versions.map((v) => `${v.attributes.versionString} (${v.attributes.appStoreState})`);
    throw new Error(
      `No version in PREPARE_FOR_SUBMISSION. Present: ${states.join(', ') || 'none'}.\n`
      + 'Details and media can only be changed while a version is editable.\n'
      + 'Create one with: npm run publish:prepare',
    );
  }

  // A released version can never be reopened, so publishing new work means a new
  // version number. The string comes from project.yml, not from this script.
  console.log(`  creating version ${wanted}`);
  const created = await client.post('/v1/appStoreVersions', {
    data: {
      type: 'appStoreVersions',
      attributes: {
        platform: 'IOS',
        versionString: wanted,
        // Release the moment App Review approves, with no manual hold. Set this
        // back to 'MANUAL' for a release that has to be held after approval,
        // which is only possible on a version that has not been submitted yet.
        releaseType: 'AFTER_APPROVAL',
      },
      relationships: { app: { data: { type: 'apps', id: appId } } },
    },
  });
  return created.data;
}

/**
 * Creates the store localizations that do not exist yet.
 *
 * A new version starts with only the primary locale, and the app info carries
 * its own separate set. Both have to be created before any localized copy or
 * media can be attached, and the two are different resources with different
 * parents, which is the usual place this goes wrong.
 */
async function ensureLocalizations(client, { version, appInfoId, locales, create }) {
  const wanted = [...new Set(locales)].sort();
  const report = { created: [], existing: [], failed: [] };

  const versionLocales = new Map(
    (await client.getAll(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`))
      .map((l) => [l.attributes.locale, l]),
  );

  for (const locale of wanted) {
    if (versionLocales.has(locale)) {
      report.existing.push(locale);
      continue;
    }
    if (!create) {
      report.failed.push(`${locale}: version localization missing`);
      continue;
    }
    try {
      const created = await client.post('/v1/appStoreVersionLocalizations', {
        data: {
          type: 'appStoreVersionLocalizations',
          attributes: { locale },
          relationships: {
            appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } },
          },
        },
      });
      report.created.push(locale);
      versionLocales.set(locale, created.data);
    } catch (error) {
      // Apple names the offending value, so surface its message rather than a
      // generic failure. An unsupported locale is the usual cause.
      report.failed.push(`${locale}: ${error.message.split('\n').pop()}`);
    }
  }

  // App info localizations are a separate resource. The subtitle lives here, and
  // a locale with no app info localization cannot carry one.
  if (appInfoId) {
    const infoLocales = new Map(
      (await client.getAll(`/v1/appInfos/${appInfoId}/appInfoLocalizations?limit=200`))
        .map((l) => [l.attributes.locale, l]),
    );
    for (const locale of wanted) {
      if (infoLocales.has(locale)) continue;
      if (!create) continue;
      try {
        await client.post('/v1/appInfoLocalizations', {
          data: {
            type: 'appInfoLocalizations',
            attributes: { locale, name: 'TidyByte' },
            relationships: { appInfo: { data: { type: 'appInfos', id: appInfoId } } },
          },
        });
        report.created.push(`appInfo:${locale}`);
      } catch (error) {
        report.failed.push(`appInfo ${locale}: ${error.message.split('\n').pop()}`);
      }
    }
  }

  return report;
}

// ---------------------------------------------------------------------------
// build
// ---------------------------------------------------------------------------

/**
 * Where altool looks for a key named by `--apiKey`.
 *
 * altool does not accept a path: given a Key ID it searches a fixed list of
 * directories for `AuthKey_<KEYID>.p8`. A key at an arbitrary path — which is
 * where `ASC_KEY_PATH` usually points — is not found, and the error says the
 * key is missing rather than that it was never searched for. Checking this
 * first turns that into a specific instruction.
 */
const ALTOOL_KEY_DIRECTORIES = [
  join(homedir(), 'private_keys'),
  join(process.cwd(), 'private_keys'),
  join(homedir(), '.appstoreconnect', 'private_keys'),
  join(process.cwd(), '.appstoreconnect', 'private_keys'),
];

/**
 * Uploads the IPA with altool.
 *
 * The App Store Connect API can read build metadata but not create a build, so
 * the binary goes up through altool. An API key authenticates this the same way
 * it authenticates the REST calls, which means no Apple ID password is needed.
 */
async function cmdBuild() {
  heading('Upload build');
  const ipa = args.find((a) => a.endsWith('.ipa')) ?? DEFAULT_IPA;
  if (!existsSync(ipa)) {
    throw new Error(`No IPA at ${ipa}. Build one with:\n  npm run archive`);
  }
  const size = (statSync(ipa).size / 1024 / 1024).toFixed(1);
  console.log(`  ${basename(ipa)}  ${size} MB`);

  const { keyId, issuerId, keyPath } = credentialsFromEnv();

  // altool finds the key by searching fixed directories, not by path.
  const expectedName = `AuthKey_${keyId}.p8`;
  const searchResult = ALTOOL_KEY_DIRECTORIES.map((dir) => join(dir, expectedName));
  const found = searchResult.find((candidate) => existsSync(candidate));

  if (!found) {
    console.log('\n  altool cannot find the private key.');
    console.log(`  It searches for a file named ${expectedName} in:`);
    for (const dir of ALTOOL_KEY_DIRECTORIES) console.log(`    ${dir}`);
    console.log(`\n  Your key is at ${keyPath}`);
    console.log('  altool takes a Key ID, not a path, so make it findable:');
    console.log(`\n    mkdir -p ~/.appstoreconnect/private_keys`);
    console.log(`    cp "${keyPath}" ~/.appstoreconnect/private_keys/${expectedName}`);
    console.log('\n  Then re-run. This is a copy, not a move, so ASC_KEY_PATH keeps working.');
    if (!dryRun) return;
  } else {
    console.log(`  key discoverable at ${found}`);
  }

  const altoolArgs = [
    'altool', '--upload-app',
    '-f', ipa,
    '-t', 'ios',
    '--apiKey', keyId,
    '--apiIssuer', issuerId,
    '--output-format', 'json',
  ];

  if (dryRun) {
    plan('POST', 'altool --upload-app', `${basename(ipa)} (${size} MB)`);
    return;
  }

  if (!(await confirm(`Upload ${basename(ipa)} to App Store Connect?`))) {
    console.log('  cancelled.');
    return;
  }

  try {
    const output = execFileSync('xcrun', altoolArgs, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    console.log(output.trim());
    console.log('  upload accepted. App Store Connect now processes the binary;');
    console.log('  it appears under TestFlight in a few minutes.');
  } catch (error) {
    // altool reports progress on stderr even when it succeeds, so surface both.
    const stderr = error.stderr?.toString?.() ?? '';
    const stdout = error.stdout?.toString?.() ?? '';
    throw new Error(`altool failed.\n${stdout}\n${stderr}`.trim());
  }
}

// ---------------------------------------------------------------------------
// details
// ---------------------------------------------------------------------------

/**
 * Pushes the store copy into every localization.
 *
 * Only the fields present in listings.json are sent, and `whatsNew` is included
 * because a build cannot be submitted without it. Fields are compared against
 * what the account already holds so a re-run is a no-op rather than a rewrite.
 */
async function cmdDetails() {
  const { client, appId } = await connect();
  const version = await ensureEditableVersion(client, appId, { create: args.includes('--create') });
  const listings = loadListings();

  heading(`Details for version ${version.attributes.versionString}`);

  const { LOCALE_BY_LANGUAGE } = await import('./plan.mjs');
  const wanted = Object.keys(listings).filter((key) => !key.startsWith('_'));
  const wantedLocales = wanted.map((language) => LOCALE_BY_LANGUAGE[language] ?? language);

  const appInfo = await findAppInfo(client, appId);
  const prepared = await ensureLocalizations(client, {
    version,
    appInfoId: appInfo?.id,
    locales: wantedLocales,
    create: args.includes('--create'),
  });
  if (prepared.created.length > 0) {
    console.log(`  created ${prepared.created.length} localization(s): ${prepared.created.join(', ')}`);
  }
  if (prepared.failed.length > 0) {
    console.log(`  ${prepared.failed.length} could not be prepared:`);
    for (const failure of prepared.failed) console.log(`    ${failure}`);
    console.log('  Re-run with --create to add the missing ones.');
  }

  const localizations = await client.getAll(
    `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`,
  );
  const byLocale = new Map(localizations.map((l) => [l.attributes.locale, l]));

  let changed = 0;
  let unchanged = 0;
  const missingLocales = [];

  for (const language of wanted) {
    const locale = LOCALE_BY_LANGUAGE[language] ?? language;
    const entry = listings[language];
    const localization = byLocale.get(locale);
    if (!localization) {
      missingLocales.push(`${language} -> ${locale}`);
      continue;
    }

    const attributes = {
      description: entry.description,
      keywords: entry.keywords,
      promotionalText: entry.promotionalText,
      // Required by App Review. A version cannot be submitted without a support
      // URL, and the rejection names it per localization, so omitting it looks
      // like twenty errors rather than one.
      supportUrl: SUPPORT_URL,
      marketingUrl: MARKETING_URL,
      // whatsNew is required to submit an update; listings.json carries it.
      ...(entry.whatsNew ? { whatsNew: entry.whatsNew } : {}),
    };

    const current = localization.attributes ?? {};
    const differing = Object.entries(attributes)
      .filter(([key, value]) => value !== undefined && current[key] !== value)
      .map(([key]) => key);

    if (differing.length === 0) {
      unchanged += 1;
      continue;
    }
    changed += 1;
    console.log(`  ${locale.padEnd(9)} updating ${differing.join(', ')}`);

    if (dryRun) {
      plan('PATCH', `/v1/appStoreVersionLocalizations/${localization.id}`, differing.join(','));
      continue;
    }
    await client.patch(`/v1/appStoreVersionLocalizations/${localization.id}`, {
      data: { type: 'appStoreVersionLocalizations', id: localization.id, attributes },
    });
  }

  // The subtitle lives on the app info, not the version, and it is per-locale.
  heading('Subtitle (app info localizations)');
  if (!appInfo) {
    console.log('  no app info record found; subtitle not updated.');
  } else {
    // Re-read: ensureLocalizations may have just created these.
    const infoLocalizations = await client.getAll(
      `/v1/appInfos/${appInfo.id}/appInfoLocalizations?limit=200`,
    );
    const infoByLocale = new Map(infoLocalizations.map((l) => [l.attributes.locale, l]));
    for (const language of wanted) {
      const locale = LOCALE_BY_LANGUAGE[language] ?? language;
      const localization = infoByLocale.get(locale);
      const subtitle = listings[language].subtitle;
      if (!localization) {
        missingLocales.push(`subtitle ${language} -> ${locale}`);
        continue;
      }
      if (localization.attributes?.subtitle === subtitle) continue;
      console.log(`  ${locale.padEnd(9)} subtitle -> ${subtitle}`);
      if (dryRun) {
        plan('PATCH', `/v1/appInfoLocalizations/${localization.id}`, 'subtitle');
        continue;
      }
      await client.patch(`/v1/appInfoLocalizations/${localization.id}`, {
        data: { type: 'appInfoLocalizations', id: localization.id, attributes: { subtitle } },
      });
    }

    // The privacy policy URL lives on the app info, not the version, and is
    // required before submission. It is set once per localization.
    console.log('\n  Privacy policy URL (app info localizations)');
    for (const language of wanted) {
      const locale = LOCALE_BY_LANGUAGE[language] ?? language;
      const localization = infoByLocale.get(locale);
      if (!localization) continue;
      if (localization.attributes?.privacyPolicyUrl === PRIVACY_POLICY_URL) continue;
      if (dryRun) {
        plan('PATCH', `/v1/appInfoLocalizations/${localization.id}`, 'privacyPolicyUrl');
        continue;
      }
      await client.patch(`/v1/appInfoLocalizations/${localization.id}`, {
        data: {
          type: 'appInfoLocalizations',
          id: localization.id,
          attributes: { privacyPolicyUrl: PRIVACY_POLICY_URL },
        },
      });
    }
    console.log(`  ${PRIVACY_POLICY_URL}`);
  }

  heading('Summary');
  console.log(`  ${changed} localization(s) needed changes, ${unchanged} already matched`);
  if (missingLocales.length > 0) {
    console.log(`  ${missingLocales.length} locale(s) have no App Store localization yet:`);
    for (const entry of missingLocales) console.log(`    ${entry}`);
    console.log('  Add them in App Store Connect, then re-run this command.');
  }
  if (dryRun) console.log('  dry run: nothing was written.');
}

// ---------------------------------------------------------------------------
// media
// ---------------------------------------------------------------------------

/**
 * Reads the placement catalog Apple publishes.
 *
 * The catalog is the authority on which placement types exist and which groups
 * each accepts. Resolving against it turns a wrong guess at a type name into a
 * specific error listing the real names.
 *
 * Field names here were read off the live response, not from the prose docs:
 * the types carry `placementTypeId`, groups carry `placementProfileGroupId`,
 * `specMappings` is an array of `{placementGroupId, specs}`, and features carry
 * `featureId`.
 */
async function loadPlacementCatalog(client) {
  const refData = await client.get('/v1/appAssetLibraryRefData');
  const datum = refData?.data?.[0]?.attributes ?? {};
  return {
    groups: datum.placementProfileGroups ?? [],
    types: datum.placementTypes ?? [],
    features: datum.features ?? [],
    specs: datum.imageSpecs ?? [],
  };
}

/**
 * Picks the first candidate name that Apple actually exposes, per spec.
 *
 * Returns a map from `surface/spec` to a concrete placement type, and records
 * the ones that could not be resolved so the caller can report them with the
 * full list of names Apple offers.
 */
function resolvePlacementTypes(catalog, items) {
  const available = new Set(catalog.types.map((type) => type.placementTypeId));
  const resolved = new Map();
  const unresolved = new Map();

  for (const item of items) {
    const key = `${item.surface}/${item.spec}`;
    if (resolved.has(key) || unresolved.has(key)) continue;
    const match = item.placementTypeCandidates.find((name) => available.has(name));
    if (match) resolved.set(key, match);
    else unresolved.set(key, item.placementTypeCandidates);
  }

  return { resolved, unresolved, available: [...available].sort() };
}

/**
 * Chooses the placement group for each surface/spec.
 *
 * Screenshots are device-shaped and each display family has its own group, so
 * the group comes from the plan and is verified against the catalog.
 *
 * Creatives are not device-shaped: every one of the four creative types lives in
 * a single group, `DEFAULT_PROFILE`, which the catalog states directly. Reading
 * it from the type's `specMappings` rather than hard-coding it means an Apple
 * change shows up as a resolved value, not as a failed upload.
 */
function resolvePlacementGroups(catalog, items, placementTypes) {
  const resolved = new Map();
  const unresolved = new Map();
  const allGroups = new Set(catalog.groups.map((group) => group.placementProfileGroupId));

  for (const item of items) {
    const key = `${item.surface}/${item.spec}:${item.group}`;
    if (resolved.has(key) || unresolved.has(key)) continue;

    if (item.groupId) {
      // Screenshots: the plan names the display group.
      if (allGroups.has(item.groupId)) resolved.set(key, item.groupId);
      else unresolved.set(key, `group ${item.groupId} is not in the catalog`);
      continue;
    }

    // Creatives: ask the placement type which groups accept it.
    const placementType = placementTypes.get(`${item.surface}/${item.spec}`);
    const type = catalog.types.find((entry) => entry.placementTypeId === placementType);
    const groupsForType = (type?.specMappings ?? []).map((mapping) => mapping.placementGroupId);
    if (groupsForType.length === 0) {
      unresolved.set(key, `placement type ${placementType} lists no groups`);
      continue;
    }
    if (groupsForType.length === 1) {
      resolved.set(key, groupsForType[0]);
      continue;
    }

    // More than one group accepts this type. Pick the one whose spec list
    // includes a spec matching the dimensions we rendered.
    const specById = new Map(catalog.specs.map((spec) => [spec.specId, spec]));
    const matching = groupsForType.filter((groupId) => {
      const mapping = type.specMappings.find((m) => m.placementGroupId === groupId);
      return (mapping?.specs ?? []).some((specId) => {
        const spec = specById.get(specId);
        if (!spec?.dimensions) return false;
        return spec.dimensions.minWidth <= item.width
          && spec.dimensions.maxWidth >= item.width
          && spec.dimensions.minHeight <= item.height
          && spec.dimensions.maxHeight >= item.height;
      });
    });
    if (matching.length >= 1) {
      resolved.set(key, matching[0]);
      continue;
    }
    unresolved.set(
      key,
      `${placementType} accepts ${groupsForType.length} groups and none matches ${item.width}x${item.height}`,
    );
  }

  return { resolved, unresolved };
}

/**
 * Maps every group in the plan to the localization it should be placed on.
 *
 * Four surfaces, four different target relationships. Containers that do not
 * exist yet are reported rather than created: an in-app event or custom product
 * page carries its own copy and review requirements, and creating one silently
 * as a side effect of a media upload is not a decision this script should make.
 */
async function buildTargetIndex(client, appId, version, items) {
  const index = new Map();
  const absent = [];

  const versionLocalizations = await client.getAll(
    `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`,
  );
  for (const localization of versionLocalizations) {
    index.set(`appStoreVersionLocalization:header:${localization.attributes.locale}`, localization.id);
    index.set(`appStoreVersionLocalization:search:${localization.attributes.locale}`, localization.id);
    // Screenshots share one group name per device family, so key them by the
    // item's group rather than by a fixed label.
    for (const item of items) {
      if (item.surface !== 'app-store-screenshots') continue;
      index.set(
        `appStoreVersionLocalization:${item.group}:${localization.attributes.locale}`,
        localization.id,
      );
    }
  }

  const events = await client.getAll(`/v1/apps/${appId}/appEvents?limit=200`);
  const eventByName = new Map(events.map((e) => [e.attributes?.referenceName, e]));
  for (const item of items.filter((i) => i.surface === 'in-app-events')) {
    const event = eventByName.get(item.group);
    if (!event) {
      absent.push(`in-app event "${item.group}"`);
      continue;
    }
    const localizations = await client.getAll(`/v1/appEvents/${event.id}/localizations?limit=200`);
    for (const localization of localizations) {
      index.set(`appEventLocalization:${item.group}:${localization.attributes.locale}`, localization.id);
    }
  }

  const pages = await client.getAll(`/v1/apps/${appId}/appCustomProductPages?limit=200`);
  const pageByName = new Map(pages.map((p) => [p.attributes?.name, p]));
  for (const item of items.filter((i) => i.surface === 'custom-product-pages')) {
    const page = pageByName.get(item.group);
    if (!page) {
      absent.push(`custom product page "${item.group}"`);
      continue;
    }
    const pageVersions = await client.getAll(
      `/v1/appCustomProductPages/${page.id}/appCustomProductPageVersions?limit=50`,
    );
    for (const pageVersion of pageVersions) {
      const localizations = await client.getAll(
        `/v1/appCustomProductPageVersions/${pageVersion.id}/appCustomProductPageLocalizations?limit=200`,
      );
      for (const localization of localizations) {
        index.set(
          `appCustomProductPageLocalization:${item.group}:${localization.attributes.locale}`,
          localization.id,
        );
      }
    }
  }

  const experiments = await client
    .getAll(`/v1/apps/${appId}/appStoreVersionExperimentsV2?limit=200`)
    .catch(() => []);
  for (const item of items.filter((i) => i.surface === 'product-page-optimization')) {
    const experiment = experiments.find((e) => e.attributes?.name === item.group);
    if (!experiment) {
      absent.push(`experiment "${item.group}"`);
      continue;
    }
    const treatments = await client.getAll(
      `/v1/appStoreVersionExperiments/${experiment.id}/appStoreVersionExperimentTreatments?limit=50`,
    );
    for (const treatment of treatments) {
      const localizations = await client.getAll(
        `/v1/appStoreVersionExperimentTreatments/${treatment.id}/appStoreVersionExperimentTreatmentLocalizations?limit=200`,
      );
      for (const localization of localizations) {
        index.set(
          `appStoreVersionExperimentTreatmentLocalization:${item.group}:${localization.attributes.locale}`,
          localization.id,
        );
      }
    }
  }

  return { index, absent: [...new Set(absent)] };
}

/**
 * Uploads each distinct file once, then places it on every surface it belongs to.
 *
 * This is the shape the asset library is designed for: the same bytes back many
 * placements, and App Store Connect stores and processes them once. Re-running
 * skips a file that is already in the library under the same name, so an
 * interrupted run resumes rather than duplicating.
 */
async function cmdMedia() {
  const { client, appId } = await connect();
  const version = await ensureEditableVersion(client, appId);
  const items = await loadPlan();

  heading('Asset library');
  const library = await client.get(`/v1/apps/${appId}/assetLibrary`);
  const libraryId = library?.data?.id;
  if (!libraryId) throw new Error('App has no asset library. Open the app in App Store Connect once.');
  console.log(`  library ${libraryId}`);

  heading('Placement catalog');
  const catalog = await loadPlacementCatalog(client);
  console.log(`  ${catalog.types.length} placement type(s), ${catalog.groups.length} group(s)`);
  const { resolved, unresolved, available } = resolvePlacementTypes(catalog, items);
  for (const [key, name] of [...resolved].sort()) console.log(`  ${key.padEnd(40)} -> ${name}`);
  if (unresolved.size > 0) {
    console.log('\n  COULD NOT RESOLVE these placement types:');
    for (const [key, candidates] of unresolved) {
      console.log(`    ${key}  tried: ${candidates.join(', ')}`);
    }
    console.log('\n  Names Apple currently exposes:');
    for (const name of available) console.log(`    ${name}`);
    console.log('\n  Fix the candidate list in scripts/publish/plan.mjs and re-run.');
    if (!dryRun) throw new Error(`${unresolved.size} placement type(s) unresolved.`);
  }

  heading('Placement groups');
  const groups = resolvePlacementGroups(catalog, items, resolved);
  for (const [key, name] of [...groups.resolved].sort()) {
    console.log(`  ${key.padEnd(40)} -> ${name}`);
  }
  if (groups.unresolved.size > 0) {
    console.log('\n  COULD NOT RESOLVE these placement groups:');
    for (const [key, reason] of groups.unresolved) console.log(`    ${key}: ${reason}`);
    console.log('\n  Groups Apple currently exposes:');
    for (const group of catalog.groups) {
      console.log(`    ${String(group.groupId).padEnd(48)} ${group.platform} ${group.displayClass}`);
    }
    if (!dryRun) throw new Error(`${groups.unresolved.size} placement group(s) unresolved.`);
  }

  heading('Targets');
  const { index, absent } = await buildTargetIndex(client, appId, version, items);
  console.log(`  ${index.size} localization target(s) resolved`);
  if (absent.length > 0) {
    console.log(`  ${absent.length} container(s) missing, their media will be skipped:`);
    for (const name of absent) console.log(`    ${name}`);
  }

  // Creating a version copies the previous version's screenshots onto it, and
  // those inherited placements count against the per-group limit. A group holds
  // at most 10, so a full inherited set leaves no room and the new uploads are
  // rejected with a limit error that does not mention the inherited media.
  //
  // `--replace` clears the groups this plan manages before creating anything, so
  // the gallery ends up as exactly the new set. It also clears any other
  // APP_SCREENSHOT group, because a stale row for an older display family keeps
  // showing old artwork to users on those devices instead of falling back to the
  // medium set.
  const replace = args.includes('--replace');
  if (replace) {
    heading('Replace: removing existing media');
    const managedGroups = new Set([
      ...groups.resolved.values(),
      ...items.filter((i) => i.surface === 'app-store-screenshots').map((i) => i.groupId),
    ]);
    const removable = [];
    for (const item of items) {
      const targetId = index.get(`${item.targetKind}:${item.group}:${item.locale}`);
      if (!targetId || item.targetKind !== 'appStoreVersionLocalization') continue;
      removable.push({ targetId, locale: item.locale });
    }
    const seenTargets = new Set();
    let removed = 0;
    for (const { targetId, locale } of removable) {
      if (seenTargets.has(targetId)) continue;
      seenTargets.add(targetId);
      const existingPlacements = await client.getAll(
        `/v1/appStoreVersionLocalizations/${targetId}/placements?limit=200`,
      );
      for (const placement of existingPlacements) {
        const type = placement.attributes.placementType;
        const group = placement.attributes.placementGroup;
        // Screenshots: every group, because a stale row is worse than no row.
        // Creatives: only the groups this plan writes to.
        const isScreenshot = type === 'APP_SCREENSHOT';
        const isManagedCreative = managedGroups.has(group) && type !== 'APP_SCREENSHOT';
        if (!isScreenshot && !isManagedCreative) continue;
        console.log(`  ${locale.padEnd(9)} delete ${type}/${group}`);
        if (!dryRun) await client.del(`/v1/appAssetLibraryPlacements/${placement.id}`);
        removed += 1;
      }
    }
    console.log(`  ${removed} placement(s) ${dryRun ? 'would be ' : ''}removed`);
  }

  // Drop anything with no target before uploading. An in-app event image whose
  // event does not exist has nowhere to go, and uploading it would spend a
  // gigabyte of transfer to create an orphan asset in the library. The plan
  // reports these separately instead.
  //
  // `libraryOnly` surfaces are excluded for a different reason: the
  // `asset-library` surface renders the same header and search creatives as
  // `header-and-search`, byte for byte, and targets the same localization and
  // group. Creating placements for both would ask Apple for two assets in a
  // group whose limit is one. The files still get uploaded — that is the point
  // of the library — and `header-and-search` places them.
  const placeable = items.filter((item) =>
    !item.libraryOnly
    && index.has(`${item.targetKind}:${item.group}:${item.locale}`)
    && resolved.has(`${item.surface}/${item.spec}`)
    && groups.resolved.has(`${item.surface}/${item.spec}:${item.group}`));

  const orphaned = items.length - placeable.length;
  if (orphaned > 0) {
    console.log(`\n  ${orphaned} placement(s) not created (library-only, or no container yet)`);
  }

  // One upload per distinct file *by content*, not by path.
  //
  // 42 of the files here are the same bytes on two surfaces: the header and
  // search creatives are rendered into both `header-and-search` and
  // `asset-library`. Deduplicating by content is the whole point of the asset
  // library — upload once, create a placement per surface — and keying by path
  // would upload those 42 twice.
  const hashByFile = new Map();
  const filesByHash = new Map();
  for (const item of placeable) {
    if (!hashByFile.has(item.file)) {
      const hash = createHash('sha256').update(readFileSync(item.file)).digest('hex');
      hashByFile.set(item.file, hash);
      if (!filesByHash.has(hash)) filesByHash.set(hash, item.file);
    }
  }
  const bytes = [...filesByHash.values()].reduce((n, f) => n + statSync(f).size, 0);

  heading('Plan');
  console.log(`  ${placeable.length} placement(s) to create, ${orphaned} skipped`);
  console.log(
    `  ${filesByHash.size} distinct file(s) by content, `
    + `${(bytes / 1024 / 1024).toFixed(1)} MB to upload`,
  );
  const saved = new Set(placeable.map((i) => i.file)).size - filesByHash.size;
  if (saved > 0) console.log(`  ${saved} duplicate file(s) avoided by content hash`);

  if (dryRun) {
    for (const [hash, file] of filesByHash) {
      const item = placeable.find((i) => i.file === file);
      plan('POST', '/v1/appAssetLibraryImages', `${basename(file)} (${item.category}) ${hash.slice(0, 12)}`);
    }
    console.log(`  [dry-run] then ${placeable.length} placement request(s)`);
    return;
  }

  if (!(await confirm(`Upload ${filesByHash.size} file(s) and create ${placeable.length} placement(s)?`))) {
    console.log('  cancelled.');
    return;
  }

  // Assets are named by content hash, so a re-run finds what it already sent
  // instead of uploading the same bytes again.
  const existing = new Map();
  const existingAssets = await client.getAll(`/v1/appAssetLibraries/${libraryId}/images?limit=200`);
  for (const asset of existingAssets) {
    if (asset.attributes?.referenceName) existing.set(asset.attributes.referenceName, asset.id);
  }
  console.log(`\n  library already holds ${existing.size} named image(s)`);

  const assetIdByHash = new Map();
  let uploaded = 0;
  let reused = 0;
  for (const [hash, file] of filesByHash) {
    if (existing.has(hash)) {
      assetIdByHash.set(hash, existing.get(hash));
      reused += 1;
      continue;
    }
    const item = placeable.find((i) => i.file === file);
    process.stdout.write(`  uploading ${basename(file)} ... `);
    const { assetId } = await client.uploadAsset({
      type: 'appAssetLibraryImages',
      libraryId,
      filePath: file,
      category: item.category,
      referenceName: hash,
    });
    await client.waitForAsset({ type: 'appAssetLibraryImages', assetId });
    assetIdByHash.set(hash, assetId);
    uploaded += 1;
    console.log('done');
  }
  console.log(`  ${uploaded} uploaded, ${reused} reused`);

  heading('Placements');
  let placed = 0;
  let skipped = 0;
  const failures = [];
  // Placement IDs per (target, group), so the gallery can be ordered after.
  const byTargetGroup = new Map();

  for (const item of placeable) {
    const assetId = assetIdByHash.get(hashByFile.get(item.file));
    const targetId = index.get(`${item.targetKind}:${item.group}:${item.locale}`);
    const placementType = resolved.get(`${item.surface}/${item.spec}`);
    const placementGroup = groups.resolved.get(`${item.surface}/${item.spec}:${item.group}`);
    if (!assetId || !targetId || !placementType || !placementGroup) {
      skipped += 1;
      continue;
    }
    try {
      const created = await client.post('/v1/appAssetLibraryPlacements', {
        data: {
          type: 'appAssetLibraryPlacements',
          attributes: { placementType, placementGroup },
          relationships: {
            image: { data: { type: 'appAssetLibraryImages', id: assetId } },
            [item.targetKind]: { data: { type: `${item.targetKind}s`, id: targetId } },
          },
        },
      });
      placed += 1;
      // Keyed by placementType as well as group: the header and the search
      // creative both live in DEFAULT_PROFILE on the same localization, and an
      // ordering request rejects a list that mixes two types.
      const key = `${item.targetKind}:${targetId}:${placementType}:${placementGroup}`;
      if (!byTargetGroup.has(key)) {
        byTargetGroup.set(key, {
          targetKind: item.targetKind,
          targetId,
          placementType,
          placementGroup,
          entries: [],
        });
      }
      byTargetGroup.get(key).entries.push({ id: created.data.id, order: item.order ?? 0, item });
    } catch (error) {
      failures.push(`${basename(item.file)} on ${item.targetKind} ${item.locale}: ${error.message}`);
    }
  }

  heading('Gallery order');
  // Screenshots display in sequence and the order is not the upload order, so
  // it has to be set explicitly. In-app event localizations are not orderable —
  // each of their types allows a single asset per group.
  let ordered = 0;
  for (const { targetKind, targetId, placementGroup, entries } of byTargetGroup.values()) {
    if (targetKind === 'appEventLocalization') continue;
    if (entries.length < 2) continue;
    const sequence = [...entries].sort((a, b) => a.order - b.order).map((entry) => entry.id);
    try {
      await client.post('/v1/appAssetLibraryPlacementOrderingRequests', {
        data: {
          type: 'appAssetLibraryPlacementOrderingRequests',
          attributes: { placementGroup },
          relationships: {
            orderedPlacements: {
              data: sequence.map((id) => ({ type: 'appAssetLibraryPlacements', id })),
            },
            [targetKind]: { data: { type: `${targetKind}s`, id: targetId } },
          },
        },
      });
      ordered += 1;
    } catch (error) {
      failures.push(`ordering ${placementGroup} on ${targetKind} ${targetId}: ${error.message}`);
    }
  }
  console.log(`  ${ordered} group(s) ordered`);

  heading('Summary');
  console.log(`  ${placed} placement(s) created, ${skipped} skipped (no target or group)`);
  if (failures.length > 0) {
    console.log(`  ${failures.length} failure(s):`);
    for (const failure of failures.slice(0, 20)) console.log(`    ${failure}`);
    if (failures.length > 20) console.log(`    ... and ${failures.length - 20} more`);
  }
}

// ---------------------------------------------------------------------------
// submit
// ---------------------------------------------------------------------------

/**
 * Resolves `--build=` to a build resource id.
 *
 * Accepts the resource id (a UUID) or the build number. The id is what the API
 * relationship needs, but it is a UUID that appears nowhere in this repo, while
 * the number is what `project.yml` and `publish:verify` show — so the obvious
 * thing to pass used to be the wrong thing.
 */
async function resolveBuildId(client, appId, value) {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (uuid.test(value)) return value;

  const builds = await client.getAll(
    `/v1/builds?filter[app]=${appId}&limit=50&fields[builds]=version,processingState`,
  );
  const match = builds.find((b) => b.attributes.version === value);
  if (!match) {
    const known = builds
      .map((b) => `${b.attributes.version} (${b.attributes.processingState})`)
      .join(', ');
    throw new Error(`No build "${value}" on this app. Present: ${known || 'none'}.`);
  }
  return match.id;
}

/** Creates a review submission containing the version, then submits it. */
async function cmdSubmit() {
  const { client, appId } = await connect();
  const version = await ensureEditableVersion(client, appId);
  heading(`Submit ${version.attributes.versionString} for review`);

  const buildArg = args.find((a) => a.startsWith('--build='))?.split('=')[1];
  const buildId = buildArg ? await resolveBuildId(client, appId, buildArg) : null;

  if (dryRun) {
    if (buildId) {
      plan('PATCH', '/v1/appStoreVersions/{id}/relationships/build', `attach build ${buildArg}`);
    }
    plan('POST', '/v1/reviewSubmissions', 'create submission, or reuse the open one');
    plan('POST', '/v1/reviewSubmissionItems', `add version ${version.attributes.versionString}`);
    plan('PATCH', '/v1/reviewSubmissions/{id}', 'submitted: true');
    return;
  }

  // The build attaches to the version *before* the version joins a submission.
  // Apple validates the version when the submission item is created, and a
  // version with no build cannot be reviewed: attaching afterwards fails the
  // item POST with STATE_ERROR.ENTITY_STATE_INVALID, which names no cause and
  // points at nothing. That is how the first 1.1.1 submission attempt failed.
  if (buildId) {
    await client.patch(`/v1/appStoreVersions/${version.id}/relationships/build`, {
      data: { type: 'builds', id: buildId },
    });
    console.log(`  attached build ${buildArg}`);
  }

  // Reuse an open draft rather than creating a second one. A submission that was
  // created but never submitted stays open, and a failed attempt leaves one
  // behind, so the next run would otherwise collide with it.
  const submissions = await client.getAll(
    `/v1/reviewSubmissions?filter[app]=${appId}&limit=20&fields[reviewSubmissions]=state`,
  );
  const open = submissions.find((s) => s.attributes.state === 'READY_FOR_REVIEW');
  let submissionId;
  if (open) {
    submissionId = open.id;
    console.log(`  reusing open submission ${submissionId}`);
  } else {
    const created = await client.post('/v1/reviewSubmissions', {
      data: {
        type: 'reviewSubmissions',
        attributes: { platform: version.attributes.platform },
        relationships: { app: { data: { type: 'apps', id: appId } } },
      },
    });
    submissionId = created.data.id;
    console.log(`  submission ${submissionId}`);
  }

  await client.post('/v1/reviewSubmissionItems', {
    data: {
      type: 'reviewSubmissionItems',
      relationships: {
        reviewSubmission: { data: { type: 'reviewSubmissions', id: submissionId } },
        appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } },
      },
    },
  });
  console.log('  version added to the submission');

  if (!(await confirm('Submit this version to App Review?'))) {
    console.log(`  left as a draft submission (${submissionId}). Submit it from App Store Connect.`);
    return;
  }

  await client.patch(`/v1/reviewSubmissions/${submissionId}`, {
    data: { type: 'reviewSubmissions', id: submissionId, attributes: { submitted: true } },
  });
  console.log('  submitted. App Review usually responds within 24-48 hours.');
}

// ---------------------------------------------------------------------------

/**
 * Sets the display order of existing placements.
 *
 * Separate from `media` because ordering is idempotent and cheap while
 * creating placements is neither, and because the order can only be set once
 * every placement in a group exists. Re-running `media` to fix an order would
 * create a duplicate gallery.
 *
 * Screenshots are the reason this matters: they display in a fixed sequence
 * that is not the upload order, so without this the gallery appears in
 * whatever order the files happened to be created.
 *
 * The position lookup lives in `plan.mjs` (`orderLookups` / `orderSequence`),
 * because it is the one part of this command that is pure and therefore
 * checkable without live credentials. It keys by **content hash** — the asset's
 * `referenceName` — with the basename as a tie-breaker only, so two files that
 * share a basename across device families stay distinct.
 */
async function cmdOrder() {
  const { client, appId } = await connect();
  const version = await ensureEditableVersion(client, appId);
  const items = await loadPlan();

  heading(`Gallery order for ${version.attributes.versionString}`);

  const localizations = await client.getAll(
    `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`,
  );

  const lookups = orderLookups(items, { readFile: readFileSync, createHash });

  let ordered = 0;
  for (const localization of localizations) {
    const placements = await client.getAll(
      `/v1/appStoreVersionLocalizations/${localization.id}/placements?limit=200&include=image`,
    );
    if (placements.data.length < 2) continue;

    // An ordering request accepts one placement type in one group, so the
    // placements are bucketed by both.
    const buckets = new Map();
    for (const placement of placements.data) {
      const key = `${placement.attributes.placementType}:${placement.attributes.placementGroup}`;
      if (!buckets.has(key)) {
        buckets.set(key, {
          placementType: placement.attributes.placementType,
          placementGroup: placement.attributes.placementGroup,
          placements: [],
        });
      }
      buckets.get(key).placements.push(placement);
    }

    for (const bucket of buckets.values()) {
      if (bucket.placements.length < 2) continue;
      const orderedEntries = orderSequence(
        { data: bucket.placements, included: placements.included },
        lookups,
      );
      const sequence = orderedEntries.map((entry) => entry.id);

      if (dryRun) {
        plan(
          'POST',
          '/v1/appAssetLibraryPlacementOrderingRequests',
          `${localization.attributes.locale} ${bucket.placementType} (${sequence.length})`,
        );
        for (const entry of orderedEntries) {
          console.log(`        ${String(entry.position).padStart(3)}  ${entry.name || entry.id}`);
        }
        continue;
      }
      await client.post('/v1/appAssetLibraryPlacementOrderingRequests', {
        data: {
          type: 'appAssetLibraryPlacementOrderingRequests',
          attributes: { placementGroup: bucket.placementGroup },
          relationships: {
            orderedPlacements: {
              data: sequence.map((id) => ({ type: 'appAssetLibraryPlacements', id })),
            },
            appStoreVersionLocalization: {
              data: { type: 'appStoreVersionLocalizations', id: localization.id },
            },
          },
        },
      });
      ordered += 1;
    }
  }

  console.log(`  ${ordered} group(s) ordered${dryRun ? ' (dry run)' : ''}`);
}

const COMMANDS = {
  build: cmdBuild,
  prepare: cmdPrepare,
  details: cmdDetails,
  media: cmdMedia,
  order: cmdOrder,
  submit: cmdSubmit,
  /**
   * Reports credential state without making an API call.
   *
   * Run this first after setting up a key: it distinguishes "no credentials" from
   * "credentials that do not parse" from "credentials Apple rejects", which are
   * three different problems with three different fixes. Pass --live to add the
   * last of those, which is the only step that touches the network.
   */
  async doctor() {
    const { loadEnvFile, redact } = await import('./asc.mjs');
    const live = args.includes('--live');

    heading('Credential source');
    const envPath = join(ROOT, '.env');
    const fromFile = existsSync(envPath);
    console.log(`  ${envPath}`);
    console.log(`  ${fromFile ? 'present' : 'absent (export the variables instead)'}`);
    if (fromFile) {
      // Confirm the file cannot be committed, since it holds a live credential.
      try {
        execFileSync('git', ['check-ignore', '-q', '.env'], { cwd: ROOT });
        console.log('  gitignored: yes');
      } catch {
        console.log('  gitignored: NO -- add .env to .gitignore before putting a key in it');
      }
    }

    const env = loadEnvFile(envPath, { ...process.env });
    heading('Values');
    console.log(`  ASC_KEY_ID      ${redact(env.ASC_KEY_ID)}`);
    console.log(`  ASC_ISSUER_ID   ${redact(env.ASC_ISSUER_ID)}`);
    console.log(`  ASC_KEY_PATH    ${env.ASC_KEY_PATH ?? '(unset)'}`);

    heading('Private key');
    if (!env.ASC_KEY_PATH) {
      console.log('  cannot check: ASC_KEY_PATH is unset');
      return;
    }
    if (!existsSync(env.ASC_KEY_PATH)) {
      console.log(`  NOT FOUND at ${env.ASC_KEY_PATH}`);
      console.log('  Apple lets you download a key once. If it is gone, revoke it and make a new one.');
      return;
    }
    try {
      const { createPrivateKey } = await import('node:crypto');
      const key = createPrivateKey(readFileSync(env.ASC_KEY_PATH, 'utf8'));
      console.log(`  parses as ${key.asymmetricKeyType} (${key.asymmetricKeyDetails?.namedCurve ?? 'unknown curve'})`);
      if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
        console.log('  WARNING: App Store Connect requires an EC P-256 key. This is not one.');
      } else {
        console.log('  correct type for App Store Connect');
      }
    } catch (error) {
      console.log(`  DOES NOT PARSE: ${error.message}`);
      return;
    }

    if (!live) {
      console.log('\nCredentials look usable. Re-run with --live to check them against Apple.');
      return;
    }

    heading('Live check');
    const client = createClient({ ...credentialsFromEnv(), log: () => {} });
    try {
      const app = await findApp(client, BUNDLE_ID);
      console.log(`  authenticated; found "${app.attributes.name}" (${app.id})`);
      const version = await ensureEditableVersion(client, app.id);
      console.log(`  editable version: ${version.attributes.versionString}`);
      const library = await client.get(`/v1/apps/${app.id}/assetLibrary`);
      console.log(`  asset library: ${library?.data?.id ?? '(none)'}`);
      console.log('\nReady. Next: npm run publish:build');
    } catch (error) {
      console.log(`  REJECTED: ${error.message}`);
      console.log('\n  A 401 here usually means the key ID and the .p8 do not match,');
      console.log('  or the key was revoked. A 403 means the key\'s role is too low.');
    }
  },
  /** Prints the plan without touching the network, so it works offline. */
  async plan() {
    const { summarisePlan } = await import('./plan.mjs');
    const items = await loadPlan();
    heading('Publish plan');
    console.log(summarisePlan(items));
    const byHash = new Map();
    for (const item of items) {
      const hash = createHash('sha256').update(readFileSync(item.file)).digest('hex');
      if (!byHash.has(hash)) byHash.set(hash, []);
      byHash.get(hash).push(item);
    }
    const bytes = [...byHash.keys()].reduce((n, hash) => {
      const file = byHash.get(hash)[0].file;
      return n + statSync(file).size;
    }, 0);
    console.log(
      `\n  ${byHash.size} distinct file(s) by content, `
      + `${(bytes / 1024 / 1024).toFixed(1)} MB to upload`,
    );
    console.log(`  ${items.length - byHash.size} placement(s) reuse an already-uploaded file`);
  },
  async all() {
    await cmdPrepare();
    await cmdBuild();
    await cmdDetails();
    await cmdMedia();
    await cmdSubmit();
  },
};

async function main() {
  const run = COMMANDS[command];
  if (!run) {
    console.error(`Unknown command "${command}".`);
    console.error(`Available: ${Object.keys(COMMANDS).join(', ')}`);
    process.exit(2);
  }
  if (dryRun) console.log('DRY RUN: no writes will be made.');
  await run();
  if (dryRun) console.log('\nDry run complete. Re-run without --dry-run to apply.');
}

main().catch((error) => {
  if (error instanceof AscError) {
    console.error(`\nApp Store Connect rejected the request.\n${error.message}`);
  } else {
    console.error(`\nFAILED: ${error.message}`);
  }
  process.exit(1);
});
