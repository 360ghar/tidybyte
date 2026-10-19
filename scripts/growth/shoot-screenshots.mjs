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
 *   node scripts/growth/shoot-screenshots.mjs              # iPhone + iPad
 *   node scripts/growth/shoot-screenshots.mjs --device iphone
 *   node scripts/growth/shoot-screenshots.mjs --device ipad
 *   node scripts/growth/shoot-screenshots.mjs --check      # verify, capture nothing
 *   node scripts/growth/shoot-screenshots.mjs --keep-booted
 *   node scripts/growth/shoot-screenshots.mjs --duo        # iPhone Duo only (both displays)
 *   node scripts/growth/shoot-screenshots.mjs --duo --screens swipe-home,cleanup-tools
 *   node scripts/growth/shoot-screenshots.mjs --only ipad
 *   node scripts/growth/shoot-screenshots.mjs --dry-run    # print the plan, touch nothing
 *   node scripts/growth/shoot-screenshots.mjs --probe <udid>   # print the display table, touch nothing
 *   node scripts/growth/shoot-screenshots.mjs --duo --drive-devicehub   # set the Duo pose for you
 *
 * The Duo capture keeps **five** screens per display, not seven, because a Duo
 * submission is one App Store Connect row capped at 10 screenshots and both
 * displays land in that one row (5 + 5 = 10). `--screens a,b,c` overrides the
 * set for any family; every non-Duo family still captures all seven.
 *
 * Poses (Duo only)
 * ----------------
 * A Duo boots **folded**. In the `Closed` pose only the **outer** panel is
 * active — 1398x2034, showing the app — and the **inner** panel is a live but
 * empty surface whose screenshot is blank. In the `Open` pose the app moves to
 * the **inner** panel and the **outer** panel goes black. So the two Duo
 * families can never be captured in one pose:
 *
 *     duoOuter  ->  pose `Closed`
 *     duoInner  ->  pose `Open`, inner panel rotated to native portrait
 *
 * A Duo's inner panel comes up **landscape** (2853x2007) in the `Open` pose, and
 * a portrait-only iPhone app then renders letterboxed in a centred column.
 * Device Hub's `Rotate Right` control switches it to its native portrait
 * 2007x2853, which is what a Duo capture requires.
 *
 * Poses are driven **only** from Xcode's Device Hub app; `simctl` has no hinge
 * or pose verb. `--drive-devicehub` drives it through the `cua-driver` CLI
 * (Accessibility automation), locating the `Closed` / `Open` / `Rotate Right`
 * buttons by their AX label on every run. Without the flag the script prints the
 * exact Device Hub steps and requires the operator to set the pose by hand.
 *
 * Before capturing a family the script probes both panels, infers the pose from
 * which panel has content, and stops with the Device Hub steps if it is not the
 * one the family needs. After every screenshot it also rejects a blank or
 * wrong-size PNG. Neither check writes a file it cannot vouch for.
 *
 * Output: docs/screenshots/<family>/<NN>-<slug>.png
 * The Duo families write to docs/screenshots/duo-outer/ and duo-inner/, because
 * the family key is camelCase and the directory is not.
 *
 * Capture stays per display, but the two Duo directories feed **one** App Store
 * Connect group by default: Apple's screenshot spec lists a single "iPhone Duo"
 * entry carrying all four accepted sizes, so `plan.mjs` uploads both directories
 * as one set. See `scripts/publish/README.md` → "iPhone Duo screenshots".
 *
 * iPhone Duo needs the iOS 27.1 runtime, which `--duo` checks for before it
 * builds anything. See `duoPreflight` for the exact download and create lines.
 */
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir, tmpdir } from "node:os";
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
const DUO_ONLY = argv.includes("--duo");
const DRY_RUN = argv.includes("--dry-run");
const deviceFlag = argv.indexOf("--device");
const DEVICE_FILTER = deviceFlag === -1 ? "all" : argv[deviceFlag + 1];
const onlyFlag = argv.indexOf("--only");
const ONLY_FILTER = onlyFlag === -1 ? null : argv[onlyFlag + 1];
const probeFlag = argv.indexOf("--probe");
const PROBE_UDID = probeFlag === -1 ? null : argv[probeFlag + 1];
const screensFlag = argv.indexOf("--screens");
const SCREENS_ARG = screensFlag === -1 ? null : (argv[screensFlag + 1] ?? "");
const DRIVE_DEVICEHUB = argv.includes("--drive-devicehub");

/**
 * Device Hub — the only surface that can change a Duo's pose.
 *
 * `simctl` has no hinge or pose verb, and Device Hub has no AppleScript or CLI
 * interface. Its device chrome does carry AX-labelled buttons (`Home`,
 * `Screenshot`, `Record`, `Rotate Right`, and the poses group `Closed` /
 * `Partially Open` / `Open`), so `cua-driver` — Accessibility automation, not
 * AppleScript — can press them. `--drive-devicehub` uses that path.
 */
const DEVICEHUB_BUNDLE_ID = "com.apple.dt.Devices";
const CUA_APP_NAME = "CuaDriver";
const CUA_BIN = "cua-driver";

const DUO_DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo";
const DUO_RUNTIME_VERSION = "27.1";
const DUO_DEVICE_NAME = "Tidybyte Duo (App Store)";

/**
 * The exact sizes App Store Connect accepts, from Apple's reference page.
 *
 * Apple's "Required device sizes" is only two rows today: an iPhone with
 * Dynamic Island (medium display) and, because this app ships iPad
 * (`TARGETED_DEVICE_FAMILY: "1,2"` in project.yml), an iPad 13-inch display.
 * The 6.9"/large-display set is optional — App Store Connect scales the
 * medium set down for it.
 *
 * The two Duo rows are a third and fourth family. They are opt-in (`--duo`)
 * because the runtime they need is not on every machine, and because the
 * families the default run captures must not change while the Duo rows are
 * still optional on Apple's side.
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
  // iPhone Duo, shipping Oct 2026 with iOS 27.1. One device, two displays, and
  // App Store Connect grades them as separate rows. The outer display is
  // `screenID 1` / deviceName "primary"; the inner is `screenID 3` /
  // "primary-1". `simctl` takes either, so `display` names the device name and
  // `screenID` is the fallback used when `io enumerate` does not print it.
  //
  // Both entries carry the same `deviceName`, and `resolveDevice` adds a device
  // it creates to the shared `devices` list, so the second family finds the one
  // Duo simulator the first family created instead of creating a second one.
  //
  // Sizes are Apple's accepted list for each row. `native` is the portrait size
  // this machine renders; `exactNative` makes the verification require it
  // exactly, because a Duo row is a fixed size and the 1179-vs-1206 slack the
  // iPhone row allows does not apply.
  duoOuter: {
    label: "iPhone Duo (outer display)",
    accepted: [
      [1398, 2034],
      [2034, 1398],
    ],
    deviceType: DUO_DEVICE_TYPE,
    deviceName: DUO_DEVICE_NAME,
    native: [1398, 2034],
    display: "primary",
    screenID: 1,
    duo: true,
    exactNative: true,
    dir: "duo-outer",
    // Only the outer panel is active when the Duo is folded; in any open pose
    // the app moves to the inner panel and this one goes black.
    pose: "Closed",
    orientation: "portrait",
  },
  duoInner: {
    label: "iPhone Duo (inner display)",
    accepted: [
      [2007, 2853],
      [2853, 2007],
    ],
    deviceType: DUO_DEVICE_TYPE,
    deviceName: DUO_DEVICE_NAME,
    native: [2007, 2853],
    display: "primary-1",
    screenID: 3,
    duo: true,
    exactNative: true,
    dir: "duo-inner",
    // The inner panel only carries the app when the Duo is open, and it comes
    // up landscape until Device Hub's `Rotate Right` is pressed once.
    pose: "Open",
    orientation: "portrait",
    rotateToPortrait: true,
  },
};

/** The two Duo panel sizes, used to find each panel while probing the pose. */
const DUO_OUTER_SIZE = REQUIRED_SIZES.duoOuter.native;
const DUO_INNER_SIZE = REQUIRED_SIZES.duoInner.native;

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

