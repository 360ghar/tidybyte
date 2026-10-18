#!/usr/bin/env node
/**
 * check-resizability.mjs — fail when the app sources regress into Apple's
 * banned, non-resizable layout patterns.
 *
 * iPhone Duo (foldable, iOS 27.1) can present the system bars vertically on a
 * side edge and resize the window at any moment. Code that reads the *device*
 * (screen size, idiom, orientation) instead of the *window* looks fine in one
 * pose and breaks in the next, and nothing in the build catches it. This is
 * that catch.
 *
 * Scanned roots (override with `--path`):
 *   Tidybyte/        TidybyteWidget/
 *
 * Banned patterns, one rule each:
 *   screen-main              UIScreen.main / .mainScreen / <alias>.main
 *   scene-screen             <scene>.screen read for layout
 *   device-orientation       UIDevice.current.orientation
 *   device-idiom             UIDevice.current.userInterfaceIdiom
 *   interface-orientation    interfaceOrientation (incl. effectiveGeometry.…)
 *   status-bar-orientation   statusBarOrientation
 *   ignores-safe-area-horizontal
 *                            .ignoresSafeArea(… .horizontal …) on content
 *   hardcoded-screen-size    device pixel/point sizes used as layout constants
 *
 * Skipped: test bundles, the `xcode-skills/` tree, `Preview Content`,
 * `.build`/`DerivedData`, and comments/strings that merely *document* a ban
 * (e.g. "replaces deprecated UIScreen.main").
 *
 * NOT skipped: `Tidybyte/Scripts/`. This guard scans the 125 Swift files under
 * `Tidybyte/` and `TidybyteWidget/` as-is, including
 * `Tidybyte/Scripts/GenerateAppIcon.swift`. The icon script is not layout code,
 * but it is clean against every rule, so keeping one "scan every Swift file"
 * rule is simpler than a special case. (An earlier revision of this header
 * claimed the directory was skipped; it never was.)
 *
 * Waivers — two forms, both intentional and both logged:
 *   1. Inline:  `// duo-guard:allow <reason>` on the offending line suppresses
 *      every rule for that line. Use it when one line is legitimately exempt.
 *   2. Background heuristic: `.ignoresSafeArea(… .horizontal …)` is NOT
 *      reported when the same line is a background/overlay/fill/shape layer —
 *      a full-bleed backdrop is supposed to reach the edges. Content that
 *      escapes the safe area is the bug, and that is what still fails.
 *
 * Multi-line statements: a logical statement is matched with its continuation
 * lines joined, so `UIScreen` / `.main` on two lines, or a `CGSize(` whose
 * `width:` / `height:` sit on their own lines, are caught. Findings still point
 * at the original source line. A line continues onto the next when it ends in
 * `(`, `[`, `,` or `.`, or when the next line begins with `.` (modifier chain).
 *
 * Type aliases: simple same-file `typealias X = UIScreen` aliases are resolved,
 * so `X.main` is caught. Aliases to *other* banned types (e.g.
 * `typealias D = UIDevice`) are NOT resolved — see Limits.
 *
 * Limits — what a static, regex-based scan cannot catch, so a clean run is not
 * a proof of correctness, only the absence of these textual patterns:
 *   - Layout arithmetic derived at runtime (a screen size computed from other
 *     numbers, then used to lay out a view).
 *   - Size-class assumptions: `.horizontalSizeClass`/`.verticalSizeClass`
 *     branches that silently mean "iPhone" or "iPad".
 *   - Geometry read indirectly through a helper, a protocol witness, or a value
 *     passed in from another file, so the banned token never appears here.
 *   - Aliases that reach a banned type through more than one hop, or that are
 *     declared in another file (`typealias` chains).
 *   - `.ignoresSafeArea(edges: .all)` and bare `.ignoresSafeArea()`. `.all`
 *     escapes the horizontal axis too (a known false negative); bare
 *     `.ignoresSafeArea()` is the deliberate full-bleed backdrop the app uses
 *     and is intentionally allowed.
 *   - Which of two numbers is "a screen" when the value is not one of the
 *     published device geometries (the rule keys off a known-pairs table).
 *
 * Usage:
 *   node scripts/duo/check-resizability.mjs [--verbose] [--path <dir>]…
 *   --verbose   also list every file and rule set checked, and waivers taken
 * Exit 0 clean, 1 on any finding, 2 on bad usage. No dependencies, no macOS
 * APIs — runs on any CI runner.
 */
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

