# Tidybyte for Mac

Tidybyte finds space you can reclaim on your Mac and removes it only after you approve. It is the Mac version of [Tidybyte for iPhone and iPad](https://apps.apple.com/app/tidybyte/id6775769763).

Everything runs on your Mac. Files go to the Trash, and History can restore them.

## Features

| Area | What it does |
| --- | --- |
| Overview | Startup disk capacity, Trash size, and one recommendation per area. |
| System Junk | Caches, logs, browser data, and app support caches that apps rebuild. |
| Developer | `node_modules`, build folders, Xcode DerivedData and old Device Support, unavailable simulators, and Homebrew, npm, pip, pnpm, and Docker cleanup through each tool's own command. |
| Large & Old Files | Large files, old downloads, and installers (`.dmg`, `.pkg`, `.xip`, `.iso`) older than 30 days. |
| Duplicates | Exact copies, verified with SHA-256. Fold them into APFS clones to save space without deleting anything, or move extras to the Trash. |
| Photos & Media | Similar shots, blurry photos, bursts, screenshots, screen recordings, and large videos in your folders and Photos library. Review one by one with Swipe Review. Compress photos and videos. |
| Applications | Uninstall an app with its settings, caches, containers, launch agents, and helpers. Each item shows why it matched and how sure the match is. |
| Leftovers | Data of apps you already deleted. An item counts only when no installed app from the same developer owns it and nothing in it changed for 30 days. |
| Login Items | Agents and daemons that start with your Mac, with missing programs marked. |
| Space Explorer | Eight views of your files: list, folders, sunburst, flame, bubbles, mind map, top sizes, and age map. |
| Changes | Storage forecast, comparison of two scans, and the Photos & Media trend. |
| History | Every change, with Restore where the operation supports it. |

Optional extras: a menu bar item with free space and memory status, a notification after you delete an app, weekly reminders, natural-language review ("clean python caches in old projects") with an optional AI provider you configure, and an MCP server for AI agents.

## Requirements

- macOS 26 or later
- A Mac with Apple silicon

## Install

1. Download `Tidybyte-<version>.dmg` from the [releases page](https://github.com/360ghar/tidybyte/releases).
2. Open the disk image and drag Tidybyte to Applications.
3. Open Tidybyte. Onboarding asks for Full Disk Access and, if you want, Photos access.

Tidybyte updates itself. Choose **Tidybyte › Check for Updates…** to check now.

## Permissions

| Permission | Why | Without it |
| --- | --- | --- |
| Full Disk Access | Read Mail, Safari, and other apps' containers and caches. | Those areas are skipped and their sizes show as Unknown. Tidybyte does not open other apps' containers, so macOS does not ask about them. |
| Photos | Find similar, blurry, and large items in the Photos library. | Photos & Media covers your folders only. |
| Notifications | Scan reminders and the offer to clean up after you delete an app. | No notifications. |

## Safety model

- **Selection, approval, and execution are separate.** Selecting a row never approves it. Every run goes through one confirmation sheet that lists counts per area.
- **Trash first.** Files move to the Trash; Photos items move to Recently Deleted. Empty Trash is the only permanent command, and it asks first.
- **Checked twice.** Each file's identity (device, inode, size, and modification time) is checked again just before it changes.
- **Protected paths.** Keychains, certificates and keys, provisioning profiles, `.ssh`, `.gnupg`, source code, system paths, Xcode UserData, and simulator devices are never changed. Xcode archives are review-only because they hold the debug symbols for builds you shipped.
- **Honest sizes.** A hard link with other names, or an APFS clone that shares its blocks, frees nothing alone, and the estimate says so.
- **Tool commands.** Package-manager and simulator cleanups run the tool's own command and cannot be undone. Simulator cleanup waits until Simulator and Xcode quit.
- **Unattended runs never delete.** Automatic maintenance only folds exact duplicates into clones.

## For developers

```sh
swift build                    # build
swift test                     # 492 tests (2 skip headless); destructive tests use fixture folders only
swiftlint lint --strict --baseline .swiftlint-baseline.json
Scripts/build-app.sh direct    # .build/Tidybyte.app
```

Pure SwiftPM, Swift 6 language mode, strict concurrency.

| Target | Role |
| --- | --- |
| `MacOSCleanerCore` | Services, models, safety policy, SQLite store |
| `MacOSCleanerAppKit` | SwiftUI app: views, view models, design tokens |
| `MacOSCleaner` | App executable (`Tidybyte`); `--autoscan` runs headless maintenance |
| `MacOSCleanerMCP` | `tidybyte-mcp`, an MCP server over stdio JSON-RPC |

### MCP server

`Tidybyte.app/Contents/MacOS/tidybyte-mcp` exposes scan, findings, plan, execute, history, and undo to AI agents. `execute` is a dry run until called with `confirm: true`, and high-risk destructive actions are refused; those stay in the app.

### Release

```sh
SIGNING_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE=tidybyte-notary \
SPARKLE_PUBLIC_KEY=<base64 key> SPARKLE_PRIVATE_KEY_FILE=<path> \
Scripts/package-release.sh direct
```

The script signs inside out with the hardened runtime, notarizes and staples the app and the DMG, and writes a one-item `appcast.xml`. `SIGNING_IDENTITY=- SKIP_NOTARIZE=1` runs it without credentials. The update feed is `https://tidybyte.360ghar.com/mac/appcast.xml`; set `SPARKLE_FEED_URL` to change it.

See [DESIGN.md](DESIGN.md) for the interface and [CHANGELOG.md](CHANGELOG.md) for changes.

## FAQ

**Why is there no "Free up RAM" button?** macOS manages memory better than any app can. Tidybyte shows memory use and pressure in the menu bar, and it does not purge memory.

**Why do some sizes say Unknown?** Tidybyte could not read that location, usually because Full Disk Access is off. It does not guess.

**Is anything sent over the network?** No, unless you turn on an AI provider in Settings › AI & Privacy. The default is local only. Update checks contact the update feed.
