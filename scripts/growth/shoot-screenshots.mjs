#!/usr/bin/env node
/**
 * shoot-screenshots.mjs — capture App Store Connect screenshots on the
 * required iPhone and iPad display sizes.
 *
 * Why this exists
 * ---------------
 * `docs/screenshots/` shipped a 1206x2622 set that nobody had re-measured
 * against Apple's current spec. App Store Connect accepts only exact pixel
 * sizes (see `REQUIRED_SIZES` below, sourced from
 * https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications),
 * and it rejects images that carry an alpha channel. A screenshot straight
 * from `simctl` is RGBA, so it fails that check as-is.
 *
 * This script drives the simulator end to end: build, install, seed the
 * language, pre-approve the app's URL scheme, navigate with the deep links the
 * app already implements, capture, then strip alpha and verify the dimensions.
 *
 * Navigation reuses what the app already has — no new launch arguments and no
 * new Swift:
 *   - `-hasCompletedOnboarding YES` (the flag `RootView` reads via @AppStorage)
 *   - `tidybyte://` deep links parsed by `DeepLink.from(url:)` in
 *     `Tidybyte/App/DeepLink.swift` (the widget's own routing path)
 *   - `xcrun simctl` for build/install/privacy/status-bar/screenshot
 *
 * The "Open in <App>?" prompt
 * ---------------------------
 * `simctl openurl` on an unapproved scheme raises a SpringBoard confirmation
 * dialog that no CLI flag suppresses. Writing
 * `~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Preferences/com.apple.launchservices.schemeapproval.plist`
 * while the device is booted pre-approves it, so the dialog never appears.
 * The plist must be written with the device up — writing it while shut down
 * does not take effect.
 *
 * Usage
 * -----
 *   node scripts/growth/shoot-screenshots.mjs              # both devices
 *   node scripts/growth/shoot-screenshots.mjs --device iphone
 *   node scripts/growth/shoot-screenshots.mjs --device ipad
 *   node scripts/growth/shoot-screenshots.mjs --check      # verify, capture nothing
 *   node scripts/growth/shoot-screenshots.mjs --keep-booted
 *
 * Output: docs/screenshots/<device>/<NN>-<slug>.png
 */
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { PNG } from "pngjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const OUT_ROOT = join(ROOT, "docs", "screenshots");
const BUNDLE_ID = "com.sakshammittal.tidybyte";
const URL_SCHEME = "tidybyte";
const DERIVED_DATA = join(ROOT, "build", "screenshot-dd");
const APP_PATH = join(DERIVED_DATA, "Build", "Products", "Debug-iphonesimulator", "Tidybyte.app");

const argv = process.argv.slice(2);
const CHECK_ONLY = argv.includes("--check");
const KEEP_BOOTED = argv.includes("--keep-booted");
const deviceFlag = argv.indexOf("--device");
const DEVICE_FILTER = deviceFlag === -1 ? "all" : argv[deviceFlag + 1];

/**
 * The exact sizes App Store Connect accepts, from Apple's reference page.
 *
 * Apple's "Required device sizes" is only two rows today: an iPhone with
 * Dynamic Island (medium display) and, because this app ships iPad
 * (`TARGETED_DEVICE_FAMILY: "1,2"` in project.yml), an iPad 13-inch display.
 * The 6.9"/large-display set is optional — App Store Connect scales the
 * medium set down for it.
 */
const REQUIRED_SIZES = {
  iphone: {
    label: "iPhone with Dynamic Island (medium display)",
    accepted: [
      [1179, 2556],
      [2556, 1179],
      [1206, 2622],
      [2622, 1206],
    ],
    // Preferred device type + the size this machine actually renders for it.
    // Matched by substring: CoreSimulator appends the RAM variant to some
    // identifiers (e.g. `iPad-Pro-13-inch-M5-12GB`).
    deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
    deviceName: "Tidybyte iPhone (App Store)",
    native: [1206, 2622],
  },
  ipad: {
    label: 'iPad 13" display',
    accepted: [
      [2064, 2752],
      [2752, 2064],
      [2048, 2732],
      [2732, 2048],
    ],
    deviceType: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5",
    deviceName: "Tidybyte iPad (App Store)",
    native: [2064, 2752],
  },
};