/** Each rule: id, a matcher, and the fix to state in the report. */
const RULES = [
  {
    id: "screen-main",
    re: /\bUIScreen\s*\.\s*main\b|\.mainScreen\b/,
    // Same-file `typealias X = UIScreen` names are added per file, so
    // `X.main` and `X.mainScreen` are caught alongside the literal forms.
    extraRes: (ctx) =>
      [...ctx.screenAliases].map((alias) => new RegExp(`\\b${alias}\\s*\\.\\s*(?:main|mainScreen)\\b`)),
    why: "UIScreen.main is deprecated and describes the device screen, not the resizable window. Read the window scene or the SwiftUI environment instead.",
  },
  {
    id: "scene-screen",
    re: /\b\w*[Ss]cenes?\b[\s\S]*?\.\s*screen\b/,
    why: "Reading `.screen` off a scene/window-scene is device-level geometry (exactly the shape the deleted ScreenMetrics.swift used). Derive layout from the view's own geometry or the window bounds instead.",
  },
  {
    id: "device-orientation",
    re: /\bUIDevice\s*\.\s*current\s*\.\s*orientation\b/,
    why: "Device orientation is wrong under a resizable/multi-scene window. Use the view's geometry or the scene's interface orientation.",
  },
  {
    id: "device-idiom",
    re: /\bUIDevice\s*\.\s*current\s*\.\s*userInterfaceIdiom\b/,
    why: "Idiom no longer identifies the device: a wide iPhone (Duo inner display) is .phone. Gate on window geometry or size class.",
  },
  {
    id: "interface-orientation",
    re: /\binterfaceOrientation\b/,
    why: "interfaceOrientation on a device/screen is device-level. Derive layout from the window's own geometry.",
  },
  {
    id: "status-bar-orientation",
    re: /\bstatusBarOrientation\b/,
    why: "statusBarOrientation is deprecated and wrong with a resizable window. Use the scene's interface orientation or the geometry of the view.",
  },
  {
    id: "ignores-safe-area-horizontal",
    // Match whenever the argument list names the horizontal axis, regardless of
    // whether it *also* names vertical: `[.horizontal, .vertical]` includes the
    // horizontal axis, so a content view using it is the bug. Bare
    // `.ignoresSafeArea()` (no argument) is deliberately NOT matched — a
    // full-bleed backdrop is what the app legitimately does today.
    re: /\.ignoresSafeArea\s*\([^)]*\bhorizontal\b[^)]*\)/,
    why: "Content must not escape the horizontal safe area: on Duo a vertical system bar lives there. Only a background/overlay layer may ignore it.",
  },
  {
    id: "hardcoded-screen-size",
    re: /\b(\d{3,4})\s*[x×*]\s*(\d{3,4})\b|CGSize\s*\(\s*width\s*:\s*(\d{3,4})\s*,\s*height\s*:\s*(\d{3,4})\s*\)/,
    why: "A hardcoded device size is a layout that only holds in one pose. Use the window/geometry size.",
    // Matched against the *known device geometries* rather than "any two big
    // numbers": `50 * 1024 * 1024` is a byte constant, not a screen, and a
    // checker that cannot tell the difference reports noise until people stop
    // reading it.
    check: (m) => {
      const a = Number(m[1] ?? m[3]);
      const b = Number(m[2] ?? m[4]);
      return KNOWN_DEVICE_PAIRS.has(devicePairKey(a, b));
    },
  },
];

/**
 * Point and pixel geometries of real devices, canonicalised as
 * `shorter x longer` so `844x390` and `390x844` both hit.
 */
const KNOWN_DEVICE_PAIRS = new Set(
  [
    // iPhone, points
    "320x568", "375x667", "375x812", "390x844", "393x852", "402x874",
    "414x896", "428x926", "430x932",
    // iPhone Duo, points
    "466x678", "669x951",
    // iPad, points
    "768x1024", "810x1080", "820x1180", "834x1112", "834x1194", "1024x1366",
    // iPhone / iPad, pixels
    "750x1334", "1125x2436", "1170x2532", "1179x2556", "1206x2622",
    "1242x2208", "1242x2688", "1284x2778", "1290x2796", "1320x2868",
    "1398x2034", "2007x2853", "1536x2048", "1668x2388", "2048x2732",
  ].map((pair) => {
    const [a, b] = pair.split("x").map(Number);
    return devicePairKey(a, b);
  }),
);

function devicePairKey(a, b) {
  return `${Math.min(a, b)}x${Math.max(a, b)}`;
}

/** Background-ish receivers for which a horizontal safe-area escape is fine. */
const BACKGROUND_HINT = /\b(background|overlay|fill|shape|gradient|Color\.|material|scrim)\b/i;