/**
 * The screens the Duo capture keeps by default.
 *
 * A Duo submission is graded as ONE App Store Connect row, and a row holds at
 * most 10 screenshots. Both displays are captured into that one row, so the
 * default set is **five per display** — exactly 10. These five tell the whole
 * product story; `cleanup-screenshots` and `cleanup-blurry-photos` are dropped
 * for Duo only, because they repeat the cleanup-tools surface the duplicates
 * screen already represents.
 *
 * Non-Duo families keep all seven: the iPhone and iPad rows have their own caps.
 */
const DUO_SCREEN_SLUGS = [
  "swipe-home",
  "cleanup-tools",
  "cleanup-duplicates",
  "storage-dashboard",
  "activity-savings",
];

/**
 * The `--screens a,b,c` override, resolved against SCREENS, or null.
 *
 * Resolving against SCREENS rather than building new entries keeps the deep
 * links and settle times the script's. An unknown slug stops the run instead of
 * silently capturing less than asked, and the resolved list keeps SCREENS order
 * so numbered filenames stay ascending.
 */
let SCREENS_FILTER = null;
if (SCREENS_ARG !== null) {
  const wanted = SCREENS_ARG.split(",").map((s) => s.trim()).filter(Boolean);
  const unknown = wanted.filter((slug) => !SCREENS.some((s) => s.slug === slug));
  if (wanted.length === 0 || unknown.length > 0) {
    console.error(
      unknown.length
        ? `unknown screen(s) in --screens: ${unknown.join(", ")}`
        : "--screens needs at least one slug",
    );
    console.error(`valid slugs: ${SCREENS.map((s) => s.slug).join(", ")}`);
    process.exit(1);
  }
  SCREENS_FILTER = SCREENS.filter((s) => wanted.includes(s.slug));
}

/**
 * The screens a family captures, in order.
 *
 * `--screens` wins everywhere when given; otherwise a Duo family uses the
 * five-screen default and every other family captures all seven, so the
 * iPhone/iPad capture and plan are unchanged.
 */
function screensFor(spec) {
  if (SCREENS_FILTER) return SCREENS_FILTER;
  return spec.duo ? SCREENS.filter((s) => DUO_SCREEN_SLUGS.includes(s.slug)) : SCREENS;
}

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
 * Finds the simulator for a family among the ones already installed.
 *
 * Prefers an exact device-type match on the newest runtime so a machine with
 * only, say, an iPhone 16 Pro still produces the accepted 1206x2622 size.
 *
 * Read-only: it creates nothing. `resolveDevice` layers creation on top, and the
 * dry run calls this one so that printing a plan never mutates the machine.
 */
function findExistingDevice(spec, devices) {
  const byName = devices.find((d) => d.name === spec.deviceName);
  if (byName) return byName;

  const sameType = devices
    .filter((d) => (d.deviceTypeIdentifier ?? "").includes(spec.deviceType))
    .sort((a, b) => b.runtime.localeCompare(a.runtime));
  return sameType[0] ?? null;
}

/** Newest available iOS runtime identifier, or null. */
function newestIosRuntime() {
  const runtimes = JSON.parse(run("xcrun", ["simctl", "list", "runtimes", "--json"]))
    .runtimes.filter((r) => r.isAvailable && r.identifier.includes("iOS"))
    .sort((a, b) => b.identifier.localeCompare(a.identifier));
  return runtimes[0] ?? null;
}

/**
 * Finds the simulator for a family, creating it if the machine does not have one.
 *
 * A created device is pushed into `devices` before it is returned. The caller
 * builds that array once and reuses it for every family, and both Duo families
 * carry the same `deviceName`: without the push, the second one re-runs the
 * lookup against a list that does not contain the device just made, finds
 * nothing, and creates a second simulator with the same name. `simctl` allows
 * duplicate names, so that orphan would sit in the device list unnoticed.
 */
function resolveDevice(spec, devices, { runtime = null } = {}) {
  const existing = findExistingDevice(spec, devices);
  if (existing) return existing;

  const chosen = runtime ?? newestIosRuntime();
  if (!chosen) throw new Error("no available iOS runtime to create a simulator from");
  log(`  creating ${spec.deviceName} on ${chosen.identifier}`);
  const out = run("xcrun", ["simctl", "create", spec.deviceName, spec.deviceType, chosen.identifier]);
  const created = { udid: out.trim(), name: spec.deviceName, runtime: chosen.identifier, state: "Shutdown" };
  devices.push(created);
  return created;
}

/** The output directory for a family: the key, unless the spec names another. */
function outDirFor(key, spec) {
  return join(OUT_ROOT, spec.dir ?? key);
}

/**
 * Parses `xcrun simctl io <udid> enumerate` into one record per display port.
 *
 * **What the output actually contains.** Measured against a booted iPhone 18 Pro
 * on iOS 27.0, the enumerate dump is a sequence of `Port:` blocks. The fields a
 * display block carries are:
 *
 *     UUID: <uuid>            Class: Display          Port Identifier: ...
 *     Power state: On         Display class: <n>
 *     Default width: <px>     Default height: <px>    Default pixel format: 'BGRA'
 *
 * There is **no `deviceName:` and no `screenID:` field anywhere in the output**,
 * so the two regexes this function used to carry could never match on any
 * release. They were written against the field names in the task description
 * rather than against observed output, and are deleted rather than patched.
 *
 * The `Screen ID:` / `Device Name:` pairs that do exist live in a *different*
 * port class — the `DisplayAdapter` block's `Connected Screens:` list, whose
 * entries read `Screen ID: 1` and `Device Name: primary`. That is a screen
 * registry, not a framebuffer, and it carries no `Default width`/`Default
 * height`, so it cannot be used to pick a display by size. Size comes from the
 * `Class: Display` ports, which is what this parses.
 *
 * Non-display ports (`DisplayAdapter`, `Accelerator`, `StreamProcessor`, `Audio`,
 * `LegacyHID`, `Unknown`) are skipped by the `Class: Display` filter. Only the
 * first `Class:` line of a block is read, so the nested IOSurface block inside a
 * display port does not confuse it.
 */
function parseDisplayPorts(raw) {
  const ports = [];
  // Blocks begin at a line that is exactly `Port:`.
  for (const block of raw.split(/^[ \t]*Port:[ \t]*$/m).slice(1)) {
    const cls = block.match(/^[ \t]*Class:[ \t]*(.+?)[ \t]*$/m);
    if (!cls || cls[1] !== "Display") continue;
    const uuid = block.match(/^[ \t]*UUID:[ \t]*([0-9A-Fa-f-]{36})[ \t]*$/m);
    const displayClass = block.match(/^[ \t]*Display class:[ \t]*(\d+)[ \t]*$/m);
    const width = block.match(/^[ \t]*Default width:[ \t]*(\d+)[ \t]*$/m);
    const height = block.match(/^[ \t]*Default height:[ \t]*(\d+)[ \t]*$/m);
    if (!uuid || !width || !height) continue;
    ports.push({
      uuid: uuid[1],
      displayClass: displayClass ? Number(displayClass[1]) : null,
      width: Number(width[1]),
      height: Number(height[1]),
    });
  }
  return ports;
}

