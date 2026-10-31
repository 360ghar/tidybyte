# Changelog

## 1.0.0 (unreleased)

First public release, as Tidybyte for Mac.

### Added

- One window in the style of Apple's own Mac apps: Overview, then Clean (System Junk, Developer, Large & Old Files, Duplicates, Photos & Media), Apps (Applications, Leftovers, Login Items), and Insights (Space Explorer, Changes, History).
- First-run onboarding with a Full Disk Access check that continues on its own once access is on.
- Deeper uninstaller: launch agents and daemons, privileged helpers, UUID-named containers, app-group containers from the code signature, WebKit data, and cookies. Each item shows why it matched and how sure the match is. Possible matches, and data that another installed app also uses, stay review-only.
- Leftovers of deleted apps, found only when the full app inventory is known, no installed app from the same developer owns the data, and nothing in it changed for 30 days. Launch agents whose program is gone count too.
- An offer to review leftovers after you delete an app from Applications.
- Login Items: agents and daemons that start with your Mac.
- Developer cleanup through each tool's own command: `brew cleanup --prune=all`, `docker builder prune`, `pnpm store prune`, and `xcrun simctl delete unavailable`. Simulator cleanup waits until Simulator and Xcode quit.
- Older Xcode Device Support folders (the newest per platform stays), local Time Machine snapshots (review only), and old installers in Downloads, on the Desktop, and in Documents.
- Empty Trash, with a confirmation.
- Menu bar item with free space and memory pressure (off by default).
- App icon built with Icon Composer; Sparkle updates for the direct download.

### Changed

- The app is now Tidybyte (`com.sakshammittal.tidybyte`).
- Scanning is about twice as fast, with identical results.
- `~/Library` — the largest tree on most Macs — now crawls in parallel instead of as one job at the end of the scan, duplicate pre-hashing uses the same worker pool as full hashing, and package-manager probes overlap the crawl.
- While the crawl runs, the subtitle shows a live item count and the folder being read, and each stage's duration is logged.
- Stopping a scan keeps what it found so far. The review shows the partial results with a "stopped early" note instead of an empty workspace that reads as clean.
- Reclaimable sizes count hard links and APFS clones honestly.
- Liquid Glass bars for approved changes and tool actions; native inspector, toolbar, and sheets.
- Bulk Approve and Reject act only on the rows in the current area.
- The app follows the system appearance.

### Fixed

- An empty review is no longer silent. The scan now says when app data was skipped for lack of Full Disk Access, when locations could not be read, and when a section could not be checked (Spotlight off), in the status strip and in Overview's Latest Scan.
- A full scan of a large home folder no longer runs out of memory. Folders that no review lists file by file (`node_modules`, `.git`, build output beside a build manifest, each cache entry, each simulator device) are now one item with the total size of their contents. The detailed-record budget is capped at one million records; folders past the budget are still summarized as one record each, and only files of 1 GB or more keep a record of their own. On a Mac with 7.9 million files in the home folder, the scan used 42 GB before this fix.
- Xcode archives, Xcode UserData, simulator devices, keychains, and provisioning profiles can no longer be proposed for deletion.
- Duplicate folding no longer reaches into `~/Library`.
- The autoscan agent is now bundled and registered through `SMAppService` instead of a plist the app never loaded.
- The direct build now carries the Photos entitlement that the hardened runtime requires.
- Docker's aggressive prune no longer stops at a confirmation prompt; long package commands no longer time out after 30 seconds.
