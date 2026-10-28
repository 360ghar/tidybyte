# Cleanup v1

The new Cleanup coordinator is separate from the existing scan and AI pipeline. The direct build keeps that pipeline under Advanced. The App Store build exposes the local Cleanup tools and has no network-client entitlement. Both builds require macOS 26 and use Swift 6.

## Review and sources

Folder Mode inventories one folder recursively. Full Mac Mode selects Pictures, Movies, Music, Downloads, Documents, Desktop, and an optional System Photos Library source. Downloads & Chat Media also accepts an explicitly selected exported chat folder, regardless of its name.

Folder grants use security-scoped bookmarks. Stale bookmarks are renewed. Grants stay active during inventory, analysis, previews, execution, and filesystem monitoring. Local files, Photos assets, and compound Photos resources have distinct identities. File identities include device, inode, size, and precise modification time. Hard-link paths are separate review items. Supported document packages are single items with aggregate logical bytes and a recursive metadata version.

Hidden and protected paths, application bundles, managed libraries, and network volumes are excluded. Link targets are displayed but never traversed. Cloud placeholders have no content analysis or cleanup action. Recognized cloud-provider files are read-only. Mutations verify source identity, root containment, resolved parent containment, and access again.

Swipe stores a durable draft. Keep and Skip do not change files. Move destinations are saved with the draft. Skip does not create a review-history record. The confirmation lists the actions and destinations before execution. Starting execution locks and saves the decisions; partial results survive relaunch. Tool confirmations use a fixed batch of items and settings and reject changed scan results. Failed or cancelled runs retain per-item results and do not show a successful-trash notice. Reset Review History leaves operation journals, recovery records, and activity intact.

## Local analysis and previews

The analysis pipeline uses size buckets, sampled hashes, and full SHA-256 verification. It has no 2 GB duplicate cutoff. Compound Photos assets compare their complete resource sets. Vision feature-print groups are labelled as visual matches and have distinct group identifiers. Sharpness, luminance, clipped highlights, EXIF capture time, Vision classification, and text recognition supply local image results. Similar groups use anchored creation or modification windows, which prevent timestamp chains from expanding the group.

The shared preview supports image zoom, native audio/video playback, PDF page navigation, and Quick Look. The thumbnail cache is limited to 64 MiB. Photos grid previews use local PhotoKit thumbnails instead of exporting full assets. Resource requests disable network access. Unsupported or unreadable files show an unavailable state.

## Mutation and recovery

Filesystem deletes use Trash. Photos deletes use PhotoKit and Recently Deleted. Photos exports verify every resource by length and SHA-256 before requesting deletion. Photos replacements verify the imported resource and preserve writable date, location, favorite/hidden state, and supported album membership. Confirmations explain edit-history and compound-media loss.

Compression runs at most two jobs at a time. Image presets use 0.9, 0.8, and 0.65; video presets are 1080p, 720p, and 480p. ImageIO and AVFoundation reopen and decode outputs. A smaller, verified result is required before original removal. Outputs are staged in an app-created directory and published without replacing an existing name. Unsupported animation, auxiliary depth/HDR image data, HDR video, and unsupported track layouts are rejected.

The operation journal is written before changing user data. Partial results retain both originals and created outputs. Recovery stores the actual Trash or move location and a security-scoped recovery bookmark where available. A restore checks identity and refuses an occupied original path. Photos recovery is performed in Photos; it is not filesystem Undo. Apple normally retains Recently Deleted items for 30 days, and deletion can affect iCloud Photos. See [Apple Photos recovery guidance](https://support.apple.com/guide/photos/delete-photos-videos-recover-deleted-pht3bfab2f96/mac).

## Reporting and reminders

Storage uses logical bytes and deduplicated opportunity selections. Daily snapshots are stored only after a successful, current scan and compared within the same scope. There is no interpolation for days without scans. Volume usage warns above 90%. The Trash action opens Finder.

The lifetime ledger is outside routine scan retention. It separates Trash bytes, Recently Deleted bytes, and verified compression/format reductions. Restore dates produce negative chart adjustments. Interrupted operations appear in recent activity but do not contribute to totals.

Weekly reminders are off by default and use the selected weekday at 09:00 local time. Their text includes the date and counts from the last completed scan. The `macos-cleaner://cleanup`, `macos-cleaner://swipe`, and `macos-cleaner://activity` routes only change navigation.

## Persistence

SQLite migration 6 adds Cleanup state, activity, and daily snapshot tables. Existing tables and records remain readable. The new payloads preserve subsecond dates. Review history is keyed by scope and content version. Analysis records include the scan generation and analysis settings version. Filesystem and Photos changes invalidate badges before refreshing.

## Validation

See the [release commands](release.md). The validation report and follow-up review are local QA output in `qa-results/` and are not committed. Full native workflow validation, a disposable Photos library, real video conversion checks, and external signing credentials remain release gates.