/** Families that could not resolve a display on their device. Non-empty = exit 1. */
const displayFailures = [];

/** Families that produced fewer verified files than the screens they asked for. Non-empty = exit 1. */
const captureFailures = [];

/** Runs `io enumerate` for a booted device and returns the parsed display ports. */
function enumerateDisplays(udid) {
  const r = tryRun("xcrun", ["simctl", "io", udid, "enumerate"]);
  return { ok: r.ok, ports: parseDisplayPorts(r.out), raw: r.out };
}

/**
 * Picks the `--display=` value for a family, or explains why it cannot.
 *
 * Returns `null` for a single-display family — the argument is then not added at
 * all, which keeps the iPhone and iPad calls byte-identical to before Duo
 * existed.
 *
 * For a multi-display family the selector is the **UUID of the port whose pixel
 * size is the family's `native` size**. Size is the only field that identifies a
 * display unambiguously: the `Class: Display` ports on a real device include
 * 720x480 and 7680x4320 decoys alongside the one that is actually the screen, and
 * their display classes do not line up with `Screen ID` (the iPhone 18 Pro's only
 * real screen is port `Display class: 0`, while its `Screen ID` is 1).
 *
 * Returns `{ error }` when nothing matches, and the caller prints the table and
 * exits. The numeric `screenID` fallback is used **only** when the dump yielded
 * no display ports at all, i.e. `simctl` changed shape — a numeric selector
 * cannot be size-validated before capture, so falling back to it whenever a size
 * lookup misses would silently screenshot the wrong display at the wrong size on
 * a non-Duo device. That is exactly the failure this check exists to catch.
 */
function resolveDisplayArg(spec, displays) {
  if (!spec.display) return null;
  const ports = displays?.ports ?? [];
  const [w, h] = spec.native;

  const exact = ports.find((p) => p.width === w && p.height === h);
  if (exact) return { selector: exact.uuid, via: `size ${w}x${h}`, port: exact };

  // A Duo display reports landscape on some configurations; accept the rotated
  // form of the same size before giving up.
  const rotated = ports.find((p) => p.width === h && p.height === w);
  if (rotated) return { selector: rotated.uuid, via: `size ${h}x${w} (rotated)`, port: rotated };

  if (ports.length === 0) {
    // No parsable display ports at all. Fall back to the documented screen id,
    // then to the `internal` alias, and let the post-capture size check decide.
    const selector = spec.screenID != null ? String(spec.screenID) : "internal";
    return { selector, via: `screenID fallback (no display ports parsed)`, port: null };
  }

  return { error: displayLookupFailure(spec, ports) };
}