/**
 * Screens, in upload order.
 *
 * `url: null` means "whatever the app opens on" — the Swipe home.
 * Every other entry is a deep link the app already routes.
 *
 * Screens with no deep link (Settings, an in-progress Swipe session, the album
 * picker, the session-complete screen) are deliberately absent: reaching them
 * needs a tap, and adding a launch argument to force them is out of scope for
 * this script. See the report for that gap.
 */
const SCREENS = [
  { slug: "swipe-home", url: null, settle: 6000 },
  { slug: "cleanup-tools", url: `${URL_SCHEME}://cleanup`, settle: 4500 },
  { slug: "cleanup-duplicates", url: `${URL_SCHEME}://cleanup/duplicates`, settle: 4500 },
  { slug: "cleanup-screenshots", url: `${URL_SCHEME}://cleanup/screenshots`, settle: 4500 },
  { slug: "cleanup-blurry-photos", url: `${URL_SCHEME}://cleanup/blurry`, settle: 4500 },
  { slug: "storage-dashboard", url: `${URL_SCHEME}://storage`, settle: 5000 },
  { slug: "activity-savings", url: `${URL_SCHEME}://activity`, settle: 4500 },
];

const log = (msg) => console.log(msg);
const step = (msg) => console.log(`\n▶ ${msg}`);

/** Run a command, streaming nothing, returning stdout. Throws on failure. */
function run(cmd, args, opts = {}) {
  return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...opts });
}

/** Same, but never throws — for cleanup and probe calls that may legitimately fail. */
function tryRun(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", ...opts });
  return { ok: r.status === 0, out: `${r.stdout ?? ""}${r.stderr ?? ""}` };
}

function listDevices() {
  const json = JSON.parse(run("xcrun", ["simctl", "list", "devices", "available", "--json"]));
  const all = [];
  for (const [runtime, devices] of Object.entries(json.devices)) {
    for (const d of devices) all.push({ ...d, runtime });
  }
  return all;
}

/**
 * Finds the simulator to use, creating it if the machine does not have one.
 *
 * Prefers an exact device-type match on the newest runtime so a machine with
 * only, say, an iPhone 16 Pro still produces the accepted 1206x2622 size.
 */
function resolveDevice(key, spec, devices) {
  const byName = devices.find((d) => d.name === spec.deviceName);
  if (byName) return byName;

  const sameType = devices
    .filter((d) => (d.deviceTypeIdentifier ?? "").includes(spec.deviceType))
    .sort((a, b) => b.runtime.localeCompare(a.runtime));
  if (sameType.length) return sameType[0];

  // Nothing installed — create one on the newest available iOS runtime.
  const runtimes = JSON.parse(run("xcrun", ["simctl", "list", "runtimes", "--json"]))
    .runtimes.filter((r) => r.isAvailable && r.identifier.includes("iOS"))
    .sort((a, b) => b.identifier.localeCompare(a.identifier));
  if (!runtimes.length) throw new Error("no available iOS runtime to create a simulator from");
  const runtime = runtimes[0].identifier;
  log(`  creating ${spec.deviceName} on ${runtime}`);
  const out = run("xcrun", ["simctl", "create", spec.deviceName, spec.deviceType, runtime]);
  return { udid: out.trim(), name: spec.deviceName, runtime, state: "Shutdown" };
}

function boot(udid) {
  const state = tryRun("xcrun", ["simctl", "list", "devices", "--json"]);
  const json = JSON.parse(state.out);
  for (const devices of Object.values(json.devices)) {
    const d = devices.find((x) => x.udid === udid);
    if (d && d.state === "Booted") return false; // already up — not ours to shut down
  }
  run("xcrun", ["simctl", "boot", udid]);
  run("xcrun", ["simctl", "bootstatus", udid, "-b"]);
  return true;
}

/**
 * Pre-approves the app's URL scheme so `openurl` does not raise SpringBoard's
 * "Open in <App>?" dialog. Must run while the device is booted.
 */