/** Files/dirs never scanned. */
const SKIP_PATH = /(^|\/)(Tests?|UITests?|xcode-skills|\.build|DerivedData|Preview Content)(\/|$)/;
const SKIP_FILE = /Tests?\.swift$/;

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------

const argv = process.argv.slice(2);
let verbose = false;
const roots = [];
for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  if (arg === "--verbose" || arg === "-v") verbose = true;
  else if (arg === "--path") roots.push(argv[++i]);
  else if (arg.startsWith("--path=")) roots.push(arg.slice("--path=".length));
  else if (arg === "--help" || arg === "-h") {
    console.log(
      "usage: node scripts/duo/check-resizability.mjs [--verbose] [--path <dir|file>]…\n" +
        "  --verbose   list files and rules checked, and waivers taken",
    );
    process.exit(0);
  } else {
    console.error(`unknown argument: ${arg}\n`);
    console.error("usage: node scripts/duo/check-resizability.mjs [--verbose] [--path <dir|file>]…");
    process.exit(2);
  }
}

const searchRoots = (roots.length ? roots : [join(REPO_ROOT, "Tidybyte"), join(REPO_ROOT, "TidybyteWidget")])
  .filter((r) => r)
  .map((r) => (r.startsWith("/") ? r : join(process.cwd(), r)));

for (const root of searchRoots) {
  if (!existsSync(root)) {
    console.error(`path does not exist: ${root}`);
    process.exit(2);
  }
}

// ---------------------------------------------------------------------------
// Source handling
// ---------------------------------------------------------------------------

/**
 * Blank out comments and string literals, preserving every newline so line
 * numbers stay exact. Bans must not trip on a doc comment that names them, nor
 * on a string that happens to contain "390x844".
 */
function blankCommentsAndStrings(src) {
  const out = src.split("");
  let state = "code";
  let i = 0;
  const blank = (idx) => {
    if (src[idx] !== "\n") out[idx] = " ";
  };
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (state === "code") {
      if (c === "/" && n === "/") {
        while (i < src.length && src[i] !== "\n") {
          blank(i);
          i += 1;
        }
        continue;
      }
      if (c === "/" && n === "*") {
        blank(i);
        blank(i + 1);
        i += 2;
        state = "block";
        continue;
      }
      if (c === '"' && n === '"' && src[i + 2] === '"') {
        i += 3;
        state = "multistring";
        continue;
      }
      if (c === '"') {
        i += 1;
        state = "string";
        continue;
      }
      i += 1;
      continue;
    }
    if (state === "block") {
      if (src[i] === "*" && src[i + 1] === "/") {
        blank(i);
        blank(i + 1);
        i += 2;
        state = "code";
        continue;
      }
      blank(i);
      i += 1;
      continue;
    }
    if (state === "string") {
      if (c === "\\") {
        blank(i);
        blank(i + 1);
        i += 2;
        continue;
      }
      if (c === '"') {
        state = "code";
        i += 1;
        continue;
      }
      if (c === "\n") {
        state = "code";
        i += 1;
        continue;
      }
      blank(i);
      i += 1;
      continue;
    }
    // multistring
    if (c === '"' && n === '"' && src[i + 2] === '"') {
      i += 3;
      state = "code";
      continue;
    }
    blank(i);
    i += 1;
  }
  return out.join("");
}

/**
 * Same-file `typealias X = UIScreen` names. Runs over already-stripped source
 * so a commented-out alias does not count.
 */
function screenAliasesIn(strippedSrc) {
  const aliases = new Set();
  const re = /\btypealias\s+(\w+)\s*=\s*UIScreen\b/g;
  let m;
  while ((m = re.exec(strippedSrc)) !== null) aliases.add(m[1]);
  return aliases;
}

/**
 * True when line `cur` continues onto line `next`: the line ends on an opener
 * (`(`, `[`, `,`, `.`), the next line begins with `.` (a modifier chain), or
 * the next line begins with a closing `)`/`]` (an argument list or array
 * literal whose closer sits on its own line). A blank next line always ends the
 * statement.
 */
function isContinuation(cur, next) {
  if (!next.trim()) return false;
  const c = cur.replace(/\s+$/, "");
  if (!c) return false;
  const n = next.replace(/^\s+/, "");
  if (/[(,\[.]$/.test(c)) return true;
  if (n.startsWith(".")) return true;
  return /^[)\]]/.test(n);
}

/**
 * Group stripped lines into logical statements. Joining happens with the real
 * newlines kept, so every `\s`-based rule still matches across the break while
 * `lineForOffset` maps a match back to its original 1-based line.
 */