/** The message printed when no enumerated display matches a family's size. */
function displayLookupFailure(spec, ports) {
  const lines = [];
  lines.push(`no display matched ${spec.native.join("x")} on this device.`);
  lines.push(`  ${spec.label} captures at ${spec.native.join("x")} (portrait), and no`);
  lines.push(`  enumerated display port has those pixels.`);
  lines.push("  Every display port simctl reported:");
  for (const p of ports) {
    lines.push(`    Display class: ${p.displayClass ?? "?"}   ${p.width}x${p.height}   ${p.uuid}`);
  }
  lines.push(
    `  A Duo capture needs a booted iPhone Duo on the iOS ${DUO_RUNTIME_VERSION} runtime; the`,
  );
  lines.push(
    `  ${spec.screenID} fallback would capture whatever screen ${spec.screenID} is, at the wrong size.`,
  );
  return lines.join("\n");
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
 * The PNG colour type byte, read straight out of IHDR.
 *
 * Offset 25: 8 signature bytes + 4 length + 4 "IHDR" + 4 width + 4 height +
 * 1 bit depth. 4 and 6 carry an alpha channel (grey+alpha, RGBA); 0, 2 and 3 do
 * not. Reading the header is what confirms `stripAlpha` actually took, rather
 * than trusting that it ran.
 */
function pngColorType(file) {
  return readFileSync(file)[25];
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

/**
 * Checks one written PNG against its family's spec.
 *
 * Two independent facts, because they fail for different reasons and only one of
 * them is visible in the filename: the pixel dimensions must be what the family
 * requires, and the file must carry no alpha channel. `exactNative` families
 * (Duo) must match their `native` size exactly; the legacy families keep the
 * either-or `accepted` check, because a machine rendering 1179x2556 for the
 * iPhone row is valid.
 */
function verifyFile(file, spec) {
  const size = pngSize(file);
  const colorType = pngColorType(file);
  const noAlpha = colorType !== 4 && colorType !== 6;
  const sizeOk = spec.exactNative
    ? size[0] === spec.native[0] && size[1] === spec.native[1]
    : matches(size, spec.accepted);
  return { size, colorType, noAlpha, sizeOk, ok: sizeOk && noAlpha };
}

// ---------------------------------------------------------------------------
// The blank-panel gate
// ---------------------------------------------------------------------------

/**
 * The luminance range below which a panel is treated as blank.
 *
 * Measured on a booted Duo: a black panel (the wrong pose) is exactly 0-0, while
 * a live app screen spans roughly 0-255 with a mean near 195. A flat card — all
 * black, all white, or one solid colour — has a range of a few units at most, so
 * a threshold of 10 separates "no content" from "content" with a wide margin.
 */
const BLANK_LUMA_RANGE = 10;

/**
 * Luminance statistics for a PNG.
 *
 * **Why `pngjs`, and not a hand-rolled decoder or `sips`.** `pngjs` is already a
 * devDependency and this file already imports it for `stripAlpha`, so using it
 * adds no dependency. Hand-decoding would mean re-implementing zlib inflate and
 * the scanline filters for no gain, and `sips` cannot report pixel statistics at
 * all — it converts and resizes, it does not measure. If `pngjs` ever leaves the
 * tree, `stripAlpha` breaks first, so this is not the weaker dependency.
 *
 * Samples at most ~400k pixels (a stride over the pixel count) rather than all
 * of them: a Duo panel is ~5.7M pixels and only min, max and mean are needed.
 */
function imageLuma(file) {
  const img = PNG.sync.read(readFileSync(file));
  const { width, height, data } = img;
  const total = width * height;
  const stride = Math.max(1, Math.floor(total / 400000));
  let min = 255;
  let max = 0;
  let sum = 0;
  let n = 0;
  for (let p = 0; p < total; p += stride) {
    const i = p * 4;
    const lum = data[i] * 0.2126 + data[i + 1] * 0.7152 + data[i + 2] * 0.0722;
    if (lum < min) min = lum;
    if (lum > max) max = lum;
    sum += lum;
    n += 1;
  }
  return { width, height, min, max, range: max - min, mean: sum / n, sampled: n };
}

/** Why a capture came back at the wrong size — the fix, not just the fact. */
function wrongSizeCause(spec, size) {
  const [w, h] = size;
  if (spec.rotateToPortrait && w === spec.native[1] && h === spec.native[0]) {
    return `the ${spec.label} is in landscape — in Device Hub click "Rotate Right" to rotate it to native portrait`;
  }
  return `wrong pose or wrong panel: ${spec.label} needs the "${spec.pose ?? "correct"}" pose`;
}

/**
 * The gate every captured PNG passes before it is accepted.
 *
 * Two independent rejections, because they fail for different reasons:
 *
 *   - **wrong size** — the capture is the wrong panel, or the panel is rotated.
 *   - **blank** — a flat image (all-black, all-white, or effectively one colour)
 *     means no app content was drawn: wrong pose, panel asleep, or the app not
 *     frontmost.
 *
 * This is the check that catches the black outer panel an `Open` pose produces.
 * That PNG is a valid 1398x2034 file, so a size-only check accepts it; only the
 * pixels say the panel is dark.
 */
function blankGate(file, spec) {
  const stats = imageLuma(file);
  const size = [stats.width, stats.height];
  const sizeOk = spec.exactNative
    ? size[0] === spec.native[0] && size[1] === spec.native[1]
    : matches(size, spec.accepted);
  const flat = stats.range < BLANK_LUMA_RANGE;
  const expected = spec.exactNative
    ? spec.native.join("x")
    : spec.accepted.map(([w, h]) => `${w}x${h}`).join("/");
  const blankReason = flat
    ? `blank panel (luminance ${stats.min.toFixed(0)}-${stats.max.toFixed(0)}, mean ${stats.mean.toFixed(0)})`
    : null;
  let cause = null;
  if (!sizeOk) cause = wrongSizeCause(spec, size);
  else if (flat) cause = "no app content drawn: wrong pose, panel asleep, or the app is not frontmost";
  return {
    ok: sizeOk && !flat,
    sizeOk,
    flat,
    size,
    stats,
    expected,
    blankReason,
    cause,
  };
}

// ---------------------------------------------------------------------------
// Duo poses
// ---------------------------------------------------------------------------

/** Families whose pose or orientation could not be satisfied. Non-empty = exit 1. */
const poseFailures = [];

/** The enumerated port for one Duo panel, matched by pixel size, either way up. */
function findPanelPort(ports, size) {
  const [w, h] = size;
  return ports.find((p) => p.width === w && p.height === h)
    ?? ports.find((p) => p.width === h && p.height === w)
    ?? null;
}

/** Screenshots one panel to a temp file and measures it. Writes nothing else. */
function probePanel(udid, selector, tag) {
  const file = join(tmpdir(), `tidybyte-probe-${tag}-${process.pid}.png`);
  const r = tryRun("xcrun", ["simctl", "io", udid, "screenshot", `--display=${selector}`, file]);
  if (!r.ok || !existsSync(file)) {
    return { ok: false, error: `simctl could not screenshot ${tag}: ${r.out.trim() || "(no output)"}` };
  }
  const stats = imageLuma(file);
  rmSync(file, { force: true });
  return { ok: true, stats, blank: stats.range < BLANK_LUMA_RANGE };
}

/**
 * Infers the Duo's current pose from which panel has content.
 *
 * No API reports the pose. `simctl io enumerate` lists both panels at their
 * native sizes in **every** pose (measured on a booted Duo), so the only signal
 * is the pixels: in `Closed` the outer panel shows the app and the inner panel
 * is blank; in `Open` it is the other way round. Both-blank (panels asleep) and
 * both-drawn are reported as unknown rather than guessed at.
 */
function probePose(udid, displays) {
  const ports = displays?.ports ?? [];
  const outerPort = findPanelPort(ports, DUO_OUTER_SIZE);
  const innerPort = findPanelPort(ports, DUO_INNER_SIZE);
  if (!outerPort || !innerPort) {
    return { ok: false, pose: null, error: `could not find both Duo panels among ${ports.length} display port(s)` };
  }
  const outer = probePanel(udid, outerPort.uuid, "outer");
  if (!outer.ok) return { ok: false, pose: null, error: outer.error };
  const inner = probePanel(udid, innerPort.uuid, "inner");
  if (!inner.ok) return { ok: false, pose: null, error: inner.error };

  const evidence = `outer ${outer.blank ? "blank" : "drawn"} `
    + `(${outer.stats.width}x${outer.stats.height}), `
    + `inner ${inner.blank ? "blank" : "drawn"} (${inner.stats.width}x${inner.stats.height})`;
  let pose = null;
  if (outer.blank && !inner.blank) pose = "Open";
  else if (!outer.blank && inner.blank) pose = "Closed";
  return { ok: true, pose, evidence };
}

/**
 * The manual Device Hub steps for a family, naming the exact buttons to click.
 *
 * Printed whenever the pose is wrong and the script cannot (or was not asked to)
 * fix it, so the operator never has to guess which control to press.
 */
function poseSteps(spec, deviceName) {
  const lines = [];
  lines.push("  1. Open Device Hub: Xcode > Open Developer Tool > Device Hub, or");
  lines.push("       open /Applications/Xcode.app/Contents/Applications/DeviceHub.app");
  lines.push(`  2. Select "${deviceName ?? spec.deviceName}" in the sidebar.`);
  lines.push(`  3. In the device chrome, click the "${spec.pose}" button (the poses group is Closed / Partially Open / Open).`);
  if (spec.rotateToPortrait) {
    lines.push('  4. If the inner panel comes up landscape, click "Rotate Right" once to put it in native portrait.');
  }
  lines.push("  5. Wait for the panel to settle, then re-run this command.");
  lines.push(
    `  (Or re-run with --drive-devicehub to let the script click "${spec.pose}"`
      + `${spec.rotateToPortrait ? ' and "Rotate Right"' : ""} for you.)`,
  );
  return lines;
}

// --- Device Hub, driven through the cua-driver Accessibility CLI ------------

function cuaAvailable() {
  return tryRun(CUA_BIN, ["--version"]).ok;
}

function cuaDaemonRunning() {
  const r = tryRun(CUA_BIN, ["status"]);
  return r.ok && /running/i.test(r.out);
}

/** Starts the cua-driver daemon if it is not already up. */
function ensureCuaDaemon() {
  if (cuaDaemonRunning()) return true;
  const opened = tryRun("open", ["-n", "-g", "-a", CUA_APP_NAME, "--args", "serve"]);
  if (!opened.ok) return false;
  for (let i = 0; i < 40; i += 1) {
    spawnSync("sleep", ["0.5"]);
    if (cuaDaemonRunning()) return true;
  }
  return false;
}

/**
 * Device Hub's running pid, or null when it is not running.
 *
 * Identified by bundle id (`com.apple.dt.Devices`) rather than by the display
 * name, so a differently-named build of the app is still recognised.
 */
function deviceHubPid() {
  const raw = run(CUA_BIN, ["call", "list_apps"]);
  const apps = JSON.parse(raw).apps ?? [];
  const app = apps.find((a) => a.bundle_id === DEVICEHUB_BUNDLE_ID);
  return app && app.pid ? app.pid : null;
}

/**
 * Device Hub's on-screen layer-0 window for one device, or null.
 *
 * The window title is the device's **own name**, which is not necessarily
 * `spec.deviceName` (that is the name the script would create), and Device Hub
 * may hold windows for several devices at once. The reliable identity is the
 * sidebar row's AX identifier, `TableRow.Device.<udid>`, which Device Hub emits
 * for the device the window is showing — so the tree is matched on the udid
 * rather than on a name that can drift.
 */
function deviceHubWindowFor(udid, spec) {
  const pid = deviceHubPid();
  if (pid === null) return { error: "Device Hub is not running" };
  const raw = run(CUA_BIN, ["call", "list_windows"]);
  const windows = JSON.parse(raw).windows ?? [];
  const owned = windows.filter(
    (w) => w.pid === pid && w.layer === 0 && w.is_on_screen,
  );
  // Title first, as a cheap filter, then the tree as the authority.
  const byTitle = owned.filter((w) => (w.title ?? "").includes(spec.deviceName));
  for (const w of [...byTitle, ...owned]) {
    const tree = deviceHubTree(w);
    if (tree.includes(`TableRow.Device.${udid}`)) return { win: w, tree };
  }
  return {
    error: owned.length
      ? "Device Hub is running but has no window showing this device"
      : "Device Hub is running but has no on-screen device window",
  };
}

/** Device Hub's AX tree for a window, as the markdown `get_window_state` returns. */
function deviceHubTree(win) {
  const raw = run(CUA_BIN, [
    "call", "get_window_state",
    JSON.stringify({ pid: win.pid, window_id: win.window_id }),
  ]);
  return JSON.parse(raw).tree_markdown ?? "";
}

/**
 * The `[element_index N]` of an AX button, located **by label** in a tree that
 * was just read.
 *
 * Indices are invalidated by every snapshot, so one is never cached across
 * turns: the tree is fetched, the index is read out of it, and the click uses
 * that index immediately. The `help="<label>"` attribute is required, because
 * Device Hub also renders an unrelated `Open` button for the simulator's own
 * "Open in TidyByte?" dialog and a label-only match would hit that one.
 */
function findButtonIndex(tree, label) {
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = tree.match(new RegExp(`\\[(\\d+)\\] AXButton \\(${escaped}\\) help="${escaped}"`));
  return match ? Number(match[1]) : null;
}

/**
 * Presses an AX button in Device Hub, located by label in a snapshot.
 *
 * `tree` is the snapshot the caller already holds; when it is absent a fresh
 * one is taken. Either way the index and the click come from the **same**
 * snapshot, because any intervening `get_window_state` invalidates the indices
 * of the previous one.
 */
function deviceHubPress(win, label, tree = null) {
  const snapshot = tree ?? deviceHubTree(win);
  const index = findButtonIndex(snapshot, label);
  if (index === null) {
    return { ok: false, tree: snapshot, error: `no AX button labelled "${label}" in the Device Hub window for this device` };
  }
  const r = tryRun(CUA_BIN, [
    "call", "click",
    JSON.stringify({ pid: win.pid, window_id: win.window_id, element_index: index }),
  ]);
  return { ok: r.ok, tree: snapshot, error: r.ok ? null : r.out.trim() };
}

/**
 * Makes sure the device is in the pose a family needs, or stops.
 *
 * Verification comes first, always: the pose is inferred from the panels and
 * compared to `spec.pose`. Only when it is wrong and `--drive-devicehub` was
 * given does the script press a Device Hub button, and even then it re-probes
 * afterwards — a click that did not take is a failure, not a reason to capture
 * anyway.
 */
function ensureDuoPose(key, spec, udid, displays, deviceName) {
  let state = probePose(udid, displays);
  if (!state.ok) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: could not determine the device pose.`);
    console.error(`  ${state.error}`);
    console.error("  If a panel is asleep, click the simulator once (or Device Hub's \"Home\" button) to wake it.");
    console.error(`\n  ${spec.label} needs the "${spec.pose}" pose. Set it in Device Hub:`);
    for (const line of poseSteps(spec, deviceName)) console.error(line);
    console.error(`\n  Nothing was created or written for ${key}.`);
    return false;
  }
  if (state.pose === spec.pose) {
    log(`  pose: ${state.pose} ✓ (${state.evidence})`);
    return true;
  }

  if (!DRIVE_DEVICEHUB) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: the device is in the "${state.pose ?? "unknown"}" pose, but ${spec.label} needs "${spec.pose}".`);
    console.error(`  observed: ${state.evidence}`);
    console.error("\n  Set the pose in Device Hub:");
    for (const line of poseSteps(spec, deviceName)) console.error(line);
    console.error(`\n  Nothing was created or written for ${key}.`);
    return false;
  }

  log(`  pose: ${state.pose ?? "unknown"} — driving Device Hub to "${spec.pose}" (--drive-devicehub)`);
  if (!cuaAvailable()) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: --drive-devicehub needs the "${CUA_BIN}" CLI, which is not on PATH.`);
    console.error("  Install it, or set the pose by hand:");
    for (const line of poseSteps(spec, deviceName)) console.error(line);
    return false;
  }
  if (!ensureCuaDaemon()) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: could not start the cua-driver daemon (open -n -g -a ${CUA_APP_NAME} --args serve).`);
    for (const line of poseSteps(spec, deviceName)) console.error(line);
    return false;
  }
  const found = deviceHubWindowFor(udid, spec);
  if (found.error) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: ${found.error}, so the "${spec.pose}" button cannot be pressed.`);
    console.error(`  Device: "${deviceName}" (${udid}).`);
    for (const line of poseSteps(spec, deviceName)) console.error(line);
    return false;
  }
  const { win, tree } = found;
  const pressed = deviceHubPress(win, spec.pose, tree);
  if (!pressed.ok) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: ${pressed.error}`);
    console.error("  The AX tree Device Hub returned:");
    for (const line of pressed.tree.split("\n").slice(0, 60)) console.error(`    ${line}`);
    for (const line of poseSteps(spec, deviceName)) console.error(line);
    return false;
  }

  // Let the panel wake and the app re-lay-out, then confirm: a fresh enumerate
  // must still carry the expected size, and a fresh pixel probe must show the
  // pose actually changed.
  spawnSync("sleep", ["5"]);
  const after = enumerateDisplays(udid);
  if (!findPanelPort(after.ports, spec.native)) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: after clicking "${spec.pose}", no display port has ${spec.native.join("x")}.`);
    console.error(`  simctl reported: ${after.ports.map((p) => `${p.width}x${p.height}`).join(", ") || "(none)"}`);
    return false;
  }
  state = probePose(udid, after);
  if (state.ok && state.pose === spec.pose) {
    log(`  pose: ${state.pose} ✓ (${state.evidence})`);
    return true;
  }
  poseFailures.push(key);
  console.error(`\n✗ ${key}: clicked "${spec.pose}" but the pose did not change.`);
  console.error(`  observed: ${state.ok ? state.evidence : state.error}`);
  for (const line of poseSteps(spec, deviceName)) console.error(line);
  return false;
}

/**
 * The inner panel must be captured in native portrait, not the landscape it
 * comes up in.
 *
 * `simctl io enumerate` reports the panel's native size in every pose, so the
 * orientation has to be read from a capture, not the port table. A landscape
 * capture is 2853x2007; Device Hub's `Rotate Right` fixes it.
 */
function ensureInnerPortrait(key, spec, udid, displays, deviceName) {
  const port = findPanelPort(displays?.ports ?? [], spec.native);
  if (!port) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: no display port at ${spec.native.join("x")} to check the orientation of.`);
    return false;
  }
  const shot = probePanel(udid, port.uuid, "inner-orientation");
  if (!shot.ok) {
    poseFailures.push(key);
    console.error(`\n✗ ${key}: ${shot.error}`);
    return false;
  }
  const [w, h] = [shot.stats.width, shot.stats.height];
  if (w === spec.native[0] && h === spec.native[1]) {
    log(`  orientation: portrait ✓ (${w}x${h})`);
    return true;
  }

  const landscape = w === spec.native[1] && h === spec.native[0];
  if (landscape && DRIVE_DEVICEHUB) {
    // Every step that can stop the auto-rotate says so, because silently
    // skipping it would leave the operator reading a manual-steps message while
    // --drive-devicehub was on.
    if (!cuaAvailable()) {
      log(`  ! --drive-devicehub: the "${CUA_BIN}" CLI is not on PATH, so "Rotate Right" was not pressed`);
    } else if (!ensureCuaDaemon()) {
      log("  ! --drive-devicehub: the cua-driver daemon could not be started, so \"Rotate Right\" was not pressed");
    } else {
      const found = deviceHubWindowFor(udid, spec);
      if (!found.win) {
        log(`  ! --drive-devicehub: ${found.error}, so "Rotate Right" was not pressed`);
      } else {
        log(`  orientation: landscape (${w}x${h}) — pressing "Rotate Right" (--drive-devicehub)`);
        const pressed = deviceHubPress(found.win, "Rotate Right", found.tree);
        if (!pressed.ok) {
          log(`  ! "Rotate Right" could not be pressed: ${pressed.error}`);
        } else {
          spawnSync("sleep", ["4"]);
          const after = probePanel(udid, port.uuid, "inner-orientation");
          if (after.ok && after.stats.width === spec.native[0] && after.stats.height === spec.native[1]) {
            log(`  orientation: portrait ✓ (${after.stats.width}x${after.stats.height})`);
            return true;
          }
          log(`  ! "Rotate Right" was pressed but the panel still captured ${after.ok ? `${after.stats.width}x${after.stats.height}` : "nothing"}`);
        }
      }
    }
  }

  poseFailures.push(key);
  console.error(`\n✗ ${key}: the inner panel captured ${w}x${h}; ${spec.label} must be ${spec.native.join("x")} (portrait).`);
  console.error(`  In Device Hub, select "${deviceName ?? spec.deviceName}" and click "Rotate Right" once.`);
  console.error("  (Or re-run with --drive-devicehub to let the script press it.)");
  console.error(`\n  Nothing was created or written for ${key}.`);
  return false;
}