function approveUrlScheme(udid) {
  const plist = join(
    homedir(),
    "Library/Developer/CoreSimulator/Devices",
    udid,
    "data/Library/Preferences/com.apple.launchservices.schemeapproval.plist",
  );
  tryRun("/usr/libexec/PlistBuddy", ["-c", "Clear dict", plist]);
  const r = tryRun("/usr/libexec/PlistBuddy", [
    "-c",
    `Add com.apple.CoreSimulator.CoreSimulatorBridge-->${URL_SCHEME} string ${BUNDLE_ID}`,
    plist,
  ]);
  return r.ok;
}

function statusBar(udid, clear) {
  const args = clear
    ? ["simctl", "status_bar", udid, "clear"]
    : [
        "simctl", "status_bar", udid, "override",
        "--time", "9:41",
        "--batteryState", "charged", "--batteryLevel", "100",
        "--cellularBars", "4", "--wifiBars", "3",
      ];
  tryRun("xcrun", args);
}

function pngSize(file) {
  const buf = readFileSync(file);
  return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
}

/**
 * Copies `src` to `dest` with the alpha channel dropped.
 *
 * `simctl io screenshot` emits RGBA (PNG color type 6). Apple's screenshot
 * spec says images "can't include alpha channels or transparencies", and App
 * Store Connect rejects an RGBA PNG. Rewriting as color type 2 (truecolor, no
 * alpha) with pngjs — already a dependency — drops it without touching a pixel.
 */
function stripAlpha(src, dest) {
  const img = PNG.sync.read(readFileSync(src));
  const rgb = Buffer.alloc(img.width * img.height * 3);
  for (let i = 0, j = 0; i < img.data.length; i += 4, j += 3) {
    rgb[j] = img.data[i];
    rgb[j + 1] = img.data[i + 1];
    rgb[j + 2] = img.data[i + 2];
  }
  const out = PNG.sync.write(
    { width: img.width, height: img.height, data: rgb },
    { colorType: 2, inputColorType: 2, inputHasAlpha: false, bitDepth: 8 },
  );
  writeFileSync(dest, out);
  return [img.width, img.height];
}

function matches(size, accepted) {
  return accepted.some(([w, h]) => w === size[0] && h === size[1]);
}

function captureDevice(key, spec, device) {
  const udid = device.udid;
  const outDir = join(OUT_ROOT, key);
  step(`${key}: ${device.name} (${udid})`);
  mkdirSync(outDir, { recursive: true });

  const weBooted = boot(udid);
  try {
    // A fresh container keeps a stale `appLanguagePreference` from a previous
    // run from overriding the English launch arguments below.
    tryRun("xcrun", ["simctl", "uninstall", udid, BUNDLE_ID]);
    run("xcrun", ["simctl", "install", udid, APP_PATH]);
    tryRun("xcrun", ["simctl", "privacy", udid, "grant", "photos", BUNDLE_ID]);
    tryRun("xcrun", ["simctl", "privacy", udid, "grant", "photos-add", BUNDLE_ID]);
    statusBar(udid, false);

    const approved = approveUrlScheme(udid);
    log(`  url scheme pre-approved: ${approved ? "yes" : "no (a system prompt may appear)"}`);

    // `-AppleLanguages` is the documented launch-argument override, and it
    // beats the device setting because UserDefaults reads the argument domain
    // first. Without it a simulator left in German screenshots in German.
    run("xcrun", [
      "simctl", "launch", udid, BUNDLE_ID,
      "-hasCompletedOnboarding", "YES",
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
    ]);
    // First paint + the storage scan the dashboard runs on appear.
    spawnSync("sleep", ["8"]);

    const rows = [];
    for (const [i, screen] of SCREENS.entries()) {
      const file = join(outDir, `${String(i + 1).padStart(2, "0")}-${screen.slug}.png`);
      if (screen.url) {
        const r = tryRun("xcrun", ["simctl", "openurl", udid, screen.url]);
        if (!r.ok) log(`  ! openurl failed for ${screen.url}: ${r.out.trim()}`);
      }
      spawnSync("sleep", [String(screen.settle / 1000)]);
      const raw = join(outDir, `.raw-${screen.slug}.png`);
      tryRun("xcrun", ["simctl", "io", udid, "screenshot", raw]);
      if (!existsSync(raw)) {
        log(`  ! no screenshot produced for ${screen.slug}`);
        continue;
      }
      const size = stripAlpha(raw, file);
      rmSync(raw, { force: true });
      const ok = matches(size, spec.accepted);
      rows.push({ file: `${String(i + 1).padStart(2, "0")}-${screen.slug}.png`, size, ok });
      log(`  ${ok ? "✓" : "✗"} ${rows.at(-1).file}  ${size[0]}x${size[1]}`);
    }
    return rows;
  } finally {
    statusBar(udid, true);
    if (weBooted && !KEEP_BOOTED) {
      tryRun("xcrun", ["simctl", "shutdown", udid]);
      log("  simulator shut down");
    } else if (weBooted) {
      log("  left booted (--keep-booted)");
    }
  }
}

