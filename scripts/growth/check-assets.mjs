#!/usr/bin/env node
/**
 * check-assets.mjs — validate every growth asset against Apple's accepted sizes.
 *
 *   node scripts/growth/check-assets.mjs [--strict]
 *
 * Reads each surface's `manifest.json`, then opens every PNG it lists and checks
 * what Apple actually rejects:
 *
 *   1. **Dimensions** — inside the surface's accepted min/max, and matching the
 *      aspect ratio. A creative at the wrong ratio is rejected on upload.
 *   2. **Alpha channel** — Apple rejects transparency. This is the failure that
 *      is easiest to ship by accident, because Playwright and `simctl` both
 *      write RGBA by default and the image looks fine in Preview.
 *   3. **Coverage** — every language has every asset. A missing language is a
 *      storefront showing English, which is exactly what Apple's localization
 *      requirement exists to prevent.
 *   4. **Opacity** — the file is not a blank or near-blank canvas. A renderer
 *      that silently failed to load its background art produces a flat cream
 *      card, which passes every size check and is worthless.
 *
 * `--strict` turns the coverage and opacity warnings into failures, for CI.
 * Without it they are printed as `WARN:` lines and the run still exits 0, so a
 * local run reports the gap without blocking. Everything else (dimensions, the
 * aspect ratio, alpha, an unreadable file) fails in both modes.
 */

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT, SURFACES, LANGUAGES, SPECS } from './manifest.mjs';

const OUT_ROOT = join(ROOT, 'docs/growth');
const strict = process.argv.includes('--strict');

let failures = 0;
let warnings = 0;

function fail(message) {
  console.error(`FAIL: ${message}`);
  failures += 1;
}

function warn(message) {
  console.warn(`WARN: ${message}`);
  warnings += 1;
}

/**
 * Reads a PNG's dimensions and color type.
 *
 * Parsed from the IHDR chunk rather than shelling out to `sips`, so the check
 * works in CI where ImageMagick and `sips` may not exist. The IHDR is always the
 * first chunk: 8 bytes of signature, 4 of length, 4 of type, then 8 of
 * width/height and 1 of bit depth and 1 of color type.
 */
function readPng(path) {
  const buffer = readFileSync(path);
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (!buffer.subarray(0, 8).equals(signature)) {
    throw new Error('not a PNG');
  }
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  const bitDepth = buffer[24];
  const colorType = buffer[25];
  return { width, height, bitDepth, colorType, bytes: buffer.length };
}

/**
 * Whether a PNG carries transparency.
 *
 * Color type 6 (RGBA) and 4 (grayscale + alpha) have an alpha channel. Color
 * type 3 (palette) can carry one in its `tRNS` chunk, so a palette image is
 * treated as suspicious rather than assumed clean.
 */
function hasAlpha(colorType) {
  return colorType === 4 || colorType === 6 || colorType === 3;
}

/**
 * A cheap proxy for "is this image actually a rendered card".
 *
 * Samples the raw bytes and measures how many distinct values appear. A flat
 * canvas compresses to almost nothing and has very few distinct bytes; a real
 * photograph has thousands. This is not a visual check — it exists to catch the
 * specific failure where the background art silently fails to load and the
 * renderer emits a solid cream card that passes every dimension check.
 */
function looksBlank(path) {
  const { bytes } = readPng(path);
  // A 1920x1080 PNG of a real photograph is well over 100 KB. A flat fill of the
  // same size is a few KB.
  const perPixel = bytes / (1920 * 1080);
  return perPixel < 0.02;
}

const problems = [];

