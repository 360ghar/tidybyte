#!/usr/bin/env node
// One-off final parity re-check: compare EVERY file in the pre-migration
// snapshot against dist/. Stronger than --check: proves the final
// committed state, not just internal consistency.
//
// Usage (the baseline lives only in git history):
//   git archive cdf022b site | tar -x -C /tmp/baseline-site
//   node scripts/recheck-final-parity.mjs
//
// Known benign findings: netlify.toml "missing" (moved to repo root) and
// assets/css/styles.css "extra" (gitignored in the snapshot but present
// in the deployed baseline and in dist/ alike).
import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join } from "node:path";

const BASE = "/tmp/baseline-site/site";
const DIST = join(process.cwd(), "dist");
const HASH_RE = /(\/assets\/(?:css|js)\/[A-Za-z0-9_-]+)\.[0-9a-f]{8}\.(css|js)/g;
const normalize = (s) => s.replace(HASH_RE, "$1.$2");

function filesUnder(dir, rel = "") {
  const out = [];
  for (const f of readdirSync(join(dir, rel), { withFileTypes: true })) {
    const r = rel ? `${rel}/${f.name}` : f.name;
    if (f.isDirectory()) out.push(...filesUnder(dir, r));
    else out.push(r);
  }
  return out;
}
const baseFiles = filesUnder(BASE).sort();
const distFiles = filesUnder(DIST).sort();

let same = 0, diff = [], missingInDist = [];
for (const rel of baseFiles) {
  const d = join(DIST, rel);
  if (!existsSync(d)) { missingInDist.push(rel); continue; }
  const a = readFileSync(d), b = readFileSync(join(BASE, rel));
  if (rel.endsWith(".html")) {
    if (normalize(a.toString("utf8")) !== normalize(b.toString("utf8"))) diff.push(rel); else same++;
  } else {
    if (!a.equals(b)) diff.push(rel); else same++;
  }
}
const extra = distFiles.filter((f) => !baseFiles.includes(f) && !/\.[0-9a-f]{8}\.(js|css)$/.test(f));

console.log(`snapshot files: ${baseFiles.length}, dist files: ${distFiles.length}`);
console.log(`byte-identical: ${same}/${baseFiles.length - missingInDist.length}`);
if (missingInDist.length) console.log("MISSING in dist:", missingInDist.join(", "));
if (diff.length) console.log("DIFFER:", diff.slice(0, 10).join(", "));
if (extra.length) console.log("EXTRA in dist (unexpected):", extra.join(", "));
if (!missingInDist.length && !diff.length && !extra.length) {
  console.log("FINAL PARITY CONFIRMED: every pre-migration file matches dist/");
} else process.exit(1);