function printTable(all) {
  step("captured files");
  const width = Math.max(...all.map((r) => r.file.length), "file".length);
  console.log(`  ${"device".padEnd(8)} ${"file".padEnd(width)} ${"dimensions".padEnd(14)} required`);
  console.log(`  ${"-".repeat(8)} ${"-".repeat(width)} ${"-".repeat(14)} ${"-".repeat(8)}`);
  for (const r of all) {
    const dims = `${r.size[0]}x${r.size[1]}`;
    console.log(`  ${r.device.padEnd(8)} ${r.file.padEnd(width)} ${dims.padEnd(14)} ${r.ok ? "yes" : "NO"}`);
  }
  const bad = all.filter((r) => !r.ok);
  console.log("");
  if (bad.length) {
    console.log(`✗ ${bad.length} file(s) are not an accepted App Store size`);
    return false;
  }
  console.log(`✓ ${all.length} file(s), all at an accepted App Store size, alpha stripped`);
  return true;
}

function checkExisting() {
  step("verifying docs/screenshots/<device>/");
  const rows = [];
  for (const key of Object.keys(REQUIRED_SIZES)) {
    const dir = join(OUT_ROOT, key);
    if (!existsSync(dir)) {
      console.log(`  ✗ ${key}/ missing`);
      continue;
    }
    for (const f of readdirSafe(dir)) {
      if (!f.endsWith(".png") || f.startsWith(".")) continue;
      const size = pngSize(join(dir, f));
      rows.push({ device: key, file: f, size, ok: matches(size, REQUIRED_SIZES[key].accepted) });
    }
  }
  if (!rows.length) {
    console.log("  nothing captured yet — run without --check");
    return false;
  }
  return printTable(rows);
}

function readdirSafe(dir) {
  try {
    return readdirSync(dir);
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------------------

log("TidyByte — App Store screenshot capture");
log(`required sizes: ${Object.values(REQUIRED_SIZES).map((s) => `${s.label} ${s.accepted.map(([w, h]) => `${w}x${h}`).join("/")}`).join("; ")}`);

if (CHECK_ONLY) {
  process.exit(checkExisting() ? 0 : 1);
}

const keys = Object.keys(REQUIRED_SIZES).filter((k) => DEVICE_FILTER === "all" || DEVICE_FILTER === k);
if (!keys.length) {
  console.error(`unknown --device ${DEVICE_FILTER} (expected iphone, ipad, or all)`);
  process.exit(1);
}

step("building the app for the simulator");
run(
  "xcodebuild",
  [
    "-project", join(ROOT, "Tidybyte.xcodeproj"),
    "-scheme", "Tidybyte",
    "-configuration", "Debug",
    "-sdk", "iphonesimulator",
    "-derivedDataPath", DERIVED_DATA,
    "build",
    "CODE_SIGNING_ALLOWED=NO",
  ],
  { stdio: ["ignore", "pipe", "pipe"] },
);
log(`  built ${APP_PATH}`);

const devices = listDevices();
const all = [];
for (const key of keys) {
  const spec = REQUIRED_SIZES[key];
  const device = resolveDevice(key, spec, devices);
  const rows = captureDevice(key, spec, device);
  for (const r of rows) all.push({ ...r, device: key });
}

process.exit(printTable(all) ? 0 : 1);