/**
 * Captures every screen on one device.
 *
 * The display is resolved here, after boot, because `simctl io enumerate` only
 * reports ports for a device that is up. Resolution happens **before** the output
 * directory is created and before anything is installed, so a device that cannot
 * supply the family's display leaves no partial set behind.
 */
function captureDevice(key, spec, device) {
  const udid = device.udid;
  const outDir = outDirFor(key, spec);
  step(`${key}: ${device.name} (${udid})`);

  const weBooted = boot(udid);
  try {
    let displayArg = null;
    let displays = null;
    if (spec.display) {
      displays = enumerateDisplays(udid);
      displayArg = resolveDisplayArg(spec, displays);
      if (displayArg?.error) {
        displayFailures.push(key);
        console.error(`\n✗ ${key}: ${displayArg.error}`);
        console.error(`\n  Nothing was created or written for ${key}.`);
        return [];
      }
      log(`  display: --display=${displayArg.selector} (${displayArg.via})`);
    }

    // The pose and orientation gates run before the output directory is created
    // and before anything is installed, so a device in the wrong pose leaves no
    // partial set behind. Non-Duo families carry no `pose`, so they skip both
    // and their capture is unchanged.
    if (spec.pose && !ensureDuoPose(key, spec, udid, displays, device.name)) return [];
    if (spec.rotateToPortrait && !ensureInnerPortrait(key, spec, udid, displays, device.name)) return [];

    mkdirSync(outDir, { recursive: true });
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
    const screens = screensFor(spec);
    for (const [i, screen] of screens.entries()) {
      const file = join(outDir, `${String(i + 1).padStart(2, "0")}-${screen.slug}.png`);
      if (screen.url) {
        const r = tryRun("xcrun", ["simctl", "openurl", udid, screen.url]);
        if (!r.ok) log(`  ! openurl failed for ${screen.url}: ${r.out.trim()}`);
      }
      spawnSync("sleep", [String(screen.settle / 1000)]);
      const raw = join(outDir, `.raw-${screen.slug}.png`);
      // `--display=` only appears for multi-display families. A single-display
      // family passes no flag at all, so its call is byte-identical to before.
      const shotArgs = ["simctl", "io", udid, "screenshot"];
      if (displayArg) shotArgs.push(`--display=${displayArg.selector}`);
      shotArgs.push(raw);
      const name = `${String(i + 1).padStart(2, "0")}-${screen.slug}.png`;
      const shot = tryRun("xcrun", shotArgs);
      if (!existsSync(raw)) {
        // A capture that wrote nothing still gets a row, and that row fails.
        // Skipping it instead leaves the screen with no row at all, so the
        // table has nothing to reject and a run where every screenshot failed
        // would end on `printTable([])` reporting success for zero files.
        const detail = shot.out.trim() ? ` (${shot.out.trim().split("\n").pop()})` : "";
        log(`  ✗ ${name}  no file written${detail}`);
        rows.push({
          file: name,
          size: null,
          ok: false,
          reason: `no screenshot produced for ${screen.slug}${detail}`,
        });
        continue;
      }
      stripAlpha(raw, file);
      rmSync(raw, { force: true });
      const check = verifyFile(file, spec);
      // The blank gate reads the pixels, which is the only way to see a panel
      // that is the right size and still empty. Applied to every family; on the
      // iPhone and iPad sets it has never rejected a real capture.
      const gate = blankGate(file, spec);
      const ok = check.ok && gate.ok;
      rows.push({ file: name, size: check.size, ok });
      const reasons = [];
      if (!check.sizeOk) {
        reasons.push(
          spec.exactNative
            ? `size must be ${spec.native.join("x")}`
            : `size must be one of ${spec.accepted.map(([w, h]) => `${w}x${h}`).join("/")}`,
        );
      }
      if (!check.noAlpha) reasons.push(`alpha not stripped (PNG colour type ${check.colorType})`);
      if (gate.flat) reasons.push(gate.blankReason);
      const note = reasons.length ? ` (${reasons.join("; ")})` : "";
      log(`  ${ok ? "✓" : "✗"} ${name}  ${check.size[0]}x${check.size[1]}${note}`);
      if (!gate.ok) log(`    → rejected: ${gate.cause}`);
    }

    // Every screen the family asked for must have produced a row that passed.
    // Counting rows is the check that closes the hole at the top of this loop:
    // a screen that wrote no file contributes a FAILING row now, and this
    // assertion catches the other direction, where a screen is skipped before a
    // row is ever built. Either way the family fails rather than reporting a
    // smaller set as success.
    const missingRows = screens
      .map((s, i) => `${String(i + 1).padStart(2, "0")}-${s.slug}.png`)
      .filter((expected) => !rows.some((r) => r.file === expected));
    if (missingRows.length > 0) {
      captureFailures.push(key);
      console.error(`\n✗ ${key}: ${missingRows.length} of ${screens.length} requested screen(s) produced no verification row:`);
      for (const file of missingRows) console.error(`    ${file}`);
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
  if (all.length === 0) {
    // Reached only when nothing was captured at all, which is a failure: the
    // previous version printed a success line for zero files and exited 0.
    console.log("  ✗ no files were captured — nothing to verify");
    return false;
  }
  const width = Math.max(...all.map((r) => r.file.length), "file".length);
  console.log(`  ${"device".padEnd(8)} ${"file".padEnd(width)} ${"dimensions".padEnd(14)} required`);
  console.log(`  ${"-".repeat(8)} ${"-".repeat(width)} ${"-".repeat(14)} ${"-".repeat(8)}`);
  for (const r of all) {
    const dims = r.size ? `${r.size[0]}x${r.size[1]}` : "no file";
    console.log(`  ${r.device.padEnd(8)} ${r.file.padEnd(width)} ${dims.padEnd(14)} ${r.ok ? "yes" : "NO"}`);
  }
  const bad = all.filter((r) => !r.ok);
  console.log("");
  if (bad.length) {
    console.log(`✗ ${bad.length} file(s) failed verification (not captured, wrong size, alpha not stripped, or a blank panel)`);
    for (const r of bad) {
      if (r.reason) console.log(`  ${r.device}  ${r.file}: ${r.reason}`);
    }
    return false;
  }
  console.log(`✓ ${all.length} file(s), all at the required size, alpha stripped, no blank panels`);
  return true;
}

function checkExisting(keys) {
  step("verifying docs/screenshots/<family>/");
  const rows = [];
  const missingFamilies = [];
  for (const key of keys) {
    const spec = REQUIRED_SIZES[key];
    const dir = outDirFor(key, spec);
    if (!existsSync(dir)) {
      // A missing family directory fails the check. Logging it and moving on
      // let another family's rows decide the exit code, so a fresh checkout
      // with no captures at all could still report success.
      console.log(`  ✗ ${spec.dir ?? key}/ missing — no screenshots captured for this family`);
      missingFamilies.push(key);
      continue;
    }
    const present = new Set();
    for (const f of readdirSafe(dir)) {
      if (!f.endsWith(".png") || f.startsWith(".")) continue;
      present.add(f);
      const full = join(dir, f);
      const check = verifyFile(full, spec);
      const gate = blankGate(full, spec);
      if (gate.flat) console.log(`  ✗ ${f}: ${gate.blankReason}`);
      rows.push({ device: key, file: f, size: check.size, ok: check.ok && gate.ok });
    }
    // The same completeness requirement the capture run enforces: every screen
    // the family asked for must be on disk, or the check is verifying a partial
    // set. `--screens` narrows the expected set for both paths alike.
    const missing = screensFor(spec)
      .map((s, i) => `${String(i + 1).padStart(2, "0")}-${s.slug}.png`)
      .filter((expected) => !present.has(expected));
    if (missing.length > 0) {
      console.log(`  ✗ ${spec.dir ?? key}/ is missing ${missing.length} of ${screensFor(spec).length} screen(s): ${missing.join(", ")}`);
      missingFamilies.push(key);
    }
  }
  if (!rows.length && !missingFamilies.length) {
    console.log("  nothing captured yet — run without --check");
    return false;
  }
  const tableOk = printTable(rows);
  if (missingFamilies.length) {
    console.error(`\n✗ ${missingFamilies.length} family/families are incomplete: ${missingFamilies.join(", ")}`);
    return false;
  }
  return tableOk;
}

function readdirSafe(dir) {
  try {
    return readdirSync(dir);
  } catch {
    return [];
  }
}

/** Read-only simulator inventory, so a dry run can name devices without making one. */
function listRuntimes() {
  return JSON.parse(run("xcrun", ["simctl", "list", "runtimes", "--json"])).runtimes;
}

/**
 * Fails fast, and actionably, when the machine cannot capture iPhone Duo.
 *
 * Runs before the build so a missing runtime costs seconds rather than a
 * several-minute `xcodebuild`, and before anything creates a simulator or a
 * directory, so a failure leaves no half-made device set and no partial files.
 *
 * Returns the iOS 27.1 runtime to create the Duo device on. The device type
 * declares `minRuntimeVersion 27.1`, so creating it on an older runtime fails —
 * the runtime has to be the one this found, not "the newest available".
 */
function duoPreflight() {
  const runtime = findDuoRuntime();
  const hasDeviceType = duoDeviceType();
  const missing = [];
  if (!hasDeviceType) missing.push(`the iPhone Duo device type (${DUO_DEVICE_TYPE})`);
  if (!runtime) missing.push(`an available iOS ${DUO_RUNTIME_VERSION} runtime`);
  if (missing.length === 0) return runtime;

  const runtimeId = `com.apple.CoreSimulator.SimRuntime.iOS-${DUO_RUNTIME_VERSION.replace(/\./g, "-")}`;
  console.error("");
  console.error(`✗ iPhone Duo capture is not possible on this machine yet.`);
  console.error(`  Missing: ${missing.join(" and ")}.`);
  console.error("");
  console.error("  Nothing was built, and no simulator or file was created.");
  console.error("");
  console.error("  1. Download the iOS 27.1 runtime (several GB, one time):");
  console.error(`       xcodebuild -downloadPlatform iOS -buildVersion ${DUO_RUNTIME_VERSION}`);
  console.error("");
  console.error("  2. Create the Duo simulator:");
  console.error(`       xcrun simctl create "${DUO_DEVICE_NAME}" ${DUO_DEVICE_TYPE} ${runtimeId}`);
  console.error("");
  console.error("  3. Re-run:");
  console.error("       npm run screenshots:duo");
  process.exit(1);
}

/** The iOS 27.1 runtime, or null. Read-only. */
function findDuoRuntime() {
  return listRuntimes().find(
    (r) => r.isAvailable && (r.version === DUO_RUNTIME_VERSION
      || r.identifier.includes(`iOS-${DUO_RUNTIME_VERSION.replace(/\./g, "-")}`)),
  ) ?? null;
}

/** Whether the Duo device type is installed. Read-only. */
function duoDeviceType() {
  const types = JSON.parse(run("xcrun", ["simctl", "list", "devicetypes", "--json"])).devicetypes;
  return types.some((t) => t.identifier === DUO_DEVICE_TYPE);
}

/**
 * `--probe <udid>`: print the parsed display table and the selector each family
 * would choose, then stop.
 *
 * Read-only. It builds nothing, boots nothing, writes nothing and creates no
 * device, so the display resolver can be audited against any booted simulator —
 * including a non-Duo one, where the Duo families are expected to report that no
 * display matches. The device must already be booted: `io enumerate` reports no
 * ports for a shut-down device.
 */
function probe(udid) {
  const devices = listDevices();
  const device = devices.find((d) => d.udid === udid);
  step(`probe ${udid}`);
  if (!device) {
    console.error(`  ✗ no simulator with udid ${udid} (see: xcrun simctl list devices)`);
    process.exit(1);
  }
  console.log(`  device:   ${device.name}  (${device.runtime})`);
  console.log(`  state:    ${device.state}`);
  if (device.state !== "Booted") {
    console.error(`  ✗ not booted — run: xcrun simctl boot ${udid}`);
    process.exit(1);
  }

  const displays = enumerateDisplays(udid);
  console.log(`\n  parsed display ports (Class: Display), ${displays.ports.length} found:`);
  if (!displays.ports.length) {
    console.log("    (none — simctl reported no Display ports)");
  }
  for (const p of displays.ports) {
    console.log(`    Display class: ${String(p.displayClass ?? "?").padEnd(3)} ${`${p.width}x${p.height}`.padEnd(11)} ${p.uuid}`);
  }

  // Pose inference only means something when both Duo panels are present.
  if (findPanelPort(displays.ports, DUO_OUTER_SIZE) && findPanelPort(displays.ports, DUO_INNER_SIZE)) {
    const pose = probePose(udid, displays);
    console.log("\n  current pose (inferred from which panel has content):");
    if (pose.ok) {
      console.log(`    ${pose.pose ?? "UNKNOWN (both panels blank, or both drawn)"}   ${pose.evidence}`);
    } else {
      console.log(`    could not tell: ${pose.error}`);
    }
    console.log("    duoOuter needs Closed; duoInner needs Open + native portrait.");
  }

  console.log("\n  selector per family:");
  for (const key of ALL_KEYS) {
    const spec = REQUIRED_SIZES[key];
    if (!spec.display) {
      console.log(`    ${key.padEnd(10)} no --display flag (single-display family, unchanged)`);
      continue;
    }
    const resolved = resolveDisplayArg(spec, displays);
    if (resolved?.error) {
      console.log(`    ${key.padEnd(10)} NO MATCH — would stop:`);
      for (const line of resolved.error.split("\n")) console.log(`               ${line}`);
      continue;
    }
    console.log(`    ${key.padEnd(10)} --display=${resolved.selector}   (${resolved.via})`);
  }
  console.log("\n  required pose per family:");
  for (const key of ALL_KEYS) {
    const spec = REQUIRED_SIZES[key];
    console.log(
      `    ${key.padEnd(10)} ${spec.pose ? `pose ${spec.pose}, ${spec.orientation}${spec.rotateToPortrait ? ' (rotate the inner panel with Device Hub "Rotate Right")' : ""}` : "no pose (not a foldable)"}`,
    );
  }
  console.log("\n  probe complete — nothing built, booted, created or written.");
  process.exit(0);
}

// ---------------------------------------------------------------------------

log("TidyByte — App Store screenshot capture");

if (probeFlag !== -1 && !PROBE_UDID) {
  console.error("--probe needs a simulator udid: --probe <udid>");
  process.exit(1);
}

// Family selection. `--duo` swaps the default set for the Duo displays instead
// of adding to it, so the iPhone/iPad run is untouched. `--only` (or the older
// `--device`) narrows to one family, and `--duo` still has to be given for a Duo
// family so the runtime check is never skipped by accident.
const ALL_KEYS = Object.keys(REQUIRED_SIZES);
const DUO_KEYS = ALL_KEYS.filter((k) => REQUIRED_SIZES[k].duo);
const DEFAULT_KEYS = ALL_KEYS.filter((k) => !REQUIRED_SIZES[k].duo);

if (PROBE_UDID) probe(PROBE_UDID);

const requestedFamily = ONLY_FILTER ?? (DEVICE_FILTER === "all" ? null : DEVICE_FILTER);
let keys;
if (requestedFamily) {
  if (!REQUIRED_SIZES[requestedFamily]) {
    console.error(`unknown family "${requestedFamily}" (expected ${ALL_KEYS.join(", ")})`);
    process.exit(1);
  }
  if (REQUIRED_SIZES[requestedFamily].duo && !DUO_ONLY) {
    console.error(`"${requestedFamily}" needs --duo (it needs the iOS ${DUO_RUNTIME_VERSION} runtime)`);
    process.exit(1);
  }
  keys = [requestedFamily];
} else {
  keys = DUO_ONLY ? DUO_KEYS : DEFAULT_KEYS;
}

log(
  `required sizes: ${keys.map((k) => `${REQUIRED_SIZES[k].label} ${REQUIRED_SIZES[k].accepted.map(([w, h]) => `${w}x${h}`).join("/")}`).join("; ")}`,
);

if (CHECK_ONLY) {
  process.exit(checkExisting(keys) ? 0 : 1);
}

// The Duo runtime is resolved before capture so the device is created on 27.1
// rather than on whatever is newest, but a dry run must not fail just because it
// is missing — the plan is what a dry run is for.
const needsDuo = keys.some((k) => REQUIRED_SIZES[k].duo);
const duoRuntimeNow = needsDuo ? findDuoRuntime() : null;
const duoTypeNow = needsDuo ? duoDeviceType() : false;

if (DRY_RUN) {
  step("dry run — the capture plan");
  const devices = listDevices();
  for (const key of keys) {
    const spec = REQUIRED_SIZES[key];
    const existing = findExistingDevice(spec, devices);
    const booted = existing?.state === "Booted";
    // Read-only. `io enumerate` reports ports only for a booted device, so a
    // booted device is resolved for real — matching by pixel size, the same
    // path a capture takes — and anything else prints the documented fallback.
    const displays = spec.display && booted ? enumerateDisplays(existing.udid) : null;
    let display;
    if (!spec.display) {
      display = "(single display — no --display flag)";
    } else if (displays) {
      const resolved = resolveDisplayArg(spec, displays);
      display = resolved?.error
        ? `NOT RESOLVED — ${resolved.error.split("\n")[0]}`
        : `--display=${resolved.selector} (${resolved.via})`;
    } else {
      display = `by pixel size ${spec.native.join("x")} at run time (screenID ${spec.screenID} fallback)`;
    }
    console.log(`  ${key}  ${spec.label}`);
    console.log(
      `    device:      ${spec.deviceName} ${existing ? `[installed: ${existing.udid}${booted ? ", booted" : ""}]` : "[not installed — would be created]"}`,
    );
    console.log(`    pose:        ${spec.pose ?? "(not a foldable — no pose)"}`);
    console.log(
      `    orientation: ${spec.orientation ?? "native"}${spec.rotateToPortrait ? ' (inner panel rotated to native portrait with Device Hub "Rotate Right")' : ""}`,
    );
    console.log(`    display:     ${display}`);
    console.log(`    output:      ${outDirFor(key, spec)}/`);
    console.log(`    size:        expected ${spec.native.join("x")} (portrait)`);
    if (spec.pose) {
      console.log(
        `    pose fix:    ${DRIVE_DEVICEHUB ? "--drive-devicehub is ON — Device Hub will be driven" : 'manual — Device Hub buttons "Closed" / "Open" / "Rotate Right" (or pass --drive-devicehub)'}`,
      );
    }
    const screens = screensFor(spec);
    console.log(`    screens:     ${screens.length}${spec.duo && !SCREENS_FILTER ? " (Duo default set)" : ""}`);
    if (spec.duo) {
      const gaps = [];
      if (!duoRuntimeNow) gaps.push(`iOS ${DUO_RUNTIME_VERSION} runtime not installed`);
      if (!duoTypeNow) gaps.push("Duo device type not installed");
      console.log(
        `    note:        ${gaps.length ? `${gaps.join("; ")} — a real run would stop here` : "Duo runtime and device type are installed"}`,
      );
    }
    for (const [i, screen] of screensFor(spec).entries()) {
      const name = `${String(i + 1).padStart(2, "0")}-${screen.slug}.png`;
      console.log(`      ${name.padEnd(30)} ${spec.native.join("x")}  ${screen.url ?? "(app home)"}`);
    }
  }
  console.log("\n  dry run — nothing built, nothing booted, created or written.");
  process.exit(0);
}

const duoRuntime = needsDuo ? duoPreflight() : null;

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
  const device = resolveDevice(spec, devices, { runtime: duoRuntime });
  const rows = captureDevice(key, spec, device);
  for (const r of rows) all.push({ ...r, device: key });
}

if (displayFailures.length) {
  console.error(`\n✗ ${displayFailures.length} family/families could not resolve a display: ${displayFailures.join(", ")}`);
  process.exit(1);
}
if (poseFailures.length) {
  console.error(`\n✗ ${poseFailures.length} family/families were not in the pose or orientation they need: ${poseFailures.join(", ")}`);
  process.exit(1);
}
if (captureFailures.length) {
  console.error(`\n✗ ${captureFailures.length} family/families did not produce a file for every requested screen: ${captureFailures.join(", ")}`);
  process.exit(1);
}
process.exit(printTable(all) ? 0 : 1);