function buildStatements(lines) {
  const statements = [];
  let i = 0;
  while (i < lines.length) {
    const parts = [lines[i]];
    let j = i;
    while (j + 1 < lines.length && isContinuation(lines[j], lines[j + 1])) {
      j += 1;
      parts.push(lines[j]);
    }
    const starts = [];
    let acc = 0;
    for (const part of parts) {
      starts.push(acc);
      acc += part.length + 1; // +1 for the "\n" join
    }
    const baseLine = i;
    statements.push({
      text: parts.join("\n"),
      // 0-based original line for a match offset into `text`.
      lineForOffset(offset) {
        let k = 0;
        for (let n = 0; n < starts.length; n += 1) {
          if (offset >= starts[n]) k = n;
          else break;
        }
        return baseLine + k;
      },
    });
    i = j + 1;
  }
  return statements;
}

const CWD = process.cwd();

/** Repo-relative when the file is inside the working directory, else absolute. */
function displayPath(file) {
  const rel = relative(CWD, file);
  return rel.startsWith("..") ? file : rel;
}

function swiftFiles(root) {
  const found = [];
  const stat = statSync(root);
  if (stat.isFile()) {
    if (root.endsWith(".swift")) found.push(root);
    return found;
  }
  for (const entry of readdirSync(root)) {
    const full = join(root, entry);
    const rel = relative(REPO_ROOT, full);
    if (SKIP_PATH.test(rel)) continue;
    const s = statSync(full);
    if (s.isDirectory()) found.push(...swiftFiles(full));
    else if (full.endsWith(".swift") && !SKIP_FILE.test(full)) found.push(full);
  }
  return found;
}

// ---------------------------------------------------------------------------
// Scan
// ---------------------------------------------------------------------------

const findings = [];
const waivers = [];
let scannedFiles = 0;

for (const root of searchRoots) {
  for (const file of swiftFiles(root).sort()) {
    scannedFiles += 1;
    const src = readFileSync(file, "utf8");
    const stripped = blankCommentsAndStrings(src);
    const raw = src.split("\n");
    const rel = displayPath(file);
    const ctx = { screenAliases: screenAliasesIn(stripped) };
    for (const statement of buildStatements(stripped.split("\n"))) {
      for (const rule of RULES) {
        const matchers = [rule.re, ...(rule.extraRes ? rule.extraRes(ctx) : [])];
        for (const base of matchers) {
          const re = new RegExp(base.source, base.flags.includes("g") ? base.flags : `${base.flags}g`);
          let m;
          while ((m = re.exec(statement.text)) !== null) {
            if (rule.check && !rule.check(m)) continue;
            const lineNo = statement.lineForOffset(m.index);
            const rawLine = raw[lineNo] ?? "";
            const waiver = /duo-guard:allow\s*(.*)$/.exec(rawLine);
            if (waiver) {
              waivers.push({ file: rel, line: lineNo + 1, rule: rule.id, reason: waiver[1].trim() || "(no reason given)" });
              continue;
            }
            if (rule.id === "ignores-safe-area-horizontal" && BACKGROUND_HINT.test(rawLine)) {
              waivers.push({ file: rel, line: lineNo + 1, rule: rule.id, reason: "background/overlay layer" });
              continue;
            }
            findings.push({
              file: rel,
              line: lineNo + 1,
              rule: rule.id,
              why: rule.why,
              snippet: rawLine.trim(),
            });
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

if (verbose) {
  console.log(`scanned ${scannedFiles} Swift file(s) under:`);
  for (const r of searchRoots) console.log(`  ${displayPath(r)}`);
  console.log(`rules (${RULES.length}): ${RULES.map((r) => r.id).join(", ")}`);
  if (waivers.length) {
    console.log(`waivers taken (${waivers.length}):`);
    for (const w of waivers) console.log(`  ${w.file}:${w.line} ${w.rule} — ${w.reason}`);
  } else {
    console.log("waivers taken: none");
  }
}

if (findings.length) {
  console.error(`\n✗ ${findings.length} resizability violation(s):`);
  for (const f of findings) {
    console.error(`  ${f.file}:${f.line}: [${f.rule}] ${f.snippet}`);
    console.error(`      ${f.why}`);
  }
  console.error(
    "\nIf a hit is legitimate, either move it to a background layer or add" +
      " `// duo-guard:allow <reason>` on the line.",
  );
  process.exit(1);
}

console.log(`✓ resizability clean — ${scannedFiles} Swift file(s), ${RULES.length} rules, ${waivers.length} waiver(s)`);
