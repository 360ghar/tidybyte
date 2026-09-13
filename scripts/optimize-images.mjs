#!/usr/bin/env node
/**
 * optimize-images.mjs — one-time (and re-runnable) screenshot optimizer.
 *
 * Converts the large PNG app screenshots referenced by the marketing site
 * into AVIF + WebP renditions. The full-size PNGs stay on disk (they are
 * still the JSON-LD screenshot fallback) but pages serve the modern
 * formats via <picture> with a 768w/1206w srcset.
 *
 * Usage: node scripts/optimize-images.mjs
 */
import sharp from "sharp";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DIR = join(ROOT, "public", "assets", "img", "screenshots");

// Screenshots actually referenced by pages or JSON-LD.
const NAMES = [
  "01-swipe-home",
  "02-cleanup-tools",
  "03-storage-dashboard",
  "04-settings",
  "05-swipe-session",
  "06-album-picker",
  "07-session-complete",
];

let totalIn = 0;
let totalOut = 0;
for (const name of NAMES) {
  for (const variant of [`${name}-768.png`, `${name}.png`]) {
    const src = join(DIR, variant);
    if (!existsSync(src)) {
      console.log(`skip (missing): ${variant}`);
      continue;
    }
    const stem = variant.replace(/\.png$/, "");
    const input = sharp(src);
    const meta = await input.metadata();
    totalIn += meta.size ?? 0;

    const avifOut = join(DIR, `${stem}.avif`);
    const webpOut = join(DIR, `${stem}.webp`);
    await input.clone().avif({ quality: 55, effort: 4 }).toFile(avifOut);
    await input.clone().webp({ quality: 78 }).toFile(webpOut);

    const { size: aSize } = await import("node:fs").then((fs) =>
      fs.promises.stat(avifOut),
    );
    const { size: wSize } = await import("node:fs").then((fs) =>
      fs.promises.stat(webpOut),
    );
    totalOut += aSize + wSize;
    console.log(
      `${variant} (${((meta.size ?? 0) / 1024).toFixed(0)} KB) -> ${stem}.avif (${(aSize / 1024).toFixed(0)} KB) + ${stem}.webp (${(wSize / 1024).toFixed(0)} KB)`,
    );
  }
}
console.log(
  `total: ${(totalIn / 1024).toFixed(0)} KB PNG -> ${(totalOut / 1024).toFixed(0)} KB AVIF+WebP`,
);
