#!/usr/bin/env node
/**
 * Read-only report on what App Store Connect currently holds.
 *
 * This runs before anything is written. Uploading is only safe against a
 * version in an editable state, and only useful when we know which localizations
 * and media already exist — so the first command against a live account is
 * always this one.
 *
 * It also dumps the asset library reference data, which is where the valid
 * placement groups come from. Those identifiers are strings, not an enum, and
 * Apple adds new device families without an API version change, so the upload
 * step reads them at runtime rather than hard-coding them.
 *
 * Usage: node scripts/publish/verify.mjs
 */

import { EDITABLE_STATES, createClient, credentialsFromEnv, findApp } from './asc.mjs';
import { BUNDLE_ID, loadPlan, summarisePlan } from './plan.mjs';

const RELEVANT_FEATURES = [
  'APP_STORE_VERSIONS',
  'APP_CUSTOM_PRODUCT_PAGES',
  'IN_APP_EVENTS',
  'PRODUCT_PAGE_OPTIMIZATIONS',
  'APP_ASSET_LIBRARY',
];

function heading(text) {
  console.log(`\n${text}`);
  console.log('-'.repeat(text.length));
}

async function main() {
  const client = createClient({ ...credentialsFromEnv(), log: console.log });
  const app = await findApp(client, BUNDLE_ID);
  const appId = app.id;

  heading('App record');
  console.log(`  id              ${appId}`);
  console.log(`  name            ${app.attributes?.name}`);
  console.log(`  bundleId        ${app.attributes?.bundleId}`);
  console.log(`  primaryLocale   ${app.attributes?.primaryLocale}`);
  console.log(`  sku             ${app.attributes?.sku}`);

  // The asset library is per-app and its ID is stable, so resolve it once.
  heading('Asset library');
  const library = await client.get(`/v1/apps/${appId}/assetLibrary`);
  const libraryId = library?.data?.id ?? null;
  console.log(`  library id      ${libraryId ?? '(none returned)'}`);

  // Every version, so we can see which one is editable. Placements can only be
  // created while the parent surface is in PREPARE_FOR_SUBMISSION.
  heading('App Store versions');
  const versions = await client.getAll(
    `/v1/apps/${appId}/appStoreVersions?limit=50`
    + '&fields[appStoreVersions]=versionString,appStoreState,platform,createdDate',
  );
  if (versions.length === 0) {
    console.log('  (no versions yet)');
  }
  for (const version of versions) {
    const a = version.attributes ?? {};
    console.log(`  ${String(a.versionString).padEnd(8)} ${String(a.appStoreState).padEnd(28)} ${a.platform}  ${version.id}`);
  }

  const editable = versions.filter((v) => EDITABLE_STATES.has(v.attributes?.appStoreState));
  if (editable.length === 0) {
    console.log('\n  WARNING: no editable version.');
    console.log('  Placements cannot be created against an approved or in-review version.');
  } else {
    console.log(`\n  editable: ${editable.map((v) => v.attributes.versionString).join(', ')}`);
  }

  for (const version of editable) {
    heading(`Localizations on ${version.attributes.versionString}`);
    const localizations = await client.getAll(
      `/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`
      + '&fields[appStoreVersionLocalizations]=locale,description,keywords,marketingUrl,promotionalText,supportUrl,whatsNew',
    );
    console.log(`  ${localizations.length} localization(s)`);
    for (const localization of localizations) {
      const a = localization.attributes ?? {};
      console.log(
        `    ${String(a.locale).padEnd(9)}`
        + ` desc=${String(a.description?.length ?? 0).padStart(5)}`
        + ` kw=${String(a.keywords?.length ?? 0).padStart(3)}`
        + ` promo=${String(a.promotionalText?.length ?? 0).padStart(3)}`
        + `  ${localization.id}`,
      );
    }

    heading('Media on this version');
    for (const localization of localizations) {
      const placements = await client.getAll(
        `/v1/appStoreVersionLocalizations/${localization.id}/placements?limit=200`
        + '&sort=placementGroupPosition',
      );
      if (placements.length === 0) continue;
      const byGroup = new Map();
      for (const placement of placements) {
        const key = `${placement.attributes?.placementType}/${placement.attributes?.placementGroup}`;
        byGroup.set(key, (byGroup.get(key) ?? 0) + 1);
      }
      const summary = [...byGroup].map(([key, count]) => `${key}=${count}`).join('  ');
      console.log(`    ${String(localization.attributes.locale).padEnd(9)} ${summary}`);
    }
  }

  heading('In-App Events');
  // `eventType` is not a field on appEvents. Asking for it fails the whole
  // request with PARAMETER_ERROR.INVALID, which is what used to kill this report
  // here — before the asset-library dump, so the Duo group id was never printed.
  // The event's kind is not exposed as an attribute at all, so state and name
  // are what there is to show.
  const events = await client.getAll(
    `/v1/apps/${appId}/appEvents?limit=200&fields[appEvents]=referenceName,eventState`,
  );
  if (events.length === 0) console.log('  (none)');
  for (const event of events) {
    const a = event.attributes ?? {};
    console.log(`  ${String(a.eventState).padEnd(22)} ${String(a.referenceName).padEnd(30)} ${event.id}`);
  }

  heading('Custom product pages');
  const pages = await client.getAll(`/v1/apps/${appId}/appCustomProductPages?limit=200`);
  if (pages.length === 0) console.log('  (none)');
  for (const page of pages) {
    console.log(`  ${page.attributes?.name}  ${page.id}  visible=${page.attributes?.isVisible}`);
  }

  heading('App Store version experiments (Product Page Optimization)');
  const experiments = await client.getAll(
    `/v1/apps/${appId}/appStoreVersionExperimentsV2?limit=200`,
  ).catch(() => []);
  if (experiments.length === 0) console.log('  (none, or the v2 relationship is unavailable)');
  for (const experiment of experiments) {
    const a = experiment.attributes ?? {};
    console.log(`  ${String(a.state).padEnd(20)} ${a.name}  ${experiment.id}`);
  }

  // The reference data is the source of truth for placement groups. Printing
  // the relevant slice here means the upload step never has to guess.
  heading('Reference data: placement groups');
  const refData = await client.get('/v1/appAssetLibraryRefData');
  const datum = refData?.data?.[0]?.attributes ?? {};
  const groups = datum.placementProfileGroups ?? [];
  const types = datum.placementTypes ?? [];
  const specs = datum.imageSpecs ?? [];
  const features = datum.features ?? [];

  console.log(`  ${groups.length} group(s), ${types.length} placement type(s), ${specs.length} image spec(s)`);

  console.log('\n  features we use:');
  for (const feature of features) {
    if (!RELEVANT_FEATURES.includes(feature.featureId)) continue;
    const policies = (feature.placementPolicies ?? [])
      .map((policy) => {
        const limits = (policy.groupLimits ?? [])
          .map((limit) => `${(limit.groupIds ?? []).join('|')}=${limit.maxCount}`)
          .join(', ');
        return `${policy.placementType}${limits ? ` [${limits}]` : ''}`;
      });
    console.log(`    ${feature.featureId}`);
    for (const policy of policies) console.log(`      ${policy}`);
  }

  console.log('\n  placement types we plan to use, with the groups each accepts:');
  const wanted = ['APP_SCREENSHOT', 'APP_PREVIEW', 'PRODUCT_PAGE_HEADER_ASSET', 'EVENT_CARD_ASSET', 'EVENT_DETAILS_ASSET', 'SEARCH_RESULTS_ASSET'];
  for (const type of types) {
    if (!wanted.includes(type.placementTypeId)) continue;
    const groupsForType = Object.keys(type.specMappings ?? {});
    console.log(`    ${type.placementTypeId}  accepts=${(type.acceptsAssetCategories ?? []).join(',')}`);
    console.log(`      groups: ${groupsForType.join(', ') || '(none listed)'}`);
  }

  console.log('\n  every group identifier Apple currently exposes:');
  for (const group of groups) {
    console.log(`    ${String(group.placementProfileGroupId).padEnd(48)} ${String(group.platform).padEnd(18)} ${group.displayClassId}`);
  }

  // Finally, what we intend to push, so the local and remote pictures are
  // side by side before anything is written.
  heading('Local plan');
  const plan = await loadPlan();
  console.log(summarisePlan(plan));

  console.log('\nRead-only report complete. Nothing was written.');
}

main().catch((error) => {
  console.error(`\nFAILED: ${error.message}`);
  process.exit(1);
});