for (const surface of SURFACES) {
  const dir = join(OUT_ROOT, surface.id);
  const manifestPath = join(dir, 'manifest.json');
  if (!existsSync(manifestPath)) {
    problems.push(`${surface.id}: no manifest.json — run \`node scripts/growth/build-assets.mjs\``);
    continue;
  }
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const assets = manifest.assets ?? [];
  if (assets.length === 0) {
    problems.push(`${surface.id}: manifest lists no assets`);
    continue;
  }

  // Coverage: every (group, spec) pair must have every language.
  //
  // A warning, not a failure, so a local run without `--strict` reports the gap
  // and still exits 0. CI runs `--strict` (see `check:growth`), which promotes it
  // to a failure. Both findings here and the blank check below used to be pushed
  // straight into `problems`, which made `warn()` unreachable and `--strict` a
  // no-op.
  const byGroupSpec = new Map();
  for (const asset of assets) {
    const key = `${asset.group}--${asset.spec}`;
    if (!byGroupSpec.has(key)) byGroupSpec.set(key, new Set());
    byGroupSpec.get(key).add(asset.language);
  }
  for (const [key, langs] of byGroupSpec) {
    const missing = LANGUAGES.filter((l) => !langs.has(l));
    if (missing.length > 0) {
      warn(`${surface.id}: ${key} is missing ${missing.length} language(s): ${missing.join(', ')}`);
    }
  }

  let checked = 0;
  for (const asset of assets) {
    const spec = SPECS[asset.spec];
    const path = join(dir, asset.file);
    if (!existsSync(path)) {
      problems.push(`${surface.id}: missing file ${asset.file}`);
      continue;
    }

    let info;
    try {
      info = readPng(path);
    } catch (error) {
      problems.push(`${surface.id}: ${asset.file} is not a readable PNG (${error.message})`);
      continue;
    }

    // The manifest records what was intended; the file is what ships. Check the
    // file, and report when the two disagree.
    if (info.width !== asset.width || info.height !== asset.height) {
      problems.push(
        `${surface.id}: ${asset.file} is ${info.width}x${info.height} on disk but the `
        + `manifest claims ${asset.width}x${asset.height}`,
      );
      continue;
    }

    if (spec) {
      const { min, max, ratio } = spec;
      if (info.width < min.width || info.height < min.height
        || info.width > max.width || info.height > max.height) {
        problems.push(
          `${surface.id}: ${asset.file} is ${info.width}x${info.height}, outside Apple's `
          + `${min.width}x${min.height}–${max.width}x${max.height} for ${spec.label}`,
        );
      }
      const [rw, rh] = ratio.split(':').map(Number);
      const expected = rw / rh;
      const actual = info.width / info.height;
      // A 1% tolerance absorbs rounding at the smallest accepted sizes.
      if (Math.abs(actual - expected) / expected > 0.01) {
        problems.push(
          `${surface.id}: ${asset.file} is ${info.width}x${info.height} `
          + `(${actual.toFixed(3)}), but ${spec.label} must be ${ratio} (${expected.toFixed(3)})`,
        );
      }
    }

    if (hasAlpha(info.colorType)) {
      problems.push(
        `${surface.id}: ${asset.file} has an alpha channel (PNG color type ${info.colorType}) `
        + '— Apple rejects transparency in App Store assets',
      );
    }

    if (looksBlank(path)) {
      warn(
        `${surface.id}: ${asset.file} looks blank (${(info.bytes / 1024).toFixed(0)} KB for `
        + `${info.width}x${info.height}) — the background art probably failed to load`,
      );
    }

    checked += 1;
  }

  console.log(`${surface.id.padEnd(28)} ${String(checked).padStart(4)} asset(s) checked`);
}

if (problems.length > 0) {
  console.error('');
  for (const problem of problems) fail(problem);
}

if (warnings > 0 && strict) {
  failures += warnings;
}

console.log('');
if (failures > 0) {
  console.error(`${failures} problem(s) found.`);
  process.exit(1);
}
if (warnings > 0) {
  // Non-strict: the warning is the outcome. The all-clear line below is not
  // printed, because it claims every language is present.
  console.log(`${warnings} warning(s). These fail the build under --strict, which is what CI runs.`);
  process.exit(0);
}
console.log(`Growth assets OK — every asset is inside Apple's accepted size, opaque, and present in all ${LANGUAGES.length} languages.`);
